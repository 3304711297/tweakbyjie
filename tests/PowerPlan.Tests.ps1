BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Service start-mode mapping" {
    It "maps known start modes to Set-Service and sc.exe values" {
        (Convert-ServiceStartMode 'Auto').SetService | Should -Be 'Automatic'
        (Convert-ServiceStartMode 'Auto').Sc | Should -Be 'auto'
        (Convert-ServiceStartMode 'Manual').Sc | Should -Be 'demand'
        (Convert-ServiceStartMode 'Disabled').Sc | Should -Be 'disabled'
        (Convert-ServiceStartMode 'System').Sc | Should -Be 'system'
        (Convert-ServiceStartMode 'Boot').Sc | Should -Be 'boot'
    }
    It "returns null for unknown modes instead of guessing disabled" {
        Convert-ServiceStartMode 'Weird' | Should -Be $null
        Convert-ServiceStartMode '' | Should -Be $null
    }
}

Describe "Power plan duplicate detection" {
    It "finds same-name duplicate groups and keeps the active plan" {
        $out = @(
            '现有电源计划 (* 活动)'
            '-------------------------------------'
            '电源计划 GUID: 11111111-1111-1111-1111-111111111111  (超性能)'
            '电源计划 GUID: 22222222-2222-2222-2222-222222222222  (超性能) *'
            '电源计划 GUID: 33333333-3333-3333-3333-333333333333  (平衡)'
        ) -join "`n"
        $groups = Get-PowerPlanDuplicateGroups $out
        @($groups).Count | Should -Be 1
        $groups[0].Name | Should -Be '超性能'
        $groups[0].KeepGuid | Should -Be '22222222-2222-2222-2222-222222222222'
        @($groups[0].DuplicateGuids).Count | Should -Be 1
        $groups[0].DuplicateGuids[0] | Should -Be '11111111-1111-1111-1111-111111111111'
    }
    It "parses English output and keeps first when none is active" {
        $out = @(
            'Power Scheme GUID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa  (Balanced) *'
            'Power Scheme GUID: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb  (Balanced)'
        ) -join "`n"
        $groups = Get-PowerPlanDuplicateGroups $out
        @($groups).Count | Should -Be 1
        $groups[0].KeepGuid | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    }
    It "returns nothing when all plan names are unique" {
        $out = @(
            '电源计划 GUID: 11111111-1111-1111-1111-111111111111  (平衡) *'
            '电源计划 GUID: 22222222-2222-2222-2222-222222222222  (超性能)'
        ) -join "`n"
        Get-PowerPlanDuplicateGroups $out | Should -Be $null
    }
}
