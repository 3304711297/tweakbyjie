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
    Write-Host ""; Write-Host "============ [Part 2] 高级 BCD / Advanced BCD ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  0. 查看当前高级 BCD 状态（只读）" -ForegroundColor White
    Write-Host "  1. 应用高级计时器配置（useplatformclock / useplatformtick / disabledynamictick / tscsyncpolicy）" -ForegroundColor White
    Write-Host "  2. 恢复高级计时器修改前状态" -ForegroundColor White
    Write-Host "  3. 应用启动安全高级项（NX AlwaysOff / TPM Boot Entropy ForceDisable / nointegritychecks）" -ForegroundColor Yellow
    Write-Host "  4. 恢复启动安全高级项到修改前状态" -ForegroundColor White
    $bChoice=Read-Host "请输入 0、1、2、3 或 4 并回车"
    $timerValues=@('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy'); $securityValues=@('nx','tpmbootentropy','nointegritychecks'); $allAdvancedValues=@($script:bcdManagedValues)
    if($bChoice -eq '0'){
        $enumOut=(& bcdedit.exe /enum '{current}' 2>$null)-join "`n"; foreach($name in $allAdvancedValues){$pattern='(?m)^\s*'+[regex]::Escape($name)+'\s+([^\r\n]+)';if($enumOut -match $pattern){Write-Host ("bcdedit {0,-22} = {1}"-f $name,$Matches[1].Trim())}else{Write-Host ("bcdedit {0,-22} = <未设置（系统默认）>"-f $name)}}; if(Test-Path $script:bcdBackupFile){Write-Host "BCD 备份：$script:bcdBackupFile" -ForegroundColor Yellow}
    } elseif($bChoice -eq '1'){
        if(Ensure-BcdBackup $allAdvancedValues){Invoke-BcdEdit "/set useplatformclock no" "Use Platform Clock Off";Invoke-BcdEdit "/set useplatformtick no" "Use Platform Tick Off";Invoke-BcdEdit "/set disabledynamictick yes" "Disable Dynamic Tick";Invoke-BcdEdit "/set tscsyncpolicy Enhanced" "TSC Sync Policy Enhanced";Write-Host "[提示] BCD 计时器项属于高级/调试用途，效果依硬件与 Windows 版本而异。" -ForegroundColor Yellow;Verify-BcdValue 'useplatformclock' 'No' 'useplatformclock'|Out-Null;Verify-BcdValue 'useplatformtick' 'No' 'useplatformtick'|Out-Null;Verify-BcdValue 'disabledynamictick' 'Yes' 'disabledynamictick'|Out-Null;Verify-BcdValue 'tscsyncpolicy' 'Enhanced' 'tscsyncpolicy'|Out-Null}
    } elseif($bChoice -eq '2'){Restore-BcdBackup $timerValues
    } elseif($bChoice -eq '3'){Write-Host '[WARNING] 启动安全高级项会降低系统安全边界。' -ForegroundColor Yellow;if(Ensure-BcdBackup $allAdvancedValues){Invoke-BcdEdit "/set nx AlwaysOff" "NX (DEP) AlwaysOff";Invoke-BcdEdit "/set tpmbootentropy ForceDisable" "TPM Boot Entropy Disabled";Invoke-BcdEdit "/set nointegritychecks on" "Driver Integrity Checks Disabled";Verify-BcdValue 'nx' 'AlwaysOff' 'nx'|Out-Null;Verify-BcdValue 'tpmbootentropy' 'ForceDisable' 'tpmbootentropy'|Out-Null;Verify-BcdValue 'nointegritychecks' 'Yes' 'nointegritychecks'|Out-Null}
    } elseif($bChoice -eq '4'){Restore-BcdBackup $securityValues
    } else {Write-Host "[ERROR] 无效输入：$bChoice 。请输入 0、1、2、3 或 4" -ForegroundColor Red}
    Write-Host "Finished (Part 2 - Advanced BCD)" -ForegroundColor Cyan; Write-Host " OK : $ok  FAIL : $fail  SKIP : $skip"; Request-Restart

} elseif ($choice -eq "3") {

    # ======================= Part 3: 开启测试模式 =======================
    # 独立步骤：开启测试模式 / Enable Test Mode (bcdedit)
    Write-Host ""
    Write-Host "============ [Part 3] 开启测试模式 / Enable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""

    Invoke-BcdEdit "/set testsigning on" "bcdedit /set testsigning on"
    Invoke-BcdEdit "/debug on" "bcdedit /debug on"
    Invoke-BcdEdit "/dbgsettings local" "bcdedit /dbgsettings local"
    Invoke-BcdEdit "/set nointegritychecks on" "bcdedit /set nointegritychecks on"

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 3 - Enable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：开启测试模式后桌面右下角会显示「测试模式」水印，属正常现象。" -ForegroundColor Yellow
    Write-Host "如需关闭测试模式，可运行: bcdedit /set testsigning off" -ForegroundColor Yellow

    Request-Restart

} elseif ($choice -eq "4") {

    # ======================= Part 4: 关闭测试模式 =======================
    # 独立步骤：关闭测试模式 / Disable Test Mode（保留 nointegritychecks）
    Write-Host ""
    Write-Host "============ [Part 4] 关闭测试模式 / Disable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：此操作通过删除 testsigning 和 debug 启动项来关闭测试模式，保留 nointegritychecks。" -ForegroundColor Yellow
    Write-Host ""

    Invoke-BcdEdit "/deletevalue testsigning" "bcdedit /deletevalue testsigning"
    Invoke-BcdEdit "/deletevalue debug" "bcdedit /deletevalue debug"

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 4 - Disable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host '提示：测试模式已关闭，桌面右下角的"测试模式"水印将在重启后消失。' -ForegroundColor Yellow
    Write-Host "如需重新开启测试模式，可运行选项 3。" -ForegroundColor Yellow

    Request-Restart

} elseif ($choice -eq "5") {
    # ======================= Part 5: 关闭安全中心 =======================
    # 实现已迁移至 Modules/Defender.ps1（Invoke-DefenderModule）：
    # 策略写入前自动快照原始值到 defender-policy-backup.json，子选项 2 可按快照恢复。
    Invoke-DefenderModule

} elseif ($choice -eq "6") {

    # ======================= Part 6: 优化服务项 =======================
    # 独立步骤：禁用可安全禁用的服务 + 将 Xbox / 蓝牙 / 嵌入模式服务恢复为手动
    Write-Host ""
    Write-Host "============ [Part 6] 优化服务项继续工作 / Service Optimization ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 执行服务优化（A+B 两组共 30 个服务全部处理，另将 7 个服务改为 Manual）" -ForegroundColor White
    Write-Host "  2. 按 service-backup.json 恢复目标服务原始启动类型" -ForegroundColor White
    $serviceChoice = Read-Host "请输入 1 或 2 并回车"
    if ($serviceChoice -eq '2') {
        Restore-ServiceBackup | Out-Null
        Write-Host "[提示] 服务运行状态不强制恢复；如需立即应用启动类型，请重启。" -ForegroundColor Yellow
        Request-Restart
    } elseif ($serviceChoice -eq '1') {

    # 1) Disable service groups
    # A：通常可在不需要对应功能时禁用
    Write-Host "[Service Group A: 通常可禁用 / stop + disable]" -ForegroundColor Cyan
    $groupAServices = @(
        "DialogBlockingService","TrkWks","AppVClient","MsKeyboardFilter",
        "NetTcpPortSharing","CscService","ssh-agent","RemoteRegistry",
        "RemoteAccess","SensorDataService","SensrSvc","shpamsvc",
        "UevAgentService","WalletService","wisvc","WSAIFabricSvc",
        "dmwappushservice","DusmSvc","tzautoupdate","edgeupdate","edgeupdatem"
    )

    # B：按需禁用，可能影响诊断、兼容性、打印、搜索或预读功能
    Write-Host "[Service Group B: 按需禁用 / stop + disable]" -ForegroundColor Cyan
    $groupBServices = @(
        "DPS","WdiServiceHost","WdiSystemHost","diagsvc",
        "PhoneSvc","PcaSvc","Spooler","WSearch","SysMain"
    )

    $disableServices = @($groupAServices + $groupBServices)
    $manualServices = @(
        "XboxGipSvc","XblAuthManager","XboxNetApiSvc","XblGameSave","bthserv","embeddedmode","BITS"
    )
    $allServiceNames = @($disableServices + $manualServices)
    if (-not (Ensure-ServiceBackup $allServiceNames)) {
        Write-Host "[ABORTED] 服务备份不可用，未修改服务" -ForegroundColor Red
    } else {
    foreach ($svc in $disableServices) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            try {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                Write-Host "[OK] Service $svc stopped and disabled"
                $ok++
            } catch {
                & sc.exe config $svc start= disabled *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Service $svc disabled (stop rejected: protected service)"
                    $ok++
                } else {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            }
        } else {
            Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
            $skip++
        }
    }

    # 2) Set Xbox / Bluetooth / Embedded / BITS services to Manual
    Write-Host ""
    Write-Host "[Manual Services: Xbox / Bluetooth / Embedded / BITS]" -ForegroundColor Cyan
    foreach ($svc in $manualServices) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            try {
                Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
                Write-Host "[OK] Service $svc StartupType = Manual"
                $ok++
            } catch {
                & sc.exe config $svc start= demand *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Service $svc StartupType = Manual (sc.exe)"
                    $ok++
                } else {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            }
        } else {
            Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
            $skip++
        }
    }

    Write-Host ""
    Write-Host "[Post-Apply Verification / 服务启动类型验证]" -ForegroundColor Cyan
    foreach ($svc in $groupAServices) {
        Verify-ServiceStartupType $svc "Disabled" "Group A / $svc" | Out-Null
    }
    foreach ($svc in $groupBServices) {
        Verify-ServiceStartupType $svc "Disabled" "Group B / $svc" | Out-Null
    }
    foreach ($svc in $manualServices) {
        Verify-ServiceStartupType $svc "Manual" $svc | Out-Null
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 6 - Service Optimization)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    Request-Restart
    }
    } else {
        Write-Host "[ERROR] 无效输入：$serviceChoice 。请输入 1 或 2" -ForegroundColor Red
    }

} elseif ($choice -eq "7") {

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
            $fail++
        } else {

            # 1) Backup current active scheme (keep the earliest backup)
            if (Test-Path $backupFile) {
                Write-Host "[SKIP] 备份文件已存在，不覆盖（保护最初的原计划备份）: $backupFile" -ForegroundColor Yellow
                $skip++
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
                    $ok++
                } catch {
                    Write-Host "[FAIL] 备份当前电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
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
                    Write-Host "[OK] 超性能电源计划已导入并应用 ($newGuid)"
                    $ok++
                    $script:rebootRequired = $true
                    Invoke-PowerPlanDedupe
                } catch {
                    Write-Host "[FAIL] 导入/应用超性能电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            } else {
                Write-Host "[SKIP] 备份失败，为安全起见跳过应用超性能计划" -ForegroundColor Yellow
                $skip++
            }
        }

    } elseif ($pChoice -eq "2") {

        # Restore previously backed-up scheme
        if (-not (Test-Path $backupFile)) {
            Write-Host "[FAIL] 未找到备份文件 power-backup.pow（请先执行子选项 1 生成备份）" -ForegroundColor Red
            $fail++
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
                $ok++
                $script:rebootRequired = $true
                Invoke-PowerPlanDedupe
            } catch {
                Write-Host "[FAIL] 恢复备份的电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                $fail++
            }
        }

    } else {
        Write-Host "[ERROR] 无效输入：$pChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 7 - Ultimate Performance Power Plan)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：可用 powercfg /getactivescheme 查看当前电源计划；" -ForegroundColor Yellow
    Write-Host "如需恢复原计划，再次运行本脚本并选择 7 -> 2。" -ForegroundColor Yellow

    Request-Restart

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
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
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
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
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

 } else {
    Write-Host "[ERROR] 无效输入：$choice 。请输入 0-11 / Invalid input. Enter 0-11." -ForegroundColor Red
}
}
}
