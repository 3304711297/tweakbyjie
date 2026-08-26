function Test-BcdValueAllowed {
    param([string]$Name, [string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9._-]+$') { return $false }
    $allowed = @{
        useplatformclock  = @('Yes','No')
        useplatformtick   = @('Yes','No')
        disabledynamictick = @('Yes','No')
        tscsyncpolicy      = @('Default','Legacy','Enhanced')
        nx                 = @('OptIn','OptOut','AlwaysOn','AlwaysOff')
        tpmbootentropy     = @('Default','ForceDisable','ForceEnable')
        nointegritychecks  = @('Yes','No')
        testsigning        = @('Yes','No')
        debug              = @('Yes','No')
    }
    return $allowed.ContainsKey($Name) -and $allowed[$Name] -contains $Value
}

function Test-BcdBackupSchema {
    param([object]$Backup, [string[]]$ValueNames)
    if ($null -eq $Backup -or $Backup.Version -ne 1 -or $Backup.Object -ne '{current}') { return $false }
    $records = @($Backup.Values)
    if ($records.Count -ne $ValueNames.Count) { return $false }
    $expected = @($ValueNames | Sort-Object -Unique)
    $actual = @($records | ForEach-Object { [string]$_.Name })
    if ($actual.Count -ne $expected.Count -or (@($actual | Sort-Object -Unique).Count -ne $expected.Count)) { return $false }
    foreach ($name in $expected) {
        $record = @($records | Where-Object { $_.Name -eq $name })
        if ($record.Count -ne 1 -or $null -eq $record[0].Present) { return $false }
        if ([bool]$record[0].Present) {
            if ([string]::IsNullOrWhiteSpace([string]$record[0].Value)) { return $false }
            if (-not (Test-BcdValueAllowed $name ([string]$record[0].Value))) { return $false }
        } elseif ($null -ne $record[0].Value) {
            return $false
        }
    }
    return $true
}

function Ensure-BcdBackup {
    param([string[]]$ValueNames, [string]$BackupFile = $script:bcdBackupFile)
    try {
        $managedNames = @($ValueNames)
        if ($managedNames.Count -eq 0) { throw '未提供 BCD 备份范围' }
        if (Test-Path $BackupFile) {
            $backup = Get-Content $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-BcdBackupSchema $backup $managedNames)) { throw 'BCD 备份结构、对象或记录不完整' }
            return $true
        }
        $enumOut = (& bcdedit.exe /enum '{current}' 2>$null) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw '无法读取当前 BCD' }
        $values = foreach ($name in $managedNames) {
            $pattern = '(?m)^\s*' + [regex]::Escape($name) + '\s+([^\r\n]+)'
            if ($enumOut -match $pattern) {
                [pscustomobject]@{ Name = $name; Present = $true; Value = $Matches[1].Trim() }
            } else {
                [pscustomobject]@{ Name = $name; Present = $false; Value = $null }
            }
        }
        $backup = [pscustomobject]@{ Version = 1; Object = '{current}'; CreatedAt = (Get-Date).ToString('o'); Values = @($values) }
        if (-not (Test-BcdBackupSchema $backup $managedNames)) { throw '生成的 BCD 备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8 -ErrorAction Stop
        $check = Get-Content $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-BcdBackupSchema $check $managedNames)) { throw '写入后的 BCD 备份校验失败' }
        Write-Host "[OK] BCD 原始状态已备份：$BackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] BCD 原始状态备份失败：$($_.Exception.Message)；已阻止本次 BCD 修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-BcdBackup {
    param([string[]]$ValueNames, [string]$BackupFile = $script:bcdBackupFile, [string[]]$SchemaNames = $script:bcdManagedValues)
    if (-not (Test-Path $BackupFile)) {
        Write-Host '[FAIL] 未找到有效 BCD 备份，拒绝声称已恢复；请手动检查当前 BCD' -ForegroundColor Red
        $script:fail++
        return $false
    }
    try {
        $backup = Get-Content $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-BcdBackupSchema $backup $SchemaNames)) { throw 'BCD 备份结构、对象或记录不完整' }
        $allOk = $true
        foreach ($name in $ValueNames) {
            $record = @($backup.Values | Where-Object { $_.Name -eq $name })[0]
            if ([bool]$record.Present) {
                if (-not (Invoke-BcdEdit "/set $name $($record.Value)" "恢复 $name = $($record.Value)")) { $allOk = $false }
            } else {
                $before = $script:fail
                Remove-BcdValue $name "删除 $name（恢复原始未设置状态）"
                if ($script:fail -gt $before) { $allOk = $false }
            }
        }
        if ($allOk) { Write-Host "[OK] BCD 已按修改前快照恢复；备份文件保留：$BackupFile" -ForegroundColor Green }
        return $allOk
    } catch {
        Write-Host "[FAIL] BCD 状态恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
