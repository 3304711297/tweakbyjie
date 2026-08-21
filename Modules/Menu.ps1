function Show-TweakMenu {
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
$choice = Read-Host "请输入 0-11 并回车 (Enter 0-11)"

if ($choice -eq "0") {
    Invoke-FinalRestartPrompt
    break

} elseif ($choice -eq "1") {

    Write-Host ""; Write-Host "============ [Part 1] 核心游戏 / 系统性能优化 ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  1. 核心游戏优化（GameDVR / GameBar / Multimedia / Win32PrioritySeparation / HAGS / Games Task / Game Mode / ActivationType）" -ForegroundColor White
    Write-Host "  2. 系统行为优化（Search / Prefetch / Memory Compression / NTFS 8.3 / TRIM / Visual Effects）" -ForegroundColor White
    Write-Host "  3. CPU 安全缓解调整（FeatureSettingsOverride / Mask；修改前自动备份，可恢复）" -ForegroundColor Yellow
    Write-Host "  0. 返回主菜单" -ForegroundColor White
    $coreChoice = Read-Host "请输入 0、1、2 或 3 并回车"

    if ($coreChoice -eq '1') {
        # 01 GameDVR
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 "AppCaptureEnabled"
        Set-RegDword "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 "GameDVR_Enabled"

        # 02 ActivationType - mandatory.
        $activationReg = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.Gamebar.PresenceServer.Internal.PresenceWriter'
        $taskName = $null
        try {
            & reg.exe ADD $activationReg /v ActivationType /t REG_DWORD /d 0x00000000 /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "Administrator access denied" }
            Write-Host "[OK] ActivationType = 0"
            $ok++
            $script:rebootRequired = $true
        } catch {
            try {
                $taskName = "WindowsGameOpt_ActivationType_" + [guid]::NewGuid().ToString("N")
                $cmd = 'reg.exe ADD "' + $activationReg + '" /v ActivationType /t REG_DWORD /d 0x00000000 /f'
                $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $cmd"
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
                Start-ScheduledTask -TaskName $taskName
                Start-Sleep -Seconds 2
                $check = & reg.exe QUERY $activationReg /v ActivationType 2>$null
                if ($check -match '0x0+\s*$') {
                    Write-Host "[OK] ActivationType = 0 (SYSTEM)"
                    $ok++
                    $script:rebootRequired = $true
                } else { throw "SYSTEM retry did not verify ActivationType=0" }
            } catch {
                Write-Host "[FAIL] ActivationType = 0 : protected registry key rejected the change" -ForegroundColor Red
                Write-Host " Other core optimizations will continue." -ForegroundColor Yellow
                $fail++
            } finally {
                if ($taskName) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
            }
        }

        # 03 GameBar
        Set-RegDword "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0 "UseNexusForGameBarEnabled"
        # 04 Multimedia
        Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "0xFFFFFFFF" "NetworkThrottlingIndex"
        Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 10 "SystemResponsiveness"
        # 05 CPU priority
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation (0x26)"
        # 08 HAGS
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS"
        # 09 Games task
        $games = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        Set-RegDword $games "Affinity" 0 "Games Affinity"
        Set-RegString $games "Background Only" "False" "Games Background Only"
        Set-RegDword $games "Clock Rate" 10000 "Games Clock Rate"
        Set-RegDword $games "GPU Priority" 8 "Games GPU Priority"
        Set-RegDword $games "Priority" 6 "Games Priority"
        Set-RegString $games "Scheduling Category" "High" "Games Scheduling Category"
        Set-RegString $games "SFIO Priority" "High" "Games SFIO Priority"
        # 12 Game Mode
        Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 0 "AutoGameModeEnabled"
        Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0 "AllowAutoGameMode"

        Write-Host ""; Write-Host "[Post-Apply Verification / 核心游戏优化验证]" -ForegroundColor Cyan
        Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation" | Out-Null
        Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS" | Out-Null

    } elseif ($coreChoice -eq '2') {
        # 06 Search
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 "BingSearchEnabled"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "AllowSearchToUseLocation" 0 "AllowSearchToUseLocation"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0 "CortanaConsent"
        # 10 Prefetch
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher"
        # 11 NTFS
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisable8dot3NameCreation" 1 "NtfsDisable8dot3NameCreation"
        # 13 Memory Compression
        Write-Host ""; Write-Host "[Memory Compression]" -ForegroundColor Cyan
        try { Disable-MMAgent -mc -ErrorAction Stop; Write-Host "[OK] Memory Compression disabled"; $ok++; $script:rebootRequired=$true }
        catch { Write-Host "[FAIL] Memory Compression : $($_.Exception.Message)" -ForegroundColor Red; $fail++ }
        # 14 TRIM
        Write-Host ""; Write-Host "[TRIM]" -ForegroundColor Cyan
        try {
            $trimOut = fsutil.exe behavior set DisableDeleteNotify 0 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Host "[OK] NTFS TRIM enabled"; $ok++ }
            else { Write-Host "[FAIL] TRIM : fsutil exit code $LASTEXITCODE" -ForegroundColor Red; if($trimOut){Write-Host ($trimOut -join [Environment]::NewLine) -ForegroundColor DarkYellow}; $fail++ }
        } catch { Write-Host "[FAIL] TRIM : $($_.Exception.Message)" -ForegroundColor Red; $fail++ }

        # Visual Effects
        Write-Host ""; Write-Host "[Visual Effects 自定义 / Custom]" -ForegroundColor Cyan
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 3 "VisualFXSetting = 3 (自定义)"
        Set-RegString "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "平滑屏幕字体边缘 ON"
        Set-RegDword "HKCU:\Control Panel\Desktop" "FontSmoothingType" 2 "Font Smoothing = ClearType"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 1 "任务栏动画 ON"
        Set-RegBinary "HKCU:\Control Panel\Desktop" "UserPreferencesMask" "9012018010000000" "动画/淡入淡出/阴影全关"
        Set-RegString "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "最大/最小化动画 OFF"
        Set-RegString "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "拖动显示窗口内容 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" 0 "半透明选择框 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" 0 "图标标签阴影 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "IconsOnly" 1 "缩略图 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\DWM" "AlwaysHibernateThumbnails" 0 "任务栏缩略图缓存 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 "透明效果 OFF"
        Set-RegDword "HKCU:\Control Panel\Accessibility" "DynamicScrollbars" 1 "始终显示滚动条 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "AnimationEffects" 0 "动画效果(辅助功能) OFF"
        Set-RegDword "HKCU:\Control Panel\Accessibility" "MessageDuration" 5 "通知自动关闭时长 = 5 秒"
        $script:rebootRequired = $true
        Write-Host "视觉效果为 HKCU 设置，注销 / 重启（或重启资源管理器）后完全生效" -ForegroundColor Yellow

        Write-Host ""; Write-Host "[Post-Apply Verification / 系统行为优化验证]" -ForegroundColor Cyan
        Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher" | Out-Null
        Verify-MemoryCompressionDisabled | Out-Null
        Verify-TrimEnabled | Out-Null

    } elseif ($coreChoice -eq '3') {
        Write-Host ""; Write-Host "[CPU 安全缓解调整 / Meltdown-Spectre Mitigation]" -ForegroundColor Yellow
        Write-Host "目标值 FeatureSettingsOverride=3 / FeatureSettingsOverrideMask=3 会关闭相关缓解；仅在明确了解安全影响时使用。" -ForegroundColor Yellow
        Write-Host "  1. 查看当前值" -ForegroundColor White
        Write-Host "  2. 应用 3 / 3（修改前自动备份）" -ForegroundColor Yellow
        Write-Host "  3. 按备份恢复" -ForegroundColor White
        $mChoice = Read-Host "请输入 1、2 或 3 并回车"
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        if ($mChoice -eq '1') {
            $item=Get-Item $mmPath -ErrorAction SilentlyContinue
            foreach($n in @('FeatureSettingsOverride','FeatureSettingsOverrideMask')){
                if($item -and ($item.GetValueNames()-contains $n)){Write-Host ("{0} = {1}" -f $n,$item.GetValue($n))}else{Write-Host ("{0} = <未设置（系统默认）>" -f $n)}}
        } elseif ($mChoice -eq '2') {
            if (Ensure-SecurityMitigationBackup) {
                Set-RegDword $mmPath "FeatureSettingsOverride" 3 "FeatureSettingsOverride = 3"
                Set-RegDword $mmPath "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask = 3"
                Verify-RegDword $mmPath "FeatureSettingsOverride" 3 "FeatureSettingsOverride" | Out-Null
                Verify-RegDword $mmPath "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask" | Out-Null
            }
        } elseif ($mChoice -eq '3') {
            Restore-SecurityMitigationBackup
        } else { Write-Host "[ERROR] 无效输入：$mChoice 。" -ForegroundColor Red }
    } elseif ($coreChoice -eq '0') {
        Write-Host "[返回] 已返回主菜单。" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] 无效输入：$coreChoice 。请输入 0、1、2 或 3" -ForegroundColor Red
    }

    if ($coreChoice -ne '0') {
        Write-Host ""; Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 1 - Core / System Optimization)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Request-Restart
    }

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

    # ======================= Part 8: Native NVMe Driver =======================
    # Preferred path: ViVeTool feature IDs 60786016 + 48433719.
    # Legacy registry overrides are retained only for compatibility/inspection and
    # are no longer treated as proof that the native driver is active.
    Write-Host ""
    Write-Host "============ [Part 8] 原生 NVMe 驱动 / Native NVMe Driver (nvmedisk.sys) ============" -ForegroundColor Cyan
    Write-Host ""

    $cvKey = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildNum = [int]($cvKey.GetValue('CurrentBuildNumber'))
    $dispVer = [string]($cvKey.GetValue('DisplayVersion'))
    $nvmeDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'NVMe' })
    $sbGuid = '{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}'
    $fmPath = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
    $legacyIds = @('735209102', '1853569164', '156965516')
    $viVe = Find-ViVeTool

    Write-Host ("系统版本 : $dispVer (build $buildNum)")
    Write-Host ("NVMe 磁盘 : " + $(if ($nvmeDisks.Count -gt 0) { "检测到 $($nvmeDisks.Count) 块" } else { "未检测到" }))
    Write-Host ("ViVeTool : " + $(if ($viVe) { $viVe } else { "未找到" }))
    Write-Host ""

    Write-Host "  0. 查看当前状态（Feature / SafeBoot / Legacy Override / nvmedisk 实际状态）" -ForegroundColor White
    Write-Host "  1. 启用 Native NVMe（ViVeTool 60786016 + 48433719）" -ForegroundColor White
    Write-Host "  2. 还原到启用前快照" -ForegroundColor White
    $nChoice = Read-Host "请输入 0、1 或 2 并回车"

    if ($nChoice -eq '0') {

        if ($viVe) {
            $cfg = Test-NativeNvmeConfigured $viVe
            Write-Host "ViVeTool 60786016 : $($cfg.Feature60786016)"
            Write-Host "ViVeTool 48433719 : $($cfg.Feature48433719)"
        } else {
            Write-Host "ViVeTool 60786016 : <无法查询>"
            Write-Host "ViVeTool 48433719 : <无法查询>"
        }

        $fmItem0 = Get-Item $fmPath -ErrorAction SilentlyContinue
        $legacyText = @()
        foreach ($id in $legacyIds) {
            if ($fmItem0 -and ($fmItem0.GetValueNames() -contains $id)) {
                $kind = $fmItem0.GetValueKind($id).ToString()
                $value = $fmItem0.GetValue($id)
                $legacyText += "$id=$value（$kind）"
            } else {
                $legacyText += "$id=未写入"
            }
        }
        Write-Host ("Legacy Feature Override : " + ($legacyText -join "  "))

        foreach ($mode in @('Minimal','Network')) {
            $sbPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
            if (Test-Path $sbPath) {
                $item = Get-Item $sbPath -ErrorAction SilentlyContinue
                $defaultValue = if ($item -and ($item.GetValueNames() -contains '')) { $item.GetValue('') } else { '<默认值缺失>' }
                Write-Host ("SafeBoot {0} : 已配置，Default={1}" -f $mode, $defaultValue)
            } else {
                Write-Host ("SafeBoot {0} : 未配置" -f $mode)
            }
        }

        $effective = Test-NativeNvmeEffective
        Write-Host ("nvmedisk.sys 文件 : " + $(if ($effective.FileExists) { "存在" } else { "不存在" }))
        Write-Host ("nvmedisk 驱动状态 : $($effective.State)")

        if ($effective.State -eq 'Running') {
            Write-Host "[EFFECTIVE] Native NVMe 已实际生效，当前 nvmedisk 驱动正在运行。" -ForegroundColor Green
        } elseif ($viVe -and (Test-NativeNvmeConfigured $viVe).BothEnabled) {
            Write-Host "[CONFIGURED] 两个 Feature 已启用，但当前尚未确认 nvmedisk 实际运行；请重启后再次执行 8 -> 0。" -ForegroundColor Yellow
        } elseif ($effective.FileExists) {
            Write-Host "[NOT EFFECTIVE] 系统存在 nvmedisk.sys，但当前未确认由它运行。" -ForegroundColor Yellow
        } else {
            Write-Host "[NOT ENABLED] 当前未确认 Native NVMe 生效。" -ForegroundColor Yellow
        }

    } elseif ($nChoice -eq '1') {

        if ($nvmeDisks.Count -eq 0) {
            Write-Host "[SKIP] 未检测到 NVMe 磁盘，本项无作用，不修改。" -ForegroundColor Yellow
        } elseif ($buildNum -lt 26200) {
            Write-Host "[ABORTED] build $buildNum 低于 26200；此模块仅针对 Windows 11 25H2+（26200+）。" -ForegroundColor Red
        } elseif (-not $viVe) {
            Write-Host "[ABORTED] 未找到 ViVeTool.exe。" -ForegroundColor Red
            Write-Host "请从官方 ViVeTool 发布页获取与系统架构匹配的版本，并将 ViVeTool.exe 放在本脚本目录或加入 PATH。" -ForegroundColor Yellow
        } elseif (-not (Ensure-NvmeBackup $sbGuid $viVe $fmPath)) {
            Write-Host "[ABORTED] Native NVMe 备份不可用，未执行修改。" -ForegroundColor Red
        } else {

            Write-Host ""
            Write-Host "[1/3] 启用 Native NVMe Feature：60786016 + 48433719" -ForegroundColor Cyan
            & $viVe /enable /id:60786016,48433719 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[FAIL] ViVeTool 启用 Feature 失败，未继续修改 SafeBoot。" -ForegroundColor Red
                $fail++
            } else {
                $cfgAfter = Test-NativeNvmeConfigured $viVe
                if (-not $cfgAfter.BothEnabled) {
                    Write-Host "[WARN] ViVeTool 命令完成，但查询不到两个 Feature 都为 Enabled；停止后续修改。" -ForegroundColor Yellow
                    $fail++
                } else {
                    Write-Host "[OK] 60786016 + 48433719 = Enabled" -ForegroundColor Green
                    $ok += 2
                    $script:rebootRequired = $true

                    Write-Host ""
                    Write-Host "[2/3] SafeBoot NVMe 加固" -ForegroundColor Cyan
                    $safeBootOk = $true
                    foreach ($mode in @('Minimal','Network')) {
                        $sbReg = Convert-RegExePath "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
                        & reg.exe ADD $sbReg /ve /t REG_SZ /d "Storage Disks" /f *> $null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[OK] SafeBoot $mode = Storage Disks"
                            $script:ok++
                        } else {
                            Write-Host "[FAIL] SafeBoot $mode : reg.exe exit code $LASTEXITCODE" -ForegroundColor Red
                            $script:fail++
                            $safeBootOk = $false
                        }
                    }

                    if (-not $safeBootOk) {
                        Write-Host "[FAIL] SafeBoot 配置未完整完成，正在按启用前 Version 3 快照回滚。" -ForegroundColor Red
                        Restore-NvmeSafeBootBackup $sbGuid $viVe $fmPath | Out-Null
                    } else {
                        Write-Host ""
                        Write-Host "[3/3] Legacy Override 兼容说明" -ForegroundColor Cyan
                        Write-Host "[INFO] 保留现有 735209102 / 1853569164 / 156965516，不再自动写入或删除它们。" -ForegroundColor Yellow
                        Write-Host "[INFO] 这些旧值仍可在 8 -> 0 中查看，但不再作为 Native NVMe 已生效的判断依据。" -ForegroundColor Yellow

                        Write-Host ""
                        Write-Host "配置已完成，但必须重启后才能确认实际驱动。" -ForegroundColor Yellow
                        Write-Host "重启后执行：8 -> 0" -ForegroundColor Yellow
                        Write-Host "真正成功条件：nvmedisk 驱动状态 = Running。" -ForegroundColor Yellow
                        Request-Restart
                    }
                }
            }
        }

    } elseif ($nChoice -eq '2') {

        if (-not $viVe) {
            Write-Host "[ABORTED] 未找到 ViVeTool.exe，无法精确恢复 Feature 状态。" -ForegroundColor Red
            Write-Host "请将与启用时相同的 ViVeTool.exe 放回脚本目录或 PATH，再执行 8 -> 2。" -ForegroundColor Yellow
            $fail++
        } else {
            Restore-NvmeSafeBootBackup $sbGuid $viVe $fmPath | Out-Null
            Request-Restart
        }

    } else {
        Write-Host "[ERROR] 无效输入：$nChoice 。请输入 0、1 或 2" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 8 - Native NVMe Driver)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
} elseif ($choice -eq "9") {

    # ======================= Part 9: 清除 Device Guard EFI 锁定 =======================
    # 应对 UEFI 锁定：选项 10 的关闭子项可通过注册表关闭 VBS/HVCI/Credential Guard，
    # 但 安全中心 / msinfo32 仍显示"内存完整性"或"凭据保护"开启时，
    # 用 SecConfig.efi 引导清除 EFI 变量（硬手段，等效于官方 DG_Readiness_Tool）。
    Write-Host ""
    Write-Host "============ [Part 9] 清除 Device Guard EFI 锁定 / Clear DG UEFI Lock (SecConfig.efi) ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 适用场景：UEFI 锁定 —— 已运行选项 10（注册表关闭），但 安全中心/msinfo32 仍显示" -ForegroundColor Yellow
    Write-Host "            内核隔离-内存完整性 或 凭据保护 处于开启状态。" -ForegroundColor Yellow
    Write-Host " 原理：把 SecConfig.efi 设为一次性引导项，开机进入后清除 Device Guard 的 EFI 变量。" -ForegroundColor Yellow
    Write-Host ""

    $dgGuid = '{0cb3b571-2f2e-4343-a879-d86a476d7215}'

    Write-Host "  1. 执行（BitLocker 预检查 -> 挂载 EFI 分区 -> 复制 SecConfig.efi -> 配置一次性引导项）" -ForegroundColor White
    Write-Host "  2. 清理（删除一次性引导项、清空引导序列、卸载 EFI 分区盘符；不重启）" -ForegroundColor White
    $gChoice = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"

    if ($gChoice -eq "1") {

        Write-Host ""
        Write-Host " [WARNING] 执行后重启时，开机会出现一个确认界面，需按屏幕提示按键（通常为 F3）确认" -ForegroundColor Yellow
        Write-Host "           禁用 Credential Guard；错过或拒绝则本次不生效（一次性引导项不会再次出现，可重跑）。" -ForegroundColor Yellow
        Write-Host " [WARNING] 若机器开启了 BitLocker，清除 EFI 变量会改变 TPM 度量值，可能触发恢复模式" -ForegroundColor Yellow
        Write-Host "           （要求输入 48 位恢复密钥）。本选项已内置 BitLocker 预检查，检测到已开启会拒绝执行。" -ForegroundColor Yellow
        $confirmDg = Read-Host "确定执行吗？(Y = 执行 / N = 取消)"
        if ($confirmDg -notin @('Y','y')) {
            Write-Host "[SKIP] 已取消，未做任何修改（不重启）" -ForegroundColor Yellow
        } else {

            # 1) BitLocker 预检查：任一分区保护开启或状态无法确认都拒绝执行
            $blBlocked = $false
            $blCheckFailed = $false
            try {
                $blOn = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' })
                if ($blOn.Count -gt 0) {
                    $blBlocked = $true
                    Write-Host "[FAIL] 检测到 BitLocker 保护已开启，为避免触发恢复模式，已拒绝执行：" -ForegroundColor Red
                    foreach ($v in $blOn) {
                        Write-Host ("        {0}  {1}" -f $v.MountPoint, $v.VolumeStatus) -ForegroundColor Red
                    }
                    Write-Host "        请先暂停保护（Suspend-BitLocker，可维持数次重启）或彻底解密后再运行本选项" -ForegroundColor Yellow
                    $fail++
                } else {
                    Write-Host "[OK] BitLocker 预检查通过（未开启保护，无恢复模式风险）"
                    $ok++
                }
            } catch {
                $blCheckFailed = $true
                Write-Host "[FAIL] 无法查询 BitLocker 状态：$($_.Exception.Message)；已拒绝 EFI 修改" -ForegroundColor Red
                $fail++
            }

            if (-not $blBlocked -and -not $blCheckFailed) {

                # 2) SecConfig.efi 源文件检查
                $secSrc = Join-Path $env:SystemRoot 'System32\SecConfig.efi'
                if (-not (Test-Path $secSrc)) {
                    Write-Host "[FAIL] 未找到 $secSrc，当前系统不带此文件，无法执行" -ForegroundColor Red
                    $fail++
                } else {

                    # 3) 选择空闲盘符并挂载 EFI 分区
                    $efiLetter = $null
                    foreach ($l in @('X','Y','Z','V','W','U')) {
                        if (-not (Test-Path "$($l):\")) { $efiLetter = $l; break }
                    }
                    if (-not $efiLetter) {
                        Write-Host "[FAIL] 找不到空闲盘符（X/Y/Z/V/W/U 均被占用）" -ForegroundColor Red
                        $fail++
                    } else {
                        $mounted = $false
                        try {
                            & mountvol.exe "$($efiLetter):" /s *> $null
                            if ($LASTEXITCODE -ne 0) { throw "mountvol exit code $LASTEXITCODE" }
                            $mounted = $true
                            Write-Host "[OK] EFI 分区已挂载到 $($efiLetter):"
                            $ok++
                        } catch {
                            Write-Host "[FAIL] 挂载 EFI 分区失败（本机可能非 UEFI 启动）：$($_.Exception.Message)" -ForegroundColor Red
                            $fail++
                        }

                        if ($mounted) {

                            # 4) 复制 SecConfig.efi 到 EFI 分区（复制成功才配置引导项）
                            $copyOk = $false
                            try {
                                $bootDir = "$($efiLetter):\EFI\Microsoft\Boot"
                                if (-not (Test-Path $bootDir)) { New-Item -ItemType Directory -Path $bootDir -Force | Out-Null }
                                Copy-Item $secSrc (Join-Path $bootDir 'SecConfig.efi') -Force -ErrorAction Stop
                                $copyOk = $true
                                Write-Host "[OK] SecConfig.efi 已复制到 $bootDir"
                                $ok++
                            } catch {
                                Write-Host "[FAIL] 复制 SecConfig.efi : $($_.Exception.Message)" -ForegroundColor Red
                                $fail++
                            }

                            $efiConfigured = $false
                            if ($copyOk) {

                                # 5) 配置一次性引导项；任一步失败都停止并清理临时项
                                & bcdedit.exe /delete $dgGuid /f *> $null
                                $bcdOk = Invoke-BcdEdit "/create $dgGuid /d DebugTool /application osloader" "创建 BCD 引导项 (DebugTool)"
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid path \EFI\Microsoft\Boot\SecConfig.efi" "引导项路径 SecConfig.efi" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid device partition=$($efiLetter):" "引导项设备分区 $($efiLetter):" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid loadoptions DISABLE-LSA-ISO" "LoadOptions = DISABLE-LSA-ISO" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set {bootmgr} bootsequence $dgGuid" "设为下次开机一次性引导" }
                                if ($bcdOk) {
                                    $efiConfigured = $true
                                } else {
                                    Write-Host "[FAIL] EFI 一次性引导配置未完成，正在清理临时 BCD 项" -ForegroundColor Red
                                    & bcdedit.exe /delete $dgGuid /f *> $null
                                    & bcdedit.exe /deletevalue '{bootmgr}' bootsequence *> $null
                                }
                            }

                            # 6) 卸载 EFI 分区
                            & mountvol.exe "$($efiLetter):" /d *> $null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[OK] EFI 分区已卸载（$($efiLetter):）"
                                $ok++
                            } else {
                                Write-Host "[WARN] EFI 分区卸载失败，可稍后手动执行: mountvol $($efiLetter): /d" -ForegroundColor Yellow
                            }

                            if ($efiConfigured) {
                                $script:rebootRequired = $true
                                # Summary
                                Write-Host ""
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host " Finished (Part 9 - Clear DG UEFI Lock)" -ForegroundColor Cyan
                                Write-Host " OK : $ok" -ForegroundColor Green
                                Write-Host " FAIL : $fail" -ForegroundColor Red
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host ""
                                Write-Host " 重启开机会出现确认界面，请按屏幕提示按键（通常为 F3）确认禁用！" -ForegroundColor Yellow
                                Write-Host " 重启确认后可用 msinfo32 -> 系统摘要 -> 基于虚拟化的安全性 验证是否已关闭。" -ForegroundColor Yellow

                                                    Request-Restart
                            } else {
                                Write-Host ""
                                Write-Host "[提示] EFI 一次性引导配置未完成，未设置待重启状态" -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }

            if ($blBlocked) {
                Write-Host ""
                Write-Host "[提示] 未做任何修改（不重启）" -ForegroundColor Yellow
            }
        }

    } elseif ($gChoice -eq "2") {

        # 1) 删除一次性引导项（如存在）
        & bcdedit.exe /enum $dgGuid *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-BcdEdit "/delete $dgGuid /f" "删除 BCD 引导项 (DebugTool)"
        } else {
            Write-Host "[SKIP] BCD 引导项不存在（无需删除）" -ForegroundColor Yellow
            $skip++
        }

        # 2) 清空 {bootmgr} 的 bootsequence（如仍指向该引导项）
        $bmEnum = & bcdedit.exe /enum '{bootmgr}' 2>$null
        if ($LASTEXITCODE -eq 0 -and ($bmEnum -join "`n") -match 'bootsequence') {
            Invoke-BcdEdit "/deletevalue {bootmgr} bootsequence" "清空一次性引导序列"
        } else {
            Write-Host "[SKIP] bootsequence 未设置（无需清理）" -ForegroundColor Yellow
            $skip++
        }

        # 3) 卸载残留的 EFI 分区盘符（仅当该盘符下存在脚本复制的 SecConfig.efi）
        $unmounted = 0
        foreach ($l in @('X','Y','Z','V','W','U')) {
            if (Test-Path "$($l):\EFI\Microsoft\Boot\SecConfig.efi") {
                & mountvol.exe "$($l):" /d *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] 已卸载 EFI 分区盘符 $($l):"
                    $ok++
                    $unmounted++
                } else {
                    Write-Host "[FAIL] 卸载 $($l): 失败，可手动执行: mountvol $($l): /d" -ForegroundColor Red
                    $fail++
                    $unmounted++
                }
            }
        }
        if ($unmounted -eq 0) {
            Write-Host "[SKIP] 无残留的 EFI 分区挂载" -ForegroundColor Yellow
            $skip++
        }

        # Summary（无需重启）
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 9 - Cleanup)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "提示：清理完成，无需重启。" -ForegroundColor Yellow

    } else {
        Write-Host "[ERROR] 无效输入：$gChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
    }

} elseif ($choice -eq "10") {
    Write-Host ""; Write-Host "============ [Part 10] 虚拟化 / VBS / Hyper-V 管理 ============" -ForegroundColor Cyan; Write-Host ""
    $dgRegValues=@(@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity';Name='Enabled'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard';Name='EnableVirtualizationBasedSecurity'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\LSA';Name='LsaCfgFlags'},@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard';Name='EnableVirtualizationBasedSecurity'},@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard';Name='RequirePlatformSecurityFeatures'})
    Write-Host "  0. 查看当前状态";Write-Host "  1. 关闭 VBS/HVCI/Credential Guard + Hyper-V" -ForegroundColor Yellow;Write-Host "  2. 删除脚本覆盖并尝试启用 Hyper-V（不是原始状态精确回滚）"
    $vChoice=Read-Host "请输入 0、1 或 2 并回车"
    if($vChoice -eq '0'){
        $bcEnum=(& bcdedit.exe /enum '{current}' 2>$null)-join "`n";foreach($n in @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')){if($bcEnum -match ('(?m)^\s*'+[regex]::Escape($n)+'\s+(\S+)')){Write-Host ("bcdedit {0,-24} = {1}"-f $n,$Matches[1])}else{Write-Host ("bcdedit {0,-24} = <未设置（系统默认）>"-f $n)}};foreach($v in $dgRegValues){$item=Get-Item $v.Path -ErrorAction SilentlyContinue;if($item -and ($item.GetValueNames()-contains $v.Name)){Write-Host ("注册表 {0} -> {1} = {2}"-f $v.Path,$v.Name,$item.GetValue($v.Name))}};foreach($fn in @('Microsoft-Hyper-V-All','VirtualMachinePlatform','HypervisorPlatform')){$f=Get-WindowsOptionalFeature -Online -FeatureName $fn -ErrorAction SilentlyContinue;if($f){Write-Host ("功能 {0,-26} = {1}"-f $fn,$f.State)}};$cs=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue;if($cs){Write-Host ("运行时 HypervisorPresent = {0}"-f $cs.HypervisorPresent)}
    } elseif($vChoice -eq '1'){
        foreach($v in $dgRegValues){Set-RegDword $v.Path $v.Name 0 ("关闭虚拟化安全 "+$v.Name)}
        try{$hv=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop;if($hv.State -in @('Enabled','EnablePending')){$null=Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart -ErrorAction Stop;Write-Host '[OK] Hyper-V 功能组件已禁用';$ok++;$script:rebootRequired=$true}else{Write-Host '[SKIP] Hyper-V 功能组件未启用' -ForegroundColor Yellow;$skip++}}catch{Write-Host "[FAIL] Hyper-V 功能组件禁用 : $($_.Exception.Message)" -ForegroundColor Red;$fail++}
        Invoke-BcdEdit "/set hypervisorlaunchtype off" "Hypervisor Launch Type Off";Invoke-BcdEdit "/set isolatedcontext no" "Isolated Context Off";Invoke-BcdEdit "/set vsmlaunchtype off" "VSM Launch Type Off";Verify-BcdValue 'hypervisorlaunchtype' 'Off' 'hypervisorlaunchtype'|Out-Null;Verify-BcdValue 'isolatedcontext' 'No' 'isolatedcontext'|Out-Null;Verify-BcdValue 'vsmlaunchtype' 'Off' 'vsmlaunchtype'|Out-Null;Write-Host '[提示] 重启后再验证 HypervisorPresent / msinfo32 实际运行状态。' -ForegroundColor Yellow
    } elseif($vChoice -eq '2'){
        foreach($v in $dgRegValues){$item=Get-Item $v.Path -ErrorAction SilentlyContinue;if($item -and ($item.GetValueNames()-contains $v.Name)){$regPath=Convert-RegExePath $v.Path;& reg.exe DELETE $regPath /v $v.Name /f *> $null;if($LASTEXITCODE -eq 0){Write-Host ("[OK] 已删除注册表值 {0} -> {1}"-f $v.Path,$v.Name);$ok++;$script:rebootRequired=$true}else{Write-Host ("[FAIL] 删除注册表值 {0} -> {1}"-f $v.Path,$v.Name) -ForegroundColor Red;$fail++}}else{Write-Host ("[SKIP] 注册表值不存在: {0} -> {1}"-f $v.Path,$v.Name) -ForegroundColor Yellow;$skip++}}
        Remove-BcdValue 'hypervisorlaunchtype' '还原 hypervisorlaunchtype';Remove-BcdValue 'vsmlaunchtype' '还原 vsmlaunchtype';Remove-BcdValue 'isolatedcontext' '还原 isolatedcontext';try{$null=Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop;Write-Host '[OK] 已尝试启用 Hyper-V 功能组件（重启后生效）';$ok++;$script:rebootRequired=$true}catch{Write-Host "[FAIL] Hyper-V 功能组件启用 : $($_.Exception.Message)" -ForegroundColor Red;$fail++}
    } else {Write-Host "[ERROR] 无效输入：$vChoice 。请输入 0、1 或 2" -ForegroundColor Red}
    Write-Host "Finished (Part 10 - Virtualization Management)" -ForegroundColor Cyan;Write-Host " OK : $ok  FAIL : $fail  SKIP : $skip";Request-Restart

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
