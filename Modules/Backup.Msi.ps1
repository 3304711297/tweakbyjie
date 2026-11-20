# Backup.Msi.ps1 - PCIe 设备 MSI 中断模式快照与恢复
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Test-MsiDeviceEligible {
    <#
        安全白名单过滤：
        纳管：显示适配器 (Display)、网络适配器 (Net)、存储控制器 (SCSIAdapter, hdc, IDE)
        严格排除：音频控制器 (MEDIA / Audio)、系统主板芯片与 PCI 桥 (System, Bridge, Root Port)
    #>
    param([string]$Class, [string]$DeviceDesc)
    if ([string]::IsNullOrWhiteSpace($Class)) { return $false }

    # 显式黑名单排除
    if ($Class -in @('MEDIA', 'System', 'Bridge', 'Volume', 'DiskDrive')) { return $false }
    if ($DeviceDesc -match '(?i)Audio|Sound|Bridge|Root Port|Host Bridge|SRAM|LPC|eSPI|SMBus|Serial IO') { return $false }

    # 白名单匹配
    if ($Class -in @('Display', 'Net', 'SCSIAdapter', 'hdc', 'IDE')) {
        return $true
    }
    return $false
}

function Get-MsiManagedDevices {
    $pciBase = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI'
    if (-not (Test-Path $pciBase)) { return @() }

    $devices = @()
    foreach ($venKey in (Get-ChildItem $pciBase -ErrorAction SilentlyContinue)) {
        foreach ($instKey in (Get-ChildItem $venKey.PSPath -ErrorAction SilentlyContinue)) {
            $regPath = $instKey.PSPath
            $msiPath = Join-Path $regPath 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
            if (-not (Test-Path $msiPath)) { continue }

            $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            $desc = if ($props.DeviceDesc) { ($props.DeviceDesc -split ';')[-1] } else { $props.FriendlyName }
            if (-not $desc) { $desc = $instKey.PSChildName }
            $class = if ($props.Class) {
                [string]$props.Class
            } elseif ($props.ClassGUID) {
                [string](Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$($props.ClassGUID)" -ErrorAction SilentlyContinue).Class
            } else { '' }

            if (-not (Test-MsiDeviceEligible $class $desc)) { continue }

            $msiProps = Get-ItemProperty $msiPath -ErrorAction SilentlyContinue
            $msiVal = if ($null -ne $msiProps.MSISupported) { [uint32]$msiProps.MSISupported } else { $null }
            $limitVal = if ($null -ne $msiProps.MessageNumberLimit) { [uint32]$msiProps.MessageNumberLimit } else { $null }

            $instanceId = [string]$instKey.Name -replace '^HKEY_LOCAL_MACHINE\\\\SYSTEM\\\\CurrentControlSet\\\\Enum\\\\', ''
            $standardMsiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $affinityPath = (ConvertTo-TweakRegistryPsPath "$regPath\Device Parameters\Interrupt Management\Affinity Policy")
            $devicePriority = Get-TweakRegistryValue -Path $affinityPath -Name 'DevicePriority'

            $devices += [pscustomobject]@{
                InstanceId     = $instanceId
                DeviceDesc     = $desc
                Class          = $class
                MSISupported   = $msiVal
                MessageLimit   = $limitVal
                RegPath        = $standardMsiPath
                AffinityPath   = $affinityPath
                DevicePriority = [pscustomobject]@{
                    Existed = [bool]$devicePriority.Exists
                    Kind    = [string]$devicePriority.Kind
                    Value   = $devicePriority.Value
                }
            }
        }
    }
    return $devices
}

function Test-MsiBackupSchema {
    param([object]$Backup)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        if ($null -eq $Backup.Devices) { return $false }

        foreach ($d in @($Backup.Devices)) {
            if ([string]::IsNullOrWhiteSpace([string]$d.InstanceId)) { return $false }
            if ($null -ne $d.MSISupported) {
                try { $null = [uint32]$d.MSISupported } catch { return $false }
            }
            if ($null -ne $d.MessageLimit) {
                try { $null = [uint32]$d.MessageLimit } catch { return $false }
            }
            if ($d.PSObject.Properties['DevicePriority'] -and $null -ne $d.DevicePriority) {
                $dp = $d.DevicePriority
                if ($null -eq $dp.Existed) { return $false }
                if ([bool]$dp.Existed) {
                    $kind = [string]$dp.Kind
                    if ([string]::IsNullOrWhiteSpace($kind)) { return $false }
                    if (@('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary') -notcontains $kind) { return $false }
                }
            }
        }
        return $true
    } catch { return $false }
}

function Ensure-MsiBackup {
    try {
        if (Test-Path -LiteralPath $script:msiBackupFile -PathType Leaf) {
            $backup = Get-Content -LiteralPath $script:msiBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-MsiBackupSchema $backup)) { throw 'msi-backup.json 结构或机器绑定不正确' }

            # 旧版本快照没有 DevicePriority 字段：保留首次记录的 MSISupported/MessageLimit，
            # 只为缺失的设备补记 DevicePriority（并追加新发现的设备），否则升级后首轮删除无快照可用。
            $devices = @(Get-MsiManagedDevices)
            $records = [System.Collections.Generic.List[object]]::new()
            foreach ($record in @($backup.Devices)) { $records.Add($record) }
            $existingIds = @($records | ForEach-Object { [string]$_.InstanceId })
            $added = 0
            foreach ($d in $devices) {
                $id = [string]$d.InstanceId
                $match = @($records | Where-Object { [string]$_.InstanceId -eq $id }) | Select-Object -First 1
                if ($match) {
                    if (-not $match.PSObject.Properties['DevicePriority']) {
                        $match | Add-Member -NotePropertyName 'DevicePriority' -NotePropertyValue $d.DevicePriority -Force
                        $added++
                    }
                } elseif ($existingIds -notcontains $id) {
                    $records.Add([pscustomobject]@{
                        InstanceId     = $id
                        DeviceDesc     = [string]$d.DeviceDesc
                        Class          = [string]$d.Class
                        MSISupported   = $d.MSISupported
                        MessageLimit   = $d.MessageLimit
                        DevicePriority = $d.DevicePriority
                    })
                    $added++
                }
            }

            if ($added -gt 0) {
                $backup.Devices = @($records)
                if (-not (Test-MsiBackupSchema $backup)) { throw '合并 DevicePriority 后的 MSI 快照未通过结构校验' }
                $json = ConvertTo-Json -InputObject $backup -Depth 5
                Write-TweakAtomicTextFile -Path $script:msiBackupFile -Content $json -Overwrite
                Write-Host "[OK] 已为现有 PCIe MSI 快照补充 $added 个 DevicePriority/设备记录：$script:msiBackupFile" -ForegroundColor Green
            } else {
                Write-Host "[OK] 已存在有效的 PCIe MSI 快照：$script:msiBackupFile" -ForegroundColor Green
            }
            return $true
        }

        $devices = Get-MsiManagedDevices
        $records = @(foreach ($d in $devices) {
            [pscustomobject]@{
                InstanceId     = [string]$d.InstanceId
                DeviceDesc     = [string]$d.DeviceDesc
                Class          = [string]$d.Class
                MSISupported   = $d.MSISupported
                MessageLimit   = $d.MessageLimit
                DevicePriority = $d.DevicePriority
            }
        })

        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Devices   = $records
        }

        if (-not (Test-MsiBackupSchema $backup)) { throw '生成的 MSI 备份未通过结构校验' }
        $json = ConvertTo-Json -InputObject $backup -Depth 5
        Write-TweakAtomicTextFile -Path $script:msiBackupFile -Content $json
        $check = Get-Content -LiteralPath $script:msiBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-MsiBackupSchema $check)) { throw '写入后的 MSI 备份校验失败' }

        Write-Host "[OK] PCIe MSI 原始状态已备份：$script:msiBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] PCIe MSI 原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Get-MsiAffinityPath {
    # 设备中断亲和性键：历史工具把 DevicePriority 写死在这里（通常 REG_SZ = High），
    # 它会把 MSI 消息挤到单核，需要在启用 MSI 后清理；还原时按快照写回。
    param(
        [string]$InstanceId,
        [string]$EnumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
    )
    if ([string]::IsNullOrWhiteSpace($EnumRoot)) { $EnumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum' }
    return "$EnumRoot\$InstanceId\Device Parameters\Interrupt Management\Affinity Policy"
}

function Remove-MsiAffinityDevicePriority {
    param([string]$AffinityPath, [string]$DeviceDesc)
    if ([string]::IsNullOrWhiteSpace($AffinityPath)) { return $false }
    try {
        $removed = Remove-TweakRegistryValue -Path $AffinityPath -Name 'DevicePriority'
        if ($removed) {
            Write-Host "[OK] 已清理 $DeviceDesc 的历史中断绑核 DevicePriority（删除前已快照）" -ForegroundColor Green
            $script:rebootRequired = $true
            return $true
        }
        Write-Host "[SKIP] $DeviceDesc 未设置 Affinity Policy\DevicePriority（无需清理）" -ForegroundColor Yellow
        $script:skip++
        return $false
    } catch {
        Write-Host "[FAIL] 清理 $DeviceDesc DevicePriority 失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-MsiBackup {
    param([string]$EnumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum')
    if (-not (Test-Path -LiteralPath $script:msiBackupFile -PathType Leaf)) {
        Write-Host '[FAIL] 未找到 msi-backup.json，拒绝声称已恢复。' -ForegroundColor Red
        $script:fail++
        return $false
    }

    try {
        $backup = Get-Content -LiteralPath $script:msiBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-MsiBackupSchema $backup)) { throw 'msi-backup.json 结构不正确或与本机绑定不匹配' }

        $allOk = $true
        foreach ($d in @($backup.Devices)) {
            $before = $script:fail
            $instanceId = [string]$d.InstanceId
            $regBase = "$EnumRoot\$instanceId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"

            # 1) Affinity Policy\DevicePriority：独立于 MSI 键存在，先按快照还原/删除
            $devicePriority = if ($d.PSObject.Properties['DevicePriority']) { $d.DevicePriority } else { $null }
            if ($null -ne $devicePriority) {
                $affinityPath = Get-MsiAffinityPath -InstanceId $instanceId -EnumRoot $EnumRoot
                try {
                    if ([bool]$devicePriority.Existed) {
                        Set-TweakRegistryTypedValue -Path $affinityPath -Name 'DevicePriority' -Kind ([string]$devicePriority.Kind) -Value $devicePriority.Value
                        Write-Host "[OK] 恢复 $($d.DeviceDesc) DevicePriority = $($devicePriority.Value)（$($devicePriority.Kind)）" -ForegroundColor Green
                    } else {
                        $removed = Remove-TweakRegistryValue -Path $affinityPath -Name 'DevicePriority'
                        if ($removed) {
                            Write-Host "[OK] 删除 $($d.DeviceDesc) DevicePriority（原本不存在）" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-Host "[FAIL] 恢复 $($d.DeviceDesc) DevicePriority 失败：$($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            }

            # 2) MSI 配置：键不存在时跳过，避免凭空创建未声明 MSI 的设备
            if (Test-Path $regBase) {
                if ($null -eq $d.MSISupported) {
                    $null = Remove-RegDwordValue $regBase 'MSISupported' ("还原 $($d.DeviceDesc) MSISupported（删除）")
                } else {
                    $null = Set-RegDword $regBase 'MSISupported' ([uint32]$d.MSISupported) ("恢复 $($d.DeviceDesc) MSISupported = $($d.MSISupported)")
                }

                if ($null -eq $d.MessageLimit) {
                    $null = Remove-RegDwordValue $regBase 'MessageNumberLimit' ("还原 $($d.DeviceDesc) MessageNumberLimit（删除）")
                } else {
                    $null = Set-RegDword $regBase 'MessageNumberLimit' ([uint32]$d.MessageLimit) ("恢复 $($d.DeviceDesc) MessageNumberLimit = $($d.MessageLimit)")
                }
            }

            if ($script:fail -gt $before) { $allOk = $false; break }
        }

        if ($allOk) {
            Write-Host '[OK] PCIe 设备 MSI 中断配置已按快照完整恢复。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] PCIe MSI 恢复未完全成功，请复查错误。' -ForegroundColor Yellow
        }
        return $allOk
    } catch {
        Write-Host "[FAIL] PCIe MSI 状态恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
