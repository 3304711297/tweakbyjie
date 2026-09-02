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

Describe "Power module renames the applied plan" {
    BeforeAll {
        $powCalls = [System.Collections.Generic.List[string]]::new()
        Mock powercfg.exe {
            $line = ($args -join ' ')
            $powCalls.Add($line)
            $global:LASTEXITCODE = 0
            switch -Regex ($line) {
                'getactivescheme' { return '电源方案 GUID: eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee  (平衡)' }
                'import .*ultimate-performance\.pow' { return '导入电源方案: cccccccc-cccc-cccc-cccc-cccccccccccc' }
                'import .*power-backup\.pow' { return '导入电源方案: dddddddd-dddd-dddd-dddd-dddddddddddd' }
                default { }
            }
        }
        Mock Read-Host { return '1' }
        Set-TweakAdapters -Confirm { param($Prompt) return $false }
        $backupPath = Join-Path $script:RepoRoot 'power-backup.pow'
        if (-not (Test-Path $backupPath)) { Set-Content -Path $backupPath -Value 'mock backup for test' }
    }

    AfterAll {
        Initialize-TweakAdapters
        Remove-Item (Join-Path $script:RepoRoot 'power-backup.pow') -Force -ErrorAction SilentlyContinue
    }

    It "applies changename to ultimate-performance with the imported GUID" {
        Invoke-PowerModule | Out-Null
        $change = @($powCalls | Where-Object { $_ -match 'changename' })
        $change.Count | Should -Be 1
        $change[0] | Should -Match 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $change[0] | Should -Match 'ultimate-performance'
    }

    It "does not rename when restoring a backed-up plan" {
        $powCalls.Clear()
        Mock Read-Host { return '2' }
        Invoke-PowerModule | Out-Null
        (@($powCalls | Where-Object { $_ -match 'changename' })).Count | Should -Be 0
    }
}
