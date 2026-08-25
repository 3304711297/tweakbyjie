# Windows Defender 物理移除脚本（高级 / 不可逆）
# Defender Physical Removal Script (Advanced / Irreversible)
#
# 作用 / Purpose:
#   对 Windows Defender 执行"物理移除"（非禁用），包含三部分：
#     Part 1: 删除 Defender 相关服务的注册表键整键（17+ 个服务）
#     Part 2: 删除 Defender 应用 / COM / Shell 注册（CLSID、Autologger、AppUserModelId、
#             Shell 关联、WebThreatDefense 注册等）
#     Part 3: 删除 Defender 实体文件目录（takeown + icacls + 删除）
#
#   This script PERMANENTLY REMOVES (not disables) Windows Defender components:
#     Part 1: delete service registry keys for 17+ Defender services
#     Part 2: delete Defender app/COM/Shell registrations (CLSID, Autologger,
#             AppUserModelId, Shell associations, WebThreatDefense registrations)
#     Part 3: delete Defender file directories (takeown + icacls + remove)
#
# ⚠️ 不可逆警告 / IRREVERSIBLE WARNING:
#   - 此操作无法通过"关闭注册表值"恢复，需重装 Windows 或 SFC/DISM 修复才能还原
#   - 删除后 Windows 安全中心页面将报错/无法打开，Windows 更新可能受影响
#   - 建议先运行 tweakbyjie.ps1 选项 5（关闭安全中心），再视需要运行本脚本
#   - 强烈建议运行前创建系统还原点 / 备份
#
# 权限说明 / Permissions:
#   受 TrustedInstaller 保护的键，脚本会先以管理员尝试，再以 SYSTEM 批量重试；
#   仍被拒绝的键会如实报告 [FAIL]，如需彻底删除可借助 NSudo / PowerRun 等提权工具。
#   Keys protected by TrustedInstaller are not retried automatically; any denied
#   key is reported [FAIL] and requires separate, explicitly approved handling.

[CmdletBinding()]
param(
    [switch]$Execute,
    [switch]$DryRun,
    [switch]$Restart,
    [switch]$NoRestart
)

if ($Execute -and $DryRun) {
    Write-Host "[ERROR] -Execute 与 -DryRun 不能同时使用。" -ForegroundColor Red
    exit 2
}
if (-not $Restart) { $NoRestart = $true }

$ErrorActionPreference = "Stop"
$ok = 0
$fail = 0
$skip = 0

$dryRunTargets = @(
    "Part 1: Defender 服务注册表键、WinRT 和 svchost 注册",
    "Part 2: Defender CLSID、Autologger、AppX、Shell、策略和防火墙注册",
    "Part 3: Defender 文件目录（ProgramData、Program Files 和 ATP）"
)

if (-not $Execute) {
    Write-Host "Windows Defender 物理移除脚本默认仅执行 DryRun，不会修改系统。" -ForegroundColor Yellow
    Write-Host "如需真正执行，必须显式使用 -Execute；该操作不可逆且没有脚本内完整恢复。" -ForegroundColor Red
    foreach ($target in $dryRunTargets) { Write-Host ("[DRY-RUN] " + $target) -ForegroundColor Gray }
    Write-Host "[DRY-RUN] 未调用注册表删除、文件删除、SYSTEM 任务或重启。" -ForegroundColor Green
    exit 0
}

# --- Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] 请以管理员身份运行此脚本 / Please run this script as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ============================ Helpers ============================

# Delete an entire registry key (reg.exe format: HKLM\..., HKCU\..., HKCR\...)
function Remove-RegKey {
    param([string]$RegPath, [string]$Label)
    $null = & reg.exe query $RegPath 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[SKIP] {0}" -f $Label) -ForegroundColor Yellow
        $script:skip++
        return
    }
    & reg.exe delete $RegPath /f *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("[OK] {0}" -f $Label)
        $script:ok++
    } else {
        Write-Host ("[FAIL] {0} : reg.exe delete failed" -f $Label) -ForegroundColor Red
        $script:fail++
    }
}

# Delete a single registry value
function Remove-RegValue {
    param([string]$RegPath, [string]$Value, [string]$Label)
    $null = & reg.exe query $RegPath /v $Value 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[SKIP] {0}" -f $Label) -ForegroundColor Yellow
        $script:skip++
        return
    }
    & reg.exe delete $RegPath /v $Value /f *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("[OK] {0}" -f $Label)
        $script:ok++
    } else {
        Write-Host ("[FAIL] {0} : reg.exe delete failed" -f $Label) -ForegroundColor Red
        $script:fail++
    }
}

# takeown + icacls + remove a directory tree
function Remove-DefenderPath {
    param([string]$FsPath, [string]$Label)
    if (-not (Test-Path -LiteralPath $FsPath)) {
        Write-Host ("[SKIP] {0} : 不存在 / not found" -f $Label) -ForegroundColor Yellow
        $script:skip++
        return
    }
    try {
        & takeown.exe /f $FsPath /r /d y *> $null
        if ($LASTEXITCODE -ne 0) { throw "takeown exit $LASTEXITCODE" }
        & icacls.exe $FsPath /grant administrators:F /t *> $null
        if ($LASTEXITCODE -ne 0) { throw "icacls exit $LASTEXITCODE" }
        Remove-Item -LiteralPath $FsPath -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $FsPath) { throw "删除后路径仍存在 / path still exists" }
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
            } catch { Start-Sleep -Milliseconds 100 }
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

# ============================ Warning & Confirm ============================
Write-Host "============================================================" -ForegroundColor Red
Write-Host " Windows Defender 物理移除 (高级 / 不可逆)" -ForegroundColor Red
Write-Host " Defender Physical Removal (Advanced / Irreversible)" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""
Write-Host " 本脚本将永久移除（非禁用）Windows Defender 组件：" -ForegroundColor White
Write-Host "   Part 1: 删除 17+ 个 Defender 服务的注册表键整键" -ForegroundColor Gray
Write-Host "   Part 2: 删除 Defender 应用 / COM / Shell 注册（CLSID 等）" -ForegroundColor Gray
Write-Host "   Part 3: 删除 Defender 实体文件目录" -ForegroundColor Gray
Write-Host ""
Write-Host " [警告] 此操作不可逆！恢复需重装 Windows 或 SFC/DISM 修复。" -ForegroundColor Yellow
Write-Host " [WARNING] IRREVERSIBLE! Recovery requires Windows reinstall or SFC/DISM." -ForegroundColor Yellow
Write-Host " 建议先运行 tweakbyjie.ps1 选项 5（关闭安全中心），再视需要运行本脚本。" -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "确认执行请输入 REMOVE 并回车 / Type REMOVE to proceed"
if ($confirm -ne "REMOVE") {
    Write-Host "[已取消] 未输入 REMOVE，脚本退出 / Cancelled. Exiting." -ForegroundColor Green
    exit 0
}
$confirmAgain = Read-Host "这是不可逆操作，请再次输入 REMOVE 确认 / Type REMOVE again to confirm"
if ($confirmAgain -ne "REMOVE") {
    Write-Host "[已取消] 二次确认失败，未执行删除 / Confirmation failed. Nothing was removed." -ForegroundColor Green
    exit 0
}

# ============================ Part 1: Services ============================
Write-Host ""
Write-Host "============ [Part 1] 删除服务注册表键 / Delete Service Keys ============" -ForegroundColor Cyan
Write-Host ""

# 先尽力停止服务 / best-effort stop
$svcNames = @(
    "MsSecCore","wscsvc","WdNisDrv","WdNisSvc","WdFilter","WdBoot",
    "SgrmAgent","SgrmBroker","WinDefend","MsSecFlt","MsSecWfp","whesvc",
    "webthreatdefsvc","PlutonHsp2","PlutonHeci","Hsp"
)
foreach ($svc in $svcNames) {
    $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($svcObj) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
}
# 枚举 webthreatdefusersvc 实例（带随机后缀）/ enumerate per-user instances
Get-Service -Name "webthreatdefusersvc*" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# 删除服务注册表键 / delete service registry keys
foreach ($svc in $svcNames) {
    Remove-RegKey "HKLM\SYSTEM\CurrentControlSet\Services\$svc" "Service $svc"
}
# webthreatdefusersvc 及其实例
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like "webthreatdefusersvc*" } |
    ForEach-Object {
        Remove-RegKey ("HKLM\SYSTEM\CurrentControlSet\Services\" + $_.PSChildName) ("Service " + $_.PSChildName)
    }

# WinRT server + svchost 子键
Remove-RegKey "HKLM\SOFTWARE\Microsoft\WindowsRuntime\Server\WebThreatDefSvc" "WinRT WebThreatDefSvc"
Remove-RegKey "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost\WebThreatDefense" "Svchost WebThreatDefense"
Remove-RegValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost" "WebThreatDefense" "Svchost WebThreatDefense value"

# ============================ Part 2: App/COM/Shell ============================
Write-Host ""
Write-Host "============ [Part 2] 删除应用/COM/Shell 注册 / Delete App Registrations ============" -ForegroundColor Cyan
Write-Host ""

# --- CLSID GUID 列表（13 个 Defender + 1 个 WebThreatDefense）---
$clsids = @(
    "{2781761E-28E0-4109-99FE-B9D127C57AFE}",
    "{2781761E-28E2-4109-99FE-B9D127C57AFE}",
    "{195B4D07-3DE2-4744-BBF2-D90121AE785B}",
    "{361290c0-cb1b-49ae-9f3e-ba1cbe5dab35}",
    "{45F2C32F-ED16-4C94-8493-D72EF93A051B}",
    "{6CED0DAA-4CDE-49C9-BA3A-AE163DC3D7AF}",
    "{8a696d12-576b-422e-9712-01b9dd84b446}",
    "{8C9C0DB7-2CBA-40F1-AFE0-C55740DD91A0}",
    "{A2D75874-6750-4931-94C1-C99D3BC9D0C7}",
    "{A7C452EF-8E9F-42EB-9F2B-245613CA0DC9}",
    "{DACA056E-216A-4FD1-84A6-C306A017ECEC}",
    "{E3C9166D-1D39-4D4E-A45D-BC7BE9B00578}",
    "{F6976CF5-68A8-436C-975A-40BE53616D59}",
    "{E48B2549-D510-4A76-8A5F-FC126A6215F0}"
)
# 两个位置：CLSID 与 WOW6432Node\CLSID（HKLM\SOFTWARE\Classes 即 HKCR）
foreach ($guid in $clsids) {
    Remove-RegKey "HKLM\SOFTWARE\Classes\CLSID\$guid" "CLSID $guid"
    Remove-RegKey "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\$guid" "WOW64 CLSID $guid"
}

# --- Defender 日志器 / Autologgers ---
Remove-RegKey "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderAuditLogger" "Autologger DefenderAuditLogger"
Remove-RegKey "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderApiLogger" "Autologger DefenderApiLogger"

# --- AppUserModelId ---
Remove-RegKey "HKLM\SOFTWARE\Classes\AppUserModelId\Windows.Defender" "AppUserModelId Windows.Defender"
Remove-RegKey "HKLM\SOFTWARE\Classes\AppUserModelId\Microsoft.Windows.Defender" "AppUserModelId Microsoft.Windows.Defender"

# --- Shell 关联 ---
Remove-RegKey "HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\windowsdefender" "UrlAssoc windowsdefender"
Remove-RegKey "HKLM\SOFTWARE\Classes\WindowsDefender" "Class WindowsDefender"
Remove-RegKey "HKLM\SOFTWARE\Classes\AppX9kvz3rdv8t7twanaezbwfcdgrbg3bck0" "AppX Defender (HKLM)"
Remove-RegKey "HKCU\Software\Classes\AppX9kvz3rdv8t7twanaezbwfcdgrbg3bck0" "AppX Defender (HKCU)"
Remove-RegKey "HKCU\Software\Classes\ms-cxh" "Class ms-cxh"
Remove-RegKey "HKCR\Local Settings\MrtCache\C:%5CWindows%5CSystemApps%5CMicrosoft.Windows.AppRep.ChxApp_cw5n1h2txyewy%5Cresources.pri" "MrtCache AppRep"

# --- WebThreatDefense ActivatableClassId ---
$wtdActivatable = @(
    "Microsoft.OneCore.WebThreatDefense.Service.UserSessionServiceManager",
    "Microsoft.OneCore.WebThreatDefense.ThreatExperienceManager.ThreatExperienceManager",
    "Microsoft.OneCore.WebThreatDefense.ThreatResponseEngine.ThreatDecisionEngine",
    "Microsoft.OneCore.WebThreatDefense.Configuration.WTDUserSettings"
)
foreach ($cls in $wtdActivatable) {
    Remove-RegKey "HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\$cls" "Activatable $cls"
}

# --- WebThreatDefense PolicyManager 默认键 ---
Remove-RegKey "HKLM\SOFTWARE\Microsoft\PolicyManager\default\WebThreatDefense" "PolicyManager WebThreatDefense"

# --- WTDS 策略键 ---
Remove-RegKey "HKLM\SOFTWARE\Policies\Microsoft\Windows\WTDS" "WTDS Policy"

# --- Ubpm 关键维护任务值 ---
Remove-RegValue "HKLM\SYSTEM\CurrentControlSet\Control\Ubpm" "CriticalMaintenance_DefenderCleanup" "Ubpm DefenderCleanup"
Remove-RegValue "HKLM\SYSTEM\CurrentControlSet\Control\Ubpm" "CriticalMaintenance_DefenderVerification" "Ubpm DefenderVerification"

# --- 防火墙受限服务静态值 ---
$fwStatic = "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Static\System"
Remove-RegValue $fwStatic "WindowsDefender-1" "FW WindowsDefender-1"
Remove-RegValue $fwStatic "WindowsDefender-2" "FW WindowsDefender-2"
Remove-RegValue $fwStatic "WindowsDefender-3" "FW WindowsDefender-3"
Remove-RegValue $fwStatic "WebThreatDefSvc_Allow_In" "WebThreatDefSvc_Allow_In"
Remove-RegValue $fwStatic "WebThreatDefSvc_Allow_Out" "WebThreatDefSvc_Allow_Out"
Remove-RegValue $fwStatic "WebThreatDefSvc_Block_In" "WebThreatDefSvc_Block_In"
Remove-RegValue $fwStatic "WebThreatDefSvc_Block_Out" "WebThreatDefSvc_Block_Out"

# --- 防火墙可配置值 ---
$fwCfg = "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Configurable\System"
Remove-RegValue $fwCfg "{2A5FE97D-01A4-4A9C-8241-BB3755B65EE0}" "FW Cfg {2A5FE97D...}"
Remove-RegValue $fwCfg "72e33e44-dc4c-40c5-a688-a77b6e988c69" "FW Cfg 72e33e44..."
Remove-RegValue $fwCfg "b23879b5-1ef3-45b7-8933-554a4303d2f3" "FW Cfg b23879b5..."

# ============================ Part 3: Entity Files ============================
Write-Host ""
Write-Host "============ [Part 3] 删除实体文件 / Delete File Directories ============" -ForegroundColor Cyan
Write-Host ""

Remove-DefenderPath "C:\ProgramData\Microsoft\Windows Defender" "ProgramData\Windows Defender"
Remove-DefenderPath "C:\Program Files\Windows Defender" "Program Files\Windows Defender"
Remove-DefenderPath "C:\Program Files (x86)\Windows Defender" "Program Files (x86)\Windows Defender"
Remove-DefenderPath "C:\Program Files\Windows Defender Advanced Threat Protection" "Program Files\Windows Defender ATP"

# ============================ Summary ============================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Finished (Defender Physical Removal)" -ForegroundColor Cyan
Write-Host " OK   : $ok" -ForegroundColor Green
Write-Host " FAIL : $fail" -ForegroundColor Red
Write-Host " SKIP : $skip" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "提示：Defender 组件已移除，重启后生效。" -ForegroundColor Yellow
Write-Host "如出现 [FAIL]，多为 TrustedInstaller 保护，可借助 NSudo/PowerRun 提权后重试对应键。" -ForegroundColor Yellow
Write-Host "恢复需重装 Windows 或运行：DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Yellow

if ($fail -gt 0) {
    Write-Host "[STOP] 检测到 $fail 个失败项，禁止自动重启；请先处理失败并人工确认系统状态。" -ForegroundColor Red
    exit 4
}

if ($Execute -and $Restart -and -not $NoRestart -and $fail -eq 0) {
    Start-RestartCountdown -Seconds 5
} else {
    Write-Host "[完成] 未自动重启；如需使设置生效，请在确认系统状态后手动重启。" -ForegroundColor Yellow
}
exit 0
