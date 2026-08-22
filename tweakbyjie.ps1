# Windows Game Optimization + BCDEdit Addons - Layered Menu Edition
# Run as Administrator. Each setting is applied independently.
# ActivationType is handled separately because the key may be protected.
#
# 菜单 / Menu:
#   输入 1 回车 = 核心性能分层菜单：核心游戏 / 系统行为 / CPU 安全缓解
#   输入 2 回车 = 高级 BCD / 计时器与启动安全（独立配置，修改前备份）
#   输入 3 回车 = 开启测试模式（bcdedit testsigning / debug / dbgsettings local / nointegritychecks）
#   输入 4 回车 = 关闭测试模式（删除 testsigning / debug 启动项，保留 nointegritychecks）
#   输入 5 回车 = 关闭安全中心（禁用 Defender/SmartScreen 策略并可选删除类优化；策略值自动快照，可按快照恢复）
#   输入 6 回车 = 服务优化（A/B 功能依赖分组，支持快照恢复）
#   输入 7 回车 = 超性能电源计划（备份并应用 / 恢复备份）
#   输入 8 回车 = 原生 NVMe 驱动配置（含 SafeBoot 快照）
#   输入 9 回车 = 清除 Device Guard EFI 锁定（SecConfig.efi 流程）
#   输入 10 回车 = 虚拟化 / VBS / Hyper-V 管理（删除脚本覆盖并尝试启用）
#   输入 11 回车 = MPO 设置管理（三方案互斥，修改前备份，可恢复）
#   修改完成后只标记待重启；退出主菜单时统一询问是否重启。

param(
    # 非交互执行指定模块：编号 0-11，支持逗号分隔（如 -RunModule '7,11'）；省略则进入交互菜单
    [string]$RunModule = ''
)

$ErrorActionPreference = "Continue"
# 版本号：与 Git tag（v*）及 CHANGELOG.md 对应，菜单标题会显示
$script:TweakVersion = '0.2.1'
$ok = 0
$fail = 0
$skip = 0

# --- Administrator check ---
# 本地开发/CI 可设 TWEAK_SKIP_ADMIN_CHECK=1 跳过（仅跳过检查，不会获得管理员权限）
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $env:TWEAK_SKIP_ADMIN_CHECK -ne '1') {
    Write-Host "[ERROR] 请以管理员身份运行此脚本 / Please run this script as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}


# --- Session log ---
# 仅在作为脚本执行时记录（点源加载不记录，避免测试污染）；日志位于 %LOCALAPPDATA%\tweakbyjie\logs
$__isScript = ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.CommandOrigin -ne 'DotSource')
if ($__isScript) {
    try {
        $__logDir = Join-Path $env:LOCALAPPDATA 'tweakbyjie\logs'
        New-Item -ItemType Directory -Path $__logDir -Force -ErrorAction Stop | Out-Null
        $__logFile = Join-Path $__logDir ("session-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Start-Transcript -Path $__logFile -ErrorAction Stop | Out-Null
        Write-Host "[LOG] 本次会话输出将记录到 $__logFile"
    } catch {
        Write-Host "[WARN] 会话日志启动失败：$($_.Exception.Message)" -ForegroundColor Yellow
    }
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
$script:defenderPolicyBackupFile = Join-Path $PSScriptRoot 'defender-policy-backup.json'

# 缺模块自检
$__tweakModules = @(
    'Modules/Common.ps1',
    'Modules/Backup.Mpo.ps1',
    'Modules/Backup.Bcd.ps1',
    'Modules/Backup.Service.ps1',
    'Modules/Backup.SecurityMitigation.ps1',
    'Modules/Backup.Nvme.ps1',
    'Modules/Backup.Defender.ps1',
    'Modules/Bcd.ps1',
    'Modules/Defender.ps1',
    'Modules/Mpo.ps1',
    'Modules/Nvme.ps1',
    'Modules/Power.ps1',
    'Modules/Registry.ps1',
    'Modules/Service.ps1',
    'Modules/Virtualization.ps1',
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

if ($__isScript) {
    $__validModules = @('0','1','2','3','4','5','6','7','8','9','10','11')
    $__requested = @($RunModule -split '[,，\s]+' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
    $__bad = @($__requested | Where-Object { $__validModules -notcontains $_ })
    if ($__bad.Count -gt 0) {
        Write-Host "[ERROR] 无效模块编号: $($__bad -join ',')（有效范围 0-11）" -ForegroundColor Red
        try { Stop-Transcript } catch {}
        exit 1
    }
    Show-TweakMenu -RunModules ($__requested -join ',')
    try { Stop-Transcript } catch {}
}
