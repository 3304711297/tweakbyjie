# Nvme.ps1 - Part 8 原生 NVMe 驱动配置（交互编排）
# 备份/恢复逻辑见 Modules/Backup.Nvme.ps1

function Invoke-NvmeModule {

    # ======================= Part 8: Native NVMe Driver =======================
    # Preferred path: ViVeTool feature IDs 60786016 + 48433719.
    # Legacy registry overrides are retained only for compatibility/inspection and
    # are no longer treated as proof that the native driver is active.
    Write-Host ""
    Write-Host "============ [Part 8] 原生 NVMe 驱动 / Native NVMe Driver (nvmedisk.sys) ============" -ForegroundColor Cyan
    Write-Host ""

    $cvKey = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildNum = [int]($cvKey.GetValue('CurrentBuildNumber'))
    $dispVer = [string]($cvKey.GetValue('DisplayVersion'))
    $nvmeDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'NVMe' })
    $sbGuid = '{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}'
    $fmPath = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
    $legacyIds = @('735209102', '1853569164', '156965516')
    $viVe = Find-ViVeTool

    Write-Host ("系统版本 : $dispVer (build $buildNum)")
    Write-Host ("NVMe 磁盘 : " + $(if ($nvmeDisks.Count -gt 0) { "检测到 $($nvmeDisks.Count) 块" } else { "未检测到" }))
    Write-Host ("ViVeTool : " + $(if ($viVe) { $viVe } else { "未找到" }))
    Write-Host ""

    Write-Host "  0. 查看当前状态（Feature / SafeBoot / Legacy Override / nvmedisk 实际状态）" -ForegroundColor White
    Write-Host "  1. 启用 Native NVMe（ViVeTool 60786016 + 48433719）" -ForegroundColor White
    Write-Host "  2. 还原到启用前快照" -ForegroundColor White
    $nChoice = Read-Host "请输入 0、1 或 2 并回车"

    if ($nChoice -eq '0') {

        if ($viVe) {
            $cfg = Test-NativeNvmeConfigured $viVe
            Write-Host "ViVeTool 60786016 : $($cfg.Feature60786016)"
            Write-Host "ViVeTool 48433719 : $($cfg.Feature48433719)"
        } else {
            Write-Host "ViVeTool 60786016 : <无法查询>"
            Write-Host "ViVeTool 48433719 : <无法查询>"
        }

        $fmItem0 = Get-Item $fmPath -ErrorAction SilentlyContinue
        $legacyText = @()
        foreach ($id in $legacyIds) {
            if ($fmItem0 -and ($fmItem0.GetValueNames() -contains $id)) {
                $kind = $fmItem0.GetValueKind($id).ToString()
                $value = $fmItem0.GetValue($id)
                $legacyText += "$id=$value（$kind）"
            } else {
                $legacyText += "$id=未写入"
            }
        }
        Write-Host ("Legacy Feature Override : " + ($legacyText -join "  "))

        foreach ($mode in @('Minimal','Network')) {
            $sbPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
            if (Test-Path $sbPath) {
                $item = Get-Item $sbPath -ErrorAction SilentlyContinue
                $defaultValue = if ($item -and ($item.GetValueNames() -contains '')) { $item.GetValue('') } else { '<默认值缺失>' }
                Write-Host ("SafeBoot {0} : 已配置，Default={1}" -f $mode, $defaultValue)
            } else {
                Write-Host ("SafeBoot {0} : 未配置" -f $mode)
            }
        }

        $effective = Test-NativeNvmeEffective
        Write-Host ("nvmedisk.sys 文件 : " + $(if ($effective.FileExists) { "存在" } else { "不存在" }))
        Write-Host ("nvmedisk 驱动状态 : $($effective.State)")

        if ($effective.State -eq 'Running') {
            Write-Host "[EFFECTIVE] Native NVMe 已实际生效，当前 nvmedisk 驱动正在运行。" -ForegroundColor Green
        } elseif ($viVe -and (Test-NativeNvmeConfigured $viVe).BothEnabled) {
            Write-Host "[CONFIGURED] 两个 Feature 已启用，但当前尚未确认 nvmedisk 实际运行；请重启后再次执行 8 -> 0。" -ForegroundColor Yellow
        } elseif ($effective.FileExists) {
            Write-Host "[NOT EFFECTIVE] 系统存在 nvmedisk.sys，但当前未确认由它运行。" -ForegroundColor Yellow
        } else {
            Write-Host "[NOT ENABLED] 当前未确认 Native NVMe 生效。" -ForegroundColor Yellow
        }

    } elseif ($nChoice -eq '1') {

        if ($nvmeDisks.Count -eq 0) {
            Write-Host "[SKIP] 未检测到 NVMe 磁盘，本项无作用，不修改。" -ForegroundColor Yellow
        } elseif ($buildNum -lt 26200) {
            Write-Host "[ABORTED] build $buildNum 低于 26200；此模块仅针对 Windows 11 25H2+（26200+）。" -ForegroundColor Red
        } elseif (-not $viVe) {
            Write-Host "[ABORTED] 未找到 ViVeTool.exe。" -ForegroundColor Red
            Write-Host "请从官方 ViVeTool 发布页获取与系统架构匹配的版本，并将 ViVeTool.exe 放在本脚本目录或加入 PATH。" -ForegroundColor Yellow
        } elseif (-not (Ensure-NvmeBackup $sbGuid $viVe $fmPath)) {
            Write-Host "[ABORTED] Native NVMe 备份不可用，未执行修改。" -ForegroundColor Red
        } else {

            Write-Host ""
            Write-Host "[1/3] 启用 Native NVMe Feature：60786016 + 48433719" -ForegroundColor Cyan
            & $viVe /enable /id:60786016,48433719 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[FAIL] ViVeTool 启用 Feature 失败，未继续修改 SafeBoot。" -ForegroundColor Red
                $script:fail++
            } else {
                $cfgAfter = Test-NativeNvmeConfigured $viVe
                if (-not $cfgAfter.BothEnabled) {
                    Write-Host "[WARN] ViVeTool 命令完成，但查询不到两个 Feature 都为 Enabled；停止后续修改。" -ForegroundColor Yellow
                    $script:fail++
                } else {
                    Write-Host "[OK] 60786016 + 48433719 = Enabled" -ForegroundColor Green
                    $script:ok += 2
                    $script:rebootRequired = $true

                    Write-Host ""
                    Write-Host "[2/3] SafeBoot NVMe 加固" -ForegroundColor Cyan
                    $safeBootOk = $true
                    foreach ($mode in @('Minimal','Network')) {
                        $sbReg = Convert-RegExePath "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
                        & reg.exe ADD $sbReg /ve /t REG_SZ /d "Storage Disks" /f *> $null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[OK] SafeBoot $mode = Storage Disks"
                            $script:ok++
                        } else {
                            Write-Host "[FAIL] SafeBoot $mode : reg.exe exit code $LASTEXITCODE" -ForegroundColor Red
                            $script:fail++
                            $safeBootOk = $false
                        }
                    }

                    if (-not $safeBootOk) {
                        Write-Host "[FAIL] SafeBoot 配置未完整完成，正在按启用前 Version 3 快照回滚。" -ForegroundColor Red
                        Restore-NvmeSafeBootBackup $sbGuid $viVe $fmPath | Out-Null
                    } else {
                        Write-Host ""
                        Write-Host "[3/3] Legacy Override 兼容说明" -ForegroundColor Cyan
                        Write-Host "[INFO] 保留现有 735209102 / 1853569164 / 156965516，不再自动写入或删除它们。" -ForegroundColor Yellow
                        Write-Host "[INFO] 这些旧值仍可在 8 -> 0 中查看，但不再作为 Native NVMe 已生效的判断依据。" -ForegroundColor Yellow

                        Write-Host ""
                        Write-Host "配置已完成，但必须重启后才能确认实际驱动。" -ForegroundColor Yellow
                        Write-Host "重启后执行：8 -> 0" -ForegroundColor Yellow
                        Write-Host "真正成功条件：nvmedisk 驱动状态 = Running。" -ForegroundColor Yellow
                        Request-Restart
                    }
                }
            }
        }

    } elseif ($nChoice -eq '2') {

        if (-not $viVe) {
            Write-Host "[ABORTED] 未找到 ViVeTool.exe，无法精确恢复 Feature 状态。" -ForegroundColor Red
            Write-Host "请将与启用时相同的 ViVeTool.exe 放回脚本目录或 PATH，再执行 8 -> 2。" -ForegroundColor Yellow
            $script:fail++
        } else {
            Restore-NvmeSafeBootBackup $sbGuid $viVe $fmPath | Out-Null
            Request-Restart
        }

    } else {
        Write-Host "[ERROR] 无效输入：$nChoice 。请输入 0、1 或 2" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 8 - Native NVMe Driver)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
}
