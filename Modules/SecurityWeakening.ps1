# SecurityWeakening.ps1 - Part 20 XOS B 组「安全削弱」逐项落地
# 来源：docs/reference/XOS-PLAYBOOK-INVENTORY.md 3.2 节（imribiy/xos-playbook dev @0ed60c3）
#
# 定位：这一组按设计不提升帧率，只改变安全姿态。因此：
#   - 不做批量“一键全开”，13 项逐项执行，默认什么都不做；
#   - 每项执行前强制 I-UNDERSTAND-RISK 短语确认，B13 另用 I-UNDERSTAND-MITIGATIONS-OFF；
#   - 写入前落 security-weakening-backup.json（逐值原类型原值 + 进程缓解 XML），可整体恢复；
#   - 与已落地模块重叠的值不重复写（HVCI→菜单 10，CPU 侧信道缓解→菜单 1→3）。

$script:securityWeakeningItems = @(
    [pscustomobject]@{
        Id         = 'B01'
        Name       = 'Defender 篡改防护关闭（TamperProtection=0）'
        Warning    = '关掉篡改防护后，Defender 配置可被任意进程改写。该键受 TrustedInstaller 保护，普通管理员写入通常被拒绝 —— 本仓不提供提权绕过，失败会如实报告。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features'; Name = 'TamperProtection'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B02'
        Name       = '代码完整性与信誉策略关闭（VerifiedAndReputablePolicyState=0）'
        Warning    = '关闭 CI 信誉策略，未通过微软信誉判定的代码不再被该策略拦截。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'; Name = 'VerifiedAndReputablePolicyState'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B03'
        Name       = 'System Guard 启动校验与场景关闭'
        Warning    = '关闭 System Guard 的启动度量与场景。HVCI（HypervisorEnforcedCodeIntegrity\Enabled）已由菜单 10 统一管理，这里不重复写，避免两份快照争同一值。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'ConfigureSystemGuardLaunch'; Kind = 'DWord'; Value = 2 }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard'; Name = 'Enabled'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B04'
        Name       = '保留 Defender 但削弱云保护与样本上报'
        Warning    = '不关实时防护，只关云提交、样本上报、上报端口、电池下签名更新与 SmartScreen 应用安装管控。日志服务 Start 写 4（禁用）且只在服务键已存在时写；上游写 0 是 boot-start，达不到关闭目的。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Spynet'; Name = 'SubmitSamplesConsent'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Spynet'; Name = 'SpyNetReporting'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'SubmitSamplesConsent'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'SpyNetReporting'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\DefenderApiLogger'; Name = 'Start'; Kind = 'DWord'; Value = 4; RequireKey = $true }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\DefenderAuditLogger'; Name = 'Start'; Kind = 'DWord'; Value = 4; RequireKey = $true }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting'; Name = 'DisableGenericRePorts'; Kind = 'DWord'; Value = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'DisableScheduledSignatureUpdateOnBattery'; Kind = 'DWord'; Value = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'ConfigureAppInstallControlEnabled'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'ConfigureAppInstallControl'; Kind = 'String'; Value = 'Anywhere' }
        )
    }
    [pscustomobject]@{
        Id         = 'B05'
        Name       = 'UAC 关闭（EnableLUA=0 / 无安全桌面 / 管理员免提示）'
        Warning    = '关 UAC 后所有进程默认以管理员全权运行；微软账号登录可能失效（上游 playbook.conf 自注 may break Microsoft login）。EnableLUA 放最后写，前面失败不会留下半关状态。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'PromptOnSecureDesktop'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ConsentPromptBehaviorAdmin'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableLUA'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B06'
        Name       = '管理代码签名校验关闭（ValidateAdminCodeSignatures=0）'
        Warning    = '允许未签名管理代码运行。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'ValidateAdminCodeSignatures'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B07'
        Name       = 'CPU 侧信道缓解关闭（FeatureSettingsOverride / Mask = 3）'
        Warning    = '本项已由菜单 1 → 3 提供，且带 security-mitigation-backup.json 与回读校验；此处只做参考，不重复写入，避免两份快照争同一值。'
        Kind       = 'Reference'
        Reference  = '请使用 菜单 1 → 3（CPU 安全缓解调整）：1=查看 2=应用 3/3 3=按快照恢复。'
        Operations = @()
    }
    [pscustomobject]@{
        Id         = 'B08'
        Name       = 'svchost 缓解策略关闭（EnableSvchostMitigationPolicy=0）'
        Warning    = '关闭 SCM 对 svchost 的缓解策略（CFG 等）。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SCMConfig'; Name = 'EnableSvchostMitigationPolicy'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B09'
        Name       = 'KeyGuard 遥测关闭（DisableTelemetry=1）'
        Warning    = '弱化 KeyGuard 场景的可观测性。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\KeyGuard'; Name = 'DisableTelemetry'; Kind = 'DWord'; Value = 1 }
        )
    }
    [pscustomobject]@{
        Id         = 'B10'
        Name       = 'PowerShell 无限制执行并关闭脚本审计'
        Warning    = 'ExecutionPolicy=Unrestricted（机器策略 + 本地机器两处），并关闭模块日志与脚本块日志。写入后脚本内容不再进 4103/4104 事件。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'; Name = 'ExecutionPolicy'; Kind = 'String'; Value = 'Unrestricted' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'; Name = 'ExecutionPolicy'; Kind = 'String'; Value = 'Unrestricted' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'; Name = 'EnableModuleLogging'; Kind = 'DWord'; Value = 0 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name = 'EnableScriptBlockLogging'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B11'
        Name       = '受保护事件日志关闭（EnableProtectedEventLogging=0）'
        Warning    = '敏感事件不再按证书加密写入事件日志。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\ProtectedEventLogging'; Name = 'EnableProtectedEventLogging'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'B12'
        Name       = '内核 DMA 保护关闭（DeviceEnumerationPolicy=2 + 驱动 DmaRemappingCompatible=0）'
        Warning    = '允许所有外部 DMA 设备随时枚举，并关闭已声明该标志的驱动对 DMA 重映射的要求；物理接触者可利用 Thunderbolt/PCIe DMA 读取内存。只改已存在的 REG_DWORD，非 DWORD 记 skip。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection'; Name = 'DeviceEnumerationPolicy'; Kind = 'DWord'; Value = 2 }
        )
    }
    [pscustomobject]@{
        Id         = 'B13'
        Name       = '系统级进程缓解关闭 + 关键进程 MitigationOptions=0x22'
        Warning    = '最重的一项：Set-ProcessMitigation -System 关闭 DEP/ASLR/CFG/SEHOP/ACG 等系统默认缓解，并给 fontdrvhost/dwm/lsass/svchost/WmiPrvSE/winlogon/csrss/ntoskrnl/services 写 MitigationOptions/MitigationAuditOptions=0x22。快照包含完整进程缓解 XML，可整体还原。'
        Kind       = 'Registry'
        Reference  = ''
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\fontdrvhost.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\fontdrvhost.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\dwm.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\dwm.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\lsass.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\lsass.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\svchost.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\svchost.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\WmiPrvSE.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\WmiPrvSE.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\winlogon.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\winlogon.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ntoskrnl.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ntoskrnl.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\services.exe'; Name = 'MitigationOptions'; Kind = 'String'; Value = '0x22' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\services.exe'; Name = 'MitigationAuditOptions'; Kind = 'String'; Value = '0x22' }
        )
    }
)

function Get-SecurityWeakeningItems {
    return $script:securityWeakeningItems
}

function Test-SecurityWeakeningKeyPresent {
    # 仅用于 RequireKey 目标：服务键不存在时不凭空创建半条服务注册。
    param([string]$Path)
    return (Test-Path -LiteralPath $Path -PathType Container)
}

function Get-SecurityWeakeningDmaTargets {
    <# 枚举服务 Parameters 下已存在的 DmaRemappingCompatible；只改 REG_DWORD，非 DWORD 记 skip。 #>
    param([string]$ServicesRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services')
    $operations = @()
    $skips = @()
    if ([string]::IsNullOrWhiteSpace($ServicesRoot) -or -not (Test-Path -LiteralPath $ServicesRoot -PathType Container)) {
        return [pscustomobject]@{ Operations = @(); Skips = @() }
    }
    foreach ($serviceKey in @(Get-ChildItem -LiteralPath $ServicesRoot -ErrorAction SilentlyContinue)) {
        $parametersPath = Join-Path (ConvertTo-TweakRegistryPsPath ([string]$serviceKey.PSPath)) 'Parameters'
        $current = Get-TweakRegistryValue -Path $parametersPath -Name 'DmaRemappingCompatible'
        if (-not $current.Exists) { continue }
        if ($current.Kind -ne 'DWord') {
            $skips += [pscustomobject]@{ Scope = 'B12'; Path = $parametersPath; Name = 'DmaRemappingCompatible'; Kind = $current.Kind; Reason = '已存在但不是 REG_DWORD，按硬门禁跳过' }
            continue
        }
        $operations += [pscustomobject]@{ Scope = 'B12'; Path = $parametersPath; Name = 'DmaRemappingCompatible'; Kind = 'DWord'; Value = 0 }
    }
    return [pscustomobject]@{ Operations = @($operations); Skips = @($skips) }
}

function Get-SecurityWeakeningPlan {
    <# 展开指定 B 组项的全部写入目标；备份与应用共用同一份计划。 #>
    param([string[]]$ItemIds, [hashtable]$Roots)

    if ($null -eq $ItemIds -or @($ItemIds).Count -eq 0) { throw '必须指定至少一个 B 组项' }
    $known = @{}
    foreach ($item in $script:securityWeakeningItems) { $known[$item.Id] = $item }

    $operations = [System.Collections.Generic.List[object]]::new()
    $skips = [System.Collections.Generic.List[object]]::new()
    $ids = @()
    $includeProcessMitigations = $false

    foreach ($id in @($ItemIds)) {
        if (-not $known.ContainsKey($id)) { throw "未知的 B 组项：$id" }
        $item = $known[$id]
        $ids += $id
        foreach ($op in @($item.Operations)) {
            if ($op.ContainsKey('RequireKey') -and [bool]$op.RequireKey -and -not (Test-SecurityWeakeningKeyPresent -Path ([string]$op.Path))) {
                $skips.Add([pscustomobject]@{ Scope = $id; Path = [string]$op.Path; Name = [string]$op.Name; Kind = ''; Reason = '目标服务键不存在，跳过（不凭空创建服务项）' })
                continue
            }
            $operations.Add([pscustomobject]@{ Scope = $id; Path = [string]$op.Path; Name = [string]$op.Name; Kind = [string]$op.Kind; Value = $op.Value })
        }
        if ($id -eq 'B12') {
            $servicesRoot = if ($Roots -and $Roots.ContainsKey('Services')) { [string]$Roots.Services } else { 'HKLM:\SYSTEM\CurrentControlSet\Services' }
            $dma = Get-SecurityWeakeningDmaTargets -ServicesRoot $servicesRoot
            foreach ($op in @($dma.Operations)) { $operations.Add($op) }
            foreach ($skip in @($dma.Skips)) { $skips.Add($skip) }
        }
        if ($id -eq 'B13') { $includeProcessMitigations = $true }
    }

    $unique = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($op in $operations) {
        $key = ('{0}|{1}' -f $op.Path, $op.Name).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($op)
    }

    return [pscustomobject]@{
        ItemIds                 = @($ids)
        Operations              = @($unique)
        Skips                   = @($skips)
        IncludeProcessMitigations = $includeProcessMitigations
    }
}

function Set-SecurityWeakeningProcessMitigations {
    <# 系统级关闭已文档化的进程缓解，并回读 DEP 状态作为收敛判据。 #>
    if (-not (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue)) {
        throw '当前系统缺少 ProcessMitigations 模块（Set-ProcessMitigation 不可用）'
    }
    $mitigations = @('DEP', 'EmulateAtlThunks', 'SEHOP', 'ForceRelocate', 'BottomUp', 'HighEntropy', 'StrictHandle', 'DynamicCode', 'CFG', 'BlockRemoteImages', 'BlockLowLabel', 'PreferSystem32', 'ExtensionPoint', 'DisallowChildProcessCreation')
    Set-ProcessMitigation -System -Disable $mitigations -ErrorAction Stop
    $system = Get-ProcessMitigation -System -ErrorAction Stop
    if ($null -eq $system -or -not $system.PSObject.Properties['Dep'] -or -not $system.Dep.PSObject.Properties['Enable']) {
        throw '无法回读系统级 DEP 状态'
    }
    if ([string]$system.Dep.Enable -ne 'OFF') {
        throw "系统级 DEP 回读仍为 $($system.Dep.Enable)"
    }
    Write-Host '[OK] 系统级进程缓解已关闭（DEP 回读 = OFF）。' -ForegroundColor Yellow
}

function Show-SecurityWeakeningStatus {
    param([hashtable]$Roots)
    foreach ($item in $script:securityWeakeningItems) {
        Write-Host ("[{0}] {1}" -f $item.Id, $item.Name) -ForegroundColor Cyan
        if ($item.Kind -eq 'Reference') {
            Write-Host ("  参考：{0}" -f $item.Reference) -ForegroundColor Gray
            continue
        }
        foreach ($op in @($item.Operations)) {
            $current = Get-TweakRegistryValue -Path $op.Path -Name $op.Name
            $state = if ($current.Exists) { "{0}（{1}）" -f $current.Value, $current.Kind } else { '<未设置（系统默认）>' }
            Write-Host ("  {0} -> {1} = {2}" -f $op.Path, $op.Name, $state)
        }
        if ($item.Id -eq 'B12') {
            $servicesRoot = if ($Roots -and $Roots.ContainsKey('Services')) { [string]$Roots.Services } else { 'HKLM:\SYSTEM\CurrentControlSet\Services' }
            $dma = Get-SecurityWeakeningDmaTargets -ServicesRoot $servicesRoot
            Write-Host ("  声明 DmaRemappingCompatible 的服务：{0} 个（另 {1} 个非 DWORD 被跳过）" -f @($dma.Operations).Count, @($dma.Skips).Count)
        }
    }
    if (Test-Path -LiteralPath $script:securityWeakeningBackupFile -PathType Leaf) {
        Write-Host "安全削弱备份文件就绪：$($script:securityWeakeningBackupFile)" -ForegroundColor Yellow
    } else {
        Write-Host "尚未创建安全削弱备份文件：$($script:securityWeakeningBackupFile)" -ForegroundColor Gray
    }
}

function Invoke-SecurityWeakeningModule {
    param(
        [string]$Action = '',
        [hashtable]$Roots,
        [string]$BackupFile = $script:securityWeakeningBackupFile
    )

    Write-Host ""
    Write-Host "============ [Part 20] 安全削弱（XOS B 组，逐项选择） / Security Weakening ============" -ForegroundColor Cyan
    Write-Host " [WARNING] 本节全部项目都不提升帧率，只降低系统安全边界；默认什么都不做。" -ForegroundColor Yellow
    Write-Host " [WARNING] 每项写入前落 security-weakening-backup.json，可整体恢复。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   0. 查看 13 项当前状态（只读）" -ForegroundColor White
    $index = 0
    foreach ($item in $script:securityWeakeningItems) {
        $index++
        Write-Host ("  {0,2}. [{1}] {2}" -f $index, $item.Id, $item.Name) -ForegroundColor $(if ($item.Kind -eq 'Reference') { 'Gray' } else { 'White' })
    }
    Write-Host "   r. 按快照恢复全部（security-weakening-backup.json）" -ForegroundColor White
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定子操作（0=status、1-13=逐项应用、r=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host '请输入 0-13 或 r 并回车'
    }

    if ($Action -in @('0', 'status')) {
        Show-SecurityWeakeningStatus -Roots $Roots
        return $true
    }
    if ($Action -in @('r', 'restore', 'reset')) {
        return (Restore-SecurityWeakeningBackup -BackupFile $BackupFile)
    }

    $item = $null
    if ($Action -match '^(?<idx>[1-9]|1[0-3])$') {
        $item = $script:securityWeakeningItems[[int]$Matches['idx'] - 1]
    } elseif ($Action -match '^B(?<num>\d{2})$') {
        $item = $script:securityWeakeningItems | Where-Object { $_.Id -eq ('B' + $Matches['num']) } | Select-Object -First 1
    }
    if (-not $item) {
        Write-Host "[FAIL] 无效的子操作：$Action（可用 0、1-13、r）" -ForegroundColor Red
        $script:fail++
        return $false
    }

    Write-Host ""
    Write-Host ("[{0}] {1}" -f $item.Id, $item.Name) -ForegroundColor Yellow
    Write-Host $item.Warning -ForegroundColor Yellow
    if ($item.Kind -eq 'Reference') {
        Write-Host ("[参考] {0}" -f $item.Reference) -ForegroundColor Gray
        return $true
    }

    $phrase = if ($item.Id -eq 'B13') { 'I-UNDERSTAND-MITIGATIONS-OFF' } else { 'I-UNDERSTAND-RISK' }
    if (-not (Test-HighRiskConfirmation ("确定执行 {0} {1} 吗？" -f $item.Id, $item.Name) -Phrase $phrase)) { return $false }

    $plan = Get-SecurityWeakeningPlan -ItemIds @($item.Id) -Roots $Roots
    $mitigationXml = ''
    if ($plan.IncludeProcessMitigations) {
        $xmlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('tweakbyjie-ep-snapshot-{0}.xml' -f [guid]::NewGuid().ToString('N'))
        try {
            $mitigationXml = Save-ProcessMitigationPolicyXml -Path $xmlPath
        } catch {
            Write-Host "[FAIL] 进程缓解配置快照失败：$($_.Exception.Message)；已阻止修改。" -ForegroundColor Red
            $script:fail++
            return $false
        } finally {
            if (Test-Path -LiteralPath $xmlPath) { Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not (Ensure-SecurityWeakeningBackup -BackupFile $BackupFile -Plan $plan -ProcessMitigationXml $mitigationXml)) {
        Write-Host '[FAIL] 无法备份原始状态，已阻止修改。' -ForegroundColor Red
        return $false
    }

    $beforeFail = $script:fail
    try {
        foreach ($op in @($plan.Operations)) {
            Set-TweakRegistryTypedValue -Path $op.Path -Name $op.Name -Kind $op.Kind -Value $op.Value
            Write-Host ("  [+] {0} -> {1} = {2}（{3}）" -f $op.Path, $op.Name, $op.Value, $op.Kind) -ForegroundColor Green
            $script:ok++
            $script:rebootRequired = $true
        }
        foreach ($skip in @($plan.Skips)) {
            Write-Host ("  [SKIP] {0} -> {1}（{2}）" -f $skip.Path, $skip.Name, $skip.Reason) -ForegroundColor Yellow
            $script:skip++
        }
        if ($script:fail -gt $beforeFail) { throw '写入过程中出现失败项' }
        if ($plan.IncludeProcessMitigations) { Set-SecurityWeakeningProcessMitigations }
        Write-Host ("[OK] {0} 已应用；需重启或重新登录后生效。" -f $item.Id) -ForegroundColor Green
    } catch {
        Write-Host ("[FAIL] {0} 应用失败：{1}；正在按快照回滚。" -f $item.Id, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
        Restore-SecurityWeakeningBackup -BackupFile $BackupFile | Out-Null
        return $false
    }

    Request-Restart
    return $true
}
