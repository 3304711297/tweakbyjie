# Registry.ps1 - Part 1 核心游戏 / 系统性能优化
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Invoke-RegistryModule {

    Write-Host ""; Write-Host "============ [Part 1] 核心游戏 / 系统性能优化 ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  1. 核心游戏优化（GameDVR / GameBar / Multimedia / Win32PrioritySeparation / HAGS / Games Task / Game Mode / ActivationType）" -ForegroundColor White
    Write-Host "  2. 系统行为优化（Search / Prefetch / Memory Compression / NTFS 8.3 / TRIM / Visual Effects）" -ForegroundColor White
    Write-Host "  3. CPU 安全缓解调整（FeatureSettingsOverride / Mask；修改前自动备份，可恢复）" -ForegroundColor Yellow
    Write-Host "  4. 按备份恢复核心游戏 / 系统行为优化（Memory Compression 与 TRIM 不在范围内）" -ForegroundColor White
    Write-Host "  0. 返回主菜单" -ForegroundColor White
    $coreChoice = Read-Host "请输入 0、1、2、3 或 4 并回车"

    # 子项 1/2 写入前的统一快照门禁；备份失败时改写选择值以跳过全部修改分支
    if ($coreChoice -eq '1' -or $coreChoice -eq '2') {
        if (-not (Ensure-RegistryBackup)) {
            Write-Host "[FAIL] 已阻止核心/系统优化修改：原始状态未成功备份。" -ForegroundColor Red
            $coreChoice = 'backup-failed'
        }
    }

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
            $script:ok++
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
                    $script:ok++
                    $script:rebootRequired = $true
                } else { throw "SYSTEM retry did not verify ActivationType=0" }
            } catch {
                Write-Host "[FAIL] ActivationType = 0 : protected registry key rejected the change" -ForegroundColor Red
                Write-Host " Other core optimizations will continue." -ForegroundColor Yellow
                $script:fail++
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
        try { Disable-MMAgent -mc -ErrorAction Stop; Write-Host "[OK] Memory Compression disabled"; $script:ok++; $script:rebootRequired=$true }
        catch { Write-Host "[FAIL] Memory Compression : $($_.Exception.Message)" -ForegroundColor Red; $script:fail++ }
        # 14 TRIM
        Write-Host ""; Write-Host "[TRIM]" -ForegroundColor Cyan
        try {
            $trimOut = fsutil.exe behavior set DisableDeleteNotify 0 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Host "[OK] NTFS TRIM enabled"; $script:ok++ }
            else { Write-Host "[FAIL] TRIM : fsutil exit code $LASTEXITCODE" -ForegroundColor Red; if($trimOut){Write-Host ($trimOut -join [Environment]::NewLine) -ForegroundColor DarkYellow}; $script:fail++ }
        } catch { Write-Host "[FAIL] TRIM : $($_.Exception.Message)" -ForegroundColor Red; $script:fail++ }

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
    } elseif ($coreChoice -eq '4') {
        Restore-RegistryBackup | Out-Null
    } elseif ($coreChoice -eq 'backup-failed') {
        # 备份失败已在上文报错；不执行任何修改
    } elseif ($coreChoice -eq '0') {
        Write-Host "[返回] 已返回主菜单。" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] 无效输入：$coreChoice 。请输入 0、1、2、3 或 4" -ForegroundColor Red
    }

    if ($coreChoice -ne '0' -and $coreChoice -ne 'backup-failed') {
        Write-Host ""; Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 1 - Core / System Optimization)" -ForegroundColor Cyan
        Write-Host " OK : $script:ok" -ForegroundColor Green
        Write-Host " FAIL : $script:fail" -ForegroundColor Red
        Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Request-Restart
    }

}
