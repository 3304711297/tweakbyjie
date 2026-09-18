function Get-MpoValueSnapshot {
    param([hashtable]$Definition)
    try {
        $item = Get-Item $Definition.Path -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Exists = $false; Kind = $null; Data = $null }
    }
    $exists = ($item.GetValueNames() -contains $Definition.Name)
    if (-not $exists) {
        return [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Exists = $false; Kind = $null; Data = $null }
    }
    $kind = $item.GetValueKind($Definition.Name).ToString()
    $value = $item.GetValue($Definition.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($kind -eq 'Binary') {
        $value = ([byte[]]$value | ForEach-Object { '{0:X2}' -f $_ }) -join ''
    }
    [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Exists = $true; Kind = $kind; Data = $value }
}

function Convert-RegKindForExe {
    param([string]$Kind)
    switch ($Kind) {
        'DWord' { return 'REG_DWORD' }
        'QWord' { return 'REG_QWORD' }
        'String' { return 'REG_SZ' }
        'ExpandString' { return 'REG_EXPAND_SZ' }
        'MultiString' { return 'REG_MULTI_SZ' }
        'Binary' { return 'REG_BINARY' }
        default { throw "不支持恢复的注册表类型：$Kind" }
    }
}

function Ensure-MpoBackup {
    try {
        if (Test-Path $script:mpoBackupFile) {
            $backup = Get-Content $script:mpoBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-MpoBackupSchema $backup)) { throw 'mpo-backup.json 结构、记录唯一性或值数据不正确' }
            $script:mpoBackupReady = $true
            return $true
        }
        $parent = Split-Path $script:mpoBackupFile -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
        $snapshots = @($script:mpoManagedValues | ForEach-Object { Get-MpoValueSnapshot $_ })
        $backup = [pscustomobject]@{ Version = 1; Binding = (Get-BackupMachineId); Values = $snapshots }
        if (-not (Test-MpoBackupSchema $backup)) { throw '生成的 MPO 备份未通过结构校验' }
        $json = ConvertTo-Json -InputObject $backup -Depth 6
        Write-TweakAtomicTextFile -Path $script:mpoBackupFile -Content $json
        $check = Get-Content $script:mpoBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-MpoBackupSchema $check)) { throw '写入后的 MPO 备份校验失败' }
        $script:mpoBackupReady = $true
        Write-Host "[OK] MPO 原始状态已备份：$script:mpoBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] MPO 原始状态备份失败：$($_.Exception.Message)；已阻止 MPO 修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Test-MpoBackupSchema {
    param([object]$Backup)
    if ($null -eq $Backup -or $Backup.Version -ne 1) { return $false }
    if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
    $records = @($Backup.Values)
    if ($records.Count -ne $script:mpoManagedValues.Count) { return $false }
    $expected = @($script:mpoManagedValues | ForEach-Object { "$($_.Path)|$($_.Name)" })
    $actual = @($records | ForEach-Object { "$($_.Path)|$($_.Name)" })
    if (@($actual | Sort-Object -Unique).Count -ne $expected.Count -or ($actual | Where-Object { $expected -notcontains $_ }).Count -gt 0) { return $false }
    foreach ($r in $records) {
        if ($null -eq $r.Exists) { return $false }
        if ([bool]$r.Exists) {
            if ([string]::IsNullOrWhiteSpace([string]$r.Kind) -or $null -eq $r.Data) { return $false }
            try { $null = Convert-RegKindForExe ([string]$r.Kind) } catch { return $false }
            if ($r.Kind -eq 'DWord') { try { $null = [uint32]$r.Data } catch { return $false } }
            if ($r.Kind -eq 'Binary' -and ([string]$r.Data -notmatch '^(?:[0-9A-Fa-f]{2})*$')) { return $false }
        } elseif ($null -ne $r.Kind -or $null -ne $r.Data) { return $false }
    }
    return $true
}

function Restore-MpoBackup {
    if (-not (Test-Path -LiteralPath $script:mpoBackupFile -PathType Leaf)) {
        # 没有快照就无法区分“工具值”和用户自己的同名值；恢复动作必须失败关闭。
        Write-Host "[FAIL] 未找到 mpo-backup.json，拒绝盲删受管理值；请先确认原始状态。" -ForegroundColor Red
        $script:fail++
        return $false
    }
    try {
        $backup = Get-Content -LiteralPath $script:mpoBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-MpoBackupSchema $backup)) { throw 'mpo-backup.json 结构、记录唯一性或值数据不正确' }
        $allOk = $true
        foreach ($r in @($backup.Values)) {
            $before = $script:fail
            if (-not $r.Exists) {
                Remove-RegDwordValue $r.Path $r.Name ("还原 " + $r.Name)
            } else {
                $regPath = Convert-RegExePath $r.Path
                $regType = Convert-RegKindForExe $r.Kind
                $data = [string]$r.Data
                & reg.exe ADD $regPath /v $r.Name /t $regType /d $data /f *> $null
                if ($LASTEXITCODE -ne 0) { $script:fail++; $allOk = $false }
                else {
                    Write-Host ("[OK] 已恢复 {0} 原始值 {1}" -f $r.Name, $r.Data)
                    $script:ok++
                    $script:rebootRequired = $true
                }
            }
            if ($script:fail -gt $before) { $allOk = $false }
        }
        if ($allOk) {
            Write-Host "[OK] MPO 已恢复到首次修改前状态；备份文件已保留：$script:mpoBackupFile" -ForegroundColor Green
        } else {
            Write-Host '[WARN] MPO 恢复未完全成功，请复查输出中的 FAIL 项；快照已保留供重试。' -ForegroundColor Yellow
        }
        return $allOk
    } catch {
        Write-Host "[FAIL] MPO 状态恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
