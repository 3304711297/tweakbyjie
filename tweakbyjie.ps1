# Windows Game Optimization + BCDEdit Addons - Menu Edition
# Run as Administrator. Each setting is applied independently.
# ActivationType is handled separately because the key may be protected.
#
# 菜单 / Menu:
#   输入 1 回车 = 系统优化（原脚本全部内容 + 视觉效果自定义：仅保留平滑屏幕字体边缘
#                 与任务栏动画，其余视觉效果全关），完成后 5 秒自动重启（按 Q 取消）
#   输入 2 回车 = 开启测试模式（bcdedit testsigning / debug / dbgsettings local / nointegritychecks），
#                 完成后 5 秒自动重启（按 Q 取消）
#   输入 3 回车 = 关闭测试模式（删除 testsigning / debug 启动项，保留 nointegritychecks），
#                 完成后 5 秒自动重启（按 Q 取消）
#   输入 4 回车 = 关闭安全中心（禁用 Windows Defender / SmartScreen 策略），
#                 随后可选择是否执行删除类优化（Y=执行 / N=跳过），
#                 完成后 5 秒自动重启（按 Q 取消）
#   输入 5 回车 = 优化服务项继续工作（禁用可安全禁用的服务，
#                 Xbox / 蓝牙 / 嵌入模式服务改成手动），
#                 完成后 5 秒自动重启（按 Q 取消）
#   输入 6 回车 = 应用超性能电源计划（子选项 1：先备份当前电源计划到脚本所在目录，
#                 再导入并应用仓库自带的 ultimate-performance.pow；
#                 子选项 2：恢复之前备份的电源计划），
#                 完成后 5 秒自动重启（按 Q 取消）
#   输入 7 回车 = 启用 Windows 原生 NVMe 驱动 nvmedisk.sys（需 25H2/build 26200+ 与 NVMe
#                 硬盘；子选项 0：只读查看当前状态；子选项 1：写入 3 个 Velocity
#                 功能覆盖值 + 2 条安全模式加固；子选项 2：删除覆盖值还原为系统默认），
#                 修改类操作完成后 5 秒自动重启（按 Q 取消）
#   输入 8 回车 = 清除 Device Guard EFI 锁定（应对 UEFI 锁定：注册表已关但安全中心仍
#                 显示内存完整性/凭据保护开启；先做 BitLocker 预检查，再挂载 EFI 分区
#                 复制 SecConfig.efi 并配置一次性引导项，重启开机时需按屏幕提示按键确认；
#                 子选项 2：删除引导项并卸载 EFI 盘符），
#                 执行后 5 秒自动重启（按 Q 取消）

$ErrorActionPreference = "Continue"
$ok = 0
$fail = 0
$skip = 0

# --- Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] 请以管理员身份运行此脚本 / Please run this script as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

function Convert-RegExePath {
    param([string]$Path)
    if ($Path -match '^HKLM:\\(.*)$') { return "HKLM\$($Matches[1])" }
    if ($Path -match '^HKCU:\\(.*)$') { return "HKCU\$($Matches[1])" }
    if ($Path -match '^HKEY_LOCAL_MACHINE:\\(.*)$') { return "HKLM\$($Matches[1])" }
    if ($Path -match '^HKEY_CURRENT_USER:\\(.*)$') { return "HKCU\$($Matches[1])" }
    return $Path
}

function Set-RegDword {
    param([string]$Path,[string]$Name,[object]$Value,[string]$Label)
    try {
        $regPath = Convert-RegExePath $Path
        $valueText = [string]$Value
        if ($valueText -match '^\d+$') {
            [uint64]$n = [uint64]$Value
            if ($n -le 0xFFFFFFFF) {
                $valueText = "0x{0:X8}" -f $n
            }
        }
        & reg.exe ADD $regPath /v $Name /t REG_DWORD /d $valueText /f *> $null
        if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        Write-Host ("[OK] {0} = {1}" -f $Label, $valueText)
        $script:ok++
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

function Set-RegString {
    param([string]$Path,[string]$Name,[string]$Value,[string]$Label)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force -ErrorAction Stop | Out-Null
        Write-Host ("[OK] {0} = {1}" -f $Label, $Value)
        $script:ok++
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

function Set-RegBinary {
    param([string]$Path,[string]$Name,[string]$Hex,[string]$Label)
    try {
        $regPath = Convert-RegExePath $Path
        & reg.exe ADD $regPath /v $Name /t REG_BINARY /d $Hex /f *> $null
        if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        Write-Host ("[OK] {0} = {1}" -f $Label, $Hex)
        $script:ok++
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

# Helper function for BCD
function Invoke-BcdEdit {
    param([string]$Arguments, [string]$Label)
    try {
        $process = Start-Process -FilePath "bcdedit.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Exit code $($process.ExitCode)" }
        Write-Host ("[OK] {0}" -f $Label)
        $script:ok++
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

# 5-second restart countdown, press Q to cancel
function Start-RestartCountdown {
    param([int]$Seconds = 5)
    Write-Host ""
    Write-Host "系统将在 $($Seconds) 秒后自动重启，期间按 Q 键取消重启" -ForegroundColor Yellow
    Write-Host "Restarting in $($Seconds) seconds. Press Q to cancel." -ForegroundColor Yellow
    $cancelled = $false
    for ($i = $Seconds; $i -ge 1; $i--) {
        Write-Host ("`r剩余 {0} 秒后重启，按 Q 取消 ... " -f $i) -NoNewline -ForegroundColor Yellow
        $deadline = (Get-Date).AddSeconds(1)
        while (-not $cancelled -and (Get-Date) -lt $deadline) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq [ConsoleKey]::Q) { $cancelled = $true }
                }
            } catch {
                Start-Sleep -Milliseconds 100
            }
            Start-Sleep -Milliseconds 50
        }
        if ($cancelled) { break }
    }
    Write-Host ""
    if ($cancelled) {
        Write-Host "[已取消] 重启已取消，请稍后手动重启以使设置生效" -ForegroundColor Green
        Write-Host "[CANCELLED] Restart cancelled. Restart manually later for changes to take effect." -ForegroundColor Green
        Read-Host "Press Enter to exit"
    } else {
        Write-Host "[重启] 立即重启 / Restarting now..." -ForegroundColor Red
        Restart-Computer -Force
    }
}

# ============================ Menu ============================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows Game Optimization + BCDEdit - Menu Edition" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " 请选择执行模式 / Select an option:" -ForegroundColor Cyan
Write-Host "   1. 系统优化（原脚本全部内容）" -ForegroundColor White
Write-Host "      System Optimization (original script)" -ForegroundColor Gray
Write-Host "   2. 开启测试模式（bcdedit testsigning / debug / dbgsettings local / nointegritychecks）" -ForegroundColor White
Write-Host "      Enable Test Mode (independent step)" -ForegroundColor Gray
Write-Host "   3. 关闭测试模式（删除 testsigning / debug 启动项，保留 nointegritychecks）" -ForegroundColor White
Write-Host "      Disable Test Mode (delete testsigning / debug entries, keep nointegritychecks)" -ForegroundColor Gray
Write-Host "   4. 关闭安全中心（禁用 Windows Defender / SmartScreen，可选删除类优化）" -ForegroundColor White
Write-Host "      Disable Security Center (Defender & SmartScreen policies, optional deletion step)" -ForegroundColor Gray
Write-Host "   5. 优化服务项继续工作（禁用可安全禁用的服务，Xbox/蓝牙/嵌入模式改成手动）" -ForegroundColor White
Write-Host "      Service Optimization (disable safe services, restore Xbox/Bluetooth to Manual)" -ForegroundColor Gray
Write-Host "   6. 应用超性能电源计划（备份当前计划后导入并应用，子选项 2 可恢复备份）" -ForegroundColor White
Write-Host "      Apply Ultimate Performance Power Plan (backup current, import & apply, restorable)" -ForegroundColor Gray
    Write-Host "   7. 启用原生 NVMe 驱动（写入 Velocity 覆盖 + 安全模式加固，子选项 2 可还原）" -ForegroundColor White
    Write-Host "      Enable native NVMe driver nvmedisk.sys (velocity overrides + safe boot fix, restorable)" -ForegroundColor Gray
    Write-Host "   8. 清除 Device Guard EFI 锁定（SecConfig.efi 应对 UEFI 锁定，含 BitLocker 预检查）" -ForegroundColor White
    Write-Host "      Clear Device Guard UEFI lock via SecConfig.efi (BitLocker pre-check included)" -ForegroundColor Gray
    Write-Host ""
    Write-Host " 注意：每个选项执行完成后都会在 5 秒后自动重启（期间按 Q 取消）" -ForegroundColor Yellow
    Write-Host " NOTE: Each option auto-restarts after 5 seconds (press Q to cancel)." -ForegroundColor Yellow
    Write-Host ""
$choice = Read-Host "请输入 1、2、3、4、5、6、7 或 8 并回车 (Enter 1, 2, 3, 4, 5, 6, 7 or 8)"

if ($choice -eq "1") {

    # ======================= Part 1: Original Script =======================
    Write-Host ""
    Write-Host "============ [Part 1] System Optimization (Original) ============" -ForegroundColor Cyan
    Write-Host ""

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
            } else {
                throw "SYSTEM retry did not verify ActivationType=0"
            }
        } catch {
            Write-Host "[FAIL] ActivationType = 0 : protected registry key rejected the change" -ForegroundColor Red
            Write-Host " Other optimizations will continue." -ForegroundColor Yellow
            $fail++
        } finally {
            if ($taskName) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
        }
    }

    # 03 GameBar
    Set-RegDword "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0 "UseNexusForGameBarEnabled"

    # 04 VBS / HVCI / Credential Guard（Device Guard）
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0 "HVCI Enabled"
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 0 "VBS EnableVirtualizationBasedSecurity"
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\LSA" "LsaCfgFlags" 0 "Credential Guard LsaCfgFlags"
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" "EnableVirtualizationBasedSecurity" 0 "DeviceGuard 策略层 VBS"
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" "RequirePlatformSecurityFeatures" 0 "DeviceGuard 策略层平台安全特性"

    # 05 Multimedia
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "0xFFFFFFFF" "NetworkThrottlingIndex"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 10 "SystemResponsiveness"

    # 06 CPU priority
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation (0x26)"

    # 07 Search
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 "BingSearchEnabled"
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "AllowSearchToUseLocation" 0 "AllowSearchToUseLocation"
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0 "CortanaConsent"

    # 08 Meltdown / Spectre
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverride" 3 "FeatureSettingsOverride"
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask"

    # 09 HAGS
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS"

    # 10 Disable MPO
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "DisableMPO" 1 "DisableMPO"

    # 11 Games task
    $games = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    Set-RegDword $games "Affinity" 0 "Games Affinity"
    Set-RegString $games "Background Only" "False" "Games Background Only"
    Set-RegDword $games "Clock Rate" 10000 "Games Clock Rate"
    Set-RegDword $games "GPU Priority" 8 "Games GPU Priority"
    Set-RegDword $games "Priority" 6 "Games Priority"
    Set-RegString $games "Scheduling Category" "High" "Games Scheduling Category"
    Set-RegString $games "SFIO Priority" "High" "Games SFIO Priority"

    # 12 Prefetch
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher"

    # 13 DWM
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" 5 "OverlayTestMode"

    # 14 NTFS
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisable8dot3NameCreation" 1 "NtfsDisable8dot3NameCreation"

    # 15 Game Mode
    Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 0 "AutoGameModeEnabled"
    Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0 "AllowAutoGameMode"

    # 16 Memory Compression
    Write-Host ""
    Write-Host "[Memory Compression]" -ForegroundColor Cyan
    try {
        Disable-MMAgent -mc -ErrorAction Stop
        Write-Host "[OK] Memory Compression disabled"
        $ok++
    } catch {
        Write-Host "[FAIL] Memory Compression : $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }

    # 17 TRIM
    Write-Host ""
    Write-Host "[TRIM]" -ForegroundColor Cyan
    try {
        $trimOut = fsutil.exe behavior set DisableDeleteNotify 0 2>&1
        Write-Host "[OK] NTFS TRIM command executed"
        $ok++
    } catch {
        Write-Host "[FAIL] TRIM : $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }

    # 18 BCDEdit Optimization
    Write-Host ""
    Write-Host "[BCDEdit Tweaks]" -ForegroundColor Cyan

    # VBS/Hyper-V Off (Matches Registry settings)
    Invoke-BcdEdit "/set hypervisorlaunchtype off" "Hypervisor Launch Type Off"
    Invoke-BcdEdit "/set isolatedcontext no" "Isolated Context Off"
    Invoke-BcdEdit "/set vsmlaunchtype off" "VSM Launch Type Off"

    # Clock/Ticks
    Invoke-BcdEdit "/set useplatformclock no" "Use Platform Clock Off"
    Invoke-BcdEdit "/set useplatformtick no" "Use Platform Tick Off"
    Invoke-BcdEdit "/set disabledynamictick yes" "Disable Dynamic Tick"
    Invoke-BcdEdit "/set tscsyncpolicy Enhanced" "TSC Sync Policy Enhanced"

    # Security Settings (WARNING: These are dangerous)
    Write-Host " [WARNING] Disabling NX and Integrity Checks is a security risk!" -ForegroundColor Yellow
    Invoke-BcdEdit "/set nx AlwaysOff" "NX (DEP) AlwaysOff"
    Invoke-BcdEdit "/set tpmbootentropy ForceDisable" "TPM Boot Entropy Disabled"
    Invoke-BcdEdit "/set nointegritychecks on" "Driver Integrity Checks Disabled"

    # 19 Visual Effects（性能选项-视觉效果-自定义：仅开启平滑屏幕字体边缘 + 任务栏动画；
    #     另含「设置-辅助功能-视觉效果」四项：始终显示滚动条关 / 透明效果关 / 动画效果关 / 关闭通知 5 秒）
    Write-Host ""
    Write-Host "[Visual Effects 自定义 / Custom]" -ForegroundColor Cyan

    # 总开关：3 = 自定义（对话框按以下各项值显示勾选状态）
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 3 "VisualFXSetting = 3 (自定义)"

    # ---- 开启项 ----
    # 平滑屏幕字体边缘（ClearType）
    Set-RegString "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "平滑屏幕字体边缘 ON"
    Set-RegDword "HKCU:\Control Panel\Desktop" "FontSmoothingType" 2 "Font Smoothing = ClearType"
    # 任务栏中的动画
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 1 "任务栏动画 ON"

    # ---- 关闭项 ----
    # 菜单/组合框/列表框/工具提示动画、单击后淡出菜单、指针阴影、窗口下阴影（最佳性能位掩码）
    Set-RegBinary "HKCU:\Control Panel\Desktop" "UserPreferencesMask" "9012018010000000" "动画/淡入淡出/阴影全关"
    # 在最大化/最小化时显示窗口动画
    Set-RegString "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "最大/最小化动画 OFF"
    # 拖动时显示窗口内容
    Set-RegString "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "拖动显示窗口内容 OFF"
    # 显示亚透明的选择长方形
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" 0 "半透明选择框 OFF"
    # 在桌面上为图标标签使用阴影
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" 0 "图标标签阴影 OFF"
    # 显示缩略图而不是图标（IconsOnly=1 表示只显示图标）
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "IconsOnly" 1 "缩略图 OFF"
    # 保存任务栏缩略图预览（不写入缓存）
    Set-RegDword "HKCU:\Software\Microsoft\Windows\DWM" "AlwaysHibernateThumbnails" 0 "任务栏缩略图缓存 OFF"
    # 透明效果（如需保留透明改为 1）
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 "透明效果 OFF"

    # ---- 设置 → 辅助功能 → 视觉效果（四项，透明效果已由上面 EnableTransparency 覆盖）----
    # 始终显示滚动条 = 关（DynamicScrollbars: 1=自动隐藏, 0=始终显示）
    Set-RegDword "HKCU:\Control Panel\Accessibility" "DynamicScrollbars" 1 "始终显示滚动条 OFF"
    # 动画效果 = 关
    Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "AnimationEffects" 0 "动画效果(辅助功能) OFF"
    # 在此时间后关闭通知 = 5 秒
    Set-RegDword "HKCU:\Control Panel\Accessibility" "MessageDuration" 5 "通知自动关闭时长 = 5 秒"

    Write-Host " 视觉效果为 HKCU 设置，注销 / 重启（或重启资源管理器）后完全生效" -ForegroundColor Yellow

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 1 - System Optimization)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan

    # Auto restart in 5 seconds (press Q to cancel)
    Start-RestartCountdown -Seconds 5

} elseif ($choice -eq "2") {

    # ======================= Part 2: 开启测试模式 =======================
    # 独立步骤：开启测试模式 / Enable Test Mode (bcdedit)
    Write-Host ""
    Write-Host "============ [Part 2] 开启测试模式 / Enable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""

    Invoke-BcdEdit "/set testsigning on" "bcdedit /set testsigning on"
    Invoke-BcdEdit "/debug on" "bcdedit /debug on"
    Invoke-BcdEdit "/dbgsettings local" "bcdedit /dbgsettings local"
    Invoke-BcdEdit "/set nointegritychecks on" "bcdedit /set nointegritychecks on"

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 2 - Enable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：开启测试模式后桌面右下角会显示“测试模式”水印，属正常现象。" -ForegroundColor Yellow
    Write-Host "如需关闭测试模式，可运行: bcdedit /set testsigning off" -ForegroundColor Yellow

    # Auto restart in 5 seconds (press Q to cancel)
    Start-RestartCountdown -Seconds 5

} elseif ($choice -eq "3") {

    # ======================= Part 3: 关闭测试模式 =======================
    # 独立步骤：关闭测试模式 / Disable Test Mode（保留 nointegritychecks）
    Write-Host ""
    Write-Host "============ [Part 3] 关闭测试模式 / Disable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：此操作通过删除 testsigning 和 debug 启动项来关闭测试模式，保留 nointegritychecks。" -ForegroundColor Yellow
    Write-Host ""

    Invoke-BcdEdit "/deletevalue testsigning" "bcdedit /deletevalue testsigning"
    Invoke-BcdEdit "/deletevalue debug" "bcdedit /deletevalue debug"

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 3 - Disable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：测试模式已关闭，桌面右下角的"测试模式"水印将在重启后消失。" -ForegroundColor Yellow
    Write-Host "如需重新开启测试模式，可运行选项 2。" -ForegroundColor Yellow

    # Auto restart in 5 seconds (press Q to cancel)
    Start-RestartCountdown -Seconds 5

} elseif ($choice -eq "4") {

    # ======================= Part 4: 关闭安全中心 =======================
    # 独立步骤：关闭 Windows Defender 安全中心 / Disable Security Center
    Write-Host ""
    Write-Host "============ [Part 4] 关闭安全中心 / Disable Security Center ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [WARNING] 此操作将禁用 Windows Defender 实时保护及相关安全服务！" -ForegroundColor Yellow
    Write-Host " [WARNING] This will disable Windows Defender realtime protection and related services!" -ForegroundColor Yellow
    Write-Host ""

    # --- Parent key: Windows Defender ---
    # HKLM\SOFTWARE\Policies\Microsoft\Windows Defender
    $defenderKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

    Set-RegDword $defenderKey "DisableAntiSpyware" 1 "DisableAntiSpyware"
    Set-RegDword $defenderKey "DisableAntiVirus" 1 "DisableAntiVirus"
    Set-RegDword $defenderKey "DisableRealtimeMonitoring" 1 "DisableRealtimeMonitoring"
    Set-RegDword $defenderKey "DisableRoutinelyTakingAction" 1 "DisableRoutinelyTakingAction"
    Set-RegDword $defenderKey "DisableSpecialRunningModes" 1 "DisableSpecialRunningModes"
    Set-RegDword $defenderKey "ServiceKeepAlive" 0 "ServiceKeepAlive"
    Set-RegDword $defenderKey "PUAProtection" 0 "PUAProtection"
    Set-RegDword $defenderKey "AllowFastServiceStartup" 0 "AllowFastServiceStartup"
    Set-RegDword $defenderKey "DisableLocalAdminMerge" 1 "DisableLocalAdminMerge"
    Set-RegDword $defenderKey "RandomizeScheduleTaskTimes" 0 "RandomizeScheduleTaskTimes"

    # --- Subkey: Real-Time Protection ---
    # HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection
    $rtpKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"

    Set-RegDword $rtpKey "DisableAntivirus" 1 "RTP DisableAntivirus"
    Set-RegDword $rtpKey "DisableBehaviorMonitoring" 1 "RTP DisableBehaviorMonitoring"
    Set-RegDword $rtpKey "DisableOnAccessProtection" 1 "RTP DisableOnAccessProtection"
    Set-RegDword $rtpKey "DisableScanOnRealtimeEnable" 1 "RTP DisableScanOnRealtimeEnable"
    Set-RegDword $rtpKey "DisableRealtimeMonitoring" 1 "RTP DisableRealtimeMonitoring"
    Set-RegDword $rtpKey "DisableIOAVProtection" 1 "RTP DisableIOAVProtection"
    Set-RegDword $rtpKey "DisableScriptScanning" 1 "RTP DisableScriptScanning"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableOnAccessProtection" 0 "RTP LSO DisableOnAccessProtection"
    Set-RegDword $rtpKey "LocalSettingOverrideRealtimeScanDirection" 0 "RTP LSO RealtimeScanDirection"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableIOAVProtection" 0 "RTP LSO DisableIOAVProtection"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableBehaviorMonitoring" 0 "RTP LSO DisableBehaviorMonitoring"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableIntrusionPreventionSystem" 0 "RTP LSO DisableIntrusionPreventionSystem"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableRealtimeMonitoring" 0 "RTP LSO DisableRealtimeMonitoring"
    Set-RegDword $rtpKey "RealtimeScanDirection" 2 "RTP RealtimeScanDirection"
    Set-RegDword $rtpKey "DisableInformationProtectionControl" 1 "RTP DisableInformationProtectionControl"
    Set-RegDword $rtpKey "DisableIntrusionPreventionSystem" 1 "RTP DisableIntrusionPreventionSystem"
    Set-RegDword $rtpKey "DisableRawWriteNotification" 1 "RTP DisableRawWriteNotification"

    # --- Subkey: Spynet ---
    $spynetKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"

    Set-RegDword $spynetKey "DisableBlockAtFirstSeen" 1 "Spynet DisableBlockAtFirstSeen"
    Set-RegDword $spynetKey "LocalSettingOverrideSpynetReporting" 0 "Spynet LocalSettingOverrideSpynetReporting"
    Set-RegDword $spynetKey "SpynetReporting" 0 "Spynet SpynetReporting"
    Set-RegDword $spynetKey "SubmitSamplesConsent" 2 "Spynet SubmitSamplesConsent"

    # --- Subkey: Signature Updates ---
    $signatureKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates"

    Set-RegDword $signatureKey "SignatureDisableNotification" 1 "SignatureUpdates SignatureDisableNotification"
    Set-RegDword $signatureKey "RealtimeSignatureDelivery" 0 "SignatureUpdates RealtimeSignatureDelivery"
    Set-RegDword $signatureKey "ForceUpdateFromMU" 0 "SignatureUpdates ForceUpdateFromMU"
    Set-RegDword $signatureKey "DisableScheduledSignatureUpdateOnBattery" 1 "SignatureUpdates DisableScheduledSignatureUpdateOnBattery"
    Set-RegDword $signatureKey "UpdateOnStartUp" 0 "SignatureUpdates UpdateOnStartUp"
    Set-RegDword $signatureKey "SignatureUpdateCatchupInterval" 2 "SignatureUpdates SignatureUpdateCatchupInterval"
    Set-RegDword $signatureKey "DisableUpdateOnStartupWithoutEngine" 1 "SignatureUpdates DisableUpdateOnStartupWithoutEngine"
    Set-RegDword $signatureKey "ScheduleTime" 1440 "SignatureUpdates ScheduleTime"
    Set-RegDword $signatureKey "DisableScanOnUpdate" 1 "SignatureUpdates DisableScanOnUpdate"

    # --- Subkey: Scan ---
    $scanKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan"

    Set-RegDword $scanKey "LowCpuPriority" 1 "Scan LowCpuPriority"
    Set-RegDword $scanKey "DisableRestorePoint" 1 "Scan DisableRestorePoint"
    Set-RegDword $scanKey "DisableArchiveScanning" 0 "Scan DisableArchiveScanning"
    Set-RegDword $scanKey "DisableScanningNetworkFiles" 0 "Scan DisableScanningNetworkFiles"
    Set-RegDword $scanKey "DisableCatchupFullScan" 0 "Scan DisableCatchupFullScan"
    Set-RegDword $scanKey "DisableCatchupQuickScan" 1 "Scan DisableCatchupQuickScan"
    Set-RegDword $scanKey "DisableEmailScanning" 0 "Scan DisableEmailScanning"
    Set-RegDword $scanKey "DisableHeuristics" 1 "Scan DisableHeuristics"
    Set-RegDword $scanKey "DisableReparsePointScanning" 1 "Scan DisableReparsePointScanning"

    # --- Subkey: UX Configuration ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration" "SuppressRebootNotification" 1 "UX SuppressRebootNotification"

    # --- Subkey: Reporting ---
    $reportingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting"

    Set-RegDword $reportingKey "DisableEnhancedNotifications" 1 "Reporting DisableEnhancedNotifications"
    Set-RegDword $reportingKey "DisableGenericRePorts" 1 "Reporting DisableGenericRePorts"
    Set-RegDword $reportingKey "WppTracingLevel" 0 "Reporting WppTracingLevel"
    Set-RegDword $reportingKey "WppTracingComponents" 0 "Reporting WppTracingComponents"

    # --- Subkey: MpEngine ---
    $mpEngineKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine"

    Set-RegDword $mpEngineKey "MpEnablePus" 0 "MpEngine MpEnablePus"
    Set-RegDword $mpEngineKey "MpCloudBlockLevel" 0 "MpEngine MpCloudBlockLevel"
    Set-RegDword $mpEngineKey "MpBafsExtendedTimeout" 0 "MpEngine MpBafsExtendedTimeout"
    Set-RegDword $mpEngineKey "EnableFileHashComputation" 0 "MpEngine EnableFileHashComputation"

    # --- Subkey: NIS Consumers IPS ---
    $nisKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS"

    Set-RegDword $nisKey "ThrottleDetectionEventsRate" 0 "NIS ThrottleDetectionEventsRate"
    Set-RegDword $nisKey "DisableSignatureRetirement" 1 "NIS DisableSignatureRetirement"
    Set-RegDword $nisKey "DisableProtocolRecognition" 1 "NIS DisableProtocolRecognition"

    # --- Subkey: Policy Manager ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" "DisableScanningNetworkFiles" 1 "PolicyManager DisableScanningNetworkFiles"

    # --- Subkey: Exclusions ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions" "DisableAutoExclusions" 1 "Exclusions DisableAutoExclusions"

    # --- Subkey: Exploit Guard ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access" "EnableControlledFolderAccess" 0 "ExploitGuard ControlledFolderAccess"
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection" "EnableNetworkProtection" 0 "ExploitGuard NetworkProtection"

    # --- Legacy path: Microsoft Antimalware ---
    $legacyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware"

    Set-RegDword $legacyKey "ServiceKeepAlive" 0 "Legacy ServiceKeepAlive"
    Set-RegDword $legacyKey "AllowFastServiceStartup" 0 "Legacy AllowFastServiceStartup"
    Set-RegDword $legacyKey "DisableRoutinelyTakingAction" 1 "Legacy DisableRoutinelyTakingAction"
    Set-RegDword $legacyKey "DisableAntiSpyware" 1 "Legacy DisableAntiSpyware"
    Set-RegDword $legacyKey "DisableAntiVirus" 1 "Legacy DisableAntiVirus"
    Set-RegDword "$legacyKey\SpyNet" "SpyNetReporting" 0 "Legacy SpyNet SpyNetReporting"
    Set-RegDword "$legacyKey\SpyNet" "LocalSettingOverrideSpyNetReporting" 0 "Legacy SpyNet LocalSettingOverrideSpyNetReporting"

    # --- WOW6432Node (32-bit compatibility) ---
    Set-RegDword "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender" "DisableRoutinelyTakingAction" 1 "WOW6432Node DisableRoutinelyTakingAction"

    # --- Smart App Control state ---
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" "VerifiedAndReputablePolicyState" 0 "SmartAppControl VerifiedAndReputablePolicyState"

    # --- SmartScreen ---
    # HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen
    $smartScreenKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen"

    Set-RegDword $smartScreenKey "Enabled" 0 "SmartScreen Enabled"
    Set-RegDword $smartScreenKey "EnableSmartScreenInShell" 0 "SmartScreen EnableSmartScreenInShell"
    Set-RegDword $smartScreenKey "ConfigureAppInstallControlEnabled" 1 "SmartScreen ConfigureAppInstallControlEnabled"
    Set-RegString $smartScreenKey "ConfigureAppInstallControl" "Anywhere" "SmartScreen ConfigureAppInstallControl"

    # HKLM\SOFTWARE\Policies\Microsoft\Windows\System
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0 "System EnableSmartScreen"

    # HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer
    Set-RegString "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "Explorer SmartScreenEnabled"

    # --- Edge SmartScreen ---
    $edgeSmartScreenKey = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter"
    Set-RegDword $edgeSmartScreenKey "EnabledV9" 0 "Edge SmartScreen EnabledV9"
    Set-RegDword $edgeSmartScreenKey "PreventOverride" 0 "Edge SmartScreen PreventOverride"

    # HKCU Edge SmartScreen
    Set-RegDword "HKCU:\Software\Microsoft\Edge" "SmartScreenEnabled" 0 "HKCU Edge SmartScreenEnabled"

    # HKCU AppHost (Microsoft Store apps SmartScreen)
    $appHostKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost"
    Set-RegDword $appHostKey "EnableWebContentEvaluation" 0 "AppHost EnableWebContentEvaluation"
    Set-RegDword $appHostKey "PreventOverride" 0 "AppHost PreventOverride"

    # PolicyManager SmartScreen defaults
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen" "value" 0 "PolicyManager Browser AllowSmartScreen"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell" "value" 0 "PolicyManager SmartScreen InShell"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl" "value" 0 "PolicyManager SmartScreen AppInstallControl"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell" "value" 0 "PolicyManager SmartScreen PreventOverrideForFiles"

    # --- Security Center notifications ---
    $wdscNotifKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
    Set-RegDword $wdscNotifKey "DisableEnhancedNotifications" 1 "WDSC DisableEnhancedNotifications"
    Set-RegDword $wdscNotifKey "DisableNotifications" 1 "WDSC DisableNotifications"

    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Security Center" "FirstRunDisabled" 1 "SecurityCenter FirstRunDisabled"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Security Center" "AntiVirusOverride" 1 "SecurityCenter AntiVirusOverride"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Security Center" "FirewallOverride" 1 "SecurityCenter FirewallOverride"

    # HKCU Security and Maintenance toast notification
    Set-RegDword "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" "Enabled" 0 "SecurityToast Enabled"

    # --- Stop Windows Defender Service ---
    Write-Host ""
    Write-Host "[Windows Defender Service]" -ForegroundColor Cyan
    $defenderSvc = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    if ($defenderSvc) {
        try {
            Stop-Service -Name "WinDefend" -Force -ErrorAction Stop
            Set-Service -Name "WinDefend" -StartupType Disabled -ErrorAction Stop
            Write-Host "[OK] Windows Defender Service stopped and disabled"
            $ok++
        } catch {
            Write-Host "[FAIL] Windows Defender Service : $($_.Exception.Message)" -ForegroundColor Red
            $fail++
        }
    } else {
        Write-Host "[SKIP] Windows Defender Service not found (already removed or not installed)" -ForegroundColor Yellow
        $skip++
    }

    # --- Optional: Deletion-type optimizations (Y/N) ---
    Write-Host ""
    Write-Host "[删除类优化 / Deletion-type Optimizations]" -ForegroundColor Cyan
    Write-Host " 包括：停止并禁用 Defender 相关服务、删除 Defender 计划任务、" -ForegroundColor Gray
    Write-Host " 删除安全中心自启动项、移除安全中心界面 (SecHealthUI)。" -ForegroundColor Gray
    $delChoice = Read-Host "是否执行删除类优化？Y = 确定 / N = 取消跳过 (Y = yes, N = no)"
    if ($delChoice -eq "Y" -or $delChoice -eq "y") {

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

        # 2) Delete Defender scheduled tasks
        Write-Host ""
        Write-Host "[Defender Scheduled Tasks]" -ForegroundColor Cyan
        $defenderTasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" -ErrorAction SilentlyContinue
        if ($defenderTasks) {
            foreach ($task in $defenderTasks) {
                try {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Host ("[OK] Task deleted: {0}{1}" -f $task.TaskPath, $task.TaskName)
                    $ok++
                } catch {
                    Write-Host ("[FAIL] Task {0}{1} : {2}" -f $task.TaskPath, $task.TaskName, $_.Exception.Message) -ForegroundColor Red
                    $fail++
                }
            }
        } else {
            Write-Host "[SKIP] No Defender scheduled tasks found" -ForegroundColor Yellow
            $skip++
        }

        # 3) Remove SecurityHealth / Windows Defender startup entries
        Write-Host ""
        Write-Host "[Startup Entries]" -ForegroundColor Cyan
        $startupItems = @(
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "SecurityHealth" },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; Name = "SecurityHealth" },
            @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Windows Defender" },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "WindowsDefender" }
        )
        foreach ($item in $startupItems) {
            $existing = Get-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
            if ($existing) {
                try {
                    Remove-ItemProperty -Path $item.Path -Name $item.Name -Force -ErrorAction Stop
                    Write-Host ("[OK] Startup entry removed: {0} -> {1}" -f $item.Path, $item.Name)
                    $ok++
                } catch {
                    Write-Host ("[FAIL] Startup entry {0} -> {1} : {2}" -f $item.Path, $item.Name, $_.Exception.Message) -ForegroundColor Red
                    $fail++
                }
            } else {
                Write-Host ("[SKIP] Startup entry not found: {0} -> {1}" -f $item.Path, $item.Name) -ForegroundColor Yellow
                $skip++
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
                    $ok++
                } else {
                    Write-Host "[SKIP] SecHealthUI not found" -ForegroundColor Yellow
                    $skip++
                }
            } catch {
                Write-Host "[FAIL] SecHealthUI : $($_.Exception.Message)" -ForegroundColor Red
                $fail++
            }
        } else {
            Write-Host "[SKIP] Appx module not available on this system" -ForegroundColor Yellow
            $skip++
        }

    } else {
        Write-Host "[SKIP] 删除类优化已取消/跳过 / Deletion-type optimizations skipped." -ForegroundColor Yellow
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 4 - Disable Security Center)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：Windows Defender 已被禁用，重启后生效。" -ForegroundColor Yellow
    Write-Host "如需恢复，可在 Windows 安全中心应用中手动开启实时保护。" -ForegroundColor Yellow

    # Auto restart in 5 seconds (press Q to cancel)
    Start-RestartCountdown -Seconds 5

} elseif ($choice -eq "5") {

    # ======================= Part 5: 优化服务项 =======================
    # 独立步骤：禁用可安全禁用的服务 + 将 Xbox / 蓝牙 / 嵌入模式服务恢复为手动
    Write-Host ""
    Write-Host "============ [Part 5] 优化服务项继续工作 / Service Optimization ============" -ForegroundColor Cyan
    Write-Host ""

    # 1) Disable safe-to-disable services
    Write-Host "[Safe Services: stop + disable]" -ForegroundColor Cyan
    $safeServices = @(
        "DPS","WdiServiceHost","WdiSystemHost","diagsvc",
        "DialogBlockingService","TrkWks","AppVClient","MsKeyboardFilter",
        "NetTcpPortSharing","CscService","ssh-agent","PhoneSvc","PcaSvc",
        "RemoteRegistry","RemoteAccess","SensorDataService","SensrSvc",
        "shpamsvc","UevAgentService","WalletService","wisvc","WSAIFabricSvc",
        "dmwappushservice","DusmSvc","tzautoupdate",
        "Spooler","WSearch","SysMain","edgeupdate","edgeupdatem"
    )
    foreach ($svc in $safeServices) {
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
    $manualServices = @(
        "XboxGipSvc","XblAuthManager","XboxNetApiSvc","XblGameSave","bthserv","embeddedmode","BITS"
    )
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

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 5 - Service Optimization)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    # Auto restart in 5 seconds (press Q to cancel)
    Start-RestartCountdown -Seconds 5

} elseif ($choice -eq "6") {

    # ======================= Part 6: 应用超性能电源计划 =======================
    # 独立步骤：备份当前电源计划 -> 导入并应用仓库自带的超性能计划 / 或恢复备份
    Write-Host ""
    Write-Host "============ [Part 6] 应用超性能电源计划 / Ultimate Performance Power Plan ============" -ForegroundColor Cyan
    Write-Host ""

    $planFile   = Join-Path $PSScriptRoot "ultimate-performance.pow"
    $backupFile = Join-Path $PSScriptRoot "power-backup.pow"

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
    Write-Host " Finished (Part 6 - Ultimate Performance Power Plan)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：可用 powercfg /getactivescheme 查看当前电源计划；" -ForegroundColor Yellow
    Write-Host "如需恢复原计划，再次运行本脚本并选择 6 -> 2。" -ForegroundColor Yellow

    # Auto restart in 5 seconds (press Q to cancel)
    Start-RestartCountdown -Seconds 5

} elseif ($choice -eq "7") {

    # ======================= Part 7: 启用原生 NVMe 驱动 =======================
    # 通过 Velocity 功能覆盖提前启用微软原生 NVMe 磁盘驱动 nvmedisk.sys
    # （仅作用于 NVMe 磁盘；USB 等其他总线磁盘仍使用 disk.sys）。
    # 安全模式加固为预防性写入：nvmedisk 设备类默认不在安全模式加载列表，
    # 不加固可能导致启用后无法进入安全模式。
    Write-Host ""
    Write-Host "============ [Part 7] 启用原生 NVMe 驱动 / Native NVMe Driver (nvmedisk.sys) ============" -ForegroundColor Cyan
    Write-Host ""

    # 前提检查：系统版本（需 25H2 / build 26200 及以上）与 NVMe 磁盘
    $cvKey = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildNum = [int]($cvKey.GetValue('CurrentBuildNumber'))
    $dispVer = [string]($cvKey.GetValue('DisplayVersion'))
    $nvmeDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'NVMe' })
    Write-Host ("系统版本 : $dispVer (build $buildNum)")
    Write-Host ("NVMe 磁盘 : " + $(if ($nvmeDisks.Count -gt 0) { "检测到 $($nvmeDisks.Count) 块" } else { "未检测到" }))

    if ($nvmeDisks.Count -eq 0) {
        Write-Host ""
        Write-Host "[SKIP] 未检测到 NVMe 磁盘，本项无作用，已跳过（不重启）" -ForegroundColor Yellow
    } else {
        $fmPath = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
        $sbGuid = '{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}'
        $velocityIds = @('735209102', '1853569164', '156965516')

        Write-Host ""
        Write-Host "  0. 查看当前状态（只读检查：覆盖值 / 安全模式加固 / 驱动文件 / 加载状态）" -ForegroundColor White
        Write-Host "  1. 启用（写入 3 个 Velocity 覆盖值 + 2 条安全模式加固，重启后生效）" -ForegroundColor White
        Write-Host "  2. 还原（删除 3 个覆盖值，恢复系统默认；安全模式加固保留）" -ForegroundColor White
        $nChoice = Read-Host "请输入 0、1 或 2 并回车 (Enter 0, 1 or 2)"

        if ($nChoice -eq "0") {

            # 只读状态检查，不做任何修改
            $fmItem0 = Get-Item $fmPath -ErrorAction SilentlyContinue
            $velText = @()
            foreach ($vid in $velocityIds) {
                if ($fmItem0 -and ($fmItem0.GetValueNames() -contains $vid)) { $velText += "$vid=1" }
                else { $velText += "$vid=未写入" }
            }
            $allWritten = @($velText | Where-Object { $_ -like "*=1" }).Count -eq 3
            Write-Host ("Velocity 覆盖值 : " + ($velText -join "  "))

            $sbMinOk = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Minimal\$sbGuid"
            $sbNetOk = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Network\$sbGuid"
            Write-Host ("SafeBoot 加固   : Minimal=" + $(if ($sbMinOk) { "已有" } else { "缺失" }) + "  Network=" + $(if ($sbNetOk) { "已有" } else { "缺失" }))

            $drvFile = "$env:SystemRoot\System32\drivers\nvmedisk.sys"
            $fileThere = Test-Path $drvFile
            if ($fileThere) {
                Write-Host ("nvmedisk.sys 文件: 已分发 (" + (Get-Item $drvFile).VersionInfo.FileVersion + ")")
            } else {
                Write-Host "nvmedisk.sys 文件: 未分发（当前系统不带此驱动）"
            }
            $drvState = (Get-CimInstance Win32_SystemDriver -Filter "Name='nvmedisk'" -ErrorAction SilentlyContinue).State
            Write-Host ("nvmedisk 驱动状态: " + $(if ($drvState) { $drvState } else { "未加载" }))

            Write-Host ""
            if (-not $fileThere) {
                Write-Host "结论：系统未分发 nvmedisk.sys，当前版本无法启用原生 NVMe 驱动" -ForegroundColor Yellow
            } elseif ($drvState -eq "Running") {
                Write-Host "结论：原生 NVMe 驱动已启用并正在运行（NVMe 磁盘已使用 nvmedisk.sys）" -ForegroundColor Green
            } elseif ($allWritten) {
                Write-Host "结论：覆盖值已写入，重启后生效；若重启后仍未切换，运行 7 -> 0 再查" -ForegroundColor Yellow
            } else {
                Write-Host "结论：未启用（覆盖值未写入）。选择 7 -> 1 启用" -ForegroundColor Yellow
            }

        } elseif ($nChoice -eq "1") {

            $proceed = $true
            if ($buildNum -lt 26200) {
                Write-Host ""
                Write-Host "[WARNING] build $buildNum 低于 26200（25H2）。实测：24H2（26100.x，含十月更新批次 26100.2454）无法启用，仅 25H2（26200+）支持" -ForegroundColor Yellow
                $confirmNvme = Read-Host "仍要继续吗？(Y = 继续 / N = 取消)"
                if ($confirmNvme -notin @('Y', 'y')) { $proceed = $false }
            }

            if (-not $proceed) {
                Write-Host "[SKIP] 已取消，未做任何修改（不重启）" -ForegroundColor Yellow
            } else {
                # 三个 Velocity 功能覆盖值（启用 nvmedisk.sys 灰度功能）
                foreach ($vid in $velocityIds) {
                    Set-RegDword $fmPath $vid 1 "Velocity $vid"
                }

                # 安全模式加固：将 nvmedisk 设备类加入安全模式加载列表
                foreach ($mode in @('Minimal', 'Network')) {
                    $sbReg = Convert-RegExePath "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
                    & reg.exe ADD $sbReg /ve /d "Storage Disks" /f *> $null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[OK] SafeBoot $mode 加固 = Storage Disks"
                        $script:ok++
                    } else {
                        Write-Host ("[FAIL] SafeBoot $mode 加固 : reg.exe exit code $LASTEXITCODE") -ForegroundColor Red
                        $script:fail++
                    }
                }

                # Summary
                Write-Host ""
                Write-Host "============================================================" -ForegroundColor Cyan
                Write-Host " Finished (Part 7 - Native NVMe Driver ENABLE)" -ForegroundColor Cyan
                Write-Host " OK : $ok" -ForegroundColor Green
                Write-Host " FAIL : $fail" -ForegroundColor Red
                Write-Host "============================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "重启后生效。可在 设备管理器 → 磁盘驱动器 → NVMe 磁盘属性 → 驱动程序 确认驱动文件为 nvmedisk.sys" -ForegroundColor Yellow
                Write-Host "如需还原，再次运行本脚本并选择 7 -> 2。" -ForegroundColor Yellow

                # Auto restart in 5 seconds (press Q to cancel)
                Start-RestartCountdown -Seconds 5
            }

        } elseif ($nChoice -eq "2") {

            $fmReg = Convert-RegExePath $fmPath
            $fmItem = Get-Item $fmPath -ErrorAction SilentlyContinue
            foreach ($vid in $velocityIds) {
                if ($fmItem -and ($fmItem.GetValueNames() -contains $vid)) {
                    & reg.exe DELETE $fmReg /v $vid /f *> $null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[OK] 已删除 Velocity $vid"
                        $script:ok++
                    } else {
                        Write-Host ("[FAIL] 删除 Velocity $vid : reg.exe exit code $LASTEXITCODE") -ForegroundColor Red
                        $script:fail++
                    }
                } else {
                    Write-Host "[SKIP] Velocity $vid 不存在（无需删除）" -ForegroundColor Yellow
                    $script:skip++
                }
            }
            Write-Host "安全模式加固项保留（无副作用，仅让安全模式额外加载存储驱动）" -ForegroundColor Yellow

            # Summary
            Write-Host ""
            Write-Host "============================================================" -ForegroundColor Cyan
            Write-Host " Finished (Part 7 - Native NVMe Driver RESTORE)" -ForegroundColor Cyan
            Write-Host " OK : $ok" -ForegroundColor Green
            Write-Host " FAIL : $fail" -ForegroundColor Red
            Write-Host "============================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "重启后恢复为系统默认磁盘驱动 (disk.sys)" -ForegroundColor Yellow

            # Auto restart in 5 seconds (press Q to cancel)
            Start-RestartCountdown -Seconds 5

        } else {
            Write-Host "[ERROR] 无效输入：$nChoice 。请输入 0、1 或 2 / Invalid input. Enter 0, 1 or 2." -ForegroundColor Red
        }
    }

} elseif ($choice -eq "8") {

    # ======================= Part 8: 清除 Device Guard EFI 锁定 =======================
    # 应对 UEFI 锁定：选项 1 已通过注册表关闭 VBS/HVCI/Credential Guard，
    # 但 安全中心 / msinfo32 仍显示"内存完整性"或"凭据保护"开启时，
    # 用 SecConfig.efi 引导清除 EFI 变量（硬手段，等效于官方 DG_Readiness_Tool）。
    Write-Host ""
    Write-Host "============ [Part 8] 清除 Device Guard EFI 锁定 / Clear DG UEFI Lock (SecConfig.efi) ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 适用场景：UEFI 锁定 —— 已运行选项 1（注册表关闭），但 安全中心/msinfo32 仍显示" -ForegroundColor Yellow
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

            # 1) BitLocker 预检查：任一分区保护开启则拒绝执行
            $blBlocked = $false
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
                Write-Host "[WARN] 无法查询 BitLocker 状态：$($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "        请自行确认 BitLocker 已关闭/解密后再继续" -ForegroundColor Yellow
            }

            if (-not $blBlocked) {

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

                            if ($copyOk) {

                                # 5) 配置一次性引导项（先删除可能残留的旧项，保证可重复执行）
                                & bcdedit.exe /delete $dgGuid /f *> $null
                                Invoke-BcdEdit "/create $dgGuid /d DebugTool /application osloader" "创建 BCD 引导项 (DebugTool)"
                                Invoke-BcdEdit "/set $dgGuid path \EFI\Microsoft\Boot\SecConfig.efi" "引导项路径 SecConfig.efi"
                                Invoke-BcdEdit "/set $dgGuid device partition=$($efiLetter):" "引导项设备分区 $($efiLetter):"
                                Invoke-BcdEdit "/set $dgGuid loadoptions DISABLE-LSA-ISO" "LoadOptions = DISABLE-LSA-ISO"
                                Invoke-BcdEdit "/set {bootmgr} bootsequence $dgGuid" "设为下次开机一次性引导"
                            }

                            # 6) 卸载 EFI 分区
                            & mountvol.exe "$($efiLetter):" /d *> $null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[OK] EFI 分区已卸载（$($efiLetter):）"
                                $ok++
                            } else {
                                Write-Host "[WARN] EFI 分区卸载失败，可稍后手动执行: mountvol $($efiLetter): /d" -ForegroundColor Yellow
                            }

                            if ($copyOk) {
                                # Summary
                                Write-Host ""
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host " Finished (Part 8 - Clear DG UEFI Lock)" -ForegroundColor Cyan
                                Write-Host " OK : $ok" -ForegroundColor Green
                                Write-Host " FAIL : $fail" -ForegroundColor Red
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host ""
                                Write-Host " 重启开机会出现确认界面，请按屏幕提示按键（通常为 F3）确认禁用！" -ForegroundColor Yellow
                                Write-Host " 重启确认后可用 msinfo32 -> 系统摘要 -> 基于虚拟化的安全性 验证是否已关闭。" -ForegroundColor Yellow

                                # Auto restart in 5 seconds (press Q to cancel)
                                Start-RestartCountdown -Seconds 5
                            } else {
                                Write-Host ""
                                Write-Host "[提示] SecConfig.efi 复制失败，未配置任何引导项，无需重启" -ForegroundColor Yellow
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
        Write-Host " Finished (Part 8 - Cleanup)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "提示：清理完成，无需重启。" -ForegroundColor Yellow

    } else {
        Write-Host "[ERROR] 无效输入：$gChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
    }

} else {
    Write-Host ""
    Write-Host "[ERROR] 无效输入：$choice 。请输入 1、2、3、4、5、6、7 或 8 / Invalid input. Enter 1, 2, 3, 4, 5, 6, 7 or 8." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
