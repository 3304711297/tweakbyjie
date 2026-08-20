function Ensure-ServiceBackup {
    param([string[]]$ServiceNames)
    try {
        if (Test-Path $script:serviceBackupFile) {
            $backup = Get-Content $script:serviceBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $records = @($backup.Services)
            $expected = @($ServiceNames | Sort-Object -Unique)
            $actual = @($records | ForEach-Object { [string]$_.Name })
            if ($backup.Version -ne 1 -or $records.Count -ne $expected.Count -or (@($actual | Sort-Object -Unique).Count -ne $expected.Count) -or ($actual | Where-Object { $expected -notcontains $_ }).Count -gt 0) { throw 'service-backup.json 结构或服务集合不正确' }
            foreach ($r in $records) {
                if ($null -eq $r.StartMode -and $null -ne $r.State) { throw 'service-backup.json 缺少启动类型' }
            }
            return $true
        }
        $records = foreach ($name in $ServiceNames) {
            $svc = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name.Replace("'", "''")) -ErrorAction Stop
            if ($svc) { [pscustomobject]@{ Name = $name; StartMode = $svc.StartMode; State = $svc.State } }
            else { [pscustomobject]@{ Name = $name; StartMode = $null; State = $null } }
        }
        $backup = [pscustomobject]@{ Version = 1; Services = @($records) }
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $script:serviceBackupFile -Encoding UTF8 -ErrorAction Stop
        Write-Host "[OK] 服务原始状态已备份：$script:serviceBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] 服务原始状态备份失败：$($_.Exception.Message)；已阻止服务修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-ServiceBackup {
    if (-not (Test-Path $script:serviceBackupFile)) {
        Write-Host '[FAIL] 未找到 service-backup.json，无法精确恢复服务状态' -ForegroundColor Red
        $script:fail++
        return $false
    }
    try {
        $backup = Get-Content $script:serviceBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $records = @($backup.Services)
        if ($backup.Version -ne 1 -or $records.Count -eq 0) { throw 'service-backup.json 结构不正确' }
        $allOk = $true
        foreach ($r in $records) {
            if ([string]::IsNullOrWhiteSpace([string]$r.StartMode)) {
                Write-Host "[SKIP] $($r.Name) 原本不存在，跳过恢复" -ForegroundColor Yellow
                $script:skip++
                continue
            }
            try {
                $startupType = if ($r.StartMode -eq 'Auto') { 'Automatic' } else { [string]$r.StartMode }
                Set-Service -Name $r.Name -StartupType $startupType -ErrorAction Stop
                Write-Host "[OK] 已恢复 $($r.Name) StartupType = $startupType"
                $script:ok++
                $script:rebootRequired = $true
            } catch {
                $scStart = if ($r.StartMode -eq 'Auto') { 'auto' } elseif ($r.StartMode -eq 'Manual') { 'demand' } else { 'disabled' }
                & sc.exe config $r.Name start= $scStart *> $null
                if ($LASTEXITCODE -eq 0) { $script:ok++ } else { $script:fail++; $allOk = $false }
            }
        }
        if ($allOk) { Write-Host "[OK] 服务启动类型已按快照恢复；运行状态不强制恢复" -ForegroundColor Green }
        return $allOk
    } catch {
        Write-Host "[FAIL] 服务状态恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
