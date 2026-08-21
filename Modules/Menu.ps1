function Show-TweakMenu {
    # RunModules：非交互模式，逗号分隔的模块编号队列；为空则进入交互菜单
    param([string]$RunModules = '')
    $__queue = @($RunModules -split '[,，\s]+' | Where-Object { $_ })
    $__autoMode = ($RunModules -ne '')
# ============================ Menu ============================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows Game Optimization + BCDEdit - Menu Edition  v$($script:TweakVersion)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " 请选择执行模式 / Select an option:" -ForegroundColor Cyan
Write-Host "   0. 退出 / Exit" -ForegroundColor White
Write-Host "   1. 核心游戏 / 系统性能优化（内部可分为核心游戏、系统行为、CPU 缓解）" -ForegroundColor White
Write-Host "   2. 高级 BCD / 计时器与启动安全（独立执行）" -ForegroundColor White
Write-Host "   3. 开启测试模式" -ForegroundColor White
Write-Host "   4. 关闭测试模式（保留 nointegritychecks）" -ForegroundColor White
Write-Host "   5. 关闭安全中心（Defender / SmartScreen）" -ForegroundColor White
Write-Host "   6. 服务优化（A/B 分组）" -ForegroundColor White
Write-Host "   7. 超性能电源计划" -ForegroundColor White
Write-Host "   8. 原生 NVMe 驱动" -ForegroundColor White
Write-Host "   9. 清除 Device Guard EFI 锁定" -ForegroundColor White
Write-Host "  10. 虚拟化 / VBS / Hyper-V 管理" -ForegroundColor White
Write-Host "  11. MPO 设置管理（独立排障）" -ForegroundColor White
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
    $choice = Read-Host "请输入 0-11 并回车 (Enter 0-11)"
}

if ($choice -eq "0") {
    Invoke-FinalRestartPrompt
    break

    } elseif ($choice -eq "1") {
        # ======================= Part 1: 核心游戏 / 系统性能优化 =======================
        # 实现已迁移至 Modules/Registry.ps1（Invoke-RegistryModule）
        Invoke-RegistryModule

} elseif ($choice -eq "2") {
        # ======================= Part 2: 高级 BCD / 计时器与启动安全 =======================
        # 实现已迁移至 Modules/Bcd.ps1（Invoke-BcdAdvancedModule）
        Invoke-BcdAdvancedModule

} elseif ($choice -eq "3") {
        # ======================= Part 3: 开启测试模式 =======================
        # 实现已迁移至 Modules/Bcd.ps1（Invoke-TestModeEnableModule）
        Invoke-TestModeEnableModule

} elseif ($choice -eq "4") {
        # ======================= Part 4: 关闭测试模式 =======================
        # 实现已迁移至 Modules/Bcd.ps1（Invoke-TestModeDisableModule）
        Invoke-TestModeDisableModule

} elseif ($choice -eq "5") {
    # ======================= Part 5: 关闭安全中心 =======================
    # 实现已迁移至 Modules/Defender.ps1（Invoke-DefenderModule）：
    # 策略写入前自动快照原始值到 defender-policy-backup.json，子选项 2 可按快照恢复。
    Invoke-DefenderModule

} elseif ($choice -eq "6") {
        # ======================= Part 6: 优化服务项 =======================
        # 实现已迁移至 Modules/Service.ps1（Invoke-ServiceModule）
        Invoke-ServiceModule

} elseif ($choice -eq "7") {
        # ======================= Part 7: 超性能电源计划 =======================
        # 实现已迁移至 Modules/Power.ps1（Invoke-PowerModule）
        Invoke-PowerModule

    } elseif ($choice -eq "8") {
        # ======================= Part 8: 原生 NVMe 驱动配置 =======================
        # 实现已迁移至 Modules/Nvme.ps1（Invoke-NvmeModule）
        Invoke-NvmeModule

    } elseif ($choice -eq "9") {
        # ======================= Part 9: 清除 Device Guard EFI 锁定 =======================
        # 实现已迁移至 Modules/Virtualization.ps1（Invoke-DeviceGuardModule）
        Invoke-DeviceGuardModule

    } elseif ($choice -eq "10") {
        # ======================= Part 10: 虚拟化 / VBS / Hyper-V 管理 =======================
        # 实现已迁移至 Modules/Virtualization.ps1（Invoke-VbsModule）
        Invoke-VbsModule

    } elseif ($choice -eq "11") {
        # ======================= Part 11: MPO 设置管理 =======================
        # 实现已迁移至 Modules/Mpo.ps1（Invoke-MpoModule）
        Invoke-MpoModule

    } else {
    Write-Host "[ERROR] 无效输入：$choice 。请输入 0-11 / Invalid input. Enter 0-11." -ForegroundColor Red
}
}
}
