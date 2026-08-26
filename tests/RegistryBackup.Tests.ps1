BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Registry backup schema" {
    BeforeAll {
        $coreDefs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\Reg'; Name = 'DwordValue'; Desc = 'dword' },
            @{ Path = 'HKCU:\Software\TweakByjieTest\Reg'; Name = 'AbsentValue'; Desc = 'absent' }
        )
        $systemDefs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\Reg'; Name = 'StringValue'; Desc = 'string' },
            @{ Path = 'HKCU:\Software\TweakByjieTest\Reg'; Name = 'BinaryValue'; Desc = 'binary' }
        )
        $valid = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            CreatedAt = '2026-08-26T00:00:00.0000000Z'
            Core = @(
                [pscustomobject]@{ Path = $coreDefs[0].Path; Name = 'DwordValue'; Exists = $true; Kind = 'DWord'; Data = 38 }
                [pscustomobject]@{ Path = $coreDefs[1].Path; Name = 'AbsentValue'; Exists = $false; Kind = $null; Data = $null }
            )
            System = @(
                [pscustomobject]@{ Path = $systemDefs[0].Path; Name = 'StringValue'; Exists = $true; Kind = 'String'; Data = '2' }
                [pscustomobject]@{ Path = $systemDefs[1].Path; Name = 'BinaryValue'; Exists = $true; Kind = 'Binary'; Data = '9012018010000000' }
            )
        }
    }

    It "rejects null and wrong version" {
        Test-RegistryBackupSchema $null $coreDefs $systemDefs | Should -Be $false
        Test-RegistryBackupSchema ([pscustomobject]@{ Version = 99 }) $coreDefs $systemDefs | Should -Be $false
    }

    It "accepts a valid snapshot" {
        Test-RegistryBackupSchema $valid $coreDefs $systemDefs | Should -Be $true
    }

    It "rejects foreign records in either section" {
        foreach ($section in @('Core','System')) {
            $badCore = @($valid.Core); $badSystem = @($valid.System)
            $foreign = [pscustomobject]@{ Path = 'HKCU:\Software\Foreign'; Name = 'X'; Exists = $false; Kind = $null; Data = $null }
            if ($section -eq 'Core') { $badCore = @($valid.Core) + $foreign } else { $badSystem = @($valid.System) + $foreign }
            $bad = [pscustomobject]@{ Version = 1; Core = $badCore; System = $badSystem }
            Test-RegistryBackupSchema $bad $coreDefs $systemDefs | Should -Be $false
        }
    }

    It "rejects invalid kind or malformed binary/dword data" {
        $badKind = [pscustomobject]@{
            Version = 1
            Core = $valid.Core
            System = @(
                [pscustomobject]@{ Path = $systemDefs[0].Path; Name = 'StringValue'; Exists = $true; Kind = 'Weird'; Data = 'x' }
                [pscustomobject]@{ Path = $systemDefs[1].Path; Name = 'BinaryValue'; Exists = $true; Kind = 'Binary'; Data = '9012018010000000' }
            )
        }
        Test-RegistryBackupSchema $badKind $coreDefs $systemDefs | Should -Be $false

        $badHex = [pscustomobject]@{
            Version = 1
            Core = $valid.Core
            System = @(
                [pscustomobject]@{ Path = $systemDefs[0].Path; Name = 'StringValue'; Exists = $true; Kind = 'String'; Data = '2' }
                [pscustomobject]@{ Path = $systemDefs[1].Path; Name = 'BinaryValue'; Exists = $true; Kind = 'Binary'; Data = 'ZZZZ' }
            )
        }
        Test-RegistryBackupSchema $badHex $coreDefs $systemDefs | Should -Be $false
    }
}

Describe "Registry backup/restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $key = 'HKCU:\Software\TweakByjieTest\Reg'
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'DwordValue' -PropertyType DWord -Value 38 -Force | Out-Null

        $coreDefs = @(
            @{ Path = $key; Name = 'DwordValue'; Desc = 'dword' },
            @{ Path = $key; Name = 'AbsentValue'; Desc = 'absent' }
        )
        $systemDefs = @(
            @{ Path = $key; Name = 'StringValue'; Desc = 'string' }
        )

        Mock Invoke-BcdEdit { return $true }
        $script:registryBackupFileReal = $script:registryBackupFile
        $script:registryBackupFile = Join-Path $TestDrive 'registry-backup.json'
    }

    AfterAll {
        Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:registryBackupFileReal) { $script:registryBackupFile = $script:registryBackupFileReal }
    }

    It "Ensure captures dword/string/binary kinds and absence" {
        New-ItemProperty -Path $key -Name 'StringValue' -PropertyType String -Value '2' -Force | Out-Null
        Ensure-RegistryBackup -CoreDefinitions $coreDefs -SystemDefinitions $systemDefs | Should -Be $true
        $backup = Get-Content $script:registryBackupFile -Raw | ConvertFrom-Json
        ($backup.Core | Where-Object Name -eq 'DwordValue').Exists | Should -Be $true
        ($backup.System | Where-Object Name -eq 'StringValue').Kind | Should -Be 'String'
        ($backup.System | Where-Object Name -eq 'StringValue').Data | Should -Be '2'
    }

    It "Restore brings original values back and removes new values" {
        Set-ItemProperty -Path $key -Name 'DwordValue' -Value 10
        New-ItemProperty -Path $key -Name 'AbsentValue' -PropertyType DWord -Value 5 -Force | Out-Null
        Set-ItemProperty -Path $key -Name 'StringValue' -Value '0'

        Restore-RegistryBackup -CoreDefinitions $coreDefs -SystemDefinitions $systemDefs | Should -Be $true

        [uint32](Get-ItemProperty -Path $key -Name 'DwordValue').DwordValue | Should -Be 38
        (Get-Item $key).GetValueNames() -contains 'AbsentValue' | Should -Be $false
        (Get-ItemProperty -Path $key -Name 'StringValue').StringValue | Should -Be '2'
    }
}

Describe "Registry module guards with backup" {

    It "Invoke-RegistryModule option 1 aborts all writes when backup fails" {
        Mock Read-Host { return '1' }
        Mock Ensure-RegistryBackup { return $false }
        Mock Set-RegDword { }
        Mock Set-RegString { }
        Mock Request-Restart { }
        Invoke-RegistryModule | Out-Null
        Should -Invoke Set-RegDword -Times 0
        Should -Invoke Set-RegString -Times 0
    }

    It "Invoke-RegistryModule option 2 aborts all writes when backup fails" {
        Mock Read-Host { return '2' }
        Mock Ensure-RegistryBackup { return $false }
        Mock Set-RegDword { }
        Mock Set-RegString { }
        Mock Set-RegBinary { }
        Mock Disable-MMAgent { }
        Mock Request-Restart { }
        Invoke-RegistryModule | Out-Null
        Should -Invoke Set-RegDword -Times 0
        Should -Invoke Set-RegBinary -Times 0
    }

    It "Invoke-RegistryModule option 4 restores from snapshot" {
        Mock Read-Host { return '4' }
        Mock Restore-RegistryBackup { return $true }
        Mock Request-Restart { }
        Invoke-RegistryModule | Out-Null
        Should -Invoke Restore-RegistryBackup -Times 1
    }
}
