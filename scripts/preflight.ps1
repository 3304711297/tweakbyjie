# scripts/preflight.ps1 - 启动预检 + 模块前置条件映射（外围控制层）
#
# 设计约束（总原则边界）：
#   - 本文件只做"检测与可用性判断"，不执行任何系统修改；
#     既有优化模块的执行函数、Adapters、执行内容一律不变。
#   - 禁止"系统检测结果 → 全局禁用菜单"的大一统阻断：
#       检测项 → 模块 的映射见 Get-TweakModuleAvailability，
#       未被映射命中的模块永远可用；检测失败（$null/异常）一律按"不灰"处理（fail-open），
#       避免检测环境异常反而扩大禁用面。
#   - 第三方杀软检测仅用于限制与其明确冲突的模块（菜单 5），不作为统一阻断依据。

function Get-TweakPreflight {
    <#
        启动预检：检测 Windows 构建、VBS、BitLocker、Secure Boot、第三方杀软、ViVeTool 存在性。
        结果缓存到 $script:TweakPreflight（会话内只检测一次），并输出单行摘要
        （会话日志由 tweakbyjie.ps1 的 Start-Transcript 统一落盘，本摘要便于事后 grep）。
        任何单项检测失败都将该项记为 $null（未知），不抛出、不阻断启动。
    #>
    if ($script:TweakPreflight) { return $script:TweakPreflight }

    $result = [ordered]@{
        WindowsBuild  = $null
        VbsEnabled    = $null
        BitLockerOn   = $null
        SecureBoot    = $null
        ThirdPartyAv  = $null
        ViVeTool      = $null
    }

    # Windows 构建号
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $result.WindowsBuild = [int]$os.BuildNumber
    } catch { Write-Host "[PREFLIGHT] Windows 构建检测失败：$($_.Exception.Message)" -ForegroundColor Yellow }

    # VBS 运行状态（Win32_DeviceGuard.VirtualizationBasedSecurityStatus：2 = 运行中）
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' `
            -ClassName Win32_DeviceGuard -ErrorAction Stop | Select-Object -First 1
        if ($dg) { $result.VbsEnabled = ($dg.VirtualizationBasedSecurityStatus -eq 2) }
    } catch { Write-Host "[PREFLIGHT] VBS 状态检测失败：$($_.Exception.Message)" -ForegroundColor Yellow }

    # BitLocker：任一卷保护开启即为 On
    try {
        $blOn = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' })
        $result.BitLockerOn = ($blOn.Count -gt 0)
    } catch { Write-Host "[PREFLIGHT] BitLocker 检测失败：$($_.Exception.Message)" -ForegroundColor Yellow }

    # Secure Boot（非 UEFI 环境/权限不足会抛异常，记为未知）
    try {
        $result.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
    } catch { Write-Host "[PREFLIGHT] Secure Boot 检测失败（可能是 Legacy BIOS）：$($_.Exception.Message)" -ForegroundColor Yellow }

    # 第三方杀软：SecurityCenter2 中非 Microsoft Defender 的杀软产品
    try {
        $av = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
            Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' })
        $result.ThirdPartyAv = (@($av).Count -gt 0)
        if ($result.ThirdPartyAv) { $result.ThirdPartyAvNames = @($av | ForEach-Object displayName) }
    } catch { Write-Host "[PREFLIGHT] 杀软检测失败：$($_.Exception.Message)" -ForegroundColor Yellow }

    # ViVeTool 存在性（复用 Backup.Nvme.ps1 的 Find-ViVeTool，仅判断是否可找到）
    try {
        $result.ViVeTool = [bool](Find-ViVeTool)
    } catch { Write-Host "[PREFLIGHT] ViVeTool 检测失败：$($_.Exception.Message)" -ForegroundColor Yellow }

    $script:TweakPreflight = [pscustomobject]$result
    Write-Host ("[PREFLIGHT] build={0} vbs={1} bitlocker={2} secureboot={3} 三方杀软={4} vivetool={5}（未知项不参与灰掉）" -f `
        $(Format-PreflightValue $result.WindowsBuild), $(Format-PreflightValue $result.VbsEnabled), `
          $(Format-PreflightValue $result.BitLockerOn), $(Format-PreflightValue $result.SecureBoot), `
          $(Format-PreflightValue $result.ThirdPartyAv), $(Format-PreflightValue $result.ViVeTool)) -ForegroundColor DarkGray
    return $script:TweakPreflight
}

function Format-PreflightValue {
    # 摘要显示用：$null → unknown；布尔/其他 → 原值
    param($Value)
    if ($null -eq $Value) { return 'unknown' }
    return [string]$Value
}

function Get-TweakModuleAvailability {
    <#
        模块 → 前置条件映射（预检结果的唯一消费方）：
          3/4 测试模式        : Secure Boot 必须为关（开启时 testsigning 无法生效）
          5   关闭安全中心     : 不得有第三方杀软（安全中心类修改与其明确冲突）
          8   原生 NVMe       : 需要 ViVeTool（启用路径依赖 ViVeTool 特性开关）
          9   清除 EFI 锁     : BitLocker 必须为关（清除 EFI 变量改变 TPM 度量值会触发恢复模式；
                                与模块内既有 BitLocker 预检查同一判据，仅把拒绝提前到菜单层）
        其余模块（1/2/6/7/10/11）不设前置条件，永远可用。
        检测值未知（$null）→ 该判据不生效，模块保持可用（fail-open）。
        返回：hashtable，键 '1'..'11'，值 @{ Available = [bool]; Reason = [string] }
    #>
    param($Preflight)

    $p = if ($Preflight) { $Preflight } else { Get-TweakPreflight }
    $avail = @{}
    for ($i = 1; $i -le 11; $i++) { $avail[[string]$i] = @{ Available = $true; Reason = '' } }

    if ($p.SecureBoot -eq $true) {
        foreach ($n in @('3', '4')) {
            $avail[$n] = @{ Available = $false; Reason = 'Secure Boot 开启，测试模式无法生效' }
        }
    }
    if ($p.ThirdPartyAv -eq $true) {
        $names = if ($p.PSObject.Properties['ThirdPartyAvNames'] -and $p.ThirdPartyAvNames) {
            '（' + (@($p.ThirdPartyAvNames) -join '、') + '）' } else { '' }
        $avail['5'] = @{ Available = $false; Reason = "检测到第三方杀软$names，安全中心类修改与其冲突" }
    }
    if ($p.ViVeTool -eq $false) {
        $avail['8'] = @{ Available = $false; Reason = '未找到 ViVeTool.exe，原生 NVMe 启用路径不可用' }
    }
    if ($p.BitLockerOn -eq $true) {
        $avail['9'] = @{ Available = $false; Reason = 'BitLocker 已开启，清除 EFI 锁会触发恢复模式' }
    }
    return $avail
}

function Format-MenuAvailabilitySuffix {
    # 菜单行渲染辅助：不可用 → " [不适用]（原因）"；可用 → 空串
    param([string]$ModuleNumber, $Availability)
    $entry = $Availability[[string]$ModuleNumber]
    if ($entry -and -not $entry.Available) { return ("  [不适用]（{0}）" -f $entry.Reason) }
    return ''
}
