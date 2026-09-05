# Backup.GameQos.ps1 - 游戏 QoS 策略备份与恢复

$script:GameQosBackupVersion = '1.0'
$script:GameQosKeyPath = 'HKLM:\Software\Policies\Microsoft\Windows\QoS'

function Test-GameQosBackupSchema {
    param($Snapshot)
    if ($null -eq $Snapshot) { return $false }
    if ($Snapshot.Version -ne $script:GameQosBackupVersion) { return $false }
    if (-not $Snapshot.PSObject.Properties['Policies']) { return $false }
    return $true
}

function Ensure-GameQosBackup {
    param(
        [string]$BackupFile = "$env:TEMP\gameqos-backup.json",
        [string]$RegistryBasePath = $script:GameQosKeyPath
    )
    try {
        $policies = @{}
        if (Test-Path $RegistryBasePath) {
            # 枚举/读取失败必须中止备份，禁止静默产出空/缺项快照（否则恢复时可能造成数据丢失）
            $subKeys = Get-ChildItem -Path $RegistryBasePath -ErrorAction Stop
            foreach ($key in $subKeys) {
                $name = $key.PSChildName
                $props = @{}
                $item = Get-ItemProperty -Path $key.PSPath -ErrorAction Stop
                foreach ($prop in $item.PSObject.Properties) {
                    if ($prop.Name -notmatch '^PS') {
                        $props[$prop.Name] = $prop.Value
                    }
                }
                $policies[$name] = $props
            }
        }

        $snapshot = [pscustomobject]@{
            Version   = $script:GameQosBackupVersion
            CreatedAt = (Get-Date).ToString('o')
            Policies  = $policies
        }

        $json = $snapshot | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($BackupFile, $json, [System.Text.Encoding]::UTF8)
        Write-Host ('[OK] 游戏 QoS 原始策略已备份：' + $BackupFile) -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host ('[FAIL] 游戏 QoS 策略备份失败：' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Restore-GameQosBackup {
    param(
        [string]$BackupFile = "$env:TEMP\gameqos-backup.json",
        [string]$RegistryBasePath = $script:GameQosKeyPath,
        [string[]]$ManagedPolicyNames = @()
    )
    if (-not (Test-Path $BackupFile)) {
        Write-Host ('[WARN] 未找到游戏 QoS 备份文件：' + $BackupFile + '，将清理已知托管规则...') -ForegroundColor Yellow
        $allOk = $true
        foreach ($name in $ManagedPolicyNames) {
            $keyPath = Join-Path $RegistryBasePath $name
            # 目标键不存在即已处于删除恢复后的状态，属正常分支
            if (Test-Path $keyPath) {
                try {
                    Remove-Item -Path $keyPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Host ('[FAIL] 清理托管 QoS 规则失败：' + $keyPath + '（' + $_.Exception.Message + '）') -ForegroundColor Red
                    $allOk = $false
                }
            }
        }
        return $allOk
    }

    try {
        $content = [System.IO.File]::ReadAllText($BackupFile, [System.Text.Encoding]::UTF8)
        $snapshot = $content | ConvertFrom-Json
        if (-not (Test-GameQosBackupSchema $snapshot)) {
            Write-Host '[FAIL] 备份文件 Schema 校验失败' -ForegroundColor Red
            return $false
        }

        $allOk = $true

        # 清理当前托管规则
        foreach ($name in $ManagedPolicyNames) {
            $keyPath = Join-Path $RegistryBasePath $name
            # 目标键不存在即已处于删除恢复后的状态，属正常分支
            if (Test-Path $keyPath) {
                try {
                    Remove-Item -Path $keyPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-Host ('[FAIL] 清理托管 QoS 规则失败：' + $keyPath + '（' + $_.Exception.Message + '）') -ForegroundColor Red
                    $allOk = $false
                }
            }
        }

        # 还原备份中的规则
        if (-not (Test-Path $RegistryBasePath)) {
            try {
                New-Item -Path $RegistryBasePath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Host ('[FAIL] 创建 QoS 策略根键失败：' + $RegistryBasePath + '（' + $_.Exception.Message + '）') -ForegroundColor Red
                return $false
            }
        }

        $policies = $snapshot.Policies
        if ($policies) {
            foreach ($prop in $policies.PSObject.Properties) {
                $policyName = $prop.Name
                $policyValues = $prop.Value
                $targetKey = Join-Path $RegistryBasePath $policyName
                if (-not (Test-Path $targetKey)) {
                    try {
                        New-Item -Path $targetKey -Force -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Host ('[FAIL] 创建 QoS 策略键失败：' + $targetKey + '（' + $_.Exception.Message + '）') -ForegroundColor Red
                        $allOk = $false
                        continue
                    }
                }
                foreach ($valProp in $policyValues.PSObject.Properties) {
                    try {
                        Set-ItemProperty -Path $targetKey -Name $valProp.Name -Value $valProp.Value -Type String -Force -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Host ('[FAIL] 写入 QoS 策略值失败：' + $targetKey + '\' + $valProp.Name + '（' + $_.Exception.Message + '）') -ForegroundColor Red
                        $allOk = $false
                    }
                }
            }
        }

        if (-not $allOk) {
            Write-Host '[FAIL] 游戏 QoS 策略还原未完全成功，请复查输出中的 FAIL 项。' -ForegroundColor Red
            return $false
        }
        Write-Host '[OK] 游戏 QoS 策略已成功按快照还原。' -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host ('[FAIL] 还原游戏 QoS 策略失败：' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}
