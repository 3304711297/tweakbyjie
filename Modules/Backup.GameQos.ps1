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
            $subKeys = Get-ChildItem -Path $RegistryBasePath -ErrorAction SilentlyContinue
            foreach ($key in $subKeys) {
                $name = $key.PSChildName
                $props = @{}
                $item = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
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
        foreach ($name in $ManagedPolicyNames) {
            $keyPath = Join-Path $RegistryBasePath $name
            if (Test-Path $keyPath) {
                Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        return $true
    }

    try {
        $content = [System.IO.File]::ReadAllText($BackupFile, [System.Text.Encoding]::UTF8)
        $snapshot = $content | ConvertFrom-Json
        if (-not (Test-GameQosBackupSchema $snapshot)) {
            Write-Host '[FAIL] 备份文件 Schema 校验失败' -ForegroundColor Red
            return $false
        }

        # 清理当前托管规则
        foreach ($name in $ManagedPolicyNames) {
            $keyPath = Join-Path $RegistryBasePath $name
            if (Test-Path $keyPath) {
                Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # 还原备份中的规则
        if (-not (Test-Path $RegistryBasePath)) {
            New-Item -Path $RegistryBasePath -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $policies = $snapshot.Policies
        if ($policies) {
            foreach ($prop in $policies.PSObject.Properties) {
                $policyName = $prop.Name
                $policyValues = $prop.Value
                $targetKey = Join-Path $RegistryBasePath $policyName
                if (-not (Test-Path $targetKey)) {
                    New-Item -Path $targetKey -Force -ErrorAction SilentlyContinue | Out-Null
                }
                foreach ($valProp in $policyValues.PSObject.Properties) {
                    Set-ItemProperty -Path $targetKey -Name $valProp.Name -Value $valProp.Value -Type String -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }

        Write-Host '[OK] 游戏 QoS 策略已成功按快照还原。' -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host ('[FAIL] 还原游戏 QoS 策略失败：' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}
