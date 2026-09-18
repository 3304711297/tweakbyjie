# Defender.ps1 - Part 5 关闭安全中心（策略写入 + 服务停用 + 可选删除类优化）
# 被 tweakbyjie.ps1 点源加载；策略值快照/恢复逻辑见 Modules/Backup.Defender.ps1

function Get-DefenderServiceRecord {
    param([Parameter(Mandatory = $true)][string]$Name)
    $filter = "Name='{0}'" -f $Name.Replace("'", "''")
    return Get-CimInstance -ClassName Win32_Service -Filter $filter -ErrorAction Stop | Select-Object -First 1
}

function Get-DefenderTamperProtectionState {
    try {
        $regKey = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features'
        if (-not (Test-Path -LiteralPath $regKey)) { return 'Unknown' }
        $props = Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue
        if ($null -eq $props -or $null -eq $props.TamperProtection) { return 'Unknown' }
        $val = [int]$props.TamperProtection
        if ($val -eq 5 -or $val -eq 1) { return 'Enabled' }
        if ($val -eq 0 -or $val -eq 4) { return 'Disabled' }
        return "Custom($val)"
    } catch {
        return 'Unknown'
    }
}

function Invoke-DefenderModule {
    param([string]$Action = '')

    Write-Host ""
    Write-Host "============ [Part 5] 关闭安全中心 / Disable Security Center ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [WARNING] 此操作将禁用 Windows Defender 实时保护及相关安全服务！" -ForegroundColor Yellow
    Write-Host " [WARNING] This will disable Windows Defender realtime protection and related services!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. 应用 Defender/SmartScreen 禁用策略并停用 WinDefend（高风险确认）"
    Write-Host "  1-delete. 在 1 的基础上执行删除类优化（计划任务/启动项/SecHealthUI；不可完整回滚）" -ForegroundColor Red
    Write-Host "  2. 按快照恢复 Defender 策略原始值（defender-policy-backup.json）"
    Write-Host "  0. 返回主菜单"

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定 Defender 子操作（1=apply，1-delete=apply+删除，2=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入选择并回车"
    }

    $deleteRequested = $false
    switch -Regex ($Action.ToLowerInvariant()) {
        '^(1|apply)$' { $pChoice = '1' }
        '^(1-delete|apply-delete)$' { $pChoice = '1'; $deleteRequested = $true }
        '^(2|restore|reset)$' { $pChoice = '2' }
        '^(0|status)$' { $pChoice = '0' }
        default {
            Write-Host "[FAIL] 无效 Defender 子操作：$Action（可用 0、1、1-delete、2）" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }

    if ($pChoice -eq '0') { Write-Host '[SKIP] 已取消，返回主菜单。' -ForegroundColor Yellow; $script:skip++; return $true }
    if ($pChoice -eq '2') {
        $result = Restore-DefenderPolicyBackup
        Request-Restart
        return $result
    }

    # 主禁用路径本身就是高风险操作；过去只有删除分支确认，导致普通 apply 可直接停用 Defender。
    if (-not (Test-HighRiskConfirmation '确定禁用 Defender 实时保护、相关策略和 WinDefend 服务吗？')) {
        Write-Host '[SKIP] Defender 主禁用已取消，未执行策略或服务修改。' -ForegroundColor Yellow
        return $false
    }
    if ($deleteRequested -and -not (Test-HighRiskConfirmation '确定继续执行 Defender 删除类优化吗？该部分没有完整自动回滚。')) {
        Write-Host '[SKIP] 删除类优化已取消；未执行删除类操作。' -ForegroundColor Yellow
        return $false
    }

    # 备份失败则阻止修改；快照一旦存在就保护首次原始状态，不允许覆盖。
    if (-not (Ensure-DefenderPolicyBackup)) { return $false }

    $tamperState = Get-DefenderTamperProtectionState
    if ($tamperState -eq 'Enabled') {
        Write-Host '[WARN] 检测到 Windows Defender 篡改防护 (Tamper Protection) 处于启用状态。' -ForegroundColor Yellow
        Write-Host '       根据 Microsoft 官方规范，篡改防护开启时某些注册表策略变更可能不会生效。' -ForegroundColor Yellow
        Write-Host '       注册表策略写入成功 ≠ Defender 有效状态已经关闭；如需彻底停用，建议先在安全中心手动关闭篡改防护。' -ForegroundColor Yellow
    }

    # --- 策略写入：任一写入失败就不继续停服务，并按原始快照回滚已写入的策略。 ---
    if (-not (Invoke-DefenderPolicyWrites)) {
        Write-Host '[FAIL] Defender 策略未完整写入，已阻止停用服务并尝试回滚策略。' -ForegroundColor Red
        if (-not (Restore-DefenderPolicyBackup)) {
            Write-Host '[FAIL] Defender 策略自动回滚未完全成功，请立即人工检查。' -ForegroundColor Red
        }
        return $false
    }

    # --- Stop Windows Defender Service ---
    Write-Host ""
    Write-Host "[Windows Defender Service]" -ForegroundColor Cyan
    try {
        $defenderSvc = Get-DefenderServiceRecord -Name 'WinDefend'
    } catch {
        Write-Host "[FAIL] 无法查询 Windows Defender Service：$($_.Exception.Message)；正在回滚策略" -ForegroundColor Red
        $script:fail++
        Restore-DefenderPolicyBackup | Out-Null
        return $false
    }
    if ($defenderSvc) {
        try {
            Stop-Service -Name "WinDefend" -Force -ErrorAction Stop
            Set-Service -Name "WinDefend" -StartupType Disabled -ErrorAction Stop
            if (-not (Verify-ServiceStartupType 'WinDefend' 'Disabled' 'Windows Defender Service')) {
                throw 'Windows Defender Service 启动类型回读未达到 Disabled'
            }
            Write-Host "[OK] Windows Defender Service stopped and disabled"
            $script:ok++
            $script:rebootRequired = $true
        } catch {
            Write-Host "[FAIL] Windows Defender Service : $($_.Exception.Message)；正在回滚策略" -ForegroundColor Red
            $script:fail++
            Restore-DefenderPolicyBackup | Out-Null
            return $false
        }
    } else {
        Write-Host "[SKIP] Windows Defender Service not found (already removed or not installed)" -ForegroundColor Yellow
        $script:skip++
    }

    # --- Optional deletion-type optimizations ---
    # 交互模式仍保留二次选择；非交互模式只有显式 1-delete 才能到达这里。
    $runDeletion = $deleteRequested
    if (-not $script:TweakNonInteractive -and -not $deleteRequested) {
        $runDeletion = Test-HighRiskConfirmation "是否执行删除类优化？（停止并禁用 Defender 服务、删除计划任务、移除安全中心界面；没有完整自动回滚）"
    }
    if ($runDeletion) {
        Write-Host ""
        Write-Host "[Defender Services: stop + disable]" -ForegroundColor Cyan
        $defenderServices = @(
            "WinDefend","WdNisSvc","WdNisDrv","WdBoot","WdFilter","wscsvc",
            "SgrmAgent","SgrmBroker","MsSecCore","MsSecFlt","MsSecWfp","whesvc",
            "webthreatdefsvc","webthreatdefusersvc","PlutonHsp2","PlutonHeci","Hsp"
        )
        $deletionStartFail = $script:fail
        $deletionOk = $true
        foreach ($svc in $defenderServices) {
            try {
                $svcObj = Get-DefenderServiceRecord -Name $svc
            } catch {
                Write-Host "[FAIL] 无法查询 Defender 服务 $svc：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                $deletionOk = $false
                break
            }
            if ($svcObj) {
                try {
                    Stop-Service -Name $svc -Force -ErrorAction Stop
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                    if (-not (Verify-ServiceStartupType $svc 'Disabled' "Service $svc")) {
                        throw "Service $svc 启动类型回读未达到 Disabled"
                    }
                    Write-Host "[OK] Service $svc stopped and disabled"
                    $script:ok++
                    $script:rebootRequired = $true
                } catch {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            } else {
                Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
                $script:skip++
            }
            if ($script:fail -gt $deletionStartFail) { $deletionOk = $false; break }
        }

        if ($deletionOk) {
            Write-Host ""
            Write-Host "[Defender Scheduled Tasks]" -ForegroundColor Cyan
            try {
                $defenderTasks = @(Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" -ErrorAction Stop)
            } catch {
                Write-Host "[FAIL] 无法查询 Defender 计划任务：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                $deletionOk = $false
                $defenderTasks = @()
            }
            if ($deletionOk -and $defenderTasks.Count -gt 0) {
                foreach ($task in $defenderTasks) {
                    try {
                        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                        Write-Host ("[OK] Task deleted: {0}{1}" -f $task.TaskPath, $task.TaskName)
                        $script:ok++
                        $script:rebootRequired = $true
                    } catch {
                        Write-Host ("[FAIL] Task {0}{1} : {2}" -f $task.TaskPath, $task.TaskName, $_.Exception.Message) -ForegroundColor Red
                        $script:fail++
                        $deletionOk = $false
                        break
                    }
                }
            } elseif ($deletionOk) {
                Write-Host "[SKIP] No Defender scheduled tasks found" -ForegroundColor Yellow
                $script:skip++
            }
        }
        if ($deletionOk) {
            Write-Host ""
            Write-Host "[Startup Entries]" -ForegroundColor Cyan
            foreach ($item in $script:defenderStartupValues) {
                try {
                    if (-not (Test-Path -LiteralPath $item.Path -PathType Container -ErrorAction Stop)) {
                        Write-Host ("[SKIP] Startup key not found: {0}" -f $item.Path) -ForegroundColor Yellow
                        $script:skip++
                        continue
                    }
                    $key = Get-Item -LiteralPath $item.Path -ErrorAction Stop
                    if ($key.GetValueNames() -contains $item.Name) {
                        Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -Force -ErrorAction Stop
                        Write-Host ("[OK] Startup entry removed: {0} -> {1}" -f $item.Path, $item.Name)
                        $script:ok++
                        $script:rebootRequired = $true
                    } else {
                        Write-Host ("[SKIP] Startup entry not found: {0} -> {1}" -f $item.Path, $item.Name) -ForegroundColor Yellow
                        $script:skip++
                    }
                } catch {
                    Write-Host ("[FAIL] Startup entry {0} -> {1} : {2}" -f $item.Path, $item.Name, $_.Exception.Message) -ForegroundColor Red
                    $script:fail++
                    $deletionOk = $false
                    break
                }
            }
        }

        if ($deletionOk) {
            Write-Host ""
            Write-Host "[Security Center UI (SecHealthUI)]" -ForegroundColor Cyan
            if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                Write-Host "[FAIL] Appx 模块不可用，无法确认 SecHealthUI 状态；已停止删除类优化。" -ForegroundColor Red
                $script:fail++
                $deletionOk = $false
            } else {
                try {
                    $secApp = @(Get-AppxPackage -Name "Microsoft.SecHealthUI" -ErrorAction Stop)
                    if ($secApp.Count -gt 0) {
                        $secApp | Remove-AppxPackage -ErrorAction Stop
                        Write-Host "[OK] SecHealthUI (Windows Security app) removed"
                        $script:ok++
                        $script:rebootRequired = $true
                    } else {
                        Write-Host "[SKIP] SecHealthUI not found" -ForegroundColor Yellow
                        $script:skip++
                    }
                } catch {
                    Write-Host "[FAIL] SecHealthUI 查询或删除失败：$($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                    $deletionOk = $false
                }
            }
        }
        if (-not $deletionOk) {
            Write-Host '[FAIL] Defender 删除类优化未完整完成；已停止后续删除，且该分支不提供完整自动回滚。' -ForegroundColor Red
        }
    } else {
        Write-Host "[SKIP] 删除类优化已取消/跳过。" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 5 - Disable Security Center)" -ForegroundColor Cyan
    Write-Host " OK : $($script:ok)" -ForegroundColor Green
    Write-Host " FAIL : $($script:fail)" -ForegroundColor Red
    Write-Host " SKIP : $($script:skip)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：Windows Defender 已被禁用，重启后生效。" -ForegroundColor Yellow
    Write-Host "策略值和删除类启动项可经 5 -> 2 按 defender-policy-backup.json 快照恢复；" -ForegroundColor Yellow
    Write-Host "计划任务、服务和 SecHealthUI 不在该 JSON 快照内，删除类操作仍需人工复核。" -ForegroundColor Yellow
    Request-Restart
    return ($script:fail -eq 0 -and (-not $runDeletion -or $deletionOk))
}
