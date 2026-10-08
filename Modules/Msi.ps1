# Msi.ps1 - Part 13 PCIe 设备 MSI 中断模式管理
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Invoke-MsiModule {
    param([string]$Action = '')

    Write-Host ""
    Write-Host "============ [Part 13] PCIe 设备 MSI 中断模式管理 / PCIe MSI Mode ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  0. 查看当前 PCI 设备 MSI 支持与配置状态（只读）" -ForegroundColor White
    Write-Host "  1. 优化受支持的核心硬件 MSI 模式（GPU/网卡/NVMe 开启 MSISupported=1；修改前自动备份）" -ForegroundColor White
    Write-Host "  2. 按快照恢复 PCIe MSI 原始配置（msi-backup.json）" -ForegroundColor White
    Write-Host "  0. 返回主菜单" -ForegroundColor White

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定 MSI 子操作（1=apply、2=restore、0=status）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入 0、1 或 2 并回车"
    }

    switch ($Action.ToLowerInvariant()) {
        '0' {
            Write-Host "`n--- [受管白名单设备当前 MSI 状态] ---" -ForegroundColor Cyan
            $devices = Get-MsiManagedDevices
            if ($devices.Count -eq 0) {
                Write-Host "未发现带中断管理特性的白名单设备。" -ForegroundColor Yellow
            } else {
                $devices | Select-Object DeviceDesc, Class, MSISupported, MessageLimit | Format-Table -AutoSize | Out-String | Write-Host
            }
            if (Test-Path -LiteralPath $script:msiBackupFile -PathType Leaf) {
                Write-Host "MSI 备份文件就绪：$script:msiBackupFile" -ForegroundColor Yellow
            }
            return $true
        }
        '1' {
            Write-Host "[PCIe MSI Optimization]" -ForegroundColor Cyan
            if (-not (Ensure-MsiBackup)) {
                Write-Host "[FAIL] 无法备份原始 MSI 状态，已阻止修改。" -ForegroundColor Red
                return $false
            }

            $devices = Get-MsiManagedDevices
            if ($devices.Count -eq 0) {
                Write-Host "[SKIP] 未找到受支持的白名单硬件设备。" -ForegroundColor Yellow
                $script:skip++
                return $true
            }

            $operationOk = $true
            $beforeFail = $script:fail

            foreach ($d in $devices) {
                try {
                    # 1. 确保 MSISupported = 1
                    Set-RegDword $d.RegPath 'MSISupported' 1 "$($d.DeviceDesc) MSISupported = 1"
                    if (-not (Verify-RegDword $d.RegPath 'MSISupported' 1 "$($d.DeviceDesc) MSISupported")) {
                        throw "回读验证未达到 MSISupported = 1"
                    }

                    # 2. 针对 GPU / 网卡规范消息限制（若原本未设置，规范化为 1；NVMe 保持其多队列原生限制）
                    if ($d.Class -in @('Display', 'Net') -and ($null -eq $d.MessageLimit -or $d.MessageLimit -eq 0)) {
                        Set-RegDword $d.RegPath 'MessageNumberLimit' 1 "$($d.DeviceDesc) MessageNumberLimit = 1"
                    }
                } catch {
                    Write-Host "[FAIL] 配置 $($d.DeviceDesc) MSI 异常：$($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                    $operationOk = $false
                    break
                }
            }

            if (-not $operationOk -or $script:fail -gt $beforeFail) {
                Write-Host '[FAIL] PCIe MSI 配置未完整完成，正在按原始快照回滚。' -ForegroundColor Red
                Restore-MsiBackup | Out-Null
                return $false
            }

            Write-Host '[OK] 核心 PCIe 设备（GPU/网卡/NVMe）MSI 模式已配置完成；需重启后生效。' -ForegroundColor Green
            Request-Restart
            return $true
        }
        '2' {
            $result = Restore-MsiBackup
            Request-Restart
            return $result
        }
        default {
            Write-Host "[FAIL] 无效输入：$Action 。请输入 0、1 或 2" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }
}
