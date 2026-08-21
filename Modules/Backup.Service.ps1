# Backup.Service.ps1 - Part 6 服务快照与恢复
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Convert-ServiceStartMode {
    # 把快照里的 Win32 StartMode 映射为 Set-Service / sc.exe 的目标值；未知类型返回 $null（拒绝猜测）
    param([string]$StartMode)
    switch ($StartMode) {
        'Auto'     { [pscustomobject]@{ SetService = 'Automatic'; Sc = 'auto' } }
        'Manual'   { [pscustomobject]@{ SetService = 'Manual';    Sc = 'demand' } }
        'Disabled' { [pscustomobject]@{ SetService = 'Disabled';  Sc = 'disabled' } }
        'System'   { [pscustomobject]@{ SetService = 'System';    Sc = 'system' } }
        'Boot'     { [pscustomobject]@{ SetService = 'Boot';      Sc = 'boot' } }
        default    { $null }
    }
}

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
            if ($svc) { [pscustomobject]@{ Name = $name; StartMode = $svc.StartMode; State = $svc.State; DelayedAutostart = $svc.DelayedAutostart } }
            else { [pscustomobject]@{ Name = $name; StartMode = $null; State = $null; DelayedAutostart = $null } }
        }
        $backup = [pscustomobject]@{ Version = 1; Services = @($records) }
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $script:serviceBackupFile -Encoding UTF8 -ErrorAction Stop
        $check = Get-Content $script:serviceBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($check.Version -ne 1 -or @($check.Services).Count -ne @($records).Count) { throw '写入后的服务备份校验失败' }
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
            $mapped = Convert-ServiceStartMode ([string]$r.StartMode)
            if ($null -eq $mapped) {
                Write-Host "[WARN] $($r.Name) 快照启动类型 '$($r.StartMode)' 无法识别，已跳过以避免错误禁用" -ForegroundColor Yellow
                $script:skip++
                continue
            }
            $isDelayed = ([string]$r.StartMode -eq 'Auto' -and $r.DelayedAutostart -eq $true)
            try {
                if ($isDelayed) {
                    # Set-Service 不支持延迟启动，直接用 sc.exe 还原 delayed-auto
                    & sc.exe config $r.Name start= delayed-auto *> $null
                    if ($LASTEXITCODE -ne 0) { throw "sc.exe exit code $LASTEXITCODE" }
                } else {
                    Set-Service -Name $r.Name -StartupType $mapped.SetService -ErrorAction Stop
                }
                Write-Host "[OK] 已恢复 $($r.Name) StartupType = $(if ($isDelayed) { 'Automatic (Delayed)' } else { $mapped.SetService })"
                $script:ok++
                $script:rebootRequired = $true
            } catch {
                $scStart = if ($isDelayed) { 'delayed-auto' } else { $mapped.Sc }
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
