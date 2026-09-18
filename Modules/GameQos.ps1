# GameQos.ps1 - Part 12 竞技游戏网络 QoS 策略管理（DSCP 46 数据包优先）
# 备份与恢复逻辑见 Modules/Backup.GameQos.ps1

$script:CompetitiveGameProfiles = @(
    @{ Name = "CS2"; Exe = "cs2.exe" },
    @{ Name = "Valorant"; Exe = "VALORANT-Win64-Shipping.exe" },
    @{ Name = "ApexLegends"; Exe = "r5apex.exe" },
    @{ Name = "Fortnite"; Exe = "FortniteClient-Win64-Shipping.exe" },
    @{ Name = "LeagueOfLegends"; Exe = "League of Legends.exe" },
    @{ Name = "RainbowSixSiege"; Exe = "RainbowSix.exe" },
    @{ Name = "Overwatch2"; Exe = "Overwatch.exe" },
    @{ Name = "CrossFire"; Exe = "crossfire.exe" },
    @{ Name = "NarakaBladepoint"; Exe = "NarakaBladepoint.exe" },
    @{ Name = "PUBG"; Exe = "TslGame.exe" },
    @{ Name = "CallOfDuty"; Exe = "cod.exe" }
)

function Get-GameQosManagedNames {
    return @($script:CompetitiveGameProfiles | ForEach-Object { $_.Name })
}

function Get-GameQosProperties {
    param([string]$ExeName)
    return [ordered]@{
        "Version"                 = "1.0"
        "Application Name"        = $ExeName
        "Protocol"                = "*"
        "Local Port"              = "*"
        "Local IP"                = "*"
        "Local IP Prefix Length"  = "*"
        "Remote Port"             = "*"
        "Remote IP"               = "*"
        "Remote IP Prefix Length" = "*"
        "DSCP Value"              = "46"
        "Throttle Rate"           = "-1"
    }
}

function Test-GameQosProfileInput {
    param([string]$PolicyName, [string]$ExeName)
    if (-not (Test-GameQosSafeName $PolicyName)) { return $false }
    if ([string]::IsNullOrWhiteSpace($ExeName) -or $ExeName -notmatch '^[^\\/:*?"<>|\x00-\x1F]+\.exe$') { return $false }
    return $true
}

function Test-GameQosPolicyApplied {
    param([string]$KeyPath, [System.Collections.IDictionary]$Properties)
    if (-not (Test-Path -LiteralPath $KeyPath -PathType Container)) { return $false }
    try {
        foreach ($name in $Properties.Keys) {
            $item = Get-ItemProperty -LiteralPath $KeyPath -Name $name -ErrorAction Stop
            if ([string]$item.$name -cne [string]$Properties[$name]) { return $false }
        }
        return $true
    } catch { return $false }
}

function Set-SingleGameQosPolicy {
    param(
        [string]$PolicyName,
        [string]$ExeName,
        [string]$RegistryBasePath = $script:GameQosKeyPath
    )
    if (-not (Test-GameQosProfileInput $PolicyName $ExeName)) {
        throw "拒绝不安全的游戏 QoS 配置：$PolicyName / $ExeName"
    }
    $keyPath = Join-Path $RegistryBasePath $PolicyName
    try {
        if (-not (Test-Path -LiteralPath $keyPath -PathType Container)) {
            New-Item -Path $keyPath -Force -ErrorAction Stop | Out-Null
        }
        $props = Get-GameQosProperties $ExeName
        foreach ($k in $props.Keys) {
            # 写入失败必须终止；不能再用 SilentlyContinue 后报告“成功”。
            Set-ItemProperty -LiteralPath $keyPath -Name $k -Value $props[$k] -Type String -Force -ErrorAction Stop | Out-Null
        }
        if (-not (Test-GameQosPolicyApplied $keyPath $props)) {
            throw "QoS 策略写入后回读校验失败：$keyPath"
        }
        return $true
    }
    catch {
        throw "写入游戏 QoS 策略 $PolicyName 失败：$($_.Exception.Message)"
    }
}

function Invoke-GameQosModule {
    param(
        [string]$Action = '',
        [string]$Choice = '',
        [string]$BackupFile = "$env:TEMP\gameqos-backup.json",
        [string]$RegistryBasePath = $script:GameQosKeyPath
    )

    # Choice 保留给已有调用者；新 CLI 统一使用 Action。
    if ([string]::IsNullOrWhiteSpace($Action)) { $Action = $Choice }
    $managedNames = Get-GameQosManagedNames

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定 QoS 子操作（1=apply，2=restore，0=status）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        Write-Host ""
        Write-Host "============ [Part 12] 竞技游戏网络 QoS 策略管理 ============" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  说明：通过 Windows QoS 组策略为竞技网游流量标记 DSCP 46（加速转发）并解除限速" -ForegroundColor Gray
        Write-Host "  覆盖游戏：CS2 / Valorant / Apex / 永劫无间 / 英雄联盟 / 绝地求生 / 守望先锋 / COD 等" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  1. 备份并应用竞技游戏 QoS 策略（DSCP 46 优先标记）" -ForegroundColor White
        Write-Host "  2. 还原或清理游戏 QoS 策略（恢复默认）" -ForegroundColor White
        Write-Host "  0. 返回主菜单" -ForegroundColor White
        Write-Host ""
        $Action = Read-Host "请选择 / Select an option"
    }

    switch -Regex ($Action.ToLowerInvariant()) {
        '^(1|apply|enable)$' {
            Write-Host "[INFO] 正在备份当前 QoS 策略并写入竞技游戏规则..." -ForegroundColor Cyan
            if (-not (Ensure-GameQosBackup -BackupFile $BackupFile -RegistryBasePath $RegistryBasePath)) {
                Write-Host "[FAIL] 备份失败，已终止写入。" -ForegroundColor Red
                $script:fail++
                return $false
            }

            try {
                foreach ($game in $script:CompetitiveGameProfiles) {
                    Set-SingleGameQosPolicy -PolicyName $game.Name -ExeName $game.Exe -RegistryBasePath $RegistryBasePath | Out-Null
                    Write-Host "  [+] 已配置 QoS 策略: $($game.Name) ($($game.Exe)) -> DSCP 46" -ForegroundColor Green
                }
                Write-Host "[OK] 竞技游戏 QoS 策略已应用，并已逐条回读验证。" -ForegroundColor Green
                $script:ok++
                return $true
            }
            catch {
                Write-Host "[FAIL] 竞技游戏 QoS 应用失败：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                # 快照存在时回滚已写入的部分，避免半套策略被误报成成功。
                if (-not (Restore-GameQosBackup -BackupFile $BackupFile -RegistryBasePath $RegistryBasePath -ManagedPolicyNames $managedNames)) {
                    Write-Host '[FAIL] QoS 部分回滚也未完全成功，请勿继续应用，先人工检查快照与注册表。' -ForegroundColor Red
                    $script:fail++
                } else {
                    Write-Host '[OK] 已按应用前快照回滚已写入的 QoS 规则。' -ForegroundColor Yellow
                }
                return $false
            }
        }
        '^(2|restore|reset|clean)$' {
            Write-Host "[INFO] 正在还原游戏 QoS 策略..." -ForegroundColor Cyan
            $res = Restore-GameQosBackup -BackupFile $BackupFile -RegistryBasePath $RegistryBasePath -ManagedPolicyNames $managedNames
            if ($res) { $script:ok++ } else { $script:fail++ }
            return $res
        }
        '^(0|status)$' {
            foreach ($game in $script:CompetitiveGameProfiles) {
                $keyPath = Join-Path $RegistryBasePath $game.Name
                $state = if (Test-GameQosPolicyApplied $keyPath (Get-GameQosProperties $game.Exe)) { '已配置' } else { '未配置/不完整' }
                Write-Host ("{0,-20} {1}" -f $game.Name, $state)
            }
            return $true
        }
        default {
            Write-Host "[FAIL] 无效 QoS 子操作：$Action（可用 0=status、1=apply、2=restore）" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }
}
