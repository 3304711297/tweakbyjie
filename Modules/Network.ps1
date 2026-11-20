# Network.ps1 - Part 19 网络低延迟与网卡/PCI/USB 节能关闭
# 吸收自 imribiy/xos-playbook（Executables/network.bat、laptop-desktop.bat），并按本仓安全模型重构：
#   - 只有「有线物理网卡 + 无电池的桌面/插电设备」才写入；
#   - 每个值写入前由 Modules/Backup.Network.ps1 落 network-backup.json；
#   - 非 REG_DWORD 的既有值一律跳过，绝不硬写。
# 备份与恢复逻辑见 Modules/Backup.Network.ps1

function Test-NetworkBatteryPresent {
    # Win32_Battery 存在即视为笔记本/掌机；查询失败返回 $null（未知），由门禁 fail-closed。
    try {
        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
        return ($batteries.Count -gt 0)
    } catch { return $null }
}

function Get-NetworkChassisType {
    # Win32_SystemEnclosure.ChassisTypes 首值：8/9/10/11/12/14/18/21/30/31/32 属便携设备。
    try {
        $enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop | Select-Object -First 1
        if (-not $enclosure -or -not $enclosure.ChassisTypes) { return $null }
        return [int](@($enclosure.ChassisTypes)[0])
    } catch { return $null }
}

function Get-NetworkPlatformGate {
    <#
        与上游一致的硬门禁：检测到电池（笔记本/掌机）整段不写。
        另外把「电池状态无法确认」也按 fail-closed 处理，避免在未知平台上把
        台式机参数写到移动设备上；机箱类型属于便携设备时同样拦截。
    #>
    $battery = Test-NetworkBatteryPresent
    $chassis = Get-NetworkChassisType

    if ($battery -eq $true) {
        return [pscustomobject]@{ Allowed = $false; Reason = '检测到电池（笔记本/掌机），按上游硬门禁整段跳过网络低延迟与节能写入' }
    }
    if ($null -eq $battery) {
        return [pscustomobject]@{ Allowed = $false; Reason = '无法确认电池状态，按 fail-closed 跳过网络低延迟与节能写入' }
    }
    if ($null -ne $chassis -and @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) -contains [int]$chassis) {
        return [pscustomobject]@{ Allowed = $false; Reason = "机箱类型 $chassis 属于便携设备，按上游硬门禁整段跳过" }
    }
    return [pscustomobject]@{ Allowed = $true; Reason = '' }
}

function Show-NetworkStatus {
    param([hashtable]$Roots)
    if (-not $Roots) { $Roots = Get-NetworkTargetRoots }

    $gate = Get-NetworkPlatformGate
    if ($gate.Allowed) {
        Write-Host '[状态] 平台门禁：通过（未检测到电池）' -ForegroundColor Green
    } else {
        Write-Host "[状态] 平台门禁：拦截（$($gate.Reason)）" -ForegroundColor Yellow
    }

    Write-Host "`n--- [有线物理网卡与每接口 TCP 参数] ---" -ForegroundColor Cyan
    $adapters = @(Get-NetworkWiredAdapters -Roots $Roots)
    if ($adapters.Count -eq 0) {
        Write-Host '未发现有线物理网卡（无线/虚拟网卡按设计不纳管）。' -ForegroundColor Yellow
    } else {
        $rows = foreach ($adapter in $adapters) {
            $ack = Get-TweakRegistryValue -Path $adapter.InterfacePath -Name 'TcpAckFrequency'
            $nodelay = Get-TweakRegistryValue -Path $adapter.InterfacePath -Name 'TCPNoDelay'
            [pscustomobject]@{
                Adapter       = $adapter.DriverDesc
                InterfaceGuid = $adapter.InterfaceGuid
                MediaType     = $adapter.MediaType
                TcpAckFrequency = if ($ack.Exists) { $ack.Value } else { '(未设置)' }
                TCPNoDelay      = if ($nodelay.Exists) { $nodelay.Value } else { '(未设置)' }
            }
        }
        $rows | Format-Table -AutoSize | Out-String | Write-Host
    }

    Write-Host '--- [无线适配器节能托管策略] ---' -ForegroundColor Cyan
    foreach ($policyPath in @($Roots.WcmLocal, $Roots.WcmGroupPolicy)) {
        $value = Get-TweakRegistryValue -Path $policyPath -Name 'fDisablePowerManagement'
        $state = if ($value.Exists) { [string]$value.Value } else { '(未设置)' }
        Write-Host ("  {0} -> fDisablePowerManagement = {1}" -f $policyPath, $state)
    }

    if (Test-Path -LiteralPath $script:networkBackupFile -PathType Leaf) {
        Write-Host "网络设置备份文件就绪：$($script:networkBackupFile)" -ForegroundColor Yellow
    } else {
        Write-Host "尚未创建网络设置备份文件：$($script:networkBackupFile)" -ForegroundColor Gray
    }
}

function Invoke-NetworkModule {
    param(
        [string]$Action = '',
        [hashtable]$Roots,
        [string]$BackupFile = $script:networkBackupFile
    )

    Write-Host ""
    Write-Host "============ [Part 19] 网络低延迟与网卡/PCI/USB 节能关闭 / Network ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  0. 查看有线网卡、每接口 TCP 参数与平台门禁状态（只读）" -ForegroundColor White
    Write-Host "  1. 应用：每接口 TcpAckFrequency/TCPNoDelay=1 + 网卡/PCI/USB 节能关闭（先快照）" -ForegroundColor White
    Write-Host "  2. 按快照还原（network-backup.json；原本不存在的值删除，原本存在的按原类型写回）" -ForegroundColor White
    Write-Host "  0. 返回主菜单" -ForegroundColor White
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定网络子操作（0=status、1=apply、2=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host '请输入 0、1 或 2 并回车'
    }

    switch -Regex ($Action.ToLowerInvariant()) {
        '^(0|status)$' {
            Show-NetworkStatus -Roots $Roots
            return $true
        }
        '^(1|apply|enable)$' {
            Write-Host '[网络低延迟] 正在检查平台门禁与有线网卡...' -ForegroundColor Cyan

            $gate = Get-NetworkPlatformGate
            if (-not $gate.Allowed) {
                Write-Host "[SKIP] $($gate.Reason)；未写入任何注册表值。" -ForegroundColor Yellow
                $script:skip++
                return $true
            }

            $plan = Get-NetworkWritePlan -Roots $Roots
            if (-not (Ensure-NetworkBackup -BackupFile $BackupFile -Plan $plan)) {
                Write-Host '[FAIL] 无法备份原始网络设置，已阻止修改。' -ForegroundColor Red
                return $false
            }

            $beforeFail = $script:fail
            try {
                foreach ($op in @($plan.Operations)) {
                    Set-TweakRegistryTypedValue -Path $op.Path -Name $op.Name -Kind $op.Kind -Value $op.Value
                    Write-Host ("  [+] {0}: {1} -> {2} = {3}" -f $op.Scope, $op.Path, $op.Name, $op.Value) -ForegroundColor Green
                }
                foreach ($skip in @($plan.Skips)) {
                    Write-Host ("  [SKIP] {0}: {1} -> {2}（{3}）" -f $skip.Scope, $skip.Path, $skip.Name, $skip.Reason) -ForegroundColor Yellow
                    $script:skip++
                }
                if ($script:fail -gt $beforeFail) { throw '写入过程中出现失败项' }

                Write-Host '[OK] 有线网卡低延迟与网卡/PCI/USB 节能开关已应用；需重启后生效。' -ForegroundColor Green
                $script:ok++
                Request-Restart
                return $true
            } catch {
                Write-Host "[FAIL] 网络设置应用失败：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                if (Restore-NetworkBackup -BackupFile $BackupFile) {
                    Write-Host '[OK] 已按应用前快照回滚本次写入。' -ForegroundColor Yellow
                } else {
                    Write-Host '[FAIL] 回滚未完全成功，请先人工核对 network-backup.json 与注册表。' -ForegroundColor Red
                    $script:fail++
                }
                return $false
            }
        }
        '^(2|restore|reset)$' {
            Write-Host '[网络低延迟] 正在按快照还原...' -ForegroundColor Cyan
            $result = Restore-NetworkBackup -BackupFile $BackupFile
            if ($result) { $script:ok++ } else { $script:fail++ }
            Request-Restart
            return $result
        }
        default {
            Write-Host "[FAIL] 无效网络子操作：$Action（可用 0=status、1=apply、2=restore）" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }
}
