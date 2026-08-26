BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Test mode value allowlist" {

    It "Test-BcdValueAllowed accepts testsigning and debug Yes/No" {
        Test-BcdValueAllowed 'testsigning' 'Yes' | Should -Be $true
        Test-BcdValueAllowed 'testsigning' 'No' | Should -Be $true
        Test-BcdValueAllowed 'debug' 'Yes' | Should -Be $true
        Test-BcdValueAllowed 'debug' 'No' | Should -Be $true
    }

    It "Test-BcdValueAllowed rejects command-like values for testsigning" {
        Test-BcdValueAllowed 'testsigning' 'Yes /set nx AlwaysOff' | Should -Be $false
    }
}

Describe "Backup helpers support a separate test mode backup file" {

    It "Ensure-BcdBackup accepts -BackupFile" {
        (Get-Command Ensure-BcdBackup).Parameters.ContainsKey('BackupFile') | Should -Be $true
    }

    It "Restore-BcdBackup accepts -BackupFile and -SchemaNames" {
        $params = (Get-Command Restore-BcdBackup).Parameters
        $params.ContainsKey('BackupFile') | Should -Be $true
        $params.ContainsKey('SchemaNames') | Should -Be $true
    }

    It "Ensure-BcdBackup writes a valid snapshot to the given file" {
        $file = Join-Path $TestDrive 'tm-backup.json'
        Mock bcdedit.exe {
            $global:LASTEXITCODE = 0
            @('Windows Boot Manager', '--------------------', 'testsigning          Yes', 'nointegritychecks    No')
        }
        Ensure-BcdBackup -ValueNames @('testsigning','debug','nointegritychecks') -BackupFile $file | Should -Be $true
        Test-Path $file | Should -Be $true
        $backup = Get-Content $file -Raw | ConvertFrom-Json
        Test-BcdBackupSchema $backup @('testsigning','debug','nointegritychecks') | Should -Be $true
        ($backup.Values | Where-Object Name -eq 'testsigning').Present | Should -Be $true
        ($backup.Values | Where-Object Name -eq 'debug').Present | Should -Be $false
    }

    It "Restore-BcdBackup restores from the given file using its own schema" {
        $file = Join-Path $TestDrive 'tm-restore.json'
        $values = @(
            [pscustomobject]@{ Name = 'testsigning'; Present = $true; Value = 'Yes' }
            [pscustomobject]@{ Name = 'debug'; Present = $false; Value = $null }
            [pscustomobject]@{ Name = 'nointegritychecks'; Present = $false; Value = $null }
        )
        ConvertTo-Json -InputObject ([pscustomobject]@{ Version = 1; Object = '{current}'; CreatedAt = '2026-08-26T00:00:00.0000000Z'; Values = $values }) -Depth 5 |
            Set-Content -Path $file -Encoding UTF8
        Mock Invoke-BcdEdit { return $true }
        Mock Remove-BcdValue { }
        Restore-BcdBackup -ValueNames @('testsigning','debug') -BackupFile $file -SchemaNames @('testsigning','debug','nointegritychecks') | Should -Be $true
        Should -Invoke Invoke-BcdEdit -Times 1 -ParameterFilter { $Arguments -match 'set testsigning Yes' }
        Should -Invoke Remove-BcdValue -Times 1 -ParameterFilter { $ValueName -eq 'debug' }
        Should -Invoke Remove-BcdValue -Times 0 -ParameterFilter { $ValueName -eq 'nointegritychecks' }
    }
}

Describe "Test mode modules guard with backup" {

    It "Invoke-TestModeEnableModule backs up before modifying BCD" {
        Mock Ensure-BcdBackup { return $true }
        Mock Invoke-BcdEdit { return $true }
        Mock Request-Restart { }
        Invoke-TestModeEnableModule | Out-Null
        Should -Invoke Ensure-BcdBackup -Times 1
    }

    It "Invoke-TestModeEnableModule aborts modifications when backup fails" {
        Mock Ensure-BcdBackup { return $false }
        Mock Invoke-BcdEdit { return $true }
        Mock Request-Restart { }
        Invoke-TestModeEnableModule | Out-Null
        Should -Invoke Invoke-BcdEdit -Times 0
    }

    It "Invoke-TestModeDisableModule restores from backup when it exists" {
        Mock Restore-BcdBackup { return $true } -Verifiable
        Mock Invoke-BcdEdit { return $true }
        Mock Remove-BcdValue { }
        Mock Request-Restart { }
        New-Item -Path $script:testModeBackupFile -Value '{}' -Force | Out-Null
        Invoke-TestModeDisableModule | Out-Null
        Should -Invoke Restore-BcdBackup -Times 1
        Should -Invoke Invoke-BcdEdit -Times 0 -ParameterFilter { $Arguments -match 'deletevalue testsigning' }
        Remove-Item $script:testModeBackupFile -Force -ErrorAction SilentlyContinue
    }
}
