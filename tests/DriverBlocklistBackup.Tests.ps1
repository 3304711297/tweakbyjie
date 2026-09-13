BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Driver blocklist backup schema" {
    BeforeAll {
        $defs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\DriverBlocklist'; Name = 'VulnerableDriverBlocklistEnable'; Desc = 'blocklist' },
            @{ Path = 'HKCU:\Software\TweakByjieTest\DriverBlocklist'; Name = 'AbsentValue'; Desc = 'absent' }
        )
        $valid = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            CreatedAt = '2026-09-13T00:00:00.0000000Z'
            Values = @(
                [pscustomobject]@{ Path = $defs[0].Path; Name = 'VulnerableDriverBlocklistEnable'; Present = $true; Value = [uint32]0 }
                [pscustomobject]@{ Path = $defs[1].Path; Name = 'AbsentValue'; Present = $false; Value = $null }
            )
        }
    }

    It "rejects null and wrong version" {
        Test-DriverBlocklistBackupSchema $null $defs | Should -Be $false
        $bad = [pscustomobject]@{ Version = 99 }
        Test-DriverBlocklistBackupSchema $bad $defs | Should -Be $false
    }

    It "accepts a valid snapshot" {
        Test-DriverBlocklistBackupSchema $valid $defs | Should -Be $true
    }

    It "rejects a snapshot with foreign binding" {
        $bad = [pscustomobject]@{
            Version = 1
            Binding = 'not-this-machine'
            CreatedAt = $valid.CreatedAt
            Values = $valid.Values
        }
        Test-DriverBlocklistBackupSchema $bad $defs | Should -Be $false
    }

    It "rejects foreign registry records" {
        $bad = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            CreatedAt = $valid.CreatedAt
            Values = @(
                [pscustomobject]@{ Path = 'HKCU:\Software\Foreign'; Name = 'VulnerableDriverBlocklistEnable'; Present = $true; Value = [uint32]0 }
                [pscustomobject]@{ Path = $defs[1].Path; Name = 'AbsentValue'; Present = $false; Value = $null }
            )
        }
        Test-DriverBlocklistBackupSchema $bad $defs | Should -Be $false
    }

    It "rejects an absent record that still carries a value" {
        $bad = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            CreatedAt = $valid.CreatedAt
            Values = @(
                [pscustomobject]@{ Path = $defs[0].Path; Name = 'VulnerableDriverBlocklistEnable'; Present = $true; Value = [uint32]0 }
                [pscustomobject]@{ Path = $defs[1].Path; Name = 'AbsentValue'; Present = $false; Value = [uint32]7 }
            )
        }
        Test-DriverBlocklistBackupSchema $bad $defs | Should -Be $false
    }
}

Describe "Driver blocklist backup/restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $key = 'HKCU:\Software\TweakByjieTest\DriverBlocklist'
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'VulnerableDriverBlocklistEnable' -PropertyType DWord -Value 1 -Force | Out-Null

        $defs = @(
            @{ Path = $key; Name = 'VulnerableDriverBlocklistEnable'; Desc = 'blocklist' },
            @{ Path = $key; Name = 'NeverSetValue'; Desc = 'absent' }
        )
    }

    AfterAll {
        Remove-Item -Path 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "snapshots, modifies, and restores the original value" {
        $origFile = $script:driverBlocklistBackupFile
        $script:driverBlocklistBackupFile = Join-Path $TestDrive 'driver-blocklist.json'
        try {
            Ensure-DriverBlocklistBackup -Definitions $defs | Should -Be $true
            $backup = Get-Content $script:driverBlocklistBackupFile -Raw | ConvertFrom-Json
            $backup.Values.Count | Should -Be 2
            ($backup.Values | Where-Object Name -eq 'VulnerableDriverBlocklistEnable').Value | Should -Be 1
            ($backup.Values | Where-Object Name -eq 'NeverSetValue').Present | Should -Be $false

            # 模拟菜单动作：关闭黑名单
            Set-ItemProperty -Path $key -Name 'VulnerableDriverBlocklistEnable' -Value 0 -Type DWord
            (Get-ItemProperty -Path $key -Name 'VulnerableDriverBlocklistEnable').VulnerableDriverBlocklistEnable | Should -Be 0

            Restore-DriverBlocklistBackup -Definitions $defs | Should -Be $true
            (Get-ItemProperty -Path $key -Name 'VulnerableDriverBlocklistEnable').VulnerableDriverBlocklistEnable | Should -Be 1
        } finally {
            $script:driverBlocklistBackupFile = $origFile
        }
    }

    It "refuses to restore when no backup file exists" {
        $origFile = $script:driverBlocklistBackupFile
        $script:driverBlocklistBackupFile = Join-Path $TestDrive 'missing-driver-blocklist.json'
        try {
            $script:fail = 0
            Restore-DriverBlocklistBackup -Definitions $defs | Should -Be $false
            $script:fail | Should -BeGreaterThan 0
        } finally {
            $script:driverBlocklistBackupFile = $origFile
        }
    }

    It "does not overwrite an existing valid snapshot" {
        $origFile = $script:driverBlocklistBackupFile
        $script:driverBlocklistBackupFile = Join-Path $TestDrive 'first-snapshot.json'
        try {
            Ensure-DriverBlocklistBackup -Definitions $defs | Should -Be $true
            Set-ItemProperty -Path $key -Name 'VulnerableDriverBlocklistEnable' -Value 5 -Type DWord
            Ensure-DriverBlocklistBackup -Definitions $defs | Should -Be $true
            $backup = Get-Content $script:driverBlocklistBackupFile -Raw | ConvertFrom-Json
            ($backup.Values | Where-Object Name -eq 'VulnerableDriverBlocklistEnable').Value | Should -Be 1
        } finally {
            Set-ItemProperty -Path $key -Name 'VulnerableDriverBlocklistEnable' -Value 1 -Type DWord
            $script:driverBlocklistBackupFile = $origFile
        }
    }
}

Describe "Driver blocklist definition" {
    It "targets the documented CI\\Config value" {
        $script:driverBlocklistValues.Count | Should -Be 1
        $script:driverBlocklistValues[0].Path | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config'
        $script:driverBlocklistValues[0].Name | Should -Be 'VulnerableDriverBlocklistEnable'
    }
}
