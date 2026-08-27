# Power.ps1 - Part 7 超性能电源计划（含同名重复计划清理）

function Invoke-PowerModule {

    # ======================= Part 7: 应用超性能电源计划 =======================
    # 独立步骤：备份当前电源计划 -> 导入并应用仓库自带的超性能计划 / 或恢复备份
    Write-Host ""
    Write-Host "============ [Part 7] 应用超性能电源计划 / Ultimate Performance Power Plan ============" -ForegroundColor Cyan
    Write-Host ""

    $planFile   = Join-Path $script:RepoRoot "ultimate-performance.pow"
    $backupFile = Join-Path $script:RepoRoot "power-backup.pow"

    Write-Host "  1. 备份当前电源计划，然后导入并应用超性能电源计划" -ForegroundColor White
    Write-Host "  2. 恢复之前备份的电源计划" -ForegroundColor White
    $pChoice = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"

    if ($pChoice -eq "1") {

        if (-not (Test-Path $planFile)) {
            Write-Host "[FAIL] 未找到 ultimate-performance.pow（需与本脚本放在同一目录）" -ForegroundColor Red
            $script:fail++
        } else {

            # 1) Backup current active scheme (keep the earliest backup)
            if (Test-Path $backupFile) {
                Write-Host "[SKIP] 备份文件已存在，不覆盖（保护最初的原计划备份）: $backupFile" -ForegroundColor Yellow
                $script:skip++
            } else {
                try {
                    $activeOut = & powercfg.exe /getactivescheme 2>$null
                    if ($activeOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                        $activeGuid = $Matches[1]
                    } else {
                        throw "无法解析当前电源计划 GUID"
                    }
                    & powercfg.exe /export $backupFile $activeGuid *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /export exit code $LASTEXITCODE" }
                    Write-Host "[OK] 当前电源计划已备份: $backupFile ($activeGuid)"
                    $script:ok++
                } catch {
                    Write-Host "[FAIL] 备份当前电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            }

            # 2) Import bundled plan and apply
            if (Test-Path $backupFile) {
                try {
                    $importOut = & powercfg.exe /import $planFile 2>$null
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
                    Invoke-PowerPlanDedupe
                } catch {
                    Write-Host "[FAIL] 导入/应用超性能电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            } else {
                Write-Host "[SKIP] 备份失败，为安全起见跳过应用超性能计划" -ForegroundColor Yellow
                $script:skip++
            }
        }

    } elseif ($pChoice -eq "2") {

        # Restore previously backed-up scheme
        if (-not (Test-Path $backupFile)) {
            Write-Host "[FAIL] 未找到备份文件 power-backup.pow（请先执行子选项 1 生成备份）" -ForegroundColor Red
            $script:fail++
        } else {
            try {
                $importOut = & powercfg.exe /import $backupFile 2>$null
                if ($importOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                    $newGuid = $Matches[1]
                } else {
                    throw "无法解析导入后的计划 GUID（power-backup.pow 可能已损坏）"
                }
                & powercfg.exe /setactive $newGuid *> $null
                if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive exit code $LASTEXITCODE" }
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
        Write-Host "[ERROR] 无效输入：$pChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
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
