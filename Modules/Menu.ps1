function Show-TweakMenu {
    # RunModules：模块编号队列；Actions 为严格的模块编号 -> 子操作映射。
    param([string]$RunModules = '', [hashtable]$Actions = @{}, [switch]$NonInteractive)
    $__queue = @($RunModules -split '[,，\s]+' | Where-Object { $_ })
    $__autoMode = ($RunModules -ne '')
    if ($NonInteractive -and -not $__autoMode) {
        throw '非交互菜单必须提供 -RunModule 队列，已拒绝回退到 Read-Host'
    }
    if ($NonInteractive -and $__autoMode) {
        $__required = @(Get-TweakActionRequiredModules)
        $__missing = @($__required | Where-Object { $_ -in $__queue -and -not $Actions.ContainsKey($_) })
        if ($__missing.Count -gt 0) {
            throw "非交互菜单缺少动作：$($__missing -join ',')"
        }
    }
# ============================ Menu ============================
# 启动预检（会话内只检测一次，结果缓存并写入会话日志）+ 按模块灰掉。
# 灰掉只发生在菜单层：不可用模块显示 [不适用] 且选择时被拒绝，不触碰任何执行函数。
$__preflight = Get-TweakPreflight
$__avail = Get-TweakModuleAvailability $__preflight
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows Game Optimization + BCDEdit - Menu Edition  v$($script:TweakVersion)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " 请选择执行模式 / Select an option:" -ForegroundColor Cyan
Write-Host "   0. 退出 / Exit" -ForegroundColor White
Write-Host ("   1. 核心游戏 / 系统性能优化（内部可分为核心游戏、系统行为、CPU 缓解）{0}" -f (Format-MenuAvailabilitySuffix '1' $__avail)) -ForegroundColor White
Write-Host ("   2. 高级 BCD / 计时器与启动安全（独立执行）{0}" -f (Format-MenuAvailabilitySuffix '2' $__avail)) -ForegroundColor White
Write-Host ("   3. 开启测试模式{0}" -f (Format-MenuAvailabilitySuffix '3' $__avail)) -ForegroundColor White
Write-Host ("   4. 关闭测试模式（保留 nointegritychecks）{0}" -f (Format-MenuAvailabilitySuffix '4' $__avail)) -ForegroundColor White
Write-Host ("   5. 关闭安全中心（Defender / SmartScreen）{0}" -f (Format-MenuAvailabilitySuffix '5' $__avail)) -ForegroundColor White
Write-Host ("   6. 服务优化（A/B 分组）{0}" -f (Format-MenuAvailabilitySuffix '6' $__avail)) -ForegroundColor White
Write-Host ("   7. 超性能电源计划{0}" -f (Format-MenuAvailabilitySuffix '7' $__avail)) -ForegroundColor White
Write-Host ("   8. 原生 NVMe 驱动{0}" -f (Format-MenuAvailabilitySuffix '8' $__avail)) -ForegroundColor White
Write-Host ("   9. 清除 Device Guard EFI 锁定{0}" -f (Format-MenuAvailabilitySuffix '9' $__avail)) -ForegroundColor White
Write-Host ("  10. 虚拟化 / VBS / Hyper-V 管理{0}" -f (Format-MenuAvailabilitySuffix '10' $__avail)) -ForegroundColor White
Write-Host ("  11. MPO 设置管理（独立排障）{0}" -f (Format-MenuAvailabilitySuffix '11' $__avail)) -ForegroundColor White
Write-Host ("  12. 竞技游戏网络 QoS 策略管理（DSCP 46 数据包优先）{0}" -f (Format-MenuAvailabilitySuffix '12' $__avail)) -ForegroundColor White
Write-Host ""
Write-Host "提示：一次运行可以连续执行多个模块；修改完成后统一选择是否重启。" -ForegroundColor Yellow
Write-Host " NOTE: Multiple modules can be run in one session; restart is deferred until you choose it." -ForegroundColor Yellow
Write-Host ""
while ($true) {
if ($__autoMode -and $__queue.Count -eq 0) {
    # 队列执行完毕后自动走退出流程（统一重启询问）
    $choice = '0'
} elseif ($__queue.Count -gt 0) {
    $choice = [string]($__queue | Select-Object -First 1)
    $__queue = @($__queue | Select-Object -Skip 1)
    Write-Host ""
    Write-Host ("[AUTO] 自动执行模块 " + $choice) -ForegroundColor Cyan
} else {
    $choice = Read-Host "请输入 0-12 并回车 (Enter 0-12)"
}

if ($choice -eq "0") {
    Invoke-FinalRestartPrompt
    break

    } elseif ($choice -match '^[1-9]$|^10$|^11$|^12$') {
        # 按模块前置条件灰掉：不可用模块在选择/队列执行时统一拒绝，不进入执行函数
        $entry = $__avail[$choice]
        if ($entry -and -not $entry.Available) {
            if ($__autoMode) {
                # 非交互调用者明确请求了该模块；前置条件不满足必须是失败，不能以 0 退出码伪装成成功。
                Write-Host ("[AUTO] 模块 {0} 不适用（{1}），已拒绝执行。" -f $choice, $entry.Reason) -ForegroundColor Red
                $script:fail++
                break
            } else {
                Write-Host ("[不适用] 模块 {0}：{1}" -f $choice, $entry.Reason) -ForegroundColor Red
                Write-Host "[提示] 该模块的前置条件未满足，其余模块不受影响，可继续选择。" -ForegroundColor Yellow
                continue
            }
        }
        # ======================= 分发（各 Part 实现位于 Modules/） =======================
        $__action = if ($Actions -and $Actions.ContainsKey($choice)) { [string]$Actions[$choice] } else { '' }
        $__beforeModuleFail = $script:fail
        $__moduleResult = switch ($choice) {
            '1'  { Invoke-RegistryModule -Action $__action }
            '2'  { Invoke-BcdAdvancedModule -Action $__action }
            '3'  { Invoke-TestModeEnableModule -Action $__action }
            '4'  { Invoke-TestModeDisableModule -Action $__action }
            '5'  { Invoke-DefenderModule -Action $__action }
            '6'  { Invoke-ServiceModule -Action $__action }
            '7'  { Invoke-PowerModule -Action $__action }
            '8'  { Invoke-NvmeModule -Action $__action }
            '9'  { Invoke-DeviceGuardModule -Action $__action }
            '10' { Invoke-VbsModule -Action $__action }
            '11' { Invoke-MpoModule -Action $__action }
            '12' { Invoke-GameQosModule -Action $__action }
        }
        if ($__autoMode -and ($script:fail -gt $__beforeModuleFail -or @($__moduleResult | Where-Object { $_ -is [bool] -and -not $_ }).Count -gt 0)) {
            Write-Host '[AUTO] 模块执行失败，已停止后续队列，避免在失败状态下继续写入。' -ForegroundColor Red
            break
        }
    } else {
    Write-Host "[ERROR] 无效输入：$choice 。请输入 0-12 / Invalid input. Enter 0-12." -ForegroundColor Red
}
}
}
