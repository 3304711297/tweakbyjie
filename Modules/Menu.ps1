function Show-TweakMenu {
    # RunModules：非交互模式，逗号分隔的模块编号队列；为空则进入交互菜单
    param([string]$RunModules = '')
    $__queue = @($RunModules -split '[,，\s]+' | Where-Object { $_ })
    $__autoMode = ($RunModules -ne '')
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
                Write-Host ("[AUTO] 模块 {0} 不适用（{1}），已跳过。" -f $choice, $entry.Reason) -ForegroundColor Yellow
                $script:skip++
            } else {
                Write-Host ("[不适用] 模块 {0}：{1}" -f $choice, $entry.Reason) -ForegroundColor Red
                Write-Host "[提示] 该模块的前置条件未满足，其余模块不受影响，可继续选择。" -ForegroundColor Yellow
            }
            continue
        }
        # ======================= 分发（各 Part 实现位于 Modules/，执行内容不变） =======================
        switch ($choice) {
            '1'  { Invoke-RegistryModule }
            '2'  { Invoke-BcdAdvancedModule }
            '3'  { Invoke-TestModeEnableModule }
            '4'  { Invoke-TestModeDisableModule }
            '5'  { Invoke-DefenderModule }
            '6'  { Invoke-ServiceModule }
            '7'  { Invoke-PowerModule }
            '8'  { Invoke-NvmeModule }
            '9'  { Invoke-DeviceGuardModule }
            '10' { Invoke-VbsModule }
            '11' { Invoke-MpoModule }
            '12' { Invoke-GameQosModule }
        }
    } else {
    Write-Host "[ERROR] 无效输入：$choice 。请输入 0-12 / Invalid input. Enter 0-12." -ForegroundColor Red
}
}
}
