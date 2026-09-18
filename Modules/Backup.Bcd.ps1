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

function Test-BcdDebuggerTypeAllowed {
    param([string]$Type)
    return $Type -in @('Local','Serial','1394','USB','Net')
}

function Get-BcdDebuggerSnapshot {
    try {
        $out = (& bcdedit.exe /dbgsettings 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw '无法读取 BCD debugger settings' }
        $type = $null
        if ($out -match '(?im)^\s*debugtype\s+([^\r\n]+)') { $type = $Matches[1].Trim() }
        if ([string]::IsNullOrWhiteSpace($type)) {
            return [pscustomobject]@{ Version = 1; Binding = (Get-BackupMachineId); Present = $false; Type = $null; Arguments = $null }
        }
        if (-not (Test-BcdDebuggerTypeAllowed $type)) { throw "不支持或无法安全还原的 debugger type：$type" }

        # 只把受允许字符组成的参数写回 bcdedit，绝不把整段命令输出当作参数执行。
        $arguments = switch ($type) {
            'Local' { 'local' }
            'Serial' {
                $port = if ($out -match '(?im)^\s*port\s+([^\r\n]+)') { $Matches[1].Trim() } else { '1' }
                $baud = if ($out -match '(?im)^\s*baudrate\s+([^\r\n]+)') { $Matches[1].Trim() } else { '115200' }
                "serial port:$port baudrate:$baud"
            }
            '1394' {
                $channel = if ($out -match '(?im)^\s*channel\s+([^\r\n]+)') { $Matches[1].Trim() } else { '1' }
                "1394 channel:$channel"
            }
            'USB' {
                $target = if ($out -match '(?im)^\s*targetname\s+([^\
\\n]+)') { $Matches[1].Trim() } else { throw 'USB debugger settings 缺少 targetname' }
                "usb targetname:$target"
            }
            'Net' {
                $hostIp = if ($out -match '(?im)^\s*hostip\s+([^\
\\n]+)') { $Matches[1].Trim() } else { $null }
                $hostIpv6 = if ($out -match '(?im)^\s*hostipv6\s+([^\
\\n]+)') { $Matches[1].Trim() } else { $null }
                if (-not $hostIp -and -not $hostIpv6) { throw 'Net debugger settings 缺少 hostip 或 hostipv6' }
                $port = if ($out -match '(?im)^\s*port\s+([^\
\\n]+)') { $Matches[1].Trim() } else { throw 'Net debugger settings 缺少 port' }
                $ipArg = if ($hostIp) { "hostip:$hostIp" } else { "hostipv6:$hostIpv6" }
                $netArgs = "net $ipArg port:$port"
                if ($out -match '(?im)^\s*key\s+([A-Za-z0-9.]+)') {
                    $netArgs += " key:$($Matches[1].Trim())"
                }
                if ($out -match '(?im)^\s*(?:nodhcp|dhcp\s+(?:No|False|0))') {
                    $netArgs += " nodhcp"
                }
                if ($out -match '(?im)^\s*busparams\s+([A-Za-z0-9._-]+)') {
                    $netArgs += " busparams:$($Matches[1].Trim())"
                }
                $netArgs
            }
        }
        # 全局调试参数：/start 与 /noumex
        if ($out -match '(?im)^\s*start(?:policy)?\s+([A-Za-z0-9]+)') {
            $arguments += " /start:$($Matches[1].Trim())"
        }
        if ($out -match '(?im)^\s*noumex\s+(?:Yes|True|1)') {
            $arguments += " /noumex"
        }
        if ($arguments -notmatch '^[A-Za-z0-9:._ /-]+$') { throw 'debugger settings 参数含有未允许字符' }
        [pscustomobject]@{ Version = 1; Binding = (Get-BackupMachineId); Present = $true; Type = $type; Arguments = $arguments }
    } catch { throw }
}

function Test-BcdDebuggerBackupSchema {
    param([object]$Backup)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        if ($null -eq $Backup.Present -or $Backup.Present -isnot [bool]) { return $false }
        if (-not [bool]$Backup.Present) { return ($null -eq $Backup.Type -and $null -eq $Backup.Arguments) }
        if (-not (Test-BcdDebuggerTypeAllowed ([string]$Backup.Type))) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$Backup.Arguments)) { return $false }
        return ([string]$Backup.Arguments -match '^[A-Za-z0-9:._ /-]+$')
    } catch { return $false }
}

function Ensure-BcdDebuggerBackup {
    param([string]$BackupFile = $script:testModeDebuggerBackupFile)
    try {
        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-BcdDebuggerBackupSchema $existing)) { throw '已有 debugger settings 快照结构不正确，拒绝覆盖' }
            Write-Host "[OK] 已存在有效的 BCD debugger settings 快照（不会覆盖）：$BackupFile" -ForegroundColor Green
            return $true
        }
        $snapshot = Get-BcdDebuggerSnapshot
        if (-not (Test-BcdDebuggerBackupSchema $snapshot)) { throw '生成的 debugger settings 快照未通过结构校验' }
        $json = ConvertTo-Json -InputObject $snapshot -Depth 4
        Write-TweakAtomicTextFile -Path $BackupFile -Content $json
        $check = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-BcdDebuggerBackupSchema $check)) { throw '写入后的 debugger settings 快照校验失败' }
        Write-Host "[OK] BCD debugger settings 已备份：$BackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] BCD debugger settings 备份失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-BcdDebuggerBackup {
    param([string]$BackupFile = $script:testModeDebuggerBackupFile)
    if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
        Write-Host '[WARN] 未找到 debugger settings 快照；不会声称已恢复原始调试器配置。' -ForegroundColor Yellow
        $script:fail++
        return $false
    }
    try {
        $backup = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-BcdDebuggerBackupSchema $backup)) { throw 'debugger settings 快照结构不正确' }
        if ([bool]$backup.Present) {
            if (-not (Invoke-BcdEdit ("/dbgsettings " + [string]$backup.Arguments) '恢复原始 BCD debugger settings')) { return $false }
        } else {
            # bcdedit 没有通用“关闭调试器”开关；删除受管全局值比盲设 local 更接近未设置状态。
            $ok = Invoke-BcdEdit '/deletevalue {dbgsettings} debugtype' '删除原本未设置的 BCD debugger type'
            if (-not $ok) { return $false }
        }
        Write-Host '[OK] BCD debugger settings 已按修改前快照恢复。' -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] BCD debugger settings 恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Test-BcdBackupSchema {
    param([object]$Backup, [string[]]$ValueNames)
    if ($null -eq $Backup -or $Backup.Version -ne 1 -or $Backup.Object -ne '{current}') { return $false }
    if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
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
        $backup = [pscustomobject]@{ Version = 1; Binding = (Get-BackupMachineId); Object = '{current}'; CreatedAt = (Get-Date).ToString('o'); Values = @($values) }
        if (-not (Test-BcdBackupSchema $backup $managedNames)) { throw '生成的 BCD 备份未通过结构校验' }
        $json = ConvertTo-Json -InputObject $backup -Depth 5
        Write-TweakAtomicTextFile -Path $BackupFile -Content $json
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
                if (-not (Invoke-BcdEdit "/set $name $($record.Value)" "恢复 $name = $($record.Value)")) {
                    $allOk = $false
                    break
                }
            } else {
                $before = $script:fail
                Remove-BcdValue $name "删除 $name（恢复原始未设置状态）"
                if ($script:fail -gt $before) {
                    $allOk = $false
                    break
                }
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
