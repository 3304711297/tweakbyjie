BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Defender environment and capability detection" {
    It "detects Workstation SKU when ProductType is 1" {
        $profile = Get-DefenderEnvironmentProfile -MockProductType 1 -MockWscService @{ Name = 'wscsvc'; State = 'Running' } -MockHasSecHealthUI $true
        $profile.Sku | Should -Be 'Workstation'
        $profile.IsServer | Should -Be $false
        $profile.WscCapability | Should -Be 'Present'
        $profile.UiCapability | Should -Be 'Present'
    }

    It "detects Server SKU when ProductType is 3 without collapsing UI capability" {
        $profile = Get-DefenderEnvironmentProfile -MockProductType 3 -MockWscService $null -MockHasSecHealthUI $false
        $profile.Sku | Should -Be 'Server'
        $profile.IsServer | Should -Be $true
        $profile.WscCapability | Should -Be 'Absent'
        $profile.UiCapability | Should -Be 'Absent'
    }

    It "marks capabilities as Unknown on query failure and preserves fail-closed discipline" {
        $profile = Get-DefenderEnvironmentProfile -MockProductType -1 -MockWscService 'QUERY_FAILED' -MockHasSecHealthUI 'QUERY_FAILED'
        $profile.Sku | Should -Be 'Unknown'
        $profile.WscCapability | Should -Be 'Unknown'
        $profile.UiCapability | Should -Be 'Unknown'
    }
}

Describe "Defender driver residency detection via CIM" {
    It "detects WdFilter running status and flags driver residency" {
        $residency = Get-DefenderDriverResidency -MockDrivers @{
            'WdFilter'  = @{ Name = 'WdFilter'; State = 'Running' }
            'MsSecCore' = @{ Name = 'MsSecCore'; State = 'Running' }
        }
        $residency.WdFilterState | Should -Be 'DriverRunning'
        $residency.MsSecCoreState | Should -Be 'DriverRunning'
        $residency.IsDriverPresent | Should -Be $true
    }

    It "detects stopped or absent drivers correctly" {
        $residency = Get-DefenderDriverResidency -MockDrivers @{
            'WdFilter'  = @{ Name = 'WdFilter'; State = 'Stopped' }
            'MsSecCore' = $null
        }
        $residency.WdFilterState | Should -Be 'DriverStopped'
        $residency.MsSecCoreState | Should -Be 'Absent'
        $residency.IsDriverPresent | Should -Be $false
    }

    It "handles driver query failure safely as Unknown" {
        $residency = Get-DefenderDriverResidency -MockDrivers 'QUERY_FAILED'
        $residency.WdFilterState | Should -Be 'Unknown'
        $residency.MsSecCoreState | Should -Be 'Unknown'
        $residency.IsDriverPresent | Should -Be $false
    }

    It "returns Unknown when Get-CimInstance throws rather than falling back to Absent" {
        Mock Get-CimInstance { throw "CIM provider failure" } -ParameterFilter { $ClassName -eq 'Win32_SystemDriver' }
        $residency = Get-DefenderDriverResidency
        $residency.WdFilterState | Should -Be 'Unknown'
        $residency.MsSecCoreState | Should -Be 'Unknown'
    }
}

Describe "Defender multi-dimensional status evaluation" {
    It "evaluates to PendingReboot when policy is modified and service is stopped but drivers remain present" {
        $status = Get-DefenderMultiDimensionalStatus `
            -PolicyState 'Modified' `
            -WinDefendState 'Disabled' `
            -DriverResidency @{ IsDriverPresent = $true; WdFilterState = 'DriverRunning' } `
            -TamperProtection 'Disabled'
        
        $status.Overall | Should -Be 'PendingReboot'
        $status.EffectiveVerdict | Should -Match '需重启'
    }

    It "evaluates to Converged when policy is original and service is running" {
        $status = Get-DefenderMultiDimensionalStatus `
            -PolicyState 'Original' `
            -WinDefendState 'Running' `
            -DriverResidency @{ IsDriverPresent = $true; WdFilterState = 'DriverRunning' } `
            -TamperProtection 'Enabled'
        
        $status.Overall | Should -Be 'Converged'
    }

    It "evaluates to Unknown when policy or driver probe is Unknown" {
        $status = Get-DefenderMultiDimensionalStatus `
            -PolicyState 'Unknown' `
            -WinDefendState 'Stopped' `
            -DriverResidency @{ IsDriverPresent = $false; WdFilterState = 'Unknown'; MsSecCoreState = 'Absent' } `
            -TamperProtection 'Disabled'
        
        $status.Overall | Should -Be 'Unknown'
        $status.EffectiveVerdict | Should -Match '无法得出确切收敛结论'
    }

    It "evaluates to Unknown when MsSecCore is Unknown even if WdFilter is Absent" {
        $status = Get-DefenderMultiDimensionalStatus `
            -PolicyState 'Modified' `
            -WinDefendState 'Disabled' `
            -DriverResidency @{ IsDriverPresent = $false; WdFilterState = 'Absent'; MsSecCoreState = 'Unknown' } `
            -TamperProtection 'Disabled'
        
        $status.Overall | Should -Be 'Unknown'
    }

    It "does not evaluate to Converged when TamperProtection is Enabled with Modified policy" {
        $status = Get-DefenderMultiDimensionalStatus `
            -PolicyState 'Modified' `
            -WinDefendState 'Disabled' `
            -DriverResidency @{ IsDriverPresent = $false; WdFilterState = 'Absent'; MsSecCoreState = 'Absent' } `
            -TamperProtection 'Enabled'
        
        $status.Overall | Should -Not -Be 'Converged'
        $status.EffectiveVerdict | Should -Match '篡改防护'
    }

    It "evaluates to Unknown when TamperProtection is Unknown even if other states appear disabled" {
        $status = Get-DefenderMultiDimensionalStatus `
            -PolicyState 'Modified' `
            -WinDefendState 'Disabled' `
            -DriverResidency @{ IsDriverPresent = $false; WdFilterState = 'Absent'; MsSecCoreState = 'Absent' } `
            -TamperProtection 'Unknown'
        
        $status.Overall | Should -Be 'Unknown'
        $status.EffectiveVerdict | Should -Match '无法得出确切收敛结论'
    }

    It "returns Unknown when policy registry read throws an exception" {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Real-Time Protection*' }
        Mock Get-ItemProperty { throw "Registry access denied" } -ParameterFilter { $LiteralPath -like '*Real-Time Protection*' }
        $status = Get-DefenderMultiDimensionalStatus -WinDefendState 'Disabled' -DriverResidency @{ IsDriverPresent = $false; WdFilterState = 'Absent'; MsSecCoreState = 'Absent' } -TamperProtection 'Disabled'
        $status.PolicyStore | Should -Be 'Unknown'
        $status.Overall | Should -Be 'Unknown'
    }
}
