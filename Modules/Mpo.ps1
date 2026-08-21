# Mpo.ps1 - Part 11 MPO 设置管理（交互编排）
# 备份/恢复逻辑见 Modules/Backup.Mpo.ps1

function Invoke-MpoModule {

    # ======================= Part 11: MPO 设置管理 =======================
    # MPO（Multi-Plane Overlay，多平面叠加）让显卡用独立硬件平面合成画面，异常时
    # 会引起闪屏/黑屏/切屏卡顿（N 卡多屏与 Chromium 系应用高发）。本选项管理四个
    # 注册表值，三个方案互斥（切换方案时自动清除其他方案的值）：
    #   DisableMPO      (GraphicsDrivers) = 1：驱动层禁用（旧方法；Win11 24H2/25H2
    #                                     部分版本已失效；选项 1 会写入本值）
    #   OverlayTestMode (Dwm)            = 5：社区常用的 DWM 层禁用尝试
    #   DisableOverlays (GraphicsDrivers) = 1：更激进的社区排障尝试；个别 DX12 游戏
    #                                     或叠加层可能异常；须与其他值互斥
    #   OverlayMinFPS   (Dwm)            = 0：尝试避免低帧率时撤下 MPO，常用于排查
    #                                     G-Sync/FreeSync 视频播放卡顿
    # 验证：dxdiag -> 保存所有信息 -> 搜索 MPO，仅作辅助判断；最终结合实际应用测试。
    Write-Host ""
    Write-Host "============ [Part 11] MPO 设置管理 / MPO Settings ============" -ForegroundColor Cyan
    Write-Host ""

    $mpoValues = @($script:mpoManagedValues)

    Write-Host "  0. 查看当前 MPO 设置状态（只读：四个注册表值 + dxdiag 验证方法）" -ForegroundColor White
    Write-Host "  1. 禁用 MPO — 方案 A：OverlayTestMode=5 + DisableMPO=1（社区使用较广；" -ForegroundColor White
    Write-Host "     可能影响窗口化 VRR/视频呈现；自动清除方案 B/C 的值）" -ForegroundColor White
    Write-Host "  2. 禁用 MPO — 方案 B：DisableOverlays=1（更激进的社区排障方案；个别 DX12" -ForegroundColor White
    Write-Host "     游戏或叠加层可能异常，仅在方案 A 无效时测试；自动清除方案 A/C 的值）" -ForegroundColor White
    Write-Host "  3. 尝试保持 MPO — 方案 C：OverlayMinFPS=0（常用于 G-Sync/FreeSync 视频卡顿；" -ForegroundColor White
    Write-Host "     实际效果取决于系统和驱动；自动清除方案 A/B 的值）" -ForegroundColor White
    Write-Host "  4. 还原（优先恢复首次修改前备份；无备份时删除四个值恢复系统默认）" -ForegroundColor White
    $mChoice = Read-Host "请输入 0、1、2、3 或 4 并回车 (Enter 0, 1, 2, 3 or 4)"

    if ($mChoice -eq "0") {

        # 只读状态检查，不做任何修改
        Write-Host ""
        $mpoAny = $false
        foreach ($v in $mpoValues) {
            $item = Get-Item $v.Path -ErrorAction SilentlyContinue
            if ($item -and ($item.GetValueNames() -contains $v.Name)) {
                Write-Host ("注册表 {0,-16} = {1}  ({2})" -f $v.Name, $item.GetValue($v.Name), $v.Desc)
                $mpoAny = $true
            } else {
                Write-Host ("注册表 {0,-16} = <未设置（系统默认）>  ({1})" -f $v.Name, $v.Desc)
            }
        }

        Write-Host ""
        if ($mpoAny) {
            Write-Host "结论：存在手动 MPO 设置；选 11 -> 4 可优先恢复首次修改前状态" -ForegroundColor Yellow
        } else {
            Write-Host "结论：MPO 全部为系统默认状态（未做任何修改）" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "验证提示（辅助判断，需重启后检查；不代表所有应用的运行时状态）：" -ForegroundColor Cyan
        Write-Host "  Win+R 运行 dxdiag -> 保存所有信息 -> 打开保存的 txt 搜索 MPO" -ForegroundColor White
        Write-Host "  某些系统中 MPO 条目消失或 MaxPlanes 为 0，可能表示禁用；输出格式因版本/驱动而异" -ForegroundColor White
        Write-Host "  最终请结合浏览器/视频、多显示器、窗口化游戏、DX12、HDR/录屏和覆盖层实测" -ForegroundColor White

    } elseif (($mChoice -eq "1") -or ($mChoice -eq "2") -or ($mChoice -eq "3")) {

        $gdReg = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        $dwmReg = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
        $mpoChanged = $false

        if (Ensure-MpoBackup) {
            if ($mChoice -eq "1") {
                # 方案 A：社区使用较广的禁用组合
                Remove-RegDwordValue $gdReg "DisableOverlays" "清除方案 B DisableOverlays"
                Remove-RegDwordValue $dwmReg "OverlayMinFPS" "清除方案 C OverlayMinFPS"
                Set-RegDword $dwmReg "OverlayTestMode" 5 "OverlayTestMode = 5 (社区排障配置)"
                Set-RegDword $gdReg "DisableMPO" 1 "DisableMPO = 1 (社区排障配置)"
            } elseif ($mChoice -eq "2") {
                # 方案 B：更激进的社区排障配置；与其他值互斥
                Remove-RegDwordValue $dwmReg "OverlayTestMode" "清除方案 A OverlayTestMode"
                Remove-RegDwordValue $dwmReg "OverlayMinFPS" "清除方案 C OverlayMinFPS"
                Remove-RegDwordValue $gdReg "DisableMPO" "清除旧方法 DisableMPO"
                Set-RegDword $gdReg "DisableOverlays" 1 "DisableOverlays = 1 (社区排障配置)"
                Write-Host " [警告] 该方案可能影响 DX12 游戏或叠加层，仅建议在方案 A 无效时测试" -ForegroundColor Yellow
            } else {
                # 方案 C：尝试避免低帧率时撤下 MPO；实际效果取决于系统和驱动
                Remove-RegDwordValue $dwmReg "OverlayTestMode" "清除方案 A OverlayTestMode"
                Remove-RegDwordValue $gdReg "DisableOverlays" "清除方案 B DisableOverlays"
                Remove-RegDwordValue $gdReg "DisableMPO" "清除旧方法 DisableMPO"
                Set-RegDword $dwmReg "OverlayMinFPS" 0 "OverlayMinFPS = 0 (社区排障配置)"
            }
            $mpoChanged = $true
            Write-Host " [提示] 这些是未公开的社区排障配置，不是微软或显卡厂商保证的稳定 API" -ForegroundColor Yellow
        } else {
            Write-Host "[ABORTED] 备份不可用，未修改 MPO，也不会自动重启" -ForegroundColor Red
        }

        # Summary
        $schemeLabel = $(if ($mChoice -eq "1") { "Disable (Scheme A: OverlayTestMode+DisableMPO)" } elseif ($mChoice -eq "2") { "Disable (Scheme B: DisableOverlays)" } else { "Keep MPO (Scheme C: OverlayMinFPS)" })
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 11 - MPO $schemeLabel)" -ForegroundColor Cyan
        Write-Host " OK : $script:ok" -ForegroundColor Green
        Write-Host " FAIL : $script:fail" -ForegroundColor Red
        Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " 重启后可用 dxdiag -> 保存所有信息 -> 搜索 MPO 作辅助判断；最终请结合实际应用测试" -ForegroundColor Yellow
        Write-Host " 原始状态备份：$script:mpoBackupFile；选 11 -> 4 可优先恢复首次修改前状态" -ForegroundColor Yellow

        if ($mpoChanged) { Request-Restart }

    } elseif ($mChoice -eq "4") {

        # 还原：优先恢复首次修改前状态；没有备份时才删除全部值
        Restore-MpoBackup

        # Summary
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 11 - MPO Restore)" -ForegroundColor Cyan
        Write-Host " OK : $script:ok" -ForegroundColor Green
        Write-Host " FAIL : $script:fail" -ForegroundColor Red
        Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        if (Test-Path $script:mpoBackupFile) {
            Write-Host " 重启后 MPO 恢复首次修改前状态；备份文件保留在 $script:mpoBackupFile" -ForegroundColor Yellow
        } else {
            Write-Host " 重启后 MPO 恢复系统默认（叠加平面按系统策略自动管理）" -ForegroundColor Yellow
        }

        Request-Restart

    } else {
        Write-Host "[ERROR] 无效输入：$mChoice 。请输入 0、1、2、3 或 4 / Invalid input. Enter 0, 1, 2, 3 or 4." -ForegroundColor Red
    }
}
