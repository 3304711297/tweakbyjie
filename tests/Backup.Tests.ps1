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
