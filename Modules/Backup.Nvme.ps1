function Test-NvmeSafeBootPath {
    param([object]$Record, [string]$Guid)
    $expected = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$($Record.Mode)\$Guid"
    return ([string]$Record.Path -eq $expected)
}

function Test-NvmeSafeBootValue {
    param([string]$Path, [string]$Expected)
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return (($item.GetValueNames() -contains '') -and [string]$item.GetValue('') -ceq [string]$Expected)
    } catch { return $false }
}

function Test-NvmeLegacyValue {
    param([string]$Path, [string]$Name, [uint32]$Expected)
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return (($item.GetValueNames() -contains $Name) -and [uint32]$item.GetValue($Name) -eq $Expected)
    } catch { return $false }
}

function Test-NvmeBackupSchema {
    param([object]$Backup, [string]$Guid = '{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}')
    if ($null -eq $Backup -or $Backup.Version -ne 3) { return $false }
    if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
    $safe = @($Backup.SafeBoot)
    if ($safe.Count -ne 2 -or @($safe.Mode | Sort-Object -Unique).Count -ne 2) { return $false }
    foreach ($r in $safe) {
        if ([string]$r.Mode -notin @('Minimal','Network') -or $null -eq $r.Present -or $r.Present -isnot [bool]) { return $false }
        if (-not (Test-NvmeSafeBootPath $r $Guid)) { return $false }
        if ([bool]$r.Present -and ([string]$r.Kind -ne 'String' -or $null -eq $r.Data)) { return $false }
        if (-not [bool]$r.Present -and ($null -ne $r.Kind -or $null -ne $r.Data)) { return $false }
    }
    $features = @($Backup.Features)
    if ($features.Count -ne 2 -or @($features.Id | Sort-Object -Unique).Count -ne 2) { return $false }
    foreach ($f in $features) {
        if ([string]$f.Id -notin @('60786016','48433719') -or [string]$f.BeforeState -notin @('Enabled','Disabled','Default','Unknown')) { return $false }
    }
    $legacy = @($Backup.LegacyOverrides)
    if ($legacy.Count -ne 3 -or @($legacy.Name | Sort-Object -Unique).Count -ne 3) { return $false }
    foreach ($r in $legacy) {
        if ([string]$r.Name -notin @('735209102','1853569164','156965516') -or $null -eq $r.Present -or $r.Present -isnot [bool]) { return $false }
        if ([bool]$r.Present) {
            if ([string]$r.Kind -ne 'DWord' -or $null -eq $r.Data) { return $false }
            try { if ([uint64]$r.Data -gt 0xFFFFFFFF) { return $false } } catch { return $false }
        } elseif ($null -ne $r.Kind -or $null -ne $r.Data) { return $false }
    }
    return $true
}

function Get-NvmeSafeBootSnapshot {
    param([string]$Guid)
    foreach ($mode in @('Minimal','Network')) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$Guid"
        try { $item = Get-Item $path -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { $item = $null }
        if ($item -and ($item.GetValueNames() -contains '')) {
            $kind = $item.GetValueKind('').ToString()
            $value = $item.GetValue('')
            [pscustomobject]@{ Mode = $mode; Path = $path; Present = $true; Kind = $kind; Data = [string]$value }
        } else {
            [pscustomobject]@{ Mode = $mode; Path = $path; Present = $false; Kind = $null; Data = $null }
        }
    }
}

function Get-NvmeLegacyOverrideSnapshot {
    param([string]$Path)
    foreach ($name in @('735209102','1853569164','156965516')) {
        try { $item = Get-Item $Path -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { $item = $null }
        if ($item -and ($item.GetValueNames() -contains $name)) {
            $kind = $item.GetValueKind($name).ToString()
            [pscustomobject]@{ Name = $name; Present = $true; Kind = $kind; Data = [uint32]$item.GetValue($name) }
        } else { [pscustomobject]@{ Name = $name; Present = $false; Kind = $null; Data = $null } }
    }
}

function Get-ViVeFeatureState {
    param([string]$ViVeTool, [string]$Id)
    try {
        $text = (& $ViVeTool /query /id:$Id 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { return 'Unknown' }
        # ViVeTool 的真实输出通常为 "State           : Enabled (2)"；冒号两侧的空白
        # 和状态码都必须容忍，不能只匹配测试桩中的 "State: Enabled"。
        if ($text -match '(?im)^\s*State\s*:\s*Enabled(?:\s*\(\s*2\s*\))?') { return 'Enabled' }
        if ($text -match '(?im)^\s*State\s*:\s*Disabled(?:\s*\(\s*1\s*\))?') { return 'Disabled' }
        if ($text -match '(?im)No configuration|ImageDefault') { return 'Default' }
        return 'Unknown'
    } catch { return 'Unknown' }
}

function Invoke-ViVeToolCommand {
    param([string]$ViVeTool, [string]$Verb, [string]$Id)
    $arguments = @($Verb, "/id:$Id")
    $extension = [System.IO.Path]::GetExtension($ViVeTool)
    if ($extension -in @('.cmd', '.bat')) {
        # Execute wrapper scripts through cmd /c call so their exit code is propagated.
        $quotedTool = '"' + $ViVeTool.Replace('"', '""') + '"'
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList (@('/d', '/c', 'call', $quotedTool) + $arguments) -Wait -PassThru -WindowStyle Hidden
    } else {
        $process = Start-Process -FilePath $ViVeTool -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    }
    return [int]$process.ExitCode
}

function Find-ViVeTool {
    $local = Join-Path $script:RepoRoot 'ViVeTool.exe'
    if (Test-Path $local) { return $local }
    $cmd = Get-Command 'ViVeTool.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command 'vivetool.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Test-NativeNvmeConfigured {
    param([string]$ViVeTool)
    $s1 = Get-ViVeFeatureState $ViVeTool '60786016'
    $s2 = Get-ViVeFeatureState $ViVeTool '48433719'
    $both = ($s1 -eq 'Enabled' -and $s2 -eq 'Enabled')
    [pscustomobject]@{ Feature60786016 = $s1; Feature48433719 = $s2; BothEnabled = $both }
}

function Test-NativeNvmeEffective {
    $file = Join-Path $env:SystemRoot 'System32\drivers\nvmedisk.sys'
    $exists = Test-Path $file
    $state = 'NotFound'
    try {
        $svc = Get-Service -Name 'nvmedisk' -ErrorAction SilentlyContinue
        if ($svc) {
            $state = $svc.Status.ToString()
        } else {
            $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='nvmedisk'" -ErrorAction SilentlyContinue
            if ($drv) { $state = $drv.State }
            elseif ($exists) { $state = 'Stopped' }
            else { $state = 'NotFound' }
        }
    } catch {
        $state = if ($exists) { 'Unknown' } else { 'NotFound' }
    }
    [pscustomobject]@{ FileExists = $exists; State = $state; FilePath = $file }
}

function Ensure-NvmeBackup {
    param([string]$Guid, [string]$ViVeTool, [string]$LegacyPath)
    try {
        if (Test-Path $script:nvmeBackupFile) {
            $backup = Get-Content $script:nvmeBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-NvmeBackupSchema $backup $Guid)) { throw 'nvme-backup.json 结构不正确、版本过旧或记录不完整' }
            if (@($backup.Features | Where-Object { [string]$_.BeforeState -eq 'Unknown' }).Count -gt 0) {
                throw '已有 NVMe 快照包含未知 Feature 初始状态，拒绝继续修改'
            }
            return $true
        }
        $features = @('60786016','48433719') | ForEach-Object { [pscustomobject]@{ Id = $_; BeforeState = Get-ViVeFeatureState $ViVeTool $_ } }
        if (@($features | Where-Object { $_.BeforeState -eq 'Unknown' }).Count -gt 0) { throw '无法确认 Native NVMe Feature 初始状态，拒绝创建可用于修改的快照' }
        $backup = [pscustomobject]@{
            Version = 3
            Binding = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Features = @($features)
            SafeBoot = @(Get-NvmeSafeBootSnapshot $Guid)
            LegacyOverrides = @(Get-NvmeLegacyOverrideSnapshot $LegacyPath)
        }
        if (-not (Test-NvmeBackupSchema $backup $Guid)) { throw '生成的 NVMe 备份未通过结构校验' }
        $json = ConvertTo-Json -InputObject $backup -Depth 6
        Write-TweakAtomicTextFile -Path $script:nvmeBackupFile -Content $json
        $check = Get-Content $script:nvmeBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-NvmeBackupSchema $check $Guid)) { throw '写入后的 NVMe 备份校验失败' }
        Write-Host "[OK] Native NVMe 原始状态已备份：$script:nvmeBackupFile" -ForegroundColor Green
        return $true
    } catch { Write-Host "[FAIL] Native NVMe 原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red; $script:fail++; return $false }
}

function Restore-NvmeSafeBootBackup {
    param([string]$Guid, [string]$ViVeTool, [string]$LegacyPath)
    if (-not (Test-Path $script:nvmeBackupFile)) { Write-Host '[FAIL] 未找到 nvme-backup.json，无法精确恢复 Native NVMe' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:nvmeBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-NvmeBackupSchema $backup $Guid)) { throw 'nvme-backup.json 结构不正确' }
        $allOk = $true
        $featureFailures = @()
        $safeBootFailures = @()
        $legacyFailures = @()
        if ($ViVeTool) {
            foreach ($f in @($backup.Features)) {
                $viVeExitCode = $null
                switch ([string]$f.BeforeState) {
                    'Enabled' { $viVeExitCode = Invoke-ViVeToolCommand $ViVeTool '/enable' ([string]$f.Id) }
                    'Disabled' { $viVeExitCode = Invoke-ViVeToolCommand $ViVeTool '/disable' ([string]$f.Id) }
                    'Default' { $viVeExitCode = Invoke-ViVeToolCommand $ViVeTool '/reset' ([string]$f.Id) }
                    default { $featureFailures += [string]$f.Id; $allOk = $false; $script:fail++; continue }
                }
                if ($viVeExitCode -ne 0) { $featureFailures += ("{0}:exit{1}" -f $f.Id, $viVeExitCode); $allOk = $false; $script:fail++ }
            }
        } else { Write-Host '[WARN] 未找到 ViVeTool，无法精确恢复 Feature 状态。' -ForegroundColor Yellow; $allOk = $false }
        foreach ($r in @($backup.SafeBoot)) {
            if (-not (Test-NvmeSafeBootPath $r $Guid)) { throw "SafeBoot 路径与受管理 GUID 不一致：$($r.Path)" }
            $psPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$($r.Mode)\$Guid"
            $regPath = Convert-RegExePath $psPath
            if ([bool]$r.Present) {
                $regType = if ([string]$r.Kind -eq 'String') { 'REG_SZ' } else { throw "不支持的 SafeBoot 类型：$($r.Kind)" }
                & reg.exe ADD $regPath /ve /t $regType /d ([string]$r.Data) /f *> $null
                if ($LASTEXITCODE -ne 0) {
                    $allOk = $false; $script:fail++
                } elseif (-not (Test-NvmeSafeBootValue $psPath ([string]$r.Data))) {
                    Write-Host "[FAIL] SafeBoot $($r.Mode) 写入后回读不一致" -ForegroundColor Red
                    $allOk = $false; $script:fail++
                } else {
                    $script:ok++; $script:rebootRequired = $true
                }
            }
            else {
                # A genuinely absent SafeBoot key is an expected no-op; other provider errors fail closed.
                if (-not (Test-Path -LiteralPath $psPath -PathType Container -ErrorAction Stop)) {
                    $script:skip++
                    continue
                }
                try {
                    $item = Get-Item -LiteralPath $psPath -ErrorAction Stop
                    if ($item.GetValueNames() -contains '') {
                        & reg.exe DELETE $regPath /ve /f 2>$null *> $null
                        if ($LASTEXITCODE -ne 0) { $allOk = $false; $script:fail++ }
                        else {
                            $after = Get-Item -LiteralPath $psPath -ErrorAction Stop
                            if ($after.GetValueNames() -contains '') { throw 'SafeBoot 默认值删除后仍存在' }
                            $script:ok++; $script:rebootRequired = $true
                        }
                    } else { $script:skip++ }
                } catch { $safeBootFailures += [string]$r.Mode; $allOk = $false; $script:fail++ }
            }
        }
        foreach ($r in @($backup.LegacyOverrides)) {
            $regPath = Convert-RegExePath $LegacyPath
            if ([bool]$r.Present) {
                & reg.exe ADD $regPath /v $r.Name /t REG_DWORD /d ([uint32]$r.Data) /f *> $null
                if ($LASTEXITCODE -ne 0) {
                    $allOk = $false; $script:fail++
                } elseif (-not (Test-NvmeLegacyValue $LegacyPath $r.Name ([uint32]$r.Data))) {
                    Write-Host "[FAIL] Legacy 值 $($r.Name) 写入后回读不一致" -ForegroundColor Red
                    $allOk = $false; $script:fail++
                } else {
                    $script:ok++; $script:rebootRequired = $true
                }
            }
            else {
                # An absent legacy override is an expected no-op; other provider errors fail closed.
                if (-not (Test-Path -LiteralPath $LegacyPath -PathType Container -ErrorAction Stop)) {
                    $script:skip++
                    continue
                }
                try {
                    $item = Get-Item -LiteralPath $LegacyPath -ErrorAction Stop
                    if ($item.GetValueNames() -contains $r.Name) {
                        & reg.exe DELETE $regPath /v $r.Name /f 2>$null *> $null
                        if ($LASTEXITCODE -ne 0) { $allOk = $false; $script:fail++ }
                        else {
                            $after = Get-Item -LiteralPath $LegacyPath -ErrorAction Stop
                            if ($after.GetValueNames() -contains $r.Name) { throw "Legacy 值 $($r.Name) 删除后仍存在" }
                            $script:ok++; $script:rebootRequired = $true
                        }
                    } else { $script:skip++ }
                } catch { $legacyFailures += [string]$r.Name; $allOk = $false; $script:fail++ }
            }
        }
        if ($allOk) { Write-Host '[OK] Native NVMe 已按修改前快照恢复。' -ForegroundColor Green } else {
            $viveLogText = if ($env:TWEAK_VIVE_LOG -and (Test-Path -LiteralPath $env:TWEAK_VIVE_LOG)) { (Get-Content -LiteralPath $env:TWEAK_VIVE_LOG -Raw) -replace '[\r\n]+', '/' } else { '<none>' }
            Write-Host ("::error title=NVMe restore diagnostic::features={0};safeboot={1};legacy={2};calls={3}" -f ($featureFailures -join ','), ($safeBootFailures -join ','), ($legacyFailures -join ','), $viveLogText)
            Write-Host '[WARN] Native NVMe 恢复未完全确认，请执行 8 -> 0 检查。' -ForegroundColor Yellow
        }
        return $allOk
    } catch {
        Write-Host ("::error title=NVMe restore exception::" + $_.Exception.Message)
        Write-Host "[FAIL] NVMe 恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
