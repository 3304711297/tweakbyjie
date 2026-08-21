# Virtualization.ps1 - Part 9 Device Guard EFI 清除 / Part 10 VBS 与 Hyper-V 管理
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Invoke-DeviceGuardModule {

    # ======================= Part 9: 清除 Device Guard EFI 锁定 =======================
    # 应对 UEFI 锁定：选项 10 的关闭子项可通过注册表关闭 VBS/HVCI/Credential Guard，
    # 但 安全中心 / msinfo32 仍显示"内存完整性"或"凭据保护"开启时，
    # 用 SecConfig.efi 引导清除 EFI 变量（硬手段，等效于官方 DG_Readiness_Tool）。
    Write-Host ""
    Write-Host "============ [Part 9] 清除 Device Guard EFI 锁定 / Clear DG UEFI Lock (SecConfig.efi) ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 适用场景：UEFI 锁定 —— 已运行选项 10（注册表关闭），但 安全中心/msinfo32 仍显示" -ForegroundColor Yellow
    Write-Host "            内核隔离-内存完整性 或 凭据保护 处于开启状态。" -ForegroundColor Yellow
    Write-Host " 原理：把 SecConfig.efi 设为一次性引导项，开机进入后清除 Device Guard 的 EFI 变量。" -ForegroundColor Yellow
    Write-Host ""

    $dgGuid = '{0cb3b571-2f2e-4343-a879-d86a476d7215}'

    Write-Host "  1. 执行（BitLocker 预检查 -> 挂载 EFI 分区 -> 复制 SecConfig.efi -> 配置一次性引导项）" -ForegroundColor White
    Write-Host "  2. 清理（删除一次性引导项、清空引导序列、卸载 EFI 分区盘符；不重启）" -ForegroundColor White
    $gChoice = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"

    if ($gChoice -eq "1") {

        Write-Host ""
        Write-Host " [WARNING] 执行后重启时，开机会出现一个确认界面，需按屏幕提示按键（通常为 F3）确认" -ForegroundColor Yellow
        Write-Host "           禁用 Credential Guard；错过或拒绝则本次不生效（一次性引导项不会再次出现，可重跑）。" -ForegroundColor Yellow
        Write-Host " [WARNING] 若机器开启了 BitLocker，清除 EFI 变量会改变 TPM 度量值，可能触发恢复模式" -ForegroundColor Yellow
        Write-Host "           （要求输入 48 位恢复密钥）。本选项已内置 BitLocker 预检查，检测到已开启会拒绝执行。" -ForegroundColor Yellow
        $confirmDg = Read-Host "确定执行吗？(Y = 执行 / N = 取消)"
        if ($confirmDg -notin @('Y','y')) {
            Write-Host "[SKIP] 已取消，未做任何修改（不重启）" -ForegroundColor Yellow
        } else {

            # 1) BitLocker 预检查：任一分区保护开启或状态无法确认都拒绝执行
            $blBlocked = $false
            $blCheckFailed = $false
            try {
                $blOn = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' })
                if ($blOn.Count -gt 0) {
                    $blBlocked = $true
                    Write-Host "[FAIL] 检测到 BitLocker 保护已开启，为避免触发恢复模式，已拒绝执行：" -ForegroundColor Red
                    foreach ($v in $blOn) {
                        Write-Host ("        {0}  {1}" -f $v.MountPoint, $v.VolumeStatus) -ForegroundColor Red
                    }
                    Write-Host "        请先暂停保护（Suspend-BitLocker，可维持数次重启）或彻底解密后再运行本选项" -ForegroundColor Yellow
                    $script:fail++
                } else {
                    Write-Host "[OK] BitLocker 预检查通过（未开启保护，无恢复模式风险）"
                    $script:ok++
                }
            } catch {
                $blCheckFailed = $true
                Write-Host "[FAIL] 无法查询 BitLocker 状态：$($_.Exception.Message)；已拒绝 EFI 修改" -ForegroundColor Red
                $script:fail++
            }

            if (-not $blBlocked -and -not $blCheckFailed) {

                # 2) SecConfig.efi 源文件检查
                $secSrc = Join-Path $env:SystemRoot 'System32\SecConfig.efi'
                if (-not (Test-Path $secSrc)) {
                    Write-Host "[FAIL] 未找到 $secSrc，当前系统不带此文件，无法执行" -ForegroundColor Red
                    $script:fail++
                } else {

                    # 3) 选择空闲盘符并挂载 EFI 分区
                    $efiLetter = $null
                    foreach ($l in @('X','Y','Z','V','W','U')) {
                        if (-not (Test-Path "$($l):\")) { $efiLetter = $l; break }
                    }
                    if (-not $efiLetter) {
                        Write-Host "[FAIL] 找不到空闲盘符（X/Y/Z/V/W/U 均被占用）" -ForegroundColor Red
                        $script:fail++
                    } else {
                        $mounted = $false
                        try {
                            & mountvol.exe "$($efiLetter):" /s *> $null
                            if ($LASTEXITCODE -ne 0) { throw "mountvol exit code $LASTEXITCODE" }
                            $mounted = $true
                            Write-Host "[OK] EFI 分区已挂载到 $($efiLetter):"
                            $script:ok++
                        } catch {
                            Write-Host "[FAIL] 挂载 EFI 分区失败（本机可能非 UEFI 启动）：$($_.Exception.Message)" -ForegroundColor Red
                            $script:fail++
                        }

                        if ($mounted) {

                            # 4) 复制 SecConfig.efi 到 EFI 分区（复制成功才配置引导项）
                            $copyOk = $false
                            try {
                                $bootDir = "$($efiLetter):\EFI\Microsoft\Boot"
                                if (-not (Test-Path $bootDir)) { New-Item -ItemType Directory -Path $bootDir -Force | Out-Null }
                                Copy-Item $secSrc (Join-Path $bootDir 'SecConfig.efi') -Force -ErrorAction Stop
                                $copyOk = $true
                                Write-Host "[OK] SecConfig.efi 已复制到 $bootDir"
                                $script:ok++
                            } catch {
                                Write-Host "[FAIL] 复制 SecConfig.efi : $($_.Exception.Message)" -ForegroundColor Red
                                $script:fail++
                            }

                            $efiConfigured = $false
                            if ($copyOk) {

                                # 5) 配置一次性引导项；任一步失败都停止并清理临时项
                                & bcdedit.exe /delete $dgGuid /f *> $null
                                $bcdOk = Invoke-BcdEdit "/create $dgGuid /d DebugTool /application osloader" "创建 BCD 引导项 (DebugTool)"
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid path \EFI\Microsoft\Boot\SecConfig.efi" "引导项路径 SecConfig.efi" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid device partition=$($efiLetter):" "引导项设备分区 $($efiLetter):" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid loadoptions DISABLE-LSA-ISO" "LoadOptions = DISABLE-LSA-ISO" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set {bootmgr} bootsequence $dgGuid" "设为下次开机一次性引导" }
                                if ($bcdOk) {
                                    $efiConfigured = $true
                                } else {
                                    Write-Host "[FAIL] EFI 一次性引导配置未完成，正在清理临时 BCD 项" -ForegroundColor Red
                                    & bcdedit.exe /delete $dgGuid /f *> $null
                                    & bcdedit.exe /deletevalue '{bootmgr}' bootsequence *> $null
                                }
                            }

                            # 6) 卸载 EFI 分区
                            & mountvol.exe "$($efiLetter):" /d *> $null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[OK] EFI 分区已卸载（$($efiLetter):）"
                                $script:ok++
                            } else {
                                Write-Host "[WARN] EFI 分区卸载失败，可稍后手动执行: mountvol $($efiLetter): /d" -ForegroundColor Yellow
                            }

                            if ($efiConfigured) {
                                $script:rebootRequired = $true
                                # Summary
                                Write-Host ""
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host " Finished (Part 9 - Clear DG UEFI Lock)" -ForegroundColor Cyan
                                Write-Host " OK : $script:ok" -ForegroundColor Green
                                Write-Host " FAIL : $script:fail" -ForegroundColor Red
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host ""
                                Write-Host " 重启开机会出现确认界面，请按屏幕提示按键（通常为 F3）确认禁用！" -ForegroundColor Yellow
                                Write-Host " 重启确认后可用 msinfo32 -> 系统摘要 -> 基于虚拟化的安全性 验证是否已关闭。" -ForegroundColor Yellow

                                                    Request-Restart
                            } else {
                                Write-Host ""
                                Write-Host "[提示] EFI 一次性引导配置未完成，未设置待重启状态" -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }

            if ($blBlocked) {
                Write-Host ""
                Write-Host "[提示] 未做任何修改（不重启）" -ForegroundColor Yellow
            }
        }

    } elseif ($gChoice -eq "2") {

        # 1) 删除一次性引导项（如存在）
        & bcdedit.exe /enum $dgGuid *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-BcdEdit "/delete $dgGuid /f" "删除 BCD 引导项 (DebugTool)"
        } else {
            Write-Host "[SKIP] BCD 引导项不存在（无需删除）" -ForegroundColor Yellow
            $script:skip++
        }

        # 2) 清空 {bootmgr} 的 bootsequence（如仍指向该引导项）
        $bmEnum = & bcdedit.exe /enum '{bootmgr}' 2>$null
        if ($LASTEXITCODE -eq 0 -and ($bmEnum -join "`n") -match 'bootsequence') {
            Invoke-BcdEdit "/deletevalue {bootmgr} bootsequence" "清空一次性引导序列"
        } else {
            Write-Host "[SKIP] bootsequence 未设置（无需清理）" -ForegroundColor Yellow
            $script:skip++
        }

        # 3) 卸载残留的 EFI 分区盘符（仅当该盘符下存在脚本复制的 SecConfig.efi）
        $unmounted = 0
        foreach ($l in @('X','Y','Z','V','W','U')) {
            if (Test-Path "$($l):\EFI\Microsoft\Boot\SecConfig.efi") {
                & mountvol.exe "$($l):" /d *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] 已卸载 EFI 分区盘符 $($l):"
                    $script:ok++
                    $unmounted++
                } else {
                    Write-Host "[FAIL] 卸载 $($l): 失败，可手动执行: mountvol $($l): /d" -ForegroundColor Red
                    $script:fail++
                    $unmounted++
                }
            }
        }
        if ($unmounted -eq 0) {
            Write-Host "[SKIP] 无残留的 EFI 分区挂载" -ForegroundColor Yellow
            $script:skip++
        }

        # Summary（无需重启）
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 9 - Cleanup)" -ForegroundColor Cyan
        Write-Host " OK : $script:ok" -ForegroundColor Green
        Write-Host " FAIL : $script:fail" -ForegroundColor Red
        Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "提示：清理完成，无需重启。" -ForegroundColor Yellow

    } else {
        Write-Host "[ERROR] 无效输入：$gChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
    }

}

function Invoke-VbsModule {
    Write-Host ""; Write-Host "============ [Part 10] 虚拟化 / VBS / Hyper-V 管理 ============" -ForegroundColor Cyan; Write-Host ""
    $dgRegValues=@(@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity';Name='Enabled'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard';Name='EnableVirtualizationBasedSecurity'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\LSA';Name='LsaCfgFlags'},@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard';Name='EnableVirtualizationBasedSecurity'},@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard';Name='RequirePlatformSecurityFeatures'})
    Write-Host "  0. 查看当前状态";Write-Host "  1. 关闭 VBS/HVCI/Credential Guard + Hyper-V" -ForegroundColor Yellow;Write-Host "  2. 删除脚本覆盖并尝试启用 Hyper-V（不是原始状态精确回滚）"
    $vChoice=Read-Host "请输入 0、1 或 2 并回车"
    if($vChoice -eq '0'){
        $bcEnum=(& bcdedit.exe /enum '{current}' 2>$null)-join "`n";foreach($n in @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')){if($bcEnum -match ('(?m)^\s*'+[regex]::Escape($n)+'\s+(\S+)')){Write-Host ("bcdedit {0,-24} = {1}"-f $n,$Matches[1])}else{Write-Host ("bcdedit {0,-24} = <未设置（系统默认）>"-f $n)}};foreach($v in $dgRegValues){$item=Get-Item $v.Path -ErrorAction SilentlyContinue;if($item -and ($item.GetValueNames()-contains $v.Name)){Write-Host ("注册表 {0} -> {1} = {2}"-f $v.Path,$v.Name,$item.GetValue($v.Name))}};foreach($fn in @('Microsoft-Hyper-V-All','VirtualMachinePlatform','HypervisorPlatform')){$f=Get-WindowsOptionalFeature -Online -FeatureName $fn -ErrorAction SilentlyContinue;if($f){Write-Host ("功能 {0,-26} = {1}"-f $fn,$f.State)}};$cs=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue;if($cs){Write-Host ("运行时 HypervisorPresent = {0}"-f $cs.HypervisorPresent)}
    } elseif($vChoice -eq '1'){
        foreach($v in $dgRegValues){Set-RegDword $v.Path $v.Name 0 ("关闭虚拟化安全 "+$v.Name)}
        try{$hv=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop;if($hv.State -in @('Enabled','EnablePending')){$null=Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart -ErrorAction Stop;Write-Host '[OK] Hyper-V 功能组件已禁用';$script:ok++;$script:rebootRequired=$true}else{Write-Host '[SKIP] Hyper-V 功能组件未启用' -ForegroundColor Yellow;$script:skip++}}catch{Write-Host "[FAIL] Hyper-V 功能组件禁用 : $($_.Exception.Message)" -ForegroundColor Red;$script:fail++}
        Invoke-BcdEdit "/set hypervisorlaunchtype off" "Hypervisor Launch Type Off";Invoke-BcdEdit "/set isolatedcontext no" "Isolated Context Off";Invoke-BcdEdit "/set vsmlaunchtype off" "VSM Launch Type Off";Verify-BcdValue 'hypervisorlaunchtype' 'Off' 'hypervisorlaunchtype'|Out-Null;Verify-BcdValue 'isolatedcontext' 'No' 'isolatedcontext'|Out-Null;Verify-BcdValue 'vsmlaunchtype' 'Off' 'vsmlaunchtype'|Out-Null;Write-Host '[提示] 重启后再验证 HypervisorPresent / msinfo32 实际运行状态。' -ForegroundColor Yellow
    } elseif($vChoice -eq '2'){
        foreach($v in $dgRegValues){$item=Get-Item $v.Path -ErrorAction SilentlyContinue;if($item -and ($item.GetValueNames()-contains $v.Name)){$regPath=Convert-RegExePath $v.Path;& reg.exe DELETE $regPath /v $v.Name /f *> $null;if($LASTEXITCODE -eq 0){Write-Host ("[OK] 已删除注册表值 {0} -> {1}"-f $v.Path,$v.Name);$script:ok++;$script:rebootRequired=$true}else{Write-Host ("[FAIL] 删除注册表值 {0} -> {1}"-f $v.Path,$v.Name) -ForegroundColor Red;$script:fail++}}else{Write-Host ("[SKIP] 注册表值不存在: {0} -> {1}"-f $v.Path,$v.Name) -ForegroundColor Yellow;$script:skip++}}
        Remove-BcdValue 'hypervisorlaunchtype' '还原 hypervisorlaunchtype';Remove-BcdValue 'vsmlaunchtype' '还原 vsmlaunchtype';Remove-BcdValue 'isolatedcontext' '还原 isolatedcontext';try{$null=Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop;Write-Host '[OK] 已尝试启用 Hyper-V 功能组件（重启后生效）';$script:ok++;$script:rebootRequired=$true}catch{Write-Host "[FAIL] Hyper-V 功能组件启用 : $($_.Exception.Message)" -ForegroundColor Red;$script:fail++}
    } else {Write-Host "[ERROR] 无效输入：$vChoice 。请输入 0、1 或 2" -ForegroundColor Red}
    Write-Host "Finished (Part 10 - Virtualization Management)" -ForegroundColor Cyan;Write-Host " OK : $script:ok  FAIL : $script:fail  SKIP : $script:skip";Request-Restart

}
