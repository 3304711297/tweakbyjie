function Test-NvmeBackupSchema {
    param([object]$Backup)
    if ($null -eq $Backup -or $Backup.Version -ne 3) { return $false }
    $safe = @($Backup.SafeBoot)
    if ($safe.Count -ne 2 -or @($safe.Mode | Sort-Object -Unique).Count -ne 2) { return $false }
    foreach ($r in $safe) {
        if ([string]$r.Mode -notin @('Minimal','Network') -or $null -eq $r.Present) { return $false }
        if ([bool]$r.Present -and ([string]::IsNullOrWhiteSpace([string]$r.Kind) -or $null -eq $r.Data)) { return $false }
        if (-not [bool]$r.Present -and ($null -ne $r.Kind -or $null -ne $r.Data)) { return $false }
    }
    $features = @($Backup.Features)
    if ($features.Count -ne 2) { return $false }
    foreach ($f in $features) {
        if ([string]$f.Id -notin @('60786016','48433719') -or [string]$f.BeforeState -notin @('Enabled','Disabled','Default','Unknown')) { return $false }
    }
    $legacy = @($Backup.LegacyOverrides)
    if ($legacy.Count -ne 3) { return $false }
    foreach ($r in $legacy) {
        if ([string]$r.Name -notin @('735209102','1853569164','156965516') -or $null -eq $r.Present) { return $false }
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
        $item = Get-Item $path -ErrorAction SilentlyContinue
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
        $item = Get-Item $Path -ErrorAction SilentlyContinue
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
        if ($text -match 'State:\s*Enabled\s*\(2\)') { return 'Enabled' }
        if ($text -match 'State:\s*Disabled\s*\(1\)') { return 'Disabled' }
        if ($text -match 'No configuration|ImageDefault') { return 'Default' }
        return 'Unknown'
    } catch { return 'Unknown' }
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
            if (-not (Test-NvmeBackupSchema $backup)) { throw 'nvme-backup.json 结构不正确、版本过旧或记录不完整' }
            return $true
        }
        $features = @('60786016','48433719') | ForEach-Object { [pscustomobject]@{ Id = $_; BeforeState = Get-ViVeFeatureState $ViVeTool $_ } }
        $backup = [pscustomobject]@{
            Version = 3
            CreatedAt = (Get-Date).ToString('o')
            Features = @($features)
            SafeBoot = @(Get-NvmeSafeBootSnapshot $Guid)
            LegacyOverrides = @(Get-NvmeLegacyOverrideSnapshot $LegacyPath)
        }
        if (-not (Test-NvmeBackupSchema $backup)) { throw '生成的 NVMe 备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 6 | Set-Content -Path $script:nvmeBackupFile -Encoding UTF8 -ErrorAction Stop
        $check = Get-Content $script:nvmeBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-NvmeBackupSchema $check)) { throw '写入后的 NVMe 备份校验失败' }
        Write-Host "[OK] Native NVMe 原始状态已备份：$script:nvmeBackupFile" -ForegroundColor Green
        return $true
    } catch { Write-Host "[FAIL] Native NVMe 原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red; $script:fail++; return $false }
}

function Restore-NvmeSafeBootBackup {
    param([string]$Guid, [string]$ViVeTool, [string]$LegacyPath)
    if (-not (Test-Path $script:nvmeBackupFile)) { Write-Host '[FAIL] 未找到 nvme-backup.json，无法精确恢复 Native NVMe' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:nvmeBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-NvmeBackupSchema $backup)) { throw 'nvme-backup.json 结构不正确' }
        $allOk = $true
        if ($ViVeTool) {
            foreach ($f in @($backup.Features)) {
                switch ([string]$f.BeforeState) {
                    'Enabled' { & $ViVeTool /enable /id:$($f.Id) 2>&1 | Out-Null }
                    'Disabled' { & $ViVeTool /disable /id:$($f.Id) 2>&1 | Out-Null }
                    'Default' { & $ViVeTool /reset /id:$($f.Id) 2>&1 | Out-Null }
                    default { continue }
                }
                if ($LASTEXITCODE -ne 0) { $allOk = $false; $script:fail++ }
            }
        } else { Write-Host '[WARN] 未找到 ViVeTool，无法精确恢复 Feature 状态。' -ForegroundColor Yellow; $allOk = $false }
        foreach ($r in @($backup.SafeBoot)) {
            $regPath = Convert-RegExePath $r.Path
            if ([bool]$r.Present) { & reg.exe ADD $regPath /ve /t REG_SZ /d ([string]$r.Data) /f *> $null; if ($LASTEXITCODE -ne 0) { $allOk = $false; $script:fail++ } else { $script:ok++; $script:rebootRequired = $true } }
            else { & reg.exe DELETE $regPath /ve /f *> $null; if ($LASTEXITCODE -eq 0) { $script:ok++; $script:rebootRequired = $true } else { $script:skip++ } }
        }
        foreach ($r in @($backup.LegacyOverrides)) {
            $regPath = Convert-RegExePath $LegacyPath
            if ([bool]$r.Present) { & reg.exe ADD $regPath /v $r.Name /t REG_DWORD /d ([uint32]$r.Data) /f *> $null; if ($LASTEXITCODE -ne 0) { $allOk = $false; $script:fail++ } else { $script:ok++; $script:rebootRequired = $true } }
            else { & reg.exe DELETE $regPath /v $r.Name /f *> $null; if ($LASTEXITCODE -eq 0) { $script:ok++; $script:rebootRequired = $true } else { $script:skip++ } }
        }
        if ($allOk) { Write-Host '[OK] Native NVMe 已按修改前快照恢复。' -ForegroundColor Green } else { Write-Host '[WARN] Native NVMe 恢复未完全确认，请执行 8 -> 0 检查。' -ForegroundColor Yellow }
        return $allOk
    } catch { Write-Host "[FAIL] NVMe 恢复失败：$($_.Exception.Message)" -ForegroundColor Red; $script:fail++; return $false }
}
