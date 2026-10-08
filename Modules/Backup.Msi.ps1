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

            $instanceId = [string]$instKey.Name -replace '^HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Enum\\', ''
            $standardMsiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"

            $devices += [pscustomobject]@{
                InstanceId   = $instanceId
                DeviceDesc   = $desc
                Class        = $class
                MSISupported = $msiVal
                MessageLimit = $limitVal
                RegPath      = $standardMsiPath
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
        }
        return $true
    } catch { return $false }
}

function Ensure-MsiBackup {
    try {
        if (Test-Path -LiteralPath $script:msiBackupFile -PathType Leaf) {
            $backup = Get-Content -LiteralPath $script:msiBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-MsiBackupSchema $backup)) { throw 'msi-backup.json 结构或机器绑定不正确' }
            Write-Host "[OK] 已存在有效的 PCIe MSI 快照：$script:msiBackupFile" -ForegroundColor Green
            return $true
        }

        $devices = Get-MsiManagedDevices
        $records = @(foreach ($d in $devices) {
            [pscustomobject]@{
                InstanceId   = [string]$d.InstanceId
                DeviceDesc   = [string]$d.DeviceDesc
                Class        = [string]$d.Class
                MSISupported = $d.MSISupported
                MessageLimit = $d.MessageLimit
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

function Restore-MsiBackup {
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
            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            if (-not (Test-Path $regBase)) { continue }

            $before = $script:fail
            if ($null -eq $d.MSISupported) {
                Remove-RegDwordValue $regBase 'MSISupported' ("还原 $($d.DeviceDesc) MSISupported（删除）")
            } else {
                Set-RegDword $regBase 'MSISupported' ([uint32]$d.MSISupported) ("恢复 $($d.DeviceDesc) MSISupported = $($d.MSISupported)")
            }

            if ($null -eq $d.MessageLimit) {
                Remove-RegDwordValue $regBase 'MessageNumberLimit' ("还原 $($d.DeviceDesc) MessageNumberLimit（删除）")
            } else {
                Set-RegDword $regBase 'MessageNumberLimit' ([uint32]$d.MessageLimit) ("恢复 $($d.DeviceDesc) MessageNumberLimit = $($d.MessageLimit)")
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
