# Defender.ps1 - Part 5 关闭安全中心（策略写入 + 服务停用 + 可选删除类优化）
# 被 tweakbyjie.ps1 点源加载；策略值快照/恢复逻辑见 Modules/Backup.Defender.ps1

function Invoke-DefenderModule {
    Write-Host ""
    Write-Host "============ [Part 5] 关闭安全中心 / Disable Security Center ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [WARNING] 此操作将禁用 Windows Defender 实时保护及相关安全服务！" -ForegroundColor Yellow
    Write-Host " [WARNING] This will disable Windows Defender realtime protection and related services!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. 应用 Defender/SmartScreen 禁用策略（首次运行自动快照原始值）"
    Write-Host "  2. 按快照恢复 Defender 策略原始值（defender-policy-backup.json）"
    Write-Host "  0. 返回主菜单"
    $pChoice = Read-Host "请输入选择并回车"

    if ($pChoice -eq "2") {
        Restore-DefenderPolicyBackup | Out-Null
        Request-Restart
        return
    }
    if ($pChoice -ne "1") {
        Write-Host "[SKIP] 已取消，返回主菜单。" -ForegroundColor Yellow
        return
    }

    # 备份失败则阻止修改（与 MPO/BCD/服务/NVMe 模块的备份闭环标准一致）
    if (-not (Ensure-DefenderPolicyBackup)) { return }

    # --- 策略写入（数据驱动，定义见 Modules/Backup.Defender.ps1）---
    Invoke-DefenderPolicyWrites

    # --- Stop Windows Defender Service ---
    Write-Host ""
    Write-Host "[Windows Defender Service]" -ForegroundColor Cyan
    $defenderSvc = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    if ($defenderSvc) {
        try {
            Stop-Service -Name "WinDefend" -Force -ErrorAction Stop
            Set-Service -Name "WinDefend" -StartupType Disabled -ErrorAction Stop
            Write-Host "[OK] Windows Defender Service stopped and disabled"
            $script:ok++
        } catch {
            Write-Host "[FAIL] Windows Defender Service : $($_.Exception.Message)" -ForegroundColor Red
            $script:fail++
        }
    } else {
        Write-Host "[SKIP] Windows Defender Service not found (already removed or not installed)" -ForegroundColor Yellow
        $script:skip++
    }

    # --- Optional: Deletion-type optimizations (Y/N) ---
    Write-Host ""
    Write-Host "[删除类优化 / Deletion-type Optimizations]" -ForegroundColor Cyan
    Write-Host " 包括：停止并禁用 Defender 相关服务、删除 Defender 计划任务、" -ForegroundColor Gray
    Write-Host " 删除安全中心自启动项、移除安全中心界面 (SecHealthUI)。" -ForegroundColor Gray
    if (Test-ConfirmChoice "是否执行删除类优化？Y = 确定 / N = 取消跳过") {

        # 1) Stop + disable Defender related services
        Write-Host ""
        Write-Host "[Defender Services: stop + disable]" -ForegroundColor Cyan
        $defenderServices = @(
            "WinDefend","WdNisSvc","WdNisDrv","WdBoot","WdFilter","wscsvc",
            "SgrmAgent","SgrmBroker","MsSecCore","MsSecFlt","MsSecWfp","whesvc",
            "webthreatdefsvc","webthreatdefusersvc","PlutonHsp2","PlutonHeci","Hsp"
        )
        foreach ($svc in $defenderServices) {
            $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($svcObj) {
                try {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                    Write-Host "[OK] Service $svc stopped and disabled"
                    $script:ok++
                } catch {
                    & sc.exe config $svc start= disabled *> $null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[OK] Service $svc disabled (stop rejected: protected service)"
                        $script:ok++
                    } else {
                        Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                        $script:fail++
                    }
                }
            } else {
                Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
                $script:skip++
            }
        }

        # 2) Delete Defender scheduled tasks
        Write-Host ""
        Write-Host "[Defender Scheduled Tasks]" -ForegroundColor Cyan
        $defenderTasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" -ErrorAction SilentlyContinue
        if ($defenderTasks) {
            foreach ($task in $defenderTasks) {
                try {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Host ("[OK] Task deleted: {0}{1}" -f $task.TaskPath, $task.TaskName)
                    $script:ok++
                } catch {
                    Write-Host ("[FAIL] Task {0}{1} : {2}" -f $task.TaskPath, $task.TaskName, $_.Exception.Message) -ForegroundColor Red
                    $script:fail++
                }
            }
        } else {
            Write-Host "[SKIP] No Defender scheduled tasks found" -ForegroundColor Yellow
            $script:skip++
        }

        # 3) Remove SecurityHealth / Windows Defender startup entries（原始值已在快照中，可经 5 -> 2 恢复）
        Write-Host ""
        Write-Host "[Startup Entries]" -ForegroundColor Cyan
        foreach ($item in $script:defenderStartupValues) {
            $existing = Get-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
            if ($existing) {
                try {
                    Remove-ItemProperty -Path $item.Path -Name $item.Name -Force -ErrorAction Stop
                    Write-Host ("[OK] Startup entry removed: {0} -> {1}" -f $item.Path, $item.Name)
                    $script:ok++
                } catch {
                    Write-Host ("[FAIL] Startup entry {0} -> {1} : {2}" -f $item.Path, $item.Name, $_.Exception.Message) -ForegroundColor Red
                    $script:fail++
                }
            } else {
                Write-Host ("[SKIP] Startup entry not found: {0} -> {1}" -f $item.Path, $item.Name) -ForegroundColor Yellow
                $script:skip++
            }
        }

        # 4) Remove Security Center UI (SecHealthUI)
        Write-Host ""
        Write-Host "[Security Center UI (SecHealthUI)]" -ForegroundColor Cyan
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            try {
                $secApp = Get-AppxPackage -Name "Microsoft.SecHealthUI" -ErrorAction SilentlyContinue
                if ($secApp) {
                    $secApp | Remove-AppxPackage -ErrorAction Stop
                    Write-Host "[OK] SecHealthUI (Windows Security app) removed"
                    $script:ok++
                } else {
                    Write-Host "[SKIP] SecHealthUI not found" -ForegroundColor Yellow
                    $script:skip++
                }
            } catch {
                Write-Host "[FAIL] SecHealthUI : $($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
            }
        } else {
            Write-Host "[SKIP] Appx module not available on this system" -ForegroundColor Yellow
            $script:skip++
        }

    } else {
        Write-Host "[SKIP] 删除类优化已取消/跳过 / Deletion-type optimizations skipped." -ForegroundColor Yellow
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 5 - Disable Security Center)" -ForegroundColor Cyan
    Write-Host " OK : $($script:ok)" -ForegroundColor Green
    Write-Host " FAIL : $($script:fail)" -ForegroundColor Red
    Write-Host " SKIP : $($script:skip)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：Windows Defender 已被禁用，重启后生效。" -ForegroundColor Yellow
    Write-Host "注册表策略值可经 5 -> 2 按 defender-policy-backup.json 快照恢复；" -ForegroundColor Yellow
    Write-Host "服务、计划任务和 SecHealthUI 无精确自动回滚，恢复前请检查相应状态。" -ForegroundColor Yellow

    Request-Restart
}
