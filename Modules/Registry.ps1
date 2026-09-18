# Registry.ps1 - Part 1 核心游戏 / 系统性能优化
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Invoke-RegistryStepSequence {
    param([scriptblock[]]$Steps)
    foreach ($step in $Steps) {
        $before = $script:fail
        try { $null = & $step }
        catch {
            Write-Host "[FAIL] 注册表操作步骤异常：$($_.Exception.Message)" -ForegroundColor Red
            $script:fail++
        }
        if ($script:fail -gt $before) { return $false }
    }
    return $true
}

function Invoke-RegistryModule {
    param([string]$Action = '')

    Write-Host ""; Write-Host "============ [Part 1] 核心游戏 / 系统性能优化 ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  1. 核心游戏优化（GameDVR / GameBar / Multimedia / Win32PrioritySeparation / HAGS / Games Task / Game Mode / ActivationType）" -ForegroundColor White
    Write-Host "  2. 系统行为优化（Search / Prefetch / Memory Compression / NTFS 8.3 / TRIM / Visual Effects）" -ForegroundColor White
    Write-Host "  3. CPU 安全缓解调整（FeatureSettingsOverride / Mask；修改前自动备份，可恢复）" -ForegroundColor Yellow
    Write-Host "  4. 按备份恢复核心游戏 / 系统行为优化（Memory Compression 与 TRIM 不在范围内）" -ForegroundColor White
    Write-Host "  5. 易受攻击驱动黑名单关闭（VulnerableDriverBlocklistEnable = 0；修改前自动备份，可恢复）" -ForegroundColor Yellow
    Write-Host "  0. 返回主菜单" -ForegroundColor White
    $nestedAction = ''
    if (-not [string]::IsNullOrWhiteSpace($Action) -and $Action -match '^(?<top>[1-5])-(?<sub>[1-3])$') {
        $coreChoice = $Matches['top']
        $nestedAction = $Matches['sub']
    } else {
        if ([string]::IsNullOrWhiteSpace($Action)) {
            if ($script:TweakNonInteractive) {
                Write-Host '[FAIL] 非交互模式必须通过 -Action 指定模块 1 子操作（例如 1=1-1 或 1=4）。' -ForegroundColor Red
                $script:fail++
                return $false
            }
            $Action = Read-Host "请输入 0、1、2、3、4 或 5 并回车"
        }
        $coreChoice = $Action
    }

    # 子项 1/2 写入前的统一快照门禁；备份失败时改写选择值以跳过全部修改分支
    if ($coreChoice -eq '1' -or $coreChoice -eq '2') {
        if (-not (Ensure-RegistryBackup)) {
            Write-Host "[FAIL] 已阻止核心/系统优化修改：原始状态未成功备份。" -ForegroundColor Red
            $coreChoice = 'backup-failed'
        }
    }

    $operationStartFail = $script:fail
    if ($coreChoice -eq '1') {
        # 任何一步失败都停止后续写入；函数末尾会按首次快照回滚本节。
        $activationReg = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.Gamebar.PresenceServer.Internal.PresenceWriter'
        $games = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        $steps = @(
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 "AppCaptureEnabled" },
            { Set-RegDword "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 "GameDVR_Enabled" },
            {
                $taskName = $null
                try {
                    & reg.exe ADD $activationReg /v ActivationType /t REG_DWORD /d 0x00000000 /f *> $null
                    if ($LASTEXITCODE -ne 0) { throw "Administrator access denied" }
                    Write-Host "[OK] ActivationType = 0"; $script:ok++; $script:rebootRequired = $true
                } catch {
                    try {
                        $taskName = "WindowsGameOpt_ActivationType_" + [guid]::NewGuid().ToString("N")
                        $cmd = 'reg.exe ADD "' + $activationReg + '" /v ActivationType /t REG_DWORD /d 0x00000000 /f'
                        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $cmd"
                        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
                        Start-ScheduledTask -TaskName $taskName; Start-Sleep -Seconds 2
                        $check = & reg.exe QUERY $activationReg /v ActivationType 2>$null
                        if ($check -notmatch '0x0+\s*$') { throw "SYSTEM retry did not verify ActivationType=0" }
                        Write-Host "[OK] ActivationType = 0 (SYSTEM)"; $script:ok++; $script:rebootRequired = $true
                    } catch {
                        throw 'ActivationType = 0 受保护注册表键拒绝修改'
                    } finally {
                        if ($taskName) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
                    }
                }
            },
            { Set-RegDword "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0 "UseNexusForGameBarEnabled" },
            { Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "0xFFFFFFFF" "NetworkThrottlingIndex" },
            { Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 10 "SystemResponsiveness" },
            { Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation (0x26)" },
            { Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS" },
            { Set-RegDword $games "Affinity" 0 "Games Affinity" },
            { Set-RegString $games "Background Only" "False" "Games Background Only" },
            { Set-RegDword $games "Clock Rate" 10000 "Games Clock Rate" },
            { Set-RegDword $games "GPU Priority" 8 "Games GPU Priority" },
            { Set-RegDword $games "Priority" 6 "Games Priority" },
            { Set-RegString $games "Scheduling Category" "High" "Games Scheduling Category" },
            { Set-RegString $games "SFIO Priority" "High" "Games SFIO Priority" },
            { Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 0 "AutoGameModeEnabled" },
            { Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0 "AllowAutoGameMode" }
        )
        $operationOk = Invoke-RegistryStepSequence $steps
        if ($operationOk) {
            $operationOk = (Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation" -and
                Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS")
        }
        if (-not $operationOk) { Write-Host '[FAIL] 核心游戏优化未完整完成；将按原始快照回滚。' -ForegroundColor Red }

    } elseif ($coreChoice -eq '2') {
        $games = $null
        $steps = @(
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 "BingSearchEnabled" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "AllowSearchToUseLocation" 0 "AllowSearchToUseLocation" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0 "CortanaConsent" },
            { Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher" },
            { Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisable8dot3NameCreation" 1 "NtfsDisable8dot3NameCreation" },
            {
                Write-Host ""; Write-Host "[Memory Compression]" -ForegroundColor Cyan
                try { Disable-MMAgent -mc -ErrorAction Stop; Write-Host "[OK] Memory Compression disabled"; $script:ok++; $script:rebootRequired = $true }
                catch { throw "Memory Compression : $($_.Exception.Message)" }
            },
            {
                Write-Host ""; Write-Host "[TRIM]" -ForegroundColor Cyan
                try {
                    $trimOut = fsutil.exe behavior set DisableDeleteNotify 0 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "TRIM : fsutil exit code $LASTEXITCODE" }
                    Write-Host "[OK] NTFS TRIM enabled"; $script:ok++
                } catch { throw $_.Exception.Message }
            },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 3 "VisualFXSetting = 3 (自定义)" },
            { Set-RegString "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "平滑屏幕字体边缘 ON" },
            { Set-RegDword "HKCU:\Control Panel\Desktop" "FontSmoothingType" 2 "Font Smoothing = ClearType" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 1 "任务栏动画 ON" },
            { Set-RegBinary "HKCU:\Control Panel\Desktop" "UserPreferencesMask" "9012018010000000" "动画/淡入淡出/阴影全关" },
            { Set-RegString "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "最大/最小化动画 OFF" },
            { Set-RegString "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "拖动显示窗口内容 OFF" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" 0 "半透明选择框 OFF" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" 0 "图标标签阴影 OFF" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "IconsOnly" 1 "缩略图 OFF" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\DWM" "AlwaysHibernateThumbnails" 0 "任务栏缩略图缓存 OFF" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 "透明效果 OFF" },
            { Set-RegDword "HKCU:\Control Panel\Accessibility" "DynamicScrollbars" 1 "始终显示滚动条 OFF" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "AnimationEffects" 0 "动画效果(辅助功能) OFF" },
            { Set-RegDword "HKCU:\Control Panel\Accessibility" "MessageDuration" 5 "通知自动关闭时长 = 5 秒" },
            { Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "DisableWpbtExecution" 1 "DisableWpbtExecution (阻止 WPBT 固件自动注入)" },
            { Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" 1 "TaskbarEndTask (任务栏右键直接结束任务)" },
            { Set-RegDword "HKLM:\Software\Policies\Microsoft\PowerShellCore" "EnableTelemetry" 0 "PowerShellCore EnableTelemetry (关闭遥测)" },
            { Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" "EnableActiveProbing" 0 "EnableActiveProbing (关闭 NCSI 主动探测防流氓弹窗)" }
        )
        $operationOk = Invoke-RegistryStepSequence $steps
        if ($operationOk) {
            $operationOk = (Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" "EnableActiveProbing" 0 "EnableActiveProbing" -and
                Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher" -and
                Verify-MemoryCompressionDisabled -and Verify-TrimEnabled)
        }
        if (-not $operationOk) { Write-Host '[FAIL] 系统行为优化未完整完成；将按原始快照回滚。' -ForegroundColor Red }

    } elseif ($coreChoice -eq '3') {
        Write-Host ""; Write-Host "[CPU 安全缓解调整 / Meltdown-Spectre Mitigation]" -ForegroundColor Yellow
        Write-Host "目标值 FeatureSettingsOverride=3 / FeatureSettingsOverrideMask=3 会关闭相关缓解；仅在明确了解安全影响时使用。" -ForegroundColor Yellow
        Write-Host "  1. 查看当前值" -ForegroundColor White
        Write-Host "  2. 应用 3 / 3（修改前自动备份）" -ForegroundColor Yellow
        Write-Host "  3. 按备份恢复" -ForegroundColor White
        if ($script:TweakNonInteractive -and [string]::IsNullOrWhiteSpace($nestedAction)) {
            Write-Host "[FAIL] 非交互模式的模块 1 动作必须包含二级动作，例如 -Action 1=3-2" -ForegroundColor Red
            $script:fail++
            return
        }
        $mChoice = if ([string]::IsNullOrWhiteSpace($nestedAction)) { Read-Host "请输入 1、2 或 3 并回车" } else { $nestedAction }
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        if ($mChoice -eq '1') {
            $item=Get-Item $mmPath -ErrorAction SilentlyContinue
            foreach($n in @('FeatureSettingsOverride','FeatureSettingsOverrideMask')){
                if($item -and ($item.GetValueNames()-contains $n)){Write-Host ("{0} = {1}" -f $n,$item.GetValue($n))}else{Write-Host ("{0} = <未设置（系统默认）>" -f $n)}}
        } elseif ($mChoice -eq '2') {
            if (-not (Test-HighRiskConfirmation '确定关闭 CPU 硬件安全缓解（FeatureSettingsOverride=3/Mask=3）吗？')) { return $false }
            if (Ensure-SecurityMitigationBackup) {
                $beforeFail = $script:fail
                Set-RegDword $mmPath "FeatureSettingsOverride" 3 "FeatureSettingsOverride = 3"
                if ($script:fail -eq $beforeFail) {
                    Set-RegDword $mmPath "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask = 3"
                }
                if ($script:fail -eq $beforeFail) {
                    Verify-RegDword $mmPath "FeatureSettingsOverride" 3 "FeatureSettingsOverride" | Out-Null
                    Verify-RegDword $mmPath "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask" | Out-Null
                }
                if ($script:fail -gt $beforeFail) {
                    Write-Host '[FAIL] CPU 安全缓解修改未完整验证，正在按原始快照回滚。' -ForegroundColor Red
                    Restore-SecurityMitigationBackup | Out-Null
                    return $false
                }
            }
        } elseif ($mChoice -eq '3') {
            Restore-SecurityMitigationBackup
        } else {
            Write-Host "[FAIL] 无效输入：$mChoice 。" -ForegroundColor Red
            $script:fail++
        }
    } elseif ($coreChoice -eq '4') {
        Restore-RegistryBackup | Out-Null
    } elseif ($coreChoice -eq '5') {
        Write-Host ""; Write-Host "[易受攻击驱动黑名单 / Vulnerable Driver Blocklist]" -ForegroundColor Yellow
        Write-Host "关闭后系统不再拒绝加载已知存在提权漏洞的已签名内核驱动（BYOVD 攻击面扩大）。" -ForegroundColor Yellow
        Write-Host "常见目的：让需要直读 MSR / 物理内存的工具（如 RW-Everything）能够加载驱动。" -ForegroundColor Yellow
        Write-Host "该值与内存完整性（HVCI）联动：HVCI 开启时黑名单强制生效，单改此值不解除。" -ForegroundColor Yellow
        Write-Host "  1. 查看当前值" -ForegroundColor White
        Write-Host "  2. 关闭（写入 0；修改前自动备份，可恢复）" -ForegroundColor Yellow
        Write-Host "  3. 按备份恢复" -ForegroundColor White
        if ($script:TweakNonInteractive -and [string]::IsNullOrWhiteSpace($nestedAction)) {
            Write-Host "[FAIL] 非交互模式的模块 1 动作必须包含二级动作，例如 -Action 1=5-2" -ForegroundColor Red
            $script:fail++
            return
        }
        $dChoice = if ([string]::IsNullOrWhiteSpace($nestedAction)) { Read-Host "请输入 1、2 或 3 并回车" } else { $nestedAction }
        $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config"
        if ($dChoice -eq '1') {
            $item = Get-Item $ciPath -ErrorAction SilentlyContinue
            foreach ($n in @('VulnerableDriverBlocklistEnable')) {
                if ($item -and ($item.GetValueNames() -contains $n)) { Write-Host ("{0} = {1}" -f $n, $item.GetValue($n)) } else { Write-Host ("{0} = <未设置（系统默认）>" -f $n) }
            }
        } elseif ($dChoice -eq '2') {
            if (-not (Test-HighRiskConfirmation '确定关闭易受攻击驱动黑名单吗？这会扩大 BYOVD 内核驱动攻击面。')) { return $false }
            if (Ensure-DriverBlocklistBackup) {
                $beforeFail = $script:fail
                Set-RegDword $ciPath "VulnerableDriverBlocklistEnable" 0 "VulnerableDriverBlocklistEnable = 0"
                if ($script:fail -eq $beforeFail) {
                    Verify-RegDword $ciPath "VulnerableDriverBlocklistEnable" 0 "VulnerableDriverBlocklistEnable" | Out-Null
                }
                if ($script:fail -gt $beforeFail) {
                    Write-Host '[FAIL] 易受攻击驱动黑名单修改未验证，正在按原始快照回滚。' -ForegroundColor Red
                    Restore-DriverBlocklistBackup | Out-Null
                    return $false
                }
                Write-Host "[提示] 重启后生效；HVCI 开启时此值不解除强制黑名单。" -ForegroundColor Yellow
            }
        } elseif ($dChoice -eq '3') {
            Restore-DriverBlocklistBackup | Out-Null
        } else {
            Write-Host "[FAIL] 无效输入：$dChoice 。" -ForegroundColor Red
            $script:fail++
        }
    } elseif ($coreChoice -eq 'backup-failed') {
        # 备份失败已在上文报错；不执行任何修改
    } elseif ($coreChoice -eq '0') {
        Write-Host "[返回] 已返回主菜单。" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] 无效输入：$coreChoice 。请输入 0、1、2、3、4 或 5" -ForegroundColor Red
        $script:fail++
    }

    if (($coreChoice -eq '1' -or $coreChoice -eq '2') -and $script:fail -gt $operationStartFail) {
        $section = if ($coreChoice -eq '1') { 'Core' } else { 'System' }
        Write-Host "[FAIL] 模块 1 子项 $coreChoice 未完整验证，正在按原始注册表快照回滚 $section。" -ForegroundColor Red
        if (-not (Restore-RegistryBackup -Section $section)) {
            Write-Host '[FAIL] 核心/系统注册表自动回滚未完全成功，请人工检查。' -ForegroundColor Red
        }
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
