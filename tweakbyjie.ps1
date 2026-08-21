# Windows Game Optimization + BCDEdit Addons - Layered Menu Edition
# Run as Administrator. Each setting is applied independently.
# ActivationType is handled separately because the key may be protected.
#
# 菜单 / Menu:
#   输入 1 回车 = 核心性能分层菜单：核心游戏 / 系统行为 / CPU 安全缓解
#   输入 2 回车 = 高级 BCD / 计时器与启动安全（独立配置，修改前备份）
#   输入 3 回车 = 开启测试模式（bcdedit testsigning / debug / dbgsettings local / nointegritychecks）
#   输入 4 回车 = 关闭测试模式（删除 testsigning / debug 启动项，保留 nointegritychecks）
#   输入 5 回车 = 关闭安全中心（禁用 Windows Defender / SmartScreen 策略，可选删除类优化）
#   输入 6 回车 = 服务优化（A/B 功能依赖分组，支持快照恢复）
#   输入 7 回车 = 超性能电源计划（备份并应用 / 恢复备份）
#   输入 8 回车 = 原生 NVMe 驱动配置（含 SafeBoot 快照）
#   输入 9 回车 = 清除 Device Guard EFI 锁定（SecConfig.efi 流程）
#   输入 10 回车 = 虚拟化 / VBS / Hyper-V 管理（删除脚本覆盖并尝试启用）
#   输入 11 回车 = MPO 设置管理（三方案互斥，修改前备份，可恢复）
#   修改完成后只标记待重启；退出主菜单时统一询问是否重启。

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


# --- Module loader ---
# 将功能拆到 Modules/，同时保持分发兼容与点源测试不卡死
# 保持现有语义：整仓下载、仓库根锚点、管理员检查、deferred reboot

# 仓库根锚点：模块函数体内的 $PSScriptRoot 指向 Modules/，
# 需要定位仓库根文件（ultimate-performance.pow、ViVeTool.exe 等）时一律用 $script:RepoRoot
$script:RepoRoot = $PSScriptRoot

# 统一状态（原分散在各处）
$script:mpoManagedValues = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'DisableMPO';      Desc = '驱动层禁用 MPO（旧方法）' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'DisableOverlays'; Desc = '驱动层禁用 MPO（更激进的社区排障方案）' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm';                   Name = 'OverlayTestMode'; Desc = 'DWM 层禁用 MPO（社区排障方案）' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm';                   Name = 'OverlayMinFPS';   Desc = '尝试避免低帧率时撤下 MPO' }
)
$script:mpoBackupFile = Join-Path $PSScriptRoot 'mpo-backup.json'
$script:mpoBackupReady = $false
$script:rebootRequired = $false
$script:bcdBackupFile = Join-Path $PSScriptRoot 'bcd-backup.json'
$script:bcdManagedValues = @('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy','nx','tpmbootentropy','nointegritychecks')
$script:serviceBackupFile = Join-Path $PSScriptRoot 'service-backup.json'
$script:securityMitigationBackupFile = Join-Path $PSScriptRoot 'security-mitigation-backup.json'
$script:securityMitigationValues = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverride' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverrideMask' }
)
$script:nvmeBackupFile = Join-Path $PSScriptRoot 'nvme-backup.json'

# 缺模块自检
$__tweakModules = @(
    'Modules/Common.ps1',
    'Modules/Backup.Mpo.ps1',
    'Modules/Backup.Bcd.ps1',
    'Modules/Backup.Service.ps1',
    'Modules/Backup.SecurityMitigation.ps1',
    'Modules/Backup.Nvme.ps1',
    'Modules/Menu.ps1'
)
foreach ($__m in $__tweakModules) {
    $__p = Join-Path $PSScriptRoot $__m
    if (-not (Test-Path $__p)) {
        Write-Host "[ERROR] 缺少模块 $__m，请下载完整仓库而非单独复制 .ps1" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    . $__p
}
Remove-Variable __tweakModules,__m,__p -ErrorAction SilentlyContinue

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.CommandOrigin -ne 'DotSource') {
    Show-TweakMenu
}
