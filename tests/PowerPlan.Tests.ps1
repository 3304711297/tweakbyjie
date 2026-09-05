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

# Power 计划备份→恢复内容往返（审计缺口：Backup.* 模块唯余 Power 缺往返测试；
# Power 的备份/恢复内嵌在 Modules/Power.ps1，无独立 Backup.Power.ps1）。
# 语义：子选项 1 备份当前活动计划到 power-backup.pow（mock 的 export 真实落盘），
# 子选项 2 用同一文件恢复（mock 的 import 读回并记录内容）——断言"写什么读什么"。
# 隔离：powercfg / powercfg.exe 两个名字都 mock（覆盖 Invoke-PowerPlanDedupe 里的
# 裸 `powercfg /list` 调用），仓库根重定向到 TestDrive，全程不触碰本机电源计划与真实仓库文件。
Describe "Power plan backup/restore round-trip (mocked powercfg)" {
    BeforeAll {
        $script:RealRepoRoot = $script:RepoRoot
        $script:RealHadBackup = Test-Path (Join-Path $script:RepoRoot 'power-backup.pow')
        $script:RepoRoot = $TestDrive

        # 沙盒里的"仓库自带"超性能计划（内容自定义，不依赖真实 ultimate-performance.pow）
        $script:planPath = Join-Path $TestDrive 'ultimate-performance.pow'
        [IO.File]::WriteAllText($script:planPath, 'MOCK-ULTIMATE-PLAN-CONTENT')
        $script:backupPath = Join-Path $TestDrive 'power-backup.pow'
        Remove-Item $script:backupPath -Force -ErrorAction SilentlyContinue

        $powCalls = [System.Collections.Generic.List[string]]::new()
        $script:exportedBackupContent = $null
        $script:importedBackupContent = $null
        $powercfgStub = {
            $line = ($args -join ' ')
            $powCalls.Add($line)
            $global:LASTEXITCODE = 0
            switch -Regex ($args[0]) {
                'getactivescheme' { return '电源方案 GUID: eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee  (平衡)' }
                'list' { return '电源计划 GUID: cccccccc-cccc-cccc-cccc-cccccccccccc  (ultimate-performance) *' }
                # export：模拟 powercfg 把当前活动计划真实写入目标 .pow 文件
                'export' {
                    $script:exportedBackupContent = "MOCK-POWER-BACKUP-$($args[2])"
                    [IO.File]::WriteAllText($args[1], $script:exportedBackupContent)
                }
                # import：模拟 powercfg 读回 .pow（记录读到的内容供"写什么读什么"断言）
                'import' {
                    $src = $args[1]
                    if ($src -like '*power-backup.pow') {
                        $script:importedBackupContent = [IO.File]::ReadAllText($src)
                    }
                    if ($src -like '*ultimate-performance.pow') { return '导入电源方案: cccccccc-cccc-cccc-cccc-cccccccccccc' }
                    return '导入电源方案: dddddddd-dddd-dddd-dddd-dddddddddddd'
                }
                default { }
            }
        }
        Mock powercfg.exe $powercfgStub
        Mock powercfg $powercfgStub
        Mock Read-Host { return '1' }
        Set-TweakAdapters -Confirm { param($Prompt) return $false }
    }

    AfterAll {
        Initialize-TweakAdapters
        $script:RepoRoot = $script:RealRepoRoot
    }

    It "backup phase really creates a non-empty power-backup.pow with correct call order" {
        Invoke-PowerModule | Out-Null

        # (a) 备份文件被真实创建且非空，内容即 mock export 写入的内容
        Test-Path $script:backupPath | Should -Be $true
        ([IO.File]::ReadAllText($script:backupPath)) | Should -Be $script:exportedBackupContent
        $script:exportedBackupContent | Should -Match 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'

        # (c) 调用序列：getactivescheme → export → import(超性能) → setactive → changename
        $pos = @()
        foreach ($pat in @('getactivescheme', '^/export ', 'import .*ultimate-performance\.pow', 'setactive', 'changename')) {
            $idx = $null
            for ($i = 0; $i -lt $powCalls.Count; $i++) {
                if ($powCalls[$i] -match $pat) { $idx = $i; break }
            }
            $idx | Should -Not -Be $null -Because "powercfg 应以 $pat 被调用"
            $pos += $idx
        }
        for ($i = 0; $i -lt $pos.Count - 1; $i++) {
            $pos[$i] | Should -BeLessThan $pos[$i + 1]
        }

        # export 携带备份文件路径与当时活动计划 GUID；changename 恰一次且指向导入的 GUID
        $expLine = $powCalls[$pos[1]]
        $expLine | Should -Match ([regex]::Escape($script:backupPath))
        $expLine | Should -Match 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
        $chg = @($powCalls | Where-Object { $_ -match 'changename' })
        $chg.Count | Should -Be 1
        $chg[0] | Should -Match 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $chg[0] | Should -Match 'ultimate-performance'
    }

    It "restore phase imports the exact backup file and passes its content through" {
        $powCalls.Clear()
        $script:importedBackupContent = $null
        Mock Read-Host { return '2' }
        Invoke-PowerModule | Out-Null

        # (b) 恢复以该备份文件路径调用 powercfg /import
        $imp = @($powCalls | Where-Object { $_ -match '^/import ' })
        $imp.Count | Should -Be 1
        $imp[0] | Should -Match ([regex]::Escape($script:backupPath))

        # export 与 import 之间的内容传递：写什么读什么
        $script:importedBackupContent | Should -Be $script:exportedBackupContent

        # setactive 使用恢复导入返回的 GUID；恢复路径绝不改计划名
        $act = @($powCalls | Where-Object { $_ -match 'setactive' })
        $act.Count | Should -Be 1
        $act[0] | Should -Match 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        (@($powCalls | Where-Object { $_ -match 'changename' })).Count | Should -Be 0
    }

    It "fails closed when the backup file is cleaned up before restore" {
        $powCalls.Clear()
        Mock Read-Host { return '2' }
        Remove-Item $script:backupPath -Force -ErrorAction SilentlyContinue

        Invoke-PowerModule | Out-Null

        # 缺失备份文件时绝不假装恢复成功：不产生任何 import / setactive 调用
        (@($powCalls | Where-Object { $_ -match 'import|setactive' })).Count | Should -Be 0
    }

    It "keeps the real repo root untouched by the round-trip" {
        # 沙盒外无残留：真实仓库根的 power-backup.pow 状态与测试开始前一致
        (Test-Path (Join-Path $script:RealRepoRoot 'power-backup.pow')) | Should -Be $script:RealHadBackup
        # 沙盒内的备份文件已被上一用例清理，只剩计划文件
        (Test-Path $script:backupPath) | Should -Be $false
        (Test-Path $script:planPath) | Should -Be $true
    }
}
