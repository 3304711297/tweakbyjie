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

function Set-SingleGameQosPolicy {
    param(
        [string]$PolicyName,
        [string]$ExeName,
        [string]$RegistryBasePath = $script:GameQosKeyPath
    )
    $keyPath = Join-Path $RegistryBasePath $PolicyName
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $props = @{
        "Version"                = "1.0"
        "Application Name"       = $ExeName
        "Protocol"               = "*"
        "Local Port"             = "*"
        "Local IP"               = "*"
        "Local IP Prefix Length" = "*"
        "Remote Port"            = "*"
        "Remote IP"              = "*"
        "Remote IP Prefix Length"= "*"
        "DSCP Value"             = "46"
        "Throttle Rate"          = "-1"
    }

    foreach ($k in $props.Keys) {
        Set-ItemProperty -Path $keyPath -Name $k -Value $props[$k] -Type String -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Invoke-GameQosModule {
    param(
        [string]$Choice = '',
        [string]$BackupFile = "$env:TEMP\gameqos-backup.json",
        [string]$RegistryBasePath = $script:GameQosKeyPath
    )

    $managedNames = Get-GameQosManagedNames

    if (-not $Choice) {
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
        $Choice = Read-Host "请选择 / Select an option"
    }

    switch ($Choice) {
        '1' {
            Write-Host "[INFO] 正在备份当前 QoS 策略并写入竞技游戏规则..." -ForegroundColor Cyan
            $backedUp = Ensure-GameQosBackup -BackupFile $BackupFile -RegistryBasePath $RegistryBasePath
            if (-not $backedUp) {
                Write-Host "[FAIL] 备份失败，已终止写入。" -ForegroundColor Red
                $script:fail++
                return $false
            }

            foreach ($game in $script:CompetitiveGameProfiles) {
                Set-SingleGameQosPolicy -PolicyName $game.Name -ExeName $game.Exe -RegistryBasePath $RegistryBasePath
                Write-Host "  [+] 已配置 QoS 策略: $($game.Name) ($($game.Exe)) -> DSCP 46" -ForegroundColor Green
            }
            Write-Host "[OK] 竞技游戏 QoS 策略已成功应用。" -ForegroundColor Green
            $script:ok++
            return $true
        }
        '2' {
            Write-Host "[INFO] 正在还原游戏 QoS 策略..." -ForegroundColor Cyan
            $res = Restore-GameQosBackup -BackupFile $BackupFile -RegistryBasePath $RegistryBasePath -ManagedPolicyNames $managedNames
            if ($res) { $script:ok++ } else { $script:fail++ }
            return $res
        }
        '0' {
            return $true
        }
        default {
            Write-Host "[WARN] 无效选项。" -ForegroundColor Yellow
            return $false
        }
    }
}
