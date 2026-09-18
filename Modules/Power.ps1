# Power.ps1 - Part 7 超性能电源计划（含同名重复计划清理）

function Restore-PowerPlanFile {
    param([Parameter(Mandatory = $true)][string]$BackupFile)
    $importOut = & powercfg.exe /import $BackupFile 2>$null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /import exit code $LASTEXITCODE" }
    if ($importOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $restoredGuid = $Matches[1]
    } else {
        throw "无法解析导入后的计划 GUID（$BackupFile 可能已损坏）"
    }
    & powercfg.exe /setactive $restoredGuid *> $null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive exit code $LASTEXITCODE" }
    return $restoredGuid
}

function Invoke-PowerModule {
    param([string]$Action = '')

    # ======================= Part 7: 应用超性能电源计划 =======================
    # 独立步骤：备份当前电源计划 -> 导入并应用仓库自带的超性能计划 / 或恢复备份
    Write-Host ""
    Write-Host "============ [Part 7] 应用超性能电源计划 / Ultimate Performance Power Plan ============" -ForegroundColor Cyan
    Write-Host ""

    $planFile   = Join-Path $script:RepoRoot "ultimate-performance.pow"
    $backupFile = Join-Path $script:RepoRoot "power-backup.pow"

    Write-Host "  1. 备份当前电源计划，然后导入并应用超性能电源计划" -ForegroundColor White
    Write-Host "  2. 恢复之前备份的电源计划" -ForegroundColor White
    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定电源子操作（1=apply、2=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"
    }
    $pChoice = $Action

    if ($pChoice -eq "1") {

        if (-not (Test-Path $planFile)) {
            Write-Host "[FAIL] 未找到 ultimate-performance.pow（需与本脚本放在同一目录）" -ForegroundColor Red
            $script:fail++
        } else {

            # 1) Backup current active scheme (keep the earliest backup)
            $backupPublishFailed = $false
            if (Test-Path $backupFile) {
                Write-Host "[SKIP] 备份文件已存在，不覆盖（保护最初的原计划备份）: $backupFile" -ForegroundColor Yellow
                $script:skip++
            } else {
                try {
                    $activeOut = & powercfg.exe /getactivescheme 2>$null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /getactivescheme exit code $LASTEXITCODE" }
                    if ($activeOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                        $activeGuid = $Matches[1]
                    } else {
                        throw "无法解析当前电源计划 GUID"
                    }
                    # 直接导出到首次快照路径；目标在进入此分支前已确认不存在。
                    # 导出成功后立即校验非空，空/残缺快照不得作为后续修改的安全门禁。
                    & powercfg.exe /export $backupFile $activeGuid *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /export exit code $LASTEXITCODE" }
                    if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf) -or (Get-Item -LiteralPath $backupFile -ErrorAction Stop).Length -le 0) {
                        throw 'powercfg 导出的原始计划文件为空或不存在'
                    }
                    Write-Host "[OK] 当前电源计划已备份: $backupFile ($activeGuid)"
                    $script:ok++
                } catch {
                    Write-Host "[FAIL] 备份当前电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                    $backupPublishFailed = $true
                    # 原子发布失败时不触碰目标路径：它可能是并发进程刚刚固化的首次快照，
                    # 也可能是需要人工保留的现有快照；宁可阻止后续应用，不可盲删。
                }
            }

            # 2) Import bundled plan and apply only when the original snapshot exists and is non-empty.
            # Test-Path alone would allow an empty/corrupt partial export to act as a backup gate.
            $backupReady = $false
            if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
                try { $backupReady = ((Get-Item -LiteralPath $backupFile -ErrorAction Stop).Length -gt 0) }
                catch { $backupReady = $false }
            }
            if ($backupReady -and -not $backupPublishFailed) {
                $rebootBeforeApply = $script:rebootRequired
                try {
                    $importOut = & powercfg.exe /import $planFile 2>$null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /import exit code $LASTEXITCODE" }
                    if ($importOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                        $newGuid = $Matches[1]
                    } else {
                        throw "无法解析导入后的计划 GUID（ultimate-performance.pow 可能已损坏）"
                    }
                    & powercfg.exe /setactive $newGuid *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive exit code $LASTEXITCODE" }
                    # 统一命名：导入的计划沿用 .pow 内嵌名，容易出现 kirby/中文名等漂移，
                    # 导致去重按名称分组认不出重复项、审计比对也会误判；这里强制规范为 ultimate-performance
                    & powercfg.exe /changename $newGuid "ultimate-performance" *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /changename exit code $LASTEXITCODE" }
                    Write-Host "[OK] 超性能电源计划已导入并应用 ($newGuid)，名称统一为 ultimate-performance"
                    $script:ok++
                    $script:rebootRequired = $true
                    $beforeDedupeFail = $script:fail
                    Invoke-PowerPlanDedupe
                    if ($script:fail -gt $beforeDedupeFail) { throw '电源计划重复项清理未完全成功' }
                } catch {
                    Write-Host "[FAIL] 导入/应用超性能电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                    try {
                        $restoredGuid = Restore-PowerPlanFile $backupFile
                        $script:rebootRequired = $rebootBeforeApply
                        Write-Host "[OK] 已按原始电源计划快照回滚并激活 ($restoredGuid)" -ForegroundColor Yellow
                    } catch {
                        Write-Host "[FAIL] 电源计划失败后自动回滚未成功：$($_.Exception.Message)" -ForegroundColor Red
                        $script:fail++
                    }
                }
            } else {
                Write-Host "[FAIL] 原始电源计划快照不存在或为空，为安全起见跳过应用超性能计划" -ForegroundColor Red
                $script:fail++
            }
        }

    } elseif ($pChoice -eq "2") {

        # Restore previously backed-up scheme
        $restoreBackupReady = $false
        if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
            try { $restoreBackupReady = ((Get-Item -LiteralPath $backupFile -ErrorAction Stop).Length -gt 0) } catch { $restoreBackupReady = $false }
        }
        if (-not $restoreBackupReady) {
            Write-Host "[FAIL] 备份文件 power-backup.pow 不存在或为空（请先执行子选项 1 生成有效快照）" -ForegroundColor Red
            $script:fail++
        } else {
            try {
                $newGuid = Restore-PowerPlanFile $backupFile
                Write-Host "[OK] 已恢复备份的电源计划 ($newGuid)"
                $script:ok++
                $script:rebootRequired = $true
                Invoke-PowerPlanDedupe
            } catch {
                Write-Host "[FAIL] 恢复备份的电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
            }
        }

    } else {
        Write-Host "[FAIL] 无效输入：$pChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
        $script:fail++
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 7 - Ultimate Performance Power Plan)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：可用 powercfg /getactivescheme 查看当前电源计划；" -ForegroundColor Yellow
    Write-Host "如需恢复原计划，再次运行本脚本并选择 7 -> 2。" -ForegroundColor Yellow

    Request-Restart

}
