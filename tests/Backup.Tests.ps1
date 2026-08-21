BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Backup schema validators" {

    It "Test-MpoBackupSchema rejects incomplete backup" {
        $bad = [pscustomobject]@{ Version = 1; Values = @() }
        Test-MpoBackupSchema $bad | Should -Be $false
    }

    It "Test-BcdBackupSchema rejects wrong version" {
        $bad = [pscustomobject]@{ Version = 99; Object = '{current}'; Values = @() }
        Test-BcdBackupSchema $bad @('useplatformclock') | Should -Be $false
    }

    It "Test-SecurityMitigationBackupSchema rejects null" {
        Test-SecurityMitigationBackupSchema $null | Should -Be $false
    }

    It "Test-NvmeBackupSchema rejects wrong version" {
        $bad = [pscustomobject]@{ Version = 1; SafeBoot = @(); Features = @(); LegacyOverrides = @() }
        Test-NvmeBackupSchema $bad | Should -Be $false
    }
}

Describe "Missing NVMe helpers now exist" {
    It "Test-NativeNvmeConfigured is defined" {
        Get-Command Test-NativeNvmeConfigured -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    It "Test-NativeNvmeEffective is defined" {
        Get-Command Test-NativeNvmeEffective -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    It "Test-NativeNvmeEffective returns FileExists and State" {
        $r = Test-NativeNvmeEffective
        $r.PSObject.Properties.Name | Should -Contain 'FileExists'
        $r.PSObject.Properties.Name | Should -Contain 'State'
    }
}

Describe "Defender policy backup schema" {
    It "Test-DefenderBackupSchema rejects null" {
        Test-DefenderBackupSchema $null | Should -Be $false
    }
    It "Test-DefenderBackupSchema rejects wrong version" {
        $bad = [pscustomobject]@{ Version = 99; Values = @(); StartupValues = @() }
        Test-DefenderBackupSchema $bad | Should -Be $false
    }
    It "Test-DefenderBackupSchema rejects missing StartupValues section" {
        $bad = [pscustomobject]@{ Version = 1; Values = @() }
        Test-DefenderBackupSchema $bad | Should -Be $false
    }
    It "Test-DefenderBackupSchema rejects foreign value entries" {
        $bad = [pscustomobject]@{
            Version = 1
            Values = @([pscustomobject]@{ Path = 'HKCU:\Fake'; Name = 'Nope'; Type = 'DWord'; Present = $false; Value = $null })
            StartupValues = @($script:defenderStartupValues | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Name = $_.Name; Present = $false } })
        }
        Test-DefenderBackupSchema $bad | Should -Be $false
    }
    It "Defender policy definitions contain no duplicate Path|Name pairs" {
        $keys = @($script:defenderPolicyValues | ForEach-Object { "$($_.Path)|$($_.Name)" })
        ($keys | Sort-Object -Unique).Count | Should -Be $keys.Count
    }
    It "Defender policy definitions cover about 95 managed values" {
        @($script:defenderPolicyValues).Count | Should -Be 95
    }
    It "Invoke-DefenderModule is defined" {
        Get-Command Invoke-DefenderModule -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
