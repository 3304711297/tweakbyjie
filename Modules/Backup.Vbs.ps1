# Backup.Vbs.ps1 - Part 10 VBS/HVCI/Credential Guard 关闭操作的原始状态快照与恢复
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired
# 快照、修改与恢复共用 $script:vbsRegistryValues 同一份定义，避免清单漂移。

$script:vbsRegistryValues = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Desc = 'HVCI Enabled' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Desc = 'VBS EnableVirtualizationBasedSecurity' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\LSA'; Name = 'LsaCfgFlags'; Desc = 'Credential Guard LsaCfgFlags' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Desc = '策略 VBS' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'RequirePlatformSecurityFeatures'; Desc = '策略 RequirePlatformSecurityFeatures' }
)
$script:vbsBcdNames = @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')
$script:vbsFeatureNames = @('Microsoft-Hyper-V-All','VirtualMachinePlatform','HypervisorPlatform')

function Get-VbsValueSnapshot {
    param([hashtable]$Definition)
    $item = Get-Item $Definition.Path -ErrorAction SilentlyContinue
    $present = $item -and ($item.GetValueNames() -contains $Definition.Name)
    if (-not $present) { return [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Present = $false; Value = $null } }
    if ($item.GetValueKind($Definition.Name).ToString() -ne 'DWord') { throw "$($Definition.Name) 不是 DWORD" }
    [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Present = $true; Value = [uint32]$item.GetValue($Definition.Name) }
}

function Test-VbsBcdValueAllowed {
    param([string]$Name, [string]$Value)
    $allowed = @{
        hypervisorlaunchtype = @('Off','Auto')
        vsmlaunchtype        = @('Off','Auto')
        isolatedcontext      = @('Yes','No')
    }
    return $allowed.ContainsKey($Name) -and $allowed[$Name] -contains $Value
}

function Get-VbsBcdSnapshot {
    param([string]$Name)
    $enumOut = (& bcdedit.exe /enum '{current}' 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "无法读取当前 BCD（$Name）" }
    $pattern = '(?m)^\s*' + [regex]::Escape($Name) + '\s+([^\r\n]+)'
    if ($enumOut -match $pattern) {
        $value = $Matches[1].Trim()
        if (-not (Test-VbsBcdValueAllowed $Name $value)) { throw "BCD 值 $name=$value 不在允许清单内" }
        [pscustomobject]@{ Name = $Name; Present = $true; Value = $value }
    } else {
        [pscustomobject]@{ Name = $Name; Present = $false; Value = $null }
    }
}

function Get-VbsFeatureSnapshot {
    param([string]$FeatureName)
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    if ($feature) {
        [pscustomobject]@{ Name = $FeatureName; Present = $true; State = [string]$feature.State }
    } else {
        [pscustomobject]@{ Name = $FeatureName; Present = $false; State = $null }
    }
}

function Test-VbsBackupSchema {
    # RegistryDefinitions/BcdNames/FeatureNames 可注入自定义清单（测试用 HKCU 临时键做往返验证）；默认用内置清单
    param([object]$Backup, [object[]]$RegistryDefinitions = $script:vbsRegistryValues,
        [string[]]$BcdNames = $script:vbsBcdNames, [string[]]$FeatureNames = $script:vbsFeatureNames)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }

        $registry = @($Backup.Registry)
        $expectedKeys = @($RegistryDefinitions | ForEach-Object { "$($_.Path)|$($_.Name)" })
        $actualKeys = @($registry | ForEach-Object { "$($_.Path)|$($_.Name)" })
        if ($registry.Count -ne $expectedKeys.Count -or @($actualKeys | Sort-Object -Unique).Count -ne $expectedKeys.Count) { return $false }
        if (@($actualKeys | Where-Object { $expectedKeys -notcontains $_ }).Count -gt 0) { return $false }
        foreach ($r in $registry) {
            if ($null -eq $r.Present -or $r.Present -isnot [bool]) { return $false }
            if ([bool]$r.Present) {
                try { if ([uint64]$r.Value -gt [uint32]::MaxValue) { return $false } } catch { return $false }
            } elseif ($null -ne $r.Value) { return $false }
        }

        $bcd = @($Backup.Bcd)
        if ($bcd.Count -ne $BcdNames.Count) { return $false }
        foreach ($name in $BcdNames) {
            $record = @($bcd | Where-Object { $_.Name -eq $name })
            if ($record.Count -ne 1) { return $false }
            if ($null -eq $record[0].Present -or $record[0].Present -isnot [bool]) { return $false }
            if ([bool]$record[0].Present) {
                if ([string]::IsNullOrWhiteSpace([string]$record[0].Value)) { return $false }
                if (-not (Test-VbsBcdValueAllowed $name ([string]$record[0].Value))) { return $false }
            } elseif ($null -ne $record[0].Value) { return $false }
        }

        $features = @($Backup.Features)
        if ($features.Count -ne $FeatureNames.Count) { return $false }
        foreach ($name in $FeatureNames) {
            $record = @($features | Where-Object { $_.Name -eq $name })
            if ($record.Count -ne 1) { return $false }
            if ($null -eq $record[0].Present -or $record[0].Present -isnot [bool]) { return $false }
            if ([bool]$record[0].Present) {
                if ([string]::IsNullOrWhiteSpace([string]$record[0].State)) { return $false }
            } elseif ($null -ne $record[0].State) { return $false }
        }
        return $true
    } catch { return $false }
}

function Ensure-VbsBackup {
    # 清单可注入（测试用 HKCU 临时键做往返验证）；默认用内置清单
    param([object[]]$RegistryDefinitions = $script:vbsRegistryValues,
        [string[]]$BcdNames = $script:vbsBcdNames, [string[]]$FeatureNames = $script:vbsFeatureNames)
    try {
        if (Test-Path $script:vbsBackupFile) {
            $backup = Get-Content $script:vbsBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-VbsBackupSchema $backup $RegistryDefinitions $BcdNames $FeatureNames)) { throw 'vbs-backup.json 结构不正确或与当前清单不匹配' }
            Write-Host "[OK] 已存在有效的 VBS/Hyper-V 快照：$script:vbsBackupFile" -ForegroundColor Green
            return $true
        }
        $backup = [pscustomobject]@{
            Version   = 1
            CreatedAt = (Get-Date).ToString('o')
            Registry  = @($RegistryDefinitions | ForEach-Object { Get-VbsValueSnapshot $_ })
            Bcd       = @($BcdNames | ForEach-Object { Get-VbsBcdSnapshot $_ })
            Features  = @($FeatureNames | ForEach-Object { Get-VbsFeatureSnapshot $_ })
        }
        if (-not (Test-VbsBackupSchema $backup $RegistryDefinitions $BcdNames $FeatureNames)) { throw '生成的 VBS 备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $script:vbsBackupFile -Encoding UTF8 -ErrorAction Stop
        $check = Get-Content $script:vbsBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-VbsBackupSchema $check $RegistryDefinitions $BcdNames $FeatureNames)) { throw '写入后的 VBS 备份校验失败' }
        Write-Host "[OK] VBS/Hyper-V 原始状态已备份：$script:vbsBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] VBS/Hyper-V 原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-VbsBackup {
    param([object[]]$RegistryDefinitions = $script:vbsRegistryValues,
        [string[]]$BcdNames = $script:vbsBcdNames, [string[]]$FeatureNames = $script:vbsFeatureNames)
    if (-not (Test-Path $script:vbsBackupFile)) { Write-Host '[FAIL] 未找到 vbs-backup.json，拒绝声称已恢复。' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:vbsBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-VbsBackupSchema $backup $RegistryDefinitions $BcdNames $FeatureNames)) { throw 'vbs-backup.json 结构不正确或与当前清单不匹配' }
        $allOk = $true

        foreach ($r in @($backup.Registry)) {
            $before = $script:fail
            if ([bool]$r.Present) { Set-RegDword $r.Path $r.Name ([uint32]$r.Value) ("恢复 VBS 注册表 " + $r.Name) }
            else { Remove-RegDwordValue $r.Path $r.Name ("删除 VBS 注册表 " + $r.Name + "（恢复原始未设置状态）") }
            if ($script:fail -gt $before) { $allOk = $false }
        }

        foreach ($b in @($backup.Bcd)) {
            $before = $script:fail
            if ([bool]$b.Present) { Invoke-BcdEdit "/set $($b.Name) $($b.Value)" "恢复 bcdedit $($b.Name) = $($b.Value)" | Out-Null }
            else { Remove-BcdValue $b.Name "删除 bcdedit $($b.Name)（恢复原始未设置状态）" }
            if ($script:fail -gt $before) { $allOk = $false }
        }

        foreach ($f in @($backup.Features)) {
            if (-not [bool]$f.Present) { continue }
            $state = [string]$f.State
            if ($state -in @('Disabled','DisablePending')) { continue }
            $before = $script:fail
            try {
                $null = Enable-WindowsOptionalFeature -Online -FeatureName $f.Name -NoRestart -ErrorAction Stop
                Write-Host "[OK] 恢复 Windows 功能 $($f.Name)（原状态 $state）"
                $script:ok++
                $script:rebootRequired = $true
            } catch {
                Write-Host "[FAIL] 恢复 Windows 功能 $($f.Name) : $($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
            }
            if ($script:fail -gt $before) { $allOk = $false }
        }

        if ($allOk) { Write-Host '[OK] VBS/Hyper-V 已按修改前快照恢复；UEFI 锁定不在本快照范围内。' -ForegroundColor Green }
        else { Write-Host '[WARN] VBS/Hyper-V 恢复未完全成功，请复查输出中的 FAIL 项。' -ForegroundColor Yellow }
        return $allOk
    } catch {
        Write-Host "[FAIL] VBS/Hyper-V 快照恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
