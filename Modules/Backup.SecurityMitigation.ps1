function Get-SecurityMitigationSnapshot {
    param([hashtable]$Definition)
    $item = Get-Item $Definition.Path -ErrorAction SilentlyContinue
    $present = $item -and ($item.GetValueNames() -contains $Definition.Name)
    if (-not $present) { return [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Present = $false; Value = $null } }
    if ($item.GetValueKind($Definition.Name).ToString() -ne 'DWord') { throw "$($Definition.Name) 不是 DWORD" }
    [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Present = $true; Value = [uint32]$item.GetValue($Definition.Name) }
}

function Test-SecurityMitigationBackupSchema {
    param([object]$Backup)
    if ($null -eq $Backup -or $Backup.Version -ne 1) { return $false }
    $records = @($Backup.Values)
    $expected = @($script:securityMitigationValues | ForEach-Object { "$($_.Path)|$($_.Name)" })
    $actual = @($records | ForEach-Object { "$($_.Path)|$($_.Name)" })
    if ($records.Count -ne $expected.Count -or @($actual | Sort-Object -Unique).Count -ne $expected.Count) { return $false }
    if (@($actual | Where-Object { $expected -notcontains $_ }).Count -gt 0) { return $false }
    foreach ($r in $records) {
        if ($null -eq $r.Present -or $r.Present -isnot [bool]) { return $false }
        if ([bool]$r.Present) { try { if ([uint64]$r.Value -gt 0xFFFFFFFF) { return $false } } catch { return $false } }
        elseif ($null -ne $r.Value) { return $false }
    }
    return $true
}

function Ensure-SecurityMitigationBackup {
    try {
        if (Test-Path $script:securityMitigationBackupFile) {
            $backup = Get-Content $script:securityMitigationBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-SecurityMitigationBackupSchema $backup)) { throw 'security-mitigation-backup.json 结构不正确' }
            return $true
        }
        $backup = [pscustomobject]@{ Version = 1; CreatedAt = (Get-Date).ToString('o'); Values = @($script:securityMitigationValues | ForEach-Object { Get-SecurityMitigationSnapshot $_ }) }
        if (-not (Test-SecurityMitigationBackupSchema $backup)) { throw '生成的安全缓解备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $script:securityMitigationBackupFile -Encoding UTF8 -ErrorAction Stop
        $check = Get-Content $script:securityMitigationBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-SecurityMitigationBackupSchema $check)) { throw '写入后的安全缓解备份校验失败' }
        Write-Host "[OK] CPU 安全缓解原始状态已备份：$script:securityMitigationBackupFile" -ForegroundColor Green
        return $true
    } catch { Write-Host "[FAIL] CPU 安全缓解备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red; $script:fail++; return $false }
}

function Restore-SecurityMitigationBackup {
    if (-not (Test-Path $script:securityMitigationBackupFile)) { Write-Host '[FAIL] 未找到 security-mitigation-backup.json，拒绝声称已恢复。' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:securityMitigationBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-SecurityMitigationBackupSchema $backup)) { throw 'security-mitigation-backup.json 结构不正确' }
        $allOk = $true
        foreach ($r in @($backup.Values)) {
            $before = $script:fail
            if ([bool]$r.Present) { Set-RegDword $r.Path $r.Name ([uint32]$r.Value) ("恢复 " + $r.Name) }
            else { Remove-RegDwordValue $r.Path $r.Name ("删除 " + $r.Name + "（恢复原始未设置状态）") }
            if ($script:fail -gt $before) { $allOk = $false }
        }
        if ($allOk) { Write-Host '[OK] CPU 安全缓解已按修改前快照恢复。' -ForegroundColor Green }
        return $allOk
    } catch { Write-Host "[FAIL] CPU 安全缓解恢复失败：$($_.Exception.Message)" -ForegroundColor Red; $script:fail++; return $false }
}
