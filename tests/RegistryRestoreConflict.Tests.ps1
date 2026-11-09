BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
    $script:conflictKey = 'HKCU:\Software\TweakByjieTest\RestoreConflict'
    $script:coreDefs = @(
        @{ Path = $script:conflictKey; Name = 'DwordValue'; Desc = 'dword' },
        @{ Path = $script:conflictKey; Name = 'AbsentValue'; Desc = 'absent' }
    )
    $script:systemDefs = @(
        @{ Path = $script:conflictKey; Name = 'StringValue'; Desc = 'string' }
    )
    $script:registryBackupFileReal = $script:registryBackupFile
    $script:registryAppliedFileReal = $script:registryAppliedFile
    $script:registryBackupFile = Join-Path $TestDrive 'registry-backup.json'
    $script:registryAppliedFile = Join-Path $TestDrive 'registry-applied.json'
}

AfterAll {
    Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
    $script:registryBackupFile = $script:registryBackupFileReal
    $script:registryAppliedFile = $script:registryAppliedFileReal
}

Describe 'Registry applied-state ledger' {
    BeforeEach {
        Remove-Item $script:registryBackupFile -Force -ErrorAction SilentlyContinue
        Remove-Item $script:registryAppliedFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:conflictKey -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:conflictKey -Force | Out-Null
        New-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -PropertyType DWord -Value 10 -Force | Out-Null
        New-ItemProperty -Path $script:conflictKey -Name 'StringValue' -PropertyType String -Value 'original' -Force | Out-Null
        Ensure-RegistryBackup -CoreDefinitions $script:coreDefs -SystemDefinitions $script:systemDefs | Should -Be $true
    }

    It 'records the values written after the first snapshot' {
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 20
        Set-ItemProperty -Path $script:conflictKey -Name 'StringValue' -Value 'applied'
        Save-RegistryAppliedState -Section Core -Definitions $script:coreDefs
        Save-RegistryAppliedState -Section System -Definitions $script:systemDefs

        $ledger = Get-Content $script:registryAppliedFile -Raw | ConvertFrom-Json
        $ledger.Version | Should -Be 1
        $ledger.Binding | Should -Be (Get-BackupMachineId)
        @($ledger.Entries).Count | Should -Be 2
        ($ledger.Entries | Where-Object Name -eq 'DwordValue').Data | Should -Be '20'
        ($ledger.Entries | Where-Object Name -eq 'DwordValue').Section | Should -Be 'Core'
        ($ledger.Entries | Where-Object Name -eq 'StringValue').Data | Should -Be 'applied'
        @($ledger.Entries | Where-Object Name -eq 'AbsentValue').Count | Should -Be 0
    }

    It 'skips a value that changed after the tool wrote it' {
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 20
        Set-ItemProperty -Path $script:conflictKey -Name 'StringValue' -Value 'applied'
        Save-RegistryAppliedState -Section Core -Definitions $script:coreDefs
        Save-RegistryAppliedState -Section System -Definitions $script:systemDefs
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 30

        Restore-RegistryBackup -CoreDefinitions $script:coreDefs -SystemDefinitions $script:systemDefs | Should -Be $true
        [uint32](Get-ItemProperty $script:conflictKey -Name 'DwordValue').DwordValue | Should -Be 30
        (Get-ItemProperty $script:conflictKey -Name 'StringValue').StringValue | Should -Be 'original'
        $script:registryRestoreStats.Conflict | Should -Be 1
        $script:registryRestoreStats.Restored | Should -Be 1
    }

    It 'does not report a conflict when the value is already back at the original' {
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 20
        Save-RegistryAppliedState -Section Core -Definitions $script:coreDefs
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 10

        Restore-RegistryBackup -Section Core -CoreDefinitions $script:coreDefs -SystemDefinitions $script:systemDefs | Should -Be $true
        $script:registryRestoreStats.AlreadyOriginal | Should -BeGreaterThan 0
        $script:registryRestoreStats.Conflict | Should -Be 0
    }

    It 'overwrites a conflict when -Force is used' {
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 20
        Save-RegistryAppliedState -Section Core -Definitions $script:coreDefs
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 30

        Restore-RegistryBackup -Section Core -Force -CoreDefinitions $script:coreDefs -SystemDefinitions $script:systemDefs | Should -Be $true
        [uint32](Get-ItemProperty $script:conflictKey -Name 'DwordValue').DwordValue | Should -Be 10
        $script:registryRestoreStats.Forced | Should -Be 1
    }

    It 'keeps the legacy blind restore when no ledger exists' {
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 20

        Restore-RegistryBackup -Section Core -CoreDefinitions $script:coreDefs -SystemDefinitions $script:systemDefs | Should -Be $true
        [uint32](Get-ItemProperty $script:conflictKey -Name 'DwordValue').DwordValue | Should -Be 10
        $script:registryRestoreStats.Conflict | Should -Be 0
        $script:registryRestoreStats.Legacy | Should -Be 1
    }

    It 'rejects a ledger bound to another machine' {
        Set-ItemProperty -Path $script:conflictKey -Name 'DwordValue' -Value 20
        Save-RegistryAppliedState -Section Core -Definitions $script:coreDefs
        $ledger = Get-Content $script:registryAppliedFile -Raw | ConvertFrom-Json
        $ledger.Binding = 'foreign-machine'
        Set-Content -LiteralPath $script:registryAppliedFile -Value ($ledger | ConvertTo-Json -Depth 6) -Encoding UTF8

        Test-RegistryAppliedSchema $ledger | Should -Be $false
        Restore-RegistryBackup -Section Core -CoreDefinitions $script:coreDefs -SystemDefinitions $script:systemDefs | Should -Be $true
        $script:registryRestoreStats.Conflict | Should -Be 0
        $script:registryRestoreStats.Legacy | Should -Be 1
    }
}
