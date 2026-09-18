# Virtualization.ps1 - Part 9 Device Guard EFI 清除 / Part 10 VBS 与 Hyper-V 管理
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Get-DeviceGuardBootSequenceState {
    try {
        $output = (& bcdedit.exe /enum '{bootmgr}' 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw '无法读取 {bootmgr} BCD' }
        if ($output -match '(?im)^\s*bootsequence\s+([^\r\n]+)') {
            $value = $Matches[1].Trim()
            if ($value -notmatch '^\{[0-9a-fA-F-]{36}\}(?:\s+\{[0-9a-fA-F-]{36}\})*$') {
                throw "bootsequence 含有未识别内容，拒绝保存/恢复：$value"
            }
            return [pscustomobject]@{ Present = $true; Value = $value }
        }
        return [pscustomobject]@{ Present = $false; Value = $null }
    } catch { throw }
}

function Test-DeviceGuardBackupSchema {
    param([object]$Backup)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        if ($null -eq $Backup.BootSequencePresent -or $Backup.BootSequencePresent -isnot [bool]) { return $false }
        if ([bool]$Backup.BootSequencePresent) {
            if ([string]$Backup.OriginalBootSequence -notmatch '^\{[0-9a-fA-F-]{36}\}(?:\s+\{[0-9a-fA-F-]{36}\})*$') { return $false }
        } elseif ($null -ne $Backup.OriginalBootSequence) { return $false }
        if ([string]$Backup.DgGuid -ine '{0cb3b571-2f2e-4343-a879-d86a476d7215}') { return $false }
        if ($null -eq $Backup.EfiPath -or [string]$Backup.EfiPath -notmatch '^[A-Z]:\\EFI\\Microsoft\\Boot\\SecConfig\.efi$') { return $false }
        if (([string]$Backup.EfiPath).Substring(0,1) -notin @('X','Y','Z','V','W','U')) { return $false }
        if ($null -eq $Backup.FileCreated -or $Backup.FileCreated -isnot [bool]) { return $false }
        if ([bool]$Backup.FileCreated) {
            if ([string]$Backup.FileHash -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        } elseif ($null -ne $Backup.FileHash) { return $false }
        if ($null -eq $Backup.BcdEntryCreated -or $Backup.BcdEntryCreated -isnot [bool]) { return $false }
        return $true
    } catch { return $false }
}

function Get-DeviceGuardFileHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return ([string](Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash).ToUpperInvariant() }
    catch { throw "无法读取 EFI 文件哈希：$Path" }
}

function Remove-DeviceGuardCopiedFile {
    param([object]$Backup, [string]$MountedLetter)
    if (-not [bool]$Backup.FileCreated) { return $true }
    $path = "${MountedLetter}:\EFI\Microsoft\Boot\SecConfig.efi"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "[SKIP] 工具创建的 SecConfig.efi 已不存在。" -ForegroundColor Yellow
        return $true
    }
    $actualHash = Get-DeviceGuardFileHash $path
    if ($actualHash -ine [string]$Backup.FileHash) {
        throw "拒绝删除哈希已变化的 EFI 文件：$path"
    }
    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $path -PathType Leaf) { throw "EFI 文件删除后仍存在：$path" }
    Write-Host "[OK] 已删除本工具创建且哈希匹配的 SecConfig.efi" -ForegroundColor Green
    return $true
}

function Invoke-DeviceGuardModule {
    param([string]$Action = '')

    Write-Host ""
    Write-Host "============ [Part 9] 清除 Device Guard EFI 锁定 / Clear DG UEFI Lock (SecConfig.efi) ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 执行（BitLocker 检查 -> 挂载 EFI -> 复制 SecConfig.efi -> 配置一次性引导项）" -ForegroundColor White
    Write-Host "  2. 清理本工具创建的引导项/EFI 文件，并恢复原始 bootsequence" -ForegroundColor White
    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定 EFI 子操作（1=prepare，2=cleanup）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"
    }
    if ($Action -in @('2','cleanup','restore')) {
        if (-not (Test-HighRiskConfirmation '确定清理本工具创建的 Device Guard EFI 引导项并恢复 bootsequence 吗？')) { return $false }
        if (-not (Test-Path -LiteralPath $script:deviceGuardBackupFile -PathType Leaf)) {
            Write-Host "[FAIL] 未找到受保护的 EFI 状态快照，拒绝盲删 bootsequence 或 SecConfig.efi：$script:deviceGuardBackupFile" -ForegroundColor Red
            $script:fail++
            return $false
        }
        try {
            $backup = Get-Content -LiteralPath $script:deviceGuardBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-DeviceGuardBackupSchema $backup)) { throw 'EFI 状态快照结构不正确或机器绑定不匹配' }
            $current = Get-DeviceGuardBootSequenceState
            $dgGuid = [string]$backup.DgGuid
            $currentHasTool = $current.Present -and ([string]$current.Value -match [regex]::Escape($dgGuid))
            $originalValue = if ([bool]$backup.BootSequencePresent) { [string]$backup.OriginalBootSequence } else { $null }
            $safeToRestore = $currentHasTool -or ((-not $current.Present) -and (-not $backup.BootSequencePresent)) -or
                ($current.Present -and [string]$current.Value -eq $originalValue)
            if (-not $safeToRestore) {
                throw '当前 bootsequence 已被其他内容改写，拒绝覆盖；请人工检查后再清理'
            }

            $rebootBefore = $script:rebootRequired
            $cleanupOk = $true
            if ($currentHasTool) {
                if ([bool]$backup.BootSequencePresent) {
                    if (-not (Invoke-BcdEdit "/set {bootmgr} bootsequence $originalValue" '恢复原始 bootsequence')) { $cleanupOk = $false }
                } else {
                    if (-not (Invoke-BcdEdit "/deletevalue {bootmgr} bootsequence" '删除原本未设置的 bootsequence')) { $cleanupOk = $false }
                }
            }
            $entry = & bcdedit.exe /enum $dgGuid 2>$null
            if ($LASTEXITCODE -eq 0) {
                $entryText = ($entry -join "`n")
                if ($entryText -match '(?i)SecConfig\.efi' -and $entryText -match '(?i)DISABLE-LSA-ISO' -and [bool]$backup.BcdEntryCreated) {
                    if (-not (Invoke-BcdEdit "/delete $dgGuid /f" '删除本工具创建的 Device Guard BCD 引导项')) { $cleanupOk = $false }
                } else {
                    throw '固定 Device Guard GUID 的 BCD 项不是本工具创建的 SecConfig 项，拒绝删除'
                }
            } else { Write-Host '[SKIP] 工具 BCD 引导项已不存在。' -ForegroundColor Yellow; $script:skip++ }
            if (-not $cleanupOk) { throw 'BCD 清理命令失败，保留状态快照供重试' }

            $letter = ([string]$backup.EfiPath).Substring(0,1)
            if (-not (Test-Path "${letter}:\")) {
                & mountvol.exe "${letter}:" /s *> $null
                if ($LASTEXITCODE -ne 0) { throw "挂载 EFI 分区失败：${letter}:" }
                $mountedHere = $true
            } else { $mountedHere = $false }
            $unmountOk = $true
            try { Remove-DeviceGuardCopiedFile $backup $letter | Out-Null }
            finally {
                if ($mountedHere) {
                    & mountvol.exe "${letter}:" /d *> $null
                    if ($LASTEXITCODE -ne 0) { $unmountOk = $false }
                }
            }
            if (-not $unmountOk) { throw "EFI 分区卸载失败：${letter}:，保留状态快照供重试" }

            Remove-Item -LiteralPath $script:deviceGuardBackupFile -Force -ErrorAction Stop
            $script:rebootRequired = $rebootBefore
            Write-Host '[OK] Device Guard EFI 临时状态已清理；未触碰其他 bootsequence 项。' -ForegroundColor Green
            $script:ok++
            return $true
        } catch {
            Write-Host "[FAIL] Device Guard EFI 清理失败：$($_.Exception.Message)；状态快照已保留供重试。" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }
    if ($Action -notin @('1','prepare','apply')) {
        Write-Host "[FAIL] 无效 EFI 子操作：$Action（可用 1=prepare、2=cleanup）" -ForegroundColor Red
        $script:fail++
        return $false
    }

    if (-not (Test-HighRiskConfirmation '确定执行 Device Guard EFI 清除吗？这会挂载 EFI 分区并设置一次性引导项。')) { return $false }
    try {
        $blOn = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' })
        if ($blOn.Count -gt 0) { throw '检测到 BitLocker 保护已开启，拒绝修改 EFI' }
    } catch {
        Write-Host "[FAIL] BitLocker 预检查未通过：$($_.Exception.Message)；已拒绝 EFI 修改。" -ForegroundColor Red
        $script:fail++
        return $false
    }

    $dgGuid = '{0cb3b571-2f2e-4343-a879-d86a476d7215}'
    $secSrc = Join-Path $env:SystemRoot 'System32\SecConfig.efi'
    if (-not (Test-Path -LiteralPath $secSrc -PathType Leaf)) {
        Write-Host "[FAIL] 未找到 $secSrc，无法执行。" -ForegroundColor Red
        $script:fail++
        return $false
    }
    if (Test-Path -LiteralPath $script:deviceGuardBackupFile -PathType Leaf) {
        Write-Host "[FAIL] 已存在 EFI 状态快照；请先用 -Action 9=cleanup 清理或人工核对，拒绝覆盖。" -ForegroundColor Red
        $script:fail++
        return $false
    }

    $bootState = [pscustomobject]@{ Present = $false; Value = $null }
    $sourceHash = $null
    $efiLetter = $null
    $bcdCreated = $false
    $fileCreated = $false
    $configured = $false
    try {
        $bootState = Get-DeviceGuardBootSequenceState
        if ($bootState.Present -and ([string]$bootState.Value -match [regex]::Escape($dgGuid))) {
            throw '当前 bootsequence 已包含 Device Guard 工具 GUID，拒绝覆盖已有一次性引导状态'
        }
        $existing = & bcdedit.exe /enum $dgGuid 2>$null
        if ($LASTEXITCODE -eq 0) { throw '固定 Device Guard GUID 已存在，拒绝覆盖可能属于其他工具的 BCD 项' }
        $sourceHash = Get-DeviceGuardFileHash $secSrc
        $efiLetter = @('X','Y','Z','V','W','U') | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
        if (-not $efiLetter) { throw '找不到空闲 EFI 盘符（X/Y/Z/V/W/U）' }

        $mounted = $false
        $unmountOk = $true
        try {
            & mountvol.exe "${efiLetter}:" /s *> $null
            if ($LASTEXITCODE -ne 0) { throw "mountvol exit code $LASTEXITCODE" }
            $mounted = $true
            $bootDir = "${efiLetter}:\EFI\Microsoft\Boot"
            if (-not (Test-Path -LiteralPath $bootDir -PathType Container)) { New-Item -ItemType Directory -Path $bootDir -Force -ErrorAction Stop | Out-Null }
            $target = Join-Path $bootDir 'SecConfig.efi'
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                if ((Get-DeviceGuardFileHash $target) -ine $sourceHash) { throw 'EFI 目标 SecConfig.efi 已存在但哈希不同，拒绝覆盖' }
                Write-Host '[SKIP] EFI 中已有同哈希 SecConfig.efi，不将其标记为本工具创建。' -ForegroundColor Yellow
            } else {
                Copy-Item -LiteralPath $secSrc -Destination $target -Force -ErrorAction Stop
                if ((Get-DeviceGuardFileHash $target) -ine $sourceHash) { throw '复制后的 SecConfig.efi 哈希校验失败' }
                $fileCreated = $true
                Write-Host "[OK] SecConfig.efi 已复制到 $target"
                $script:ok++
            }

            $bcdOk = Invoke-BcdEdit "/create $dgGuid /d DebugTool /application osloader" '创建 BCD 引导项 (DebugTool)'
            $bcdCreated = $bcdOk
            if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid path \EFI\Microsoft\Boot\SecConfig.efi" '引导项路径 SecConfig.efi' }
            if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid device partition=${efiLetter}:" "引导项设备分区 ${efiLetter}:" }
            if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid loadoptions DISABLE-LSA-ISO" 'LoadOptions = DISABLE-LSA-ISO' }
            if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set {bootmgr} bootsequence $dgGuid" '设为下次开机一次性引导' }
            if (-not $bcdOk) { throw 'EFI 一次性引导配置未完成' }
            $configured = $true

            $record = [pscustomobject]@{
                Version = 1
                Binding = (Get-BackupMachineId)
                CreatedAt = (Get-Date).ToString('o')
                DgGuid = $dgGuid
                BootSequencePresent = [bool]$bootState.Present
                OriginalBootSequence = $bootState.Value
                EfiPath = "${efiLetter}:\EFI\Microsoft\Boot\SecConfig.efi"
                FileCreated = [bool]$fileCreated
                FileHash = if ($fileCreated) { $sourceHash } else { $null }
                BcdEntryCreated = [bool]$bcdCreated
            }
            if (-not (Test-DeviceGuardBackupSchema $record)) { throw '生成的 EFI 状态快照未通过结构校验' }
            Write-TweakAtomicTextFile -Path $script:deviceGuardBackupFile -Content (ConvertTo-Json $record -Depth 5)
            Write-Host "[OK] EFI 状态快照已保存：$script:deviceGuardBackupFile" -ForegroundColor Green
            $script:rebootRequired = $true
        } finally {
            if ($mounted) {
                & mountvol.exe "${efiLetter}:" /d *> $null
                if ($LASTEXITCODE -ne 0) {
                    $unmountOk = $false
                    Write-Host "[FAIL] EFI 分区卸载失败：mountvol ${efiLetter}: /d" -ForegroundColor Red
                }
            }
        }
        if (-not $unmountOk) { throw "EFI 分区卸载失败，状态快照保留供清理：${efiLetter}:" }
        if (-not $configured) { throw 'EFI 配置未完成' }
        Write-Host '[OK] EFI 一次性引导已配置；请退出后重启，并在完成后执行 9 -> 2 清理临时状态。' -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] Device Guard EFI 配置失败：$($_.Exception.Message)；正在清理本次临时对象。" -ForegroundColor Red
        if ($configured -or $bcdCreated) {
            & bcdedit.exe /delete $dgGuid /f *> $null
            if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] 失败回滚 BCD 引导项 $dgGuid" -ForegroundColor Yellow }
        }
        try {
            $state = Get-DeviceGuardBootSequenceState
            if ($state.Present -and ($state.Value -match [regex]::Escape($dgGuid))) {
                if ($bootState.Present) { & bcdedit.exe /set '{bootmgr}' bootsequence $bootState.Value *> $null }
                else { & bcdedit.exe /deletevalue '{bootmgr}' bootsequence *> $null }
                if ($LASTEXITCODE -ne 0) { throw 'bcdedit bootsequence 回滚命令失败' }
            }
        } catch { Write-Host "[WARN] 失败回滚 bootsequence：$($_.Exception.Message)" -ForegroundColor Yellow }
        if ($fileCreated) {
            try {
                & mountvol.exe "${efiLetter}:" /s *> $null
                $target = "${efiLetter}:\EFI\Microsoft\Boot\SecConfig.efi"
                if ((Get-DeviceGuardFileHash $target) -ieq $sourceHash) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
                & mountvol.exe "${efiLetter}:" /d *> $null
            } catch { Write-Host "[WARN] 失败清理 EFI 文件，请检查 ${efiLetter}:\EFI\Microsoft\Boot\SecConfig.efi" -ForegroundColor Yellow }
        }
        $script:fail++
        return $false
    }
}

function Invoke-VbsModule {
    param([string]$Action = '')

    Write-Host ""
    Write-Host "============ [Part 10] 虚拟化 / VBS / Hyper-V 管理 ============" -ForegroundColor Cyan
    Write-Host ""
    $dgRegValues = $script:vbsRegistryValues
    $featureNames = @($script:vbsFeatureNames)
    Write-Host "  0. 查看当前状态"
    Write-Host "  1. 关闭 VBS/HVCI/Credential Guard + Hyper-V/VMP/HypervisorPlatform" -ForegroundColor Yellow
    Write-Host "  2. 删除脚本覆盖并尝试启用原清单中的虚拟化功能（非原始状态精确回滚）" -ForegroundColor White
    Write-Host "  3. 恢复选项 1 修改前的快照（vbs-backup.json）" -ForegroundColor White
    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定 VBS 子操作（0=status，1=disable，2=enable，3=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入 0、1、2 或 3 并回车"
    }

    if ($Action -in @('0','status')) {
        try {
            $bcEnum = (& bcdedit.exe /enum '{current}' 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw '无法读取当前 BCD' }
            foreach ($n in @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')) {
                if ($bcEnum -match ('(?m)^\s*' + [regex]::Escape($n) + '\s+(\S+)')) { Write-Host ("bcdedit {0,-24} = {1}" -f $n,$Matches[1]) }
                else { Write-Host ("bcdedit {0,-24} = <未设置（系统默认）>" -f $n) }
            }
            foreach ($v in $dgRegValues) {
                try { $item = Get-Item $v.Path -ErrorAction Stop }
                catch [System.Management.Automation.ItemNotFoundException] { $item = $null }
                if ($item -and ($item.GetValueNames() -contains $v.Name)) { Write-Host ("注册表 {0} -> {1} = {2}" -f $v.Path,$v.Name,$item.GetValue($v.Name)) }
            }
            foreach ($fn in $featureNames) {
                # $null 代表功能未安装；查询异常必须显示为失败，不能伪装成“未安装”。
                $f = Get-WindowsOptionalFeature -Online -FeatureName $fn -ErrorAction Stop
                if ($f) { Write-Host ("功能 {0,-26} = {1}" -f $fn,$f.State) }
                else { Write-Host ("功能 {0,-26} = <未安装>" -f $fn) }
            }
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if (-not $cs) { throw '无法读取 HypervisorPresent' }
            Write-Host ("运行时 HypervisorPresent = {0}" -f $cs.HypervisorPresent)
            return $true
        } catch {
            Write-Host "[FAIL] VBS 状态读取失败：$($_.Exception.Message)" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }

    if ($Action -in @('1','disable','off')) {
        if (-not (Ensure-VbsBackup)) {
            Write-Host "[FAIL] 已阻止关闭 VBS/Hyper-V：原始状态未成功备份。" -ForegroundColor Red
            return $false
        }
        $rebootBeforeOperation = $script:rebootRequired
        $operationOk = $true
        foreach ($v in $dgRegValues) {
            $before = $script:fail
            Set-RegDword $v.Path $v.Name 0 ("关闭虚拟化安全 " + $v.Name)
            if ($script:fail -gt $before) { $operationOk = $false; break }
        }
        if (-not $operationOk) {
            Write-Host '[FAIL] VBS 注册表写入未完整完成，已阻止继续修改 BCD/可选功能并尝试回滚。' -ForegroundColor Red
            $rollbackOk = Restore-VbsBackup
            if ($rollbackOk) { $script:rebootRequired = $rebootBeforeOperation }
            else { Write-Host '[FAIL] VBS 自动回滚未完全成功，请人工检查。' -ForegroundColor Red }
            return $false
        }

        foreach ($fn in $featureNames) {
            try {
                $feature = Get-WindowsOptionalFeature -Online -FeatureName $fn -ErrorAction Stop
                if ($feature -and $feature.State -in @('Enabled','EnablePending')) {
                    $null = Disable-WindowsOptionalFeature -Online -FeatureName $fn -NoRestart -ErrorAction Stop
                    Write-Host "[OK] 虚拟化功能已禁用：$fn"
                    $script:ok++
                    $script:rebootRequired = $true
                } else {
                    Write-Host "[SKIP] 虚拟化功能未启用：$fn" -ForegroundColor Yellow
                    $script:skip++
                }
            } catch {
                Write-Host "[FAIL] 虚拟化功能禁用 $fn : $($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                $operationOk = $false
                break
            }
        }
        if (-not $operationOk) {
            Write-Host '[FAIL] VBS 可选功能未完整修改，已阻止继续写入 BCD并尝试回滚。' -ForegroundColor Red
            $rollbackOk = Restore-VbsBackup
            if ($rollbackOk) { $script:rebootRequired = $rebootBeforeOperation }
            else { Write-Host '[FAIL] VBS 自动回滚未完全成功，请人工检查。' -ForegroundColor Red }
            return $false
        }

        foreach ($item in @(
                @{ Arguments = '/set hypervisorlaunchtype off'; Name = 'hypervisorlaunchtype'; Expected = 'Off' },
                @{ Arguments = '/set isolatedcontext no'; Name = 'isolatedcontext'; Expected = 'No' },
                @{ Arguments = '/set vsmlaunchtype off'; Name = 'vsmlaunchtype'; Expected = 'Off' }
            )) {
            if (-not (Invoke-BcdEdit $item.Arguments ("关闭 BCD " + $item.Name))) { $operationOk = $false; break }
        }
        if ($operationOk) {
            foreach ($item in @(
                    @{ Name = 'hypervisorlaunchtype'; Expected = 'Off' },
                    @{ Name = 'isolatedcontext'; Expected = 'No' },
                    @{ Name = 'vsmlaunchtype'; Expected = 'Off' }
                )) {
                if (-not (Verify-BcdValue $item.Name $item.Expected $item.Name)) { $operationOk = $false }
            }
            if ($operationOk) { Write-Host '[提示] 重启后再验证 HypervisorPresent / msinfo32 实际运行状态。' -ForegroundColor Yellow }
        }
        if (-not $operationOk) {
            Write-Host '[FAIL] VBS/虚拟化关闭未完整完成，正在按原始快照回滚。' -ForegroundColor Red
            $rollbackOk = Restore-VbsBackup
            if ($rollbackOk) { $script:rebootRequired = $rebootBeforeOperation; Write-Host '[OK] VBS/虚拟化已按快照回滚。' -ForegroundColor Yellow }
            else { Write-Host '[FAIL] VBS/虚拟化自动回滚未完全成功，请人工检查。' -ForegroundColor Red }
        }
    } elseif ($Action -in @('2','enable','on')) {
        # 启用路径同样需要保留首次状态；任一步失败都按快照撤销已完成的删除。
        if (-not (Ensure-VbsBackup)) {
            Write-Host '[FAIL] 已阻止启用 VBS/Hyper-V：原始状态未成功备份。' -ForegroundColor Red
            return $false
        }
        $rebootBeforeAction = $script:rebootRequired
        $operationOk = $true
        foreach ($v in $dgRegValues) {
            $item = Get-Item $v.Path -ErrorAction SilentlyContinue
            if ($item -and ($item.GetValueNames() -contains $v.Name)) {
                $regPath = Convert-RegExePath $v.Path
                & reg.exe DELETE $regPath /v $v.Name /f *> $null
                if ($LASTEXITCODE -eq 0) {
                    try {
                        $after = Get-Item $v.Path -ErrorAction Stop
                        if ($after.GetValueNames() -contains $v.Name) { throw '删除后回读仍发现该值' }
                        Write-Host ("[OK] 已删除注册表值 {0} -> {1}" -f $v.Path,$v.Name); $script:ok++; $script:rebootRequired = $true
                    } catch {
                        Write-Host ("[FAIL] 删除注册表值 {0} -> {1} 后验证失败：$($_.Exception.Message)" -f $v.Path,$v.Name) -ForegroundColor Red; $script:fail++; $operationOk = $false; break
                    }
                } else { Write-Host ("[FAIL] 删除注册表值 {0} -> {1}" -f $v.Path,$v.Name) -ForegroundColor Red; $script:fail++; $operationOk = $false; break }
            } else { Write-Host ("[SKIP] 注册表值不存在：{0} -> {1}" -f $v.Path,$v.Name) -ForegroundColor Yellow; $script:skip++ }
        }
        if ($operationOk) {
            foreach ($n in @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')) {
                $before = $script:fail
                Remove-BcdValue $n ("删除 bcdedit $n")
                if ($script:fail -gt $before) { $operationOk = $false; break }
            }
        }
        if ($operationOk) {
            $vbsSnapshot = Get-Content $script:vbsBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($fn in $featureNames) {
                $record = @($vbsSnapshot.Features | Where-Object { [string]$_.Name -eq $fn })
                if ($record.Count -ne 1) {
                    Write-Host "[FAIL] 快照缺少唯一的虚拟化功能记录：$fn" -ForegroundColor Red
                    $script:fail++
                    $operationOk = $false
                    break
                }
                if (-not [bool]$record[0].Present) {
                    Write-Host "[SKIP] 原始状态为未安装，不主动安装虚拟化功能：$fn" -ForegroundColor Yellow
                    $script:skip++
                    continue
                }
                try {
                    $null = Enable-WindowsOptionalFeature -Online -FeatureName $fn -All -NoRestart -ErrorAction Stop
                    Write-Host "[OK] 已尝试启用虚拟化功能组件：$fn（重启后生效）"
                    $script:ok++
                    $script:rebootRequired = $true
                } catch {
                    Write-Host "[FAIL] 虚拟化功能组件启用 $fn : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                    $operationOk = $false
                    break
                }
            }
        }
        if (-not $operationOk) {
            Write-Host '[FAIL] VBS/Hyper-V 启用未完整完成，正在按原始快照回滚。' -ForegroundColor Red
            $rollbackOk = Restore-VbsBackup
            if ($rollbackOk) { $script:rebootRequired = $rebootBeforeAction; Write-Host '[OK] VBS/Hyper-V 已按快照回滚。' -ForegroundColor Yellow }
            else { Write-Host '[FAIL] VBS/Hyper-V 自动回滚未完全成功，请人工检查。' -ForegroundColor Red }
            return $false
        }
    } elseif ($Action -in @('3','restore','reset')) {
        Restore-VbsBackup | Out-Null
    } else {
        Write-Host "[FAIL] 无效 VBS 子操作：$Action（可用 0、1、2、3）" -ForegroundColor Red
        $script:fail++
        return $false
    }

    Write-Host "Finished (Part 10 - Virtualization Management)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok  FAIL : $script:fail  SKIP : $script:skip"
    Request-Restart
    return ($script:fail -eq 0)
}
