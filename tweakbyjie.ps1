# Windows Game Optimization + BCDEdit Addons - Menu Edition
# Run as Administrator. Each setting is applied independently.
# ActivationType is handled separately because the key may be protected.
#
# 菜单 / Menu:
#   输入 1 回车 = 系统优化（原脚本全部内容），完成后 5 秒自动重启（按 Q 取消）
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
Write-Host ""
Write-Host " 注意：每个选项执行完成后都会在 5 秒后自动重启（期间按 Q 取消）" -ForegroundColor Yellow
Write-Host " NOTE: Each option auto-restarts after 5 seconds (press Q to cancel)." -ForegroundColor Yellow
Write-Host ""
$choice = Read-Host "请输入 1、2、3、4 或 5 并回车 (Enter 1, 2, 3, 4 or 5)"

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

    # 04 VBS / HVCI
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0 "HVCI Enabled"
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 0 "VBS EnableVirtualizationBasedSecurity"

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

} else {
    Write-Host ""
    Write-Host "[ERROR] 无效输入：$choice 。请输入 1、2、3、4 或 5 / Invalid input. Enter 1, 2, 3, 4 or 5." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
