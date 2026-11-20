# Backup.Network.ps1 - 网络低延迟与网卡/PCI/USB 节能开关的逐值快照与还原
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired
#
# 设计边界（吸收自 imribiy/xos-playbook，但比上游更严）：
#   - 只写 REG_DWORD；目标位置已有的 REG_SZ / REG_EXPAND_SZ / REG_BINARY 等一律记 skip，绝不硬写；
#   - 每个被写入的值先落「原本是否存在 / 原类型 / 原值」，还原时「原本不存在 → 删值」、
#     「原本存在 → 按原类型写回原值」，不把 0 当成“还原”；
#   - 首次快照不覆盖：快照已存在时只追加新发现的目标，绝不重写已有记录；
#   - 无线/虚拟网卡与便携设备（电池）由 Network.ps1 的硬门禁在写入前拦截。

$script:NetworkNicPowerValues = @(
    'AdvancedEEE'
    'EnableAspm'
    'EnableGreenEthernet'
    'EnablePME'
    'PowerSaveEnable'
    'ReduceSpeedOnPowerDown'
)

$script:NetworkDevicePowerValues = @(
    'EnhancedPowerManagementEnabled'
    'AllowIdleIrpInD3'
    'EnableSelectiveSuspend'
    'WdfDirectedPowerTransitionEnable'
)

$script:NetworkBackupKinds = @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')

function Get-NetworkTargetRoots {
    <#
        全部受管注册表根。测试用同一份键名把根替换到 HKCU 沙箱，
        因此真实写入逻辑可以被完整覆盖而不触碰 HKLM。
    #>
    return @{
        NicClass        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        TcpipInterfaces = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
        WcmLocal        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\Local'
        WcmGroupPolicy  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy'
        Services        = 'HKLM:\SYSTEM\CurrentControlSet\Services'
        Enum            = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
    }
}

function Test-NetworkAdapterWired {
    <#
        有线物理网卡判定（硬门禁）：
          - *PhysicalMediaType 必须是 14（NDIS 802.3）或字面量 802.3，其余（9=无线、10=蓝牙、0=未指定）一律不碰；
          - 描述命中虚拟/无线/隧道/VPN 关键词的一律不碰，避免 Hyper-V / VMware / Wi-Fi Direct 被当成有线。
    #>
    param([string]$MediaType, [string]$Description)
    if ([string]::IsNullOrWhiteSpace($MediaType)) { return $false }
    $media = $MediaType.Trim()
    if ($media -ne '14' -and $media -ine '802.3') { return $false }
    if ([string]::IsNullOrWhiteSpace($Description)) { return $false }
    if ($Description -match '(?i)Wi-?Fi|Wireless|WLAN|802\.11|Virtual|Hyper-?V|VMware|VirtualBox|Loopback|TAP-|WAN Miniport|Bluetooth|Npcap|Tailscale|ZeroTier|WireGuard|VPN|Kernel Debug') {
        return $false
    }
    return $true
}

function Get-NetworkWiredAdapters {
    <#
        枚举网卡类键下 4 位实例键，只返回有线物理网卡。
        返回对象的 ClassKeyPath 用于网卡节能值，InterfacePath 用于每接口 TCP 参数。
    #>
    param([hashtable]$Roots)
    if (-not $Roots) { $Roots = Get-NetworkTargetRoots }
    $adapters = @()
    if ([string]::IsNullOrWhiteSpace([string]$Roots.NicClass)) { return @() }
    if (-not (Test-Path -LiteralPath $Roots.NicClass -PathType Container)) { return @() }

    foreach ($key in @(Get-ChildItem -LiteralPath $Roots.NicClass -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notmatch '^\d{4}$') { continue }
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $media = [string]$props.'*PhysicalMediaType'
        $desc = [string]$props.DriverDesc
        if (-not (Test-NetworkAdapterWired -MediaType $media -Description $desc)) { continue }
        $guid = [string]$props.NetCfgInstanceId
        if ([string]::IsNullOrWhiteSpace($guid)) { continue }
        $adapters += [pscustomobject]@{
            ClassKeyPath  = (ConvertTo-TweakRegistryPsPath ([string]$key.PSPath))
            InterfaceGuid = $guid
            InterfacePath = (Join-Path $Roots.TcpipInterfaces $guid)
            DriverDesc    = $desc
            MediaType     = $media
        }
    }
    return $adapters
}

function New-NetworkOperation {
    param([string]$Scope, [string]$Path, [string]$Name, [int]$Value)
    return [pscustomobject]@{
        Scope = $Scope
        Path  = $Path
        Name  = $Name
        Kind  = 'DWord'
        Value = $Value
    }
}

function New-NetworkSkip {
    param([string]$Scope, [string]$Path, [string]$Name, [string]$Kind, [string]$Reason)
    return [pscustomobject]@{
        Scope  = $Scope
        Path   = $Path
        Name   = $Name
        Kind   = $Kind
        Reason = $Reason
    }
}

function Add-NetworkPlanOperation {
    <#
        统一写入计划入口：只有「值不存在」或「已存在且是 REG_DWORD」才安排写入；
        已存在的 REG_SZ / REG_EXPAND_SZ / REG_BINARY 等一律记 skip，绝不硬改类型。
    #>
    param($Operations, $Skips, [string]$Scope, [string]$Path, [string]$Name, [int]$Value)
    $current = Get-TweakRegistryValue -Path $Path -Name $Name
    if ($current.Exists -and $current.Kind -ne 'DWord') {
        $Skips.Add((New-NetworkSkip $Scope $Path $Name $current.Kind '已存在但不是 REG_DWORD，按硬门禁跳过'))
        return
    }
    $Operations.Add((New-NetworkOperation $Scope $Path $Name $Value))
}

function Get-NetworkNicPowerTargets {
    <#
        网卡类键节能值：只把已存在的 REG_DWORD 置 0；已存在的非 DWORD 记 skip 不中断。
        不存在的值不创建（默认不存在本身就是驱动默认行为，无需多写一个值）。
    #>
    param([string]$ClassKeyPath)
    $operations = @()
    $skips = @()
    if ([string]::IsNullOrWhiteSpace($ClassKeyPath)) { return [pscustomobject]@{ Operations = @(); Skips = @() } }

    foreach ($name in $script:NetworkNicPowerValues) {
        $current = Get-TweakRegistryValue -Path $ClassKeyPath -Name $name
        if (-not $current.Exists) { continue }
        if ($current.Kind -ne 'DWord') {
            $skips += New-NetworkSkip 'NicClass' $ClassKeyPath $name $current.Kind '已存在但不是 REG_DWORD，按硬门禁跳过'
            continue
        }
        $operations += New-NetworkOperation 'NicClass' $ClassKeyPath $name 0
    }
    return [pscustomobject]@{ Operations = $operations; Skips = $skips }
}

function Get-NetworkDevicePowerTargets {
    <#
        枚举设备实例键（Enum 树）上的电源管理值：
        只处理已存在的 REG_DWORD，非 DWORD 记 skip。上游用 reg query /s /f 逐个名字扫四遍，
        这里一次递归遍历后按值名过滤，避免把同一棵树扫四次。
    #>
    param([string]$EnumRoot)
    $operations = @()
    $skips = @()
    if ([string]::IsNullOrWhiteSpace($EnumRoot)) { return [pscustomobject]@{ Operations = @(); Skips = @() } }
    if (-not (Test-Path -LiteralPath $EnumRoot -PathType Container)) {
        return [pscustomobject]@{ Operations = @(); Skips = @() }
    }

    foreach ($key in @(Get-ChildItem -LiteralPath $EnumRoot -Recurse -ErrorAction SilentlyContinue)) {
        try {
            $valueNames = @($key.GetValueNames())
        } catch {
            # 个别受保护/损坏的设备键读不到值名：跳过该键，不影响其余设备
            continue
        }
        if ($valueNames.Count -eq 0) { continue }
        $keyPath = ConvertTo-TweakRegistryPsPath ([string]$key.PSPath)
        foreach ($name in $script:NetworkDevicePowerValues) {
            if ($valueNames -notcontains $name) { continue }
            $kind = ''
            try { $kind = $key.GetValueKind($name).ToString() } catch { $kind = 'Unknown' }
            if ($kind -ne 'DWord') {
                $skips += New-NetworkSkip 'Device' $keyPath $name $kind '已存在但不是 REG_DWORD，按硬门禁跳过'
                continue
            }
            $operations += New-NetworkOperation 'Device' $keyPath $name 0
        }
    }
    return [pscustomobject]@{ Operations = $operations; Skips = $skips }
}

function Get-NetworkWritePlan {
    <#
        生成一次应用所需的全部写入项与跳过项。备份与应用共用同一份计划，
        保证「快照覆盖的范围」与「实际写入的范围」完全一致。
    #>
    param([hashtable]$Roots)
    if (-not $Roots) { $Roots = Get-NetworkTargetRoots }

    $operations = [System.Collections.Generic.List[object]]::new()
    $skips = [System.Collections.Generic.List[object]]::new()

    # 1) 无线适配器节能托管策略（桌面/插电门禁已在调用方拦截）
    foreach ($policyPath in @([string]$Roots.WcmLocal, [string]$Roots.WcmGroupPolicy)) {
        if ([string]::IsNullOrWhiteSpace($policyPath)) { continue }
        Add-NetworkPlanOperation $operations $skips 'WcmSvc' $policyPath 'fDisablePowerManagement' 1
    }

    # 2) 有线物理网卡：每接口 TCP 低延迟 + 网卡类节能值 + PnPCapabilities
    foreach ($adapter in @(Get-NetworkWiredAdapters -Roots $Roots)) {
        foreach ($name in @('TcpAckFrequency', 'TCPNoDelay')) {
            Add-NetworkPlanOperation $operations $skips 'Tcpip' $adapter.InterfacePath $name 1
        }
        $nic = Get-NetworkNicPowerTargets -ClassKeyPath $adapter.ClassKeyPath
        foreach ($op in @($nic.Operations)) { $operations.Add($op) }
        foreach ($skip in @($nic.Skips)) { $skips.Add($skip) }
        Add-NetworkPlanOperation $operations $skips 'NicClass' $adapter.ClassKeyPath 'PnPCapabilities' 24
    }

    # 3) Enum 设备实例上的电源管理值
    $device = Get-NetworkDevicePowerTargets -EnumRoot $Roots.Enum
    foreach ($op in @($device.Operations)) { $operations.Add($op) }
    foreach ($skip in @($device.Skips)) { $skips.Add($skip) }

    # 4) USB 集线器与 PCI/USB 根端口
    $serviceTargets = @(
        @{ Service = 'USBHUB3'; Name = 'DisableLPM'; Value = 1 }
        @{ Service = 'usbccgp'; Name = 'D3ColdSupported'; Value = 0 }
        @{ Service = 'pci'; Name = 'D3ColdSupported'; Value = 0 }
    )
    foreach ($target in $serviceTargets) {
        $servicePath = Join-Path $Roots.Services $target.Service
        if (-not (Test-Path -LiteralPath $servicePath -PathType Container)) {
            $skips.Add((New-NetworkSkip 'Service' $servicePath $target.Name '' "服务 $($target.Service) 不存在，跳过"))
            continue
        }
        $parametersPath = Join-Path $servicePath 'Parameters'
        Add-NetworkPlanOperation $operations $skips 'Service' $parametersPath $target.Name ([int]$target.Value)
    }

    # 去重：同路径同值名只保留第一次（Enum 树与类键理论上不会重叠，防御性处理）
    $unique = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($op in $operations) {
        $key = ('{0}|{1}' -f $op.Path, $op.Name).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($op)
    }

    return [pscustomobject]@{ Operations = @($unique); Skips = @($skips) }
}

function Test-NetworkBackupSchema {
    param([object]$Backup)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        if ($null -eq $Backup.Entries) { return $false }
        foreach ($entry in @($Backup.Entries)) {
            if ([string]::IsNullOrWhiteSpace([string]$entry.Path)) { return $false }
            if ([string]::IsNullOrWhiteSpace([string]$entry.Name)) { return $false }
            if ($null -eq $entry.Existed) { return $false }
            if ([bool]$entry.Existed) {
                $kind = [string]$entry.Kind
                if ([string]::IsNullOrWhiteSpace($kind)) { return $false }
                if ($script:NetworkBackupKinds -notcontains $kind) { return $false }
            }
        }
        return $true
    } catch { return $false }
}

function Ensure-NetworkBackup {
    <#
        落 network-backup.json：
          - 文件不存在：按计划逐值记录 Exists / Kind / Value；
          - 文件已存在且有效：保留原记录（首次快照保护），只追加计划中新出现的目标；
          - 结构损坏或跨机快照：直接失败并阻止写入，绝不覆盖。
    #>
    param(
        [string]$BackupFile = $script:networkBackupFile,
        [hashtable]$Roots,
        [object]$Plan
    )
    try {
        if ([string]::IsNullOrWhiteSpace($BackupFile)) { throw '未指定网络设置备份文件路径' }
        if (-not $Plan) { $Plan = Get-NetworkWritePlan -Roots $Roots }

        $entries = [System.Collections.Generic.List[object]]::new()
        $existing = $null
        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-NetworkBackupSchema $existing)) { throw 'network-backup.json 结构或机器绑定不正确' }
            foreach ($entry in @($existing.Entries)) { $entries.Add($entry) }
        }

        $seen = @{}
        foreach ($entry in $entries) {
            $seen[(('{0}|{1}' -f $entry.Path, $entry.Name).ToLowerInvariant())] = $true
        }

        $added = 0
        foreach ($op in @($Plan.Operations)) {
            $key = ('{0}|{1}' -f $op.Path, $op.Name).ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $current = Get-TweakRegistryValue -Path $op.Path -Name $op.Name
            $entries.Add([pscustomobject]@{
                Path    = [string]$op.Path
                Name    = [string]$op.Name
                Existed = [bool]$current.Exists
                Kind    = [string]$current.Kind
                Value   = $current.Value
            })
            $seen[$key] = $true
            $added++
        }

        if ($null -ne $existing -and $added -eq 0) {
            Write-Host "[OK] 已存在有效的网络设置快照（$($entries.Count) 项）：$BackupFile" -ForegroundColor Green
            return $true
        }

        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Entries   = @($entries)
        }
        if (-not (Test-NetworkBackupSchema $backup)) { throw '生成的网络设置备份未通过结构校验' }

        $json = ConvertTo-Json -InputObject $backup -Depth 6
        Write-TweakAtomicTextFile -Path $BackupFile -Content $json -Overwrite:($null -ne $existing)

        $check = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-NetworkBackupSchema $check)) { throw '写入后的网络设置备份校验失败' }

        Write-Host "[OK] 网络设置原始状态已备份（共 $($entries.Count) 项）：$BackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] 网络设置原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-NetworkBackup {
    <#
        按快照逐值还原：
          Existed = $true  → 按原类型写回原值（回读校验）；
          Existed = $false → 删除该值（原本不存在）。
        缺少/损坏/跨机快照一律失败关闭，不假装恢复成功。
    #>
    param([string]$BackupFile = $script:networkBackupFile)
    if ([string]::IsNullOrWhiteSpace($BackupFile) -or -not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
        Write-Host '[FAIL] 未找到 network-backup.json，拒绝声称已恢复。' -ForegroundColor Red
        $script:fail++
        return $false
    }

    try {
        $backup = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-NetworkBackupSchema $backup)) { throw 'network-backup.json 结构不正确或与本机绑定不匹配' }

        $allOk = $true
        foreach ($entry in @($backup.Entries)) {
            try {
                if ([bool]$entry.Existed) {
                    Set-TweakRegistryTypedValue -Path ([string]$entry.Path) -Name ([string]$entry.Name) -Kind ([string]$entry.Kind) -Value $entry.Value
                    Write-Host "[OK] 恢复 $($entry.Path) -> $($entry.Name) = $($entry.Value)（$($entry.Kind)）" -ForegroundColor Green
                } else {
                    $removed = Remove-TweakRegistryValue -Path ([string]$entry.Path) -Name ([string]$entry.Name)
                    if ($removed) {
                        Write-Host "[OK] 删除 $($entry.Path) -> $($entry.Name)（原本不存在）" -ForegroundColor Green
                    } else {
                        Write-Host "[SKIP] $($entry.Path) -> $($entry.Name) 已不存在，无需删除" -ForegroundColor Yellow
                    }
                }
            } catch {
                Write-Host "[FAIL] 恢复 $($entry.Path) -> $($entry.Name) 失败：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                $allOk = $false
            }
        }

        if ($allOk) {
            Write-Host '[OK] 网络低延迟与节能设置已按快照完整恢复。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] 网络设置恢复未完全成功，请复查错误。' -ForegroundColor Yellow
        }
        return $allOk
    } catch {
        Write-Host "[FAIL] 网络设置恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
