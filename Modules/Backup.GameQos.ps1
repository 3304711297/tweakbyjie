# Backup.GameQos.ps1 - 游戏 QoS 策略备份与恢复
# 备份只创建一次：后续应用不能覆盖首次快照，否则“恢复”只会恢复到上一次应用前。

$script:GameQosBackupVersion = '1.0'
$script:GameQosKeyPath = 'HKLM:\Software\Policies\Microsoft\Windows\QoS'
$script:GameQosAllowedPropertyPattern = '^[^\\/:*?"<>|\x00-\x1F]{1,255}$'

function Test-GameQosSafeName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -in @('.', '..')) { return $false }
    return $Name -match $script:GameQosAllowedPropertyPattern
}

function Get-GameQosPolicyEntries {
    param([object]$Policies)
    if ($null -eq $Policies) { return @() }
    if ($Policies -is [hashtable]) {
        return @($Policies.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_.Key; Values = $_.Value }
        })
    }
    return @($Policies.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.Name; Values = $_.Value }
    })
}

function Get-GameQosValueEntries {
    param([object]$Values)
    if ($null -eq $Values) { return @() }
    if ($Values -is [hashtable]) {
        return @($Values.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_.Key; Value = $_.Value }
        })
    }
    return @($Values.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.Name; Value = $_.Value }
    })
}

function Test-GameQosBackupSchema {
    param($Snapshot)
    try {
        if ($null -eq $Snapshot) { return $false }
        if ([string]$Snapshot.Version -cne [string]$script:GameQosBackupVersion) { return $false }
        $policiesProperty = $Snapshot.PSObject.Properties['Policies']
        if ($null -eq $policiesProperty -or $null -eq $policiesProperty.Value) { return $false }
        foreach ($policy in @(Get-GameQosPolicyEntries $policiesProperty.Value)) {
            if (-not (Test-GameQosSafeName ([string]$policy.Name))) { return $false }
            $values = @(Get-GameQosValueEntries $policy.Values)
            if ($values.Count -gt 128) { return $false }
            foreach ($value in $values) {
                if (-not (Test-GameQosSafeName ([string]$value.Name))) { return $false }
                if ($null -eq $value.Value -or $value.Value -is [System.Collections.IDictionary] -or $value.Value -is [System.Array]) { return $false }
                $valueText = [string]$value.Value
                if ($valueText.Length -gt 4096) { return $false }
            }
        }
        return $true
    } catch { return $false }
}

function Ensure-GameQosBackup {
    param(
        [string]$BackupFile = "$env:TEMP\gameqos-backup.json",
        [string]$RegistryBasePath = $script:GameQosKeyPath
    )
    try {
        # 首次快照是恢复边界，必须保持不变；已有损坏快照不能被“自愈”覆盖。
        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-GameQosBackupSchema $existing)) {
                throw '已有游戏 QoS 快照结构不正确，拒绝覆盖；请人工检查或移走该文件'
            }
            Write-Host ('[OK] 已存在有效的游戏 QoS 原始快照（不会覆盖）：' + $BackupFile) -ForegroundColor Green
            return $true
        }

        $policies = @{}
        if (Test-Path -LiteralPath $RegistryBasePath) {
            # 枚举/读取失败必须中止备份，禁止静默产出空/缺项快照。
            $subKeys = Get-ChildItem -LiteralPath $RegistryBasePath -ErrorAction Stop
            foreach ($key in $subKeys) {
                $name = [string]$key.PSChildName
                if (-not (Test-GameQosSafeName $name)) { throw "QoS 策略名不安全：$name" }
                $props = @{}
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                foreach ($prop in $item.PSObject.Properties) {
                    if ($prop.Name -notmatch '^PS') {
                        if (-not (Test-GameQosSafeName $prop.Name)) { throw "QoS 属性名不安全：$($prop.Name)" }
                        if ($null -eq $prop.Value -or $prop.Value -is [array] -or $prop.Value -is [hashtable]) {
                            throw "QoS 属性值无法安全序列化：$name\$($prop.Name)"
                        }
                        $props[$prop.Name] = [string]$prop.Value
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
        if (-not (Test-GameQosBackupSchema $snapshot)) { throw '生成的游戏 QoS 快照未通过结构校验' }

        $json = $snapshot | ConvertTo-Json -Depth 6
        Write-TweakAtomicTextFile -Path $BackupFile -Content $json
        $check = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-GameQosBackupSchema $check)) { throw '写入后的游戏 QoS 快照校验失败' }
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

    # 先验证快照，再删除任何托管键。没有原始快照时拒绝盲删，避免把用户手工创建的同名策略当成工具产物。
    if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
        Write-Host ('[FAIL] 未找到游戏 QoS 原始快照，拒绝清理策略：' + $BackupFile) -ForegroundColor Red
        return $false
    }
    try {
        $content = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop
        $snapshot = $content | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-GameQosBackupSchema $snapshot)) { throw '备份文件 Schema 校验失败' }
    } catch {
        Write-Host ('[FAIL] 游戏 QoS 原始快照无效，拒绝删除任何策略：' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }

    $allOk = $true
    foreach ($name in @($ManagedPolicyNames)) {
        if (-not (Test-GameQosSafeName $name)) {
            Write-Host "[FAIL] 拒绝清理不安全的托管 QoS 策略名：$name" -ForegroundColor Red
            $allOk = $false
            continue
        }
        $keyPath = Join-Path $RegistryBasePath $name
        if (Test-Path -LiteralPath $keyPath) {
            try { Remove-Item -LiteralPath $keyPath -Recurse -Force -ErrorAction Stop }
            catch {
                Write-Host ('[FAIL] 清理托管 QoS 规则失败：' + $keyPath + '（' + $_.Exception.Message + '）') -ForegroundColor Red
                $allOk = $false
            }
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $RegistryBasePath)) {
            New-Item -Path $RegistryBasePath -Force -ErrorAction Stop | Out-Null
        }
        foreach ($policy in @(Get-GameQosPolicyEntries $snapshot.Policies)) {
            $targetKey = Join-Path $RegistryBasePath $policy.Name
            # Always open/create the snapshot key so a failed registry create/open is reported;
            # Test-Path alone can hide access failures and make recovery look successful.
            New-Item -Path $targetKey -Force -ErrorAction Stop | Out-Null
            foreach ($value in @(Get-GameQosValueEntries $policy.Values)) {
                Set-ItemProperty -LiteralPath $targetKey -Name $value.Name -Value ([string]$value.Value) -Type String -Force -ErrorAction Stop | Out-Null
                $actual = (Get-ItemProperty -LiteralPath $targetKey -Name $value.Name -ErrorAction Stop).$($value.Name)
                if ([string]$actual -cne [string]$value.Value) {
                    throw "恢复后的 QoS 属性回读不一致：$($policy.Name)\$($value.Name)"
                }
            }
        }
        if ($allOk) {
            Write-Host '[OK] 游戏 QoS 策略已成功按快照还原。' -ForegroundColor Green
        } else {
            Write-Host '[WARN] 游戏 QoS 策略恢复未完全成功，请复查输出中的 FAIL 项。' -ForegroundColor Yellow
        }
        return $allOk
    }
    catch {
        Write-Host ('[FAIL] 还原游戏 QoS 策略失败：' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}
