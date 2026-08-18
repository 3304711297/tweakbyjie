# Windows Game Optimization + BCDEdit Addons - Layered Menu Edition
# Run as Administrator. Each setting is applied independently.
# ActivationType is handled separately because the key may be protected.
#
# 菜单 / Menu:
#   输入 1 回车 = 核心性能分层菜单：核心游戏 / 系统行为 / CPU 安全缓解
#   输入 2 回车 = 高级 BCD / 计时器与启动安全（独立配置，修改前备份）
#   输入 3 回车 = 开启测试模式（bcdedit testsigning / debug / dbgsettings local / nointegritychecks）
#   输入 4 回车 = 关闭测试模式（删除 testsigning / debug 启动项，保留 nointegritychecks）
#   输入 5 回车 = 关闭安全中心（禁用 Windows Defender / SmartScreen 策略，可选删除类优化）
#   输入 6 回车 = 服务优化（A/B 功能依赖分组，支持快照恢复）
#   输入 7 回车 = 超性能电源计划（备份并应用 / 恢复备份）
#   输入 8 回车 = 原生 NVMe 驱动配置（含 SafeBoot 快照）
#   输入 9 回车 = 清除 Device Guard EFI 锁定（SecConfig.efi 流程）
#   输入 10 回车 = 虚拟化 / VBS / Hyper-V 管理（删除脚本覆盖并尝试启用）
#   输入 11 回车 = MPO 设置管理（三方案互斥，修改前备份，可恢复）
#   修改完成后只标记待重启；退出主菜单时统一询问是否重启。

$ErrorActionPreference = "Continue"
$ok = 0
$fail = 0
$skip = 0

# --- Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] 请以管理员身份运行此脚本 / Please run this script as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

function Convert-RegExePath {
    param([string]$Path)
    if ($Path -match '^HKLM:\\(.*)$') { return "HKLM\$($Matches[1])" }
    if ($Path -match '^HKCU:\\(.*)$') { return "HKCU\$($Matches[1])" }
    if ($Path -match '^HKEY_LOCAL_MACHINE:\\(.*)$') { return "HKLM\$($Matches[1])" }
    if ($Path -match '^HKEY_CURRENT_USER:\\(.*)$') { return "HKCU\$($Matches[1])" }
    return $Path
}

function Set-RegDword {
    param([string]$Path,[string]$Name,[object]$Value,[string]$Label)
    try {
        $regPath = Convert-RegExePath $Path
        $valueText = [string]$Value
        if ($valueText -match '^\d+$') {
            [uint64]$n = [uint64]$Value
            if ($n -le 0xFFFFFFFF) {
                $valueText = "0x{0:X8}" -f $n
            }
        }
        & reg.exe ADD $regPath /v $Name /t REG_DWORD /d $valueText /f *> $null
        if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        Write-Host ("[OK] {0} = {1}" -f $Label, $valueText)
        $script:ok++
        $script:rebootRequired = $true
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

function Set-RegString {
    param([string]$Path,[string]$Name,[string]$Value,[string]$Label)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force -ErrorAction Stop | Out-Null
        Write-Host ("[OK] {0} = {1}" -f $Label, $Value)
        $script:ok++
        $script:rebootRequired = $true
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

function Set-RegBinary {
    param([string]$Path,[string]$Name,[string]$Hex,[string]$Label)
    try {
        $regPath = Convert-RegExePath $Path
        & reg.exe ADD $regPath /v $Name /t REG_BINARY /d $Hex /f *> $null
        if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        Write-Host ("[OK] {0} = {1}" -f $Label, $Hex)
        $script:ok++
        $script:rebootRequired = $true
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

# Delete a registry value only when it exists (for restore flows)
function Remove-RegDwordValue {
    param([string]$Path,[string]$Name,[string]$Label)
    try {
        $item = Get-Item $Path -ErrorAction SilentlyContinue
        if ($item -and ($item.GetValueNames() -contains $Name)) {
            $regPath = Convert-RegExePath $Path
            & reg.exe DELETE $regPath /v $Name /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
            Write-Host ("[OK] {0}（已删除 {1} -> {2}）" -f $Label, $Path, $Name)
            $script:ok++
            $script:rebootRequired = $true
        } else {
            Write-Host "[SKIP] $Label 未设置（系统默认，无需还原）" -ForegroundColor Yellow
            $script:skip++
        }
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

$script:mpoManagedValues = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'DisableMPO';      Desc = '驱动层禁用 MPO（旧方法）' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'DisableOverlays'; Desc = '驱动层禁用 MPO（更激进的社区排障方案）' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm';                   Name = 'OverlayTestMode'; Desc = 'DWM 层禁用 MPO（社区排障方案）' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm';                   Name = 'OverlayMinFPS';   Desc = '尝试避免低帧率时撤下 MPO' }
)
$script:mpoBackupFile = Join-Path $PSScriptRoot 'mpo-backup.json'
$script:mpoBackupReady = $false

function Get-MpoValueSnapshot {
    param([hashtable]$Definition)
    $item = Get-Item $Definition.Path -ErrorAction SilentlyContinue
    $exists = $item -and ($item.GetValueNames() -contains $Definition.Name)
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
        $backup = [pscustomobject]@{ Version = 1; Values = $snapshots }
        if (-not (Test-MpoBackupSchema $backup)) { throw '生成的 MPO 备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 6 | Set-Content -Path $script:mpoBackupFile -Encoding UTF8 -ErrorAction Stop
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
    if (-not (Test-Path $script:mpoBackupFile)) {
        Write-Host "[WARN] 未找到 mpo-backup.json，将删除受管理值并恢复系统默认；这不会恢复此前的自定义值" -ForegroundColor Yellow
        foreach ($v in $script:mpoManagedValues) { Remove-RegDwordValue $v.Path $v.Name ("还原 " + $v.Name) }
        return $true
    }
    try {
        $backup = Get-Content $script:mpoBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-MpoBackupSchema $backup)) { throw 'mpo-backup.json 结构、记录唯一性或值数据不正确' }
        foreach ($r in @($backup.Values)) {
            if (-not $r.Exists) {
                Remove-RegDwordValue $r.Path $r.Name ("还原 " + $r.Name)
                continue
            }
            $regPath = Convert-RegExePath $r.Path
            $regType = Convert-RegKindForExe $r.Kind
            $data = if ($r.Kind -eq 'Binary') { [string]$r.Data } else { [string]$r.Data }
            & reg.exe ADD $regPath /v $r.Name /t $regType /d $data /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "恢复 $($r.Name) 失败，reg.exe exit code $LASTEXITCODE" }
            Write-Host ("[OK] 已恢复 {0} 原始值 {1}" -f $r.Name, $r.Data)
            $script:ok++
            $script:rebootRequired = $true
        }
        Write-Host "[OK] MPO 已恢复到首次修改前状态；备份文件已保留：$script:mpoBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] MPO 状态恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

# Helper function for BCD
function Invoke-BcdEdit {
    param([string]$Arguments, [string]$Label)
    try {
        $process = Start-Process -FilePath "bcdedit.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Exit code $($process.ExitCode)" }
        Write-Host ("[OK] {0}" -f $Label)
        $script:ok++
        $script:rebootRequired = $true
        return $true
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
        return $false
    }
}

# Delete a bcdedit value only when it exists on {current} (avoid FAIL on default entries)
function Remove-BcdValue {
    param([string]$ValueName, [string]$Label)
    $enumOut = & bcdedit.exe /enum '{current}' 2>$null
    if ($LASTEXITCODE -eq 0 -and (($enumOut -join "`n") -match [regex]::Escape($ValueName))) {
        Invoke-BcdEdit "/deletevalue $ValueName" $Label
    } else {
        Write-Host "[SKIP] $Label 未设置（系统默认，无需还原）" -ForegroundColor Yellow
        $script:skip++
    }
}

function Verify-RegDword {
    param([string]$Path, [string]$Name, [uint32]$Expected, [string]$Label)
    try {
        $item = Get-Item $Path -ErrorAction Stop
        if ($item.GetValueNames() -notcontains $Name) {
            Write-Host "[VERIFY FAIL] $Label：值不存在" -ForegroundColor Red
            $script:fail++
            return $false
        }
        $actual = [uint32]$item.GetValue($Name)
        if ($actual -eq $Expected) {
            Write-Host "[VERIFY OK] $Label = $actual" -ForegroundColor Green
            return $true
        }
        Write-Host "[VERIFY FAIL] $Label：实际=$actual，目标=$Expected" -ForegroundColor Red
        $script:fail++
        return $false
    } catch {
        Write-Host "[VERIFY FAIL] $Label：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Verify-BcdValue {
    param([string]$ValueName, [string]$Expected, [string]$Label)
    try {
        $enumOut = (& bcdedit.exe /enum '{current}' 2>$null) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'bcdedit /enum failed' }
        $pattern = '(?m)^\s*' + [regex]::Escape($ValueName) + '\s+([^\r\n]+)'
        if ($enumOut -notmatch $pattern) {
            Write-Host "[VERIFY FAIL] bcdedit $Label：值不存在" -ForegroundColor Red
            $script:fail++
            return $false
        }
        $actual = $Matches[1].Trim()
        if ($actual -ieq $Expected) {
            Write-Host "[VERIFY OK] bcdedit $Label = $actual" -ForegroundColor Green
            return $true
        }
        Write-Host "[VERIFY FAIL] bcdedit $Label：实际=$actual，目标=$Expected" -ForegroundColor Red
        $script:fail++
        return $false
    } catch {
        Write-Host "[VERIFY FAIL] bcdedit $Label：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
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

function Verify-ServiceStartupType {
    param([string]$ServiceName, [string]$Expected, [string]$Label)
    try {
        $svc = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $ServiceName.Replace("'", "''")) -ErrorAction Stop
        if (-not $svc) {
            Write-Host "[VERIFY SKIP] $Label：服务不存在" -ForegroundColor Yellow
            $script:skip++
            return $true
        }
        if ($svc.StartMode -ieq $Expected) {
            Write-Host "[VERIFY OK] $Label StartupType = $($svc.StartMode)" -ForegroundColor Green
            return $true
        }
        Write-Host "[VERIFY FAIL] $Label：实际=$($svc.StartMode)，目标=$Expected" -ForegroundColor Red
        $script:fail++
        return $false
    } catch {
        Write-Host "[VERIFY FAIL] $Label：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

$script:rebootRequired = $false
$script:moduleFailBaseline = 0
$script:bcdBackupFile = Join-Path $PSScriptRoot 'bcd-backup.json'
$script:bcdManagedValues = @('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy','nx','tpmbootentropy','nointegritychecks')
$script:serviceBackupFile = Join-Path $PSScriptRoot 'service-backup.json'
$script:securityMitigationBackupFile = Join-Path $PSScriptRoot 'security-mitigation-backup.json'
$script:securityMitigationValues = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverride' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverrideMask' }
)
$script:nvmeBackupFile = Join-Path $PSScriptRoot 'nvme-backup.json'

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
    $local = Join-Path $PSScriptRoot 'ViVeTool.exe'
    if (Test-Path $local) { return $local }
    $cmd = Get-Command 'ViVeTool.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command 'vivetool.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
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

function Request-Restart {
    if (-not $script:rebootRequired) { return }
    Write-Host '[待重启] 当前模块产生了需要重启后生效的修改；本模块不会单独触发重启。' -ForegroundColor Yellow
    Write-Host '         可继续执行其他模块，退出主菜单时统一决定是否重启。' -ForegroundColor Yellow
}

function Invoke-FinalRestartPrompt {
    if (-not $script:rebootRequired) { Write-Host '[完成] 当前会话没有待重启修改。' -ForegroundColor Green; return }
    Write-Host ''; Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' 本次会话存在待重启修改 / Restart Pending' -ForegroundColor Yellow
    if ($script:fail -gt 0) { Write-Host " [警告] 本次会话存在 $($script:fail) 个失败或验证失败项；重启不会自动解决失败项。" -ForegroundColor Red }
    $r = Read-Host '退出前现在重启吗？输入 Y 立即重启；输入 N 返回系统（默认 N）'
    if ($r -match '^[Yy]$') {
        if ($script:fail -gt 0) { $confirm = Read-Host '检测到失败/验证失败，仍要重启吗？输入 Y 确认；其他键取消'; if ($confirm -notmatch '^[Yy]$') { Write-Host '[取消] 已取消重启。' -ForegroundColor Yellow; return } }
        Write-Host '[重启] 立即重启 / Restarting now...' -ForegroundColor Red
        Restart-Computer -Force
    } else { Write-Host '[结束] 本次不重启；待重启设置仍会保留。' -ForegroundColor Green }
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
        } elseif ($null -ne $record[0].Value) {
            return $false
        }
    }
    return $true
}

function Ensure-BcdBackup {
    param([string[]]$ValueNames)
    try {
        $managedNames = @($script:bcdManagedValues)
        if (Test-Path $script:bcdBackupFile) {
            $backup = Get-Content $script:bcdBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-BcdBackupSchema $backup $managedNames)) { throw 'bcd-backup.json 结构、对象或记录不完整' }
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
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $script:bcdBackupFile -Encoding UTF8 -ErrorAction Stop
        Write-Host "[OK] BCD 原始状态已备份：$script:bcdBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] BCD 原始状态备份失败：$($_.Exception.Message)；已阻止高级 BCD 修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-BcdBackup {
    param([string[]]$ValueNames)
    if (-not (Test-Path $script:bcdBackupFile)) {
        Write-Host '[FAIL] 未找到有效 BCD 备份，拒绝声称已恢复；请手动检查当前 BCD' -ForegroundColor Red
        $script:fail++
        return $false
    }
    try {
        $backup = Get-Content $script:bcdBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-BcdBackupSchema $backup $script:bcdManagedValues)) { throw 'bcd-backup.json 结构、对象或记录不完整' }
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
        if ($allOk) { Write-Host "[OK] 高级 BCD 已按修改前快照恢复；备份文件保留：$script:bcdBackupFile" -ForegroundColor Green }
        return $allOk
    } catch {
        Write-Host "[FAIL] BCD 状态恢复失败：$($_.Exception.Message)" -ForegroundColor Red
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

function Verify-MemoryCompressionDisabled {
    try { $mma=Get-MMAgent -ErrorAction Stop; if($mma.MemoryCompression -eq $false){Write-Host "[VERIFY OK] Memory Compression = Disabled" -ForegroundColor Green;return $true}; Write-Host "[VERIFY FAIL] Memory Compression 仍处于启用状态" -ForegroundColor Red;$script:fail++;return $false }
    catch { Write-Host "[VERIFY FAIL] Memory Compression：$($_.Exception.Message)" -ForegroundColor Red;$script:fail++;return $false }
}
function Verify-TrimEnabled {
    try { $out=(& fsutil.exe behavior query DisableDeleteNotify 2>&1)-join "`n"; if($LASTEXITCODE -ne 0){throw 'fsutil 查询失败'}; if($out -match '=\s*0\s*$'){Write-Host "[VERIFY OK] NTFS TRIM = Enabled (DisableDeleteNotify = 0)" -ForegroundColor Green;return $true}; Write-Host "[VERIFY FAIL] 无法确认 TRIM = Enabled" -ForegroundColor Red;$script:fail++;return $false }
    catch { Write-Host "[VERIFY FAIL] TRIM：$($_.Exception.Message)" -ForegroundColor Red;$script:fail++;return $false }
}
function Verify-HypervisorRuntime {
    try { $cs=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; if($cs.HypervisorPresent -eq $false){Write-Host "[VERIFY OK] 运行时 HypervisorPresent = False" -ForegroundColor Green;return $true}; Write-Host "[VERIFY INFO] 运行时仍检测到 HypervisorPresent = True；重启后再复核" -ForegroundColor Yellow;$script:skip++;return $true }
    catch { Write-Host "[VERIFY SKIP] 无法读取 HypervisorPresent：$($_.Exception.Message)" -ForegroundColor Yellow;$script:skip++;return $true }
}

# ============================ Menu ============================
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows Game Optimization + BCDEdit - Menu Edition" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " 请选择执行模式 / Select an option:" -ForegroundColor Cyan
Write-Host "   0. 退出 / Exit" -ForegroundColor White
Write-Host "   1. 核心游戏 / 系统性能优化（内部可分为核心游戏、系统行为、CPU 缓解）" -ForegroundColor White
Write-Host "   2. 高级 BCD / 计时器与启动安全（独立执行）" -ForegroundColor White
Write-Host "   3. 开启测试模式" -ForegroundColor White
Write-Host "   4. 关闭测试模式（保留 nointegritychecks）" -ForegroundColor White
Write-Host "   5. 关闭安全中心（Defender / SmartScreen）" -ForegroundColor White
Write-Host "   6. 服务优化（A/B 分组）" -ForegroundColor White
Write-Host "   7. 超性能电源计划" -ForegroundColor White
Write-Host "   8. 原生 NVMe 驱动" -ForegroundColor White
Write-Host "   9. Device Guard EFI 锁定" -ForegroundColor White
Write-Host "  10. 虚拟化 / VBS / Hyper-V 管理" -ForegroundColor White
Write-Host "  11. MPO 设置管理（独立排障）" -ForegroundColor White
Write-Host ""
Write-Host "提示：一次运行可以连续执行多个模块；修改完成后统一选择是否重启。" -ForegroundColor Yellow
Write-Host " NOTE: Multiple modules can be run in one session; restart is deferred until you choose it." -ForegroundColor Yellow
Write-Host ""
while ($true) {
$choice = Read-Host "请输入 0-11 并回车 (Enter 0-11)"

if ($choice -eq "0") {
    Invoke-FinalRestartPrompt
    break

} elseif ($choice -eq "1") {

    $script:moduleFailBaseline = $fail
    Write-Host ""; Write-Host "============ [Part 1] 核心游戏 / 系统性能优化 ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  1. 核心游戏优化（GameDVR / GameBar / Multimedia / Win32PrioritySeparation / HAGS / Games Task / Game Mode / ActivationType）" -ForegroundColor White
    Write-Host "  2. 系统行为优化（Search / Prefetch / Memory Compression / NTFS 8.3 / TRIM / Visual Effects）" -ForegroundColor White
    Write-Host "  3. CPU 安全缓解调整（FeatureSettingsOverride / Mask；修改前自动备份，可恢复）" -ForegroundColor Yellow
    Write-Host "  0. 返回主菜单" -ForegroundColor White
    $coreChoice = Read-Host "请输入 0、1、2 或 3 并回车"

    if ($coreChoice -eq '1') {
        # 01 GameDVR
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 "AppCaptureEnabled"
        Set-RegDword "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 "GameDVR_Enabled"

        # 02 ActivationType - mandatory.
        $activationReg = 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.Gamebar.PresenceServer.Internal.PresenceWriter'
        $taskName = $null
        try {
            & reg.exe ADD $activationReg /v ActivationType /t REG_DWORD /d 0x00000000 /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "Administrator access denied" }
            Write-Host "[OK] ActivationType = 0"
            $ok++
            $script:rebootRequired = $true
        } catch {
            try {
                $taskName = "WindowsGameOpt_ActivationType_" + [guid]::NewGuid().ToString("N")
                $cmd = 'reg.exe ADD "' + $activationReg + '" /v ActivationType /t REG_DWORD /d 0x00000000 /f'
                $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $cmd"
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
                Start-ScheduledTask -TaskName $taskName
                Start-Sleep -Seconds 2
                $check = & reg.exe QUERY $activationReg /v ActivationType 2>$null
                if ($check -match '0x0+\s*$') {
                    Write-Host "[OK] ActivationType = 0 (SYSTEM)"
                    $ok++
                    $script:rebootRequired = $true
                } else { throw "SYSTEM retry did not verify ActivationType=0" }
            } catch {
                Write-Host "[FAIL] ActivationType = 0 : protected registry key rejected the change" -ForegroundColor Red
                Write-Host " Other core optimizations will continue." -ForegroundColor Yellow
                $fail++
            } finally {
                if ($taskName) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
            }
        }

        # 03 GameBar
        Set-RegDword "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0 "UseNexusForGameBarEnabled"
        # 04 Multimedia
        Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "0xFFFFFFFF" "NetworkThrottlingIndex"
        Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 10 "SystemResponsiveness"
        # 05 CPU priority
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation (0x26)"
        # 08 HAGS
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS"
        # 09 Games task
        $games = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        Set-RegDword $games "Affinity" 0 "Games Affinity"
        Set-RegString $games "Background Only" "False" "Games Background Only"
        Set-RegDword $games "Clock Rate" 10000 "Games Clock Rate"
        Set-RegDword $games "GPU Priority" 8 "Games GPU Priority"
        Set-RegDword $games "Priority" 6 "Games Priority"
        Set-RegString $games "Scheduling Category" "High" "Games Scheduling Category"
        Set-RegString $games "SFIO Priority" "High" "Games SFIO Priority"
        # 12 Game Mode
        Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 0 "AutoGameModeEnabled"
        Set-RegDword "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0 "AllowAutoGameMode"

        Write-Host ""; Write-Host "[Post-Apply Verification / 核心游戏优化验证]" -ForegroundColor Cyan
        Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "Win32PrioritySeparation" | Out-Null
        Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "HwSchMode / HAGS" | Out-Null

    } elseif ($coreChoice -eq '2') {
        # 06 Search
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 "BingSearchEnabled"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "AllowSearchToUseLocation" 0 "AllowSearchToUseLocation"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0 "CortanaConsent"
        # 10 Prefetch
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher"
        # 11 NTFS
        Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisable8dot3NameCreation" 1 "NtfsDisable8dot3NameCreation"
        # 13 Memory Compression
        Write-Host ""; Write-Host "[Memory Compression]" -ForegroundColor Cyan
        try { Disable-MMAgent -mc -ErrorAction Stop; Write-Host "[OK] Memory Compression disabled"; $ok++; $script:rebootRequired=$true }
        catch { Write-Host "[FAIL] Memory Compression : $($_.Exception.Message)" -ForegroundColor Red; $fail++ }
        # 14 TRIM
        Write-Host ""; Write-Host "[TRIM]" -ForegroundColor Cyan
        try {
            $trimOut = fsutil.exe behavior set DisableDeleteNotify 0 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Host "[OK] NTFS TRIM enabled"; $ok++ }
            else { Write-Host "[FAIL] TRIM : fsutil exit code $LASTEXITCODE" -ForegroundColor Red; if($trimOut){Write-Host ($trimOut -join [Environment]::NewLine) -ForegroundColor DarkYellow}; $fail++ }
        } catch { Write-Host "[FAIL] TRIM : $($_.Exception.Message)" -ForegroundColor Red; $fail++ }

        # Visual Effects
        Write-Host ""; Write-Host "[Visual Effects 自定义 / Custom]" -ForegroundColor Cyan
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 3 "VisualFXSetting = 3 (自定义)"
        Set-RegString "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "平滑屏幕字体边缘 ON"
        Set-RegDword "HKCU:\Control Panel\Desktop" "FontSmoothingType" 2 "Font Smoothing = ClearType"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 1 "任务栏动画 ON"
        Set-RegBinary "HKCU:\Control Panel\Desktop" "UserPreferencesMask" "9012018010000000" "动画/淡入淡出/阴影全关"
        Set-RegString "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "最大/最小化动画 OFF"
        Set-RegString "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "拖动显示窗口内容 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" 0 "半透明选择框 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" 0 "图标标签阴影 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "IconsOnly" 1 "缩略图 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\DWM" "AlwaysHibernateThumbnails" 0 "任务栏缩略图缓存 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 "透明效果 OFF"
        Set-RegDword "HKCU:\Control Panel\Accessibility" "DynamicScrollbars" 1 "始终显示滚动条 OFF"
        Set-RegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "AnimationEffects" 0 "动画效果(辅助功能) OFF"
        Set-RegDword "HKCU:\Control Panel\Accessibility" "MessageDuration" 5 "通知自动关闭时长 = 5 秒"
        $script:rebootRequired = $true
        Write-Host "视觉效果为 HKCU 设置，注销 / 重启（或重启资源管理器）后完全生效" -ForegroundColor Yellow

        Write-Host ""; Write-Host "[Post-Apply Verification / 系统行为优化验证]" -ForegroundColor Cyan
        Verify-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0 "EnablePrefetcher" | Out-Null
        Verify-MemoryCompressionDisabled | Out-Null
        Verify-TrimEnabled | Out-Null

    } elseif ($coreChoice -eq '3') {
        Write-Host ""; Write-Host "[CPU 安全缓解调整 / Meltdown-Spectre Mitigation]" -ForegroundColor Yellow
        Write-Host "目标值 FeatureSettingsOverride=3 / FeatureSettingsOverrideMask=3 会关闭相关缓解；仅在明确了解安全影响时使用。" -ForegroundColor Yellow
        Write-Host "  1. 查看当前值" -ForegroundColor White
        Write-Host "  2. 应用 3 / 3（修改前自动备份）" -ForegroundColor Yellow
        Write-Host "  3. 按备份恢复" -ForegroundColor White
        $mChoice = Read-Host "请输入 1、2 或 3 并回车"
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        if ($mChoice -eq '1') {
            $item=Get-Item $mmPath -ErrorAction SilentlyContinue
            foreach($n in @('FeatureSettingsOverride','FeatureSettingsOverrideMask')){
                if($item -and ($item.GetValueNames()-contains $n)){Write-Host ("{0} = {1}" -f $n,$item.GetValue($n))}else{Write-Host ("{0} = <未设置（系统默认）>" -f $n)}}
        } elseif ($mChoice -eq '2') {
            if (Ensure-SecurityMitigationBackup) {
                Set-RegDword $mmPath "FeatureSettingsOverride" 3 "FeatureSettingsOverride = 3"
                Set-RegDword $mmPath "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask = 3"
                Verify-RegDword $mmPath "FeatureSettingsOverride" 3 "FeatureSettingsOverride" | Out-Null
                Verify-RegDword $mmPath "FeatureSettingsOverrideMask" 3 "FeatureSettingsOverrideMask" | Out-Null
            }
        } elseif ($mChoice -eq '3') {
            Restore-SecurityMitigationBackup
        } else { Write-Host "[ERROR] 无效输入：$mChoice 。" -ForegroundColor Red }
    } elseif ($coreChoice -eq '0') {
        Write-Host "[返回] 已返回主菜单。" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] 无效输入：$coreChoice 。请输入 0、1、2 或 3" -ForegroundColor Red
    }

    if ($coreChoice -ne '0') {
        Write-Host ""; Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 1 - Core / System Optimization)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Request-Restart
    }

} elseif ($choice -eq "2") {
    $script:moduleFailBaseline = $fail
    Write-Host ""; Write-Host "============ [Part 2] 高级 BCD / Advanced BCD ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  0. 查看当前高级 BCD 状态（只读）" -ForegroundColor White
    Write-Host "  1. 应用高级计时器配置（useplatformclock / useplatformtick / disabledynamictick / tscsyncpolicy）" -ForegroundColor White
    Write-Host "  2. 恢复高级计时器修改前状态" -ForegroundColor White
    Write-Host "  3. 应用启动安全高级项（NX AlwaysOff / TPM Boot Entropy ForceDisable / nointegritychecks）" -ForegroundColor Yellow
    Write-Host "  4. 恢复启动安全高级项到修改前状态" -ForegroundColor White
    $bChoice=Read-Host "请输入 0、1、2、3 或 4 并回车"
    $timerValues=@('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy'); $securityValues=@('nx','tpmbootentropy','nointegritychecks'); $allAdvancedValues=@($script:bcdManagedValues)
    if($bChoice -eq '0'){
        $enumOut=(& bcdedit.exe /enum '{current}' 2>$null)-join "`n"; foreach($name in $allAdvancedValues){$pattern='(?m)^\s*'+[regex]::Escape($name)+'\s+([^\r\n]+)';if($enumOut -match $pattern){Write-Host ("bcdedit {0,-22} = {1}"-f $name,$Matches[1].Trim())}else{Write-Host ("bcdedit {0,-22} = <未设置（系统默认）>"-f $name)}}; if(Test-Path $script:bcdBackupFile){Write-Host "BCD 备份：$script:bcdBackupFile" -ForegroundColor Yellow}
    } elseif($bChoice -eq '1'){
        if(Ensure-BcdBackup $allAdvancedValues){Invoke-BcdEdit "/set useplatformclock no" "Use Platform Clock Off";Invoke-BcdEdit "/set useplatformtick no" "Use Platform Tick Off";Invoke-BcdEdit "/set disabledynamictick yes" "Disable Dynamic Tick";Invoke-BcdEdit "/set tscsyncpolicy Enhanced" "TSC Sync Policy Enhanced";Write-Host "[提示] BCD 计时器项属于高级/调试用途，效果依硬件与 Windows 版本而异。" -ForegroundColor Yellow;Verify-BcdValue 'useplatformclock' 'No' 'useplatformclock'|Out-Null;Verify-BcdValue 'useplatformtick' 'No' 'useplatformtick'|Out-Null;Verify-BcdValue 'disabledynamictick' 'Yes' 'disabledynamictick'|Out-Null;Verify-BcdValue 'tscsyncpolicy' 'Enhanced' 'tscsyncpolicy'|Out-Null}
    } elseif($bChoice -eq '2'){Restore-BcdBackup $timerValues
    } elseif($bChoice -eq '3'){Write-Host '[WARNING] 启动安全高级项会降低系统安全边界。' -ForegroundColor Yellow;if(Ensure-BcdBackup $allAdvancedValues){Invoke-BcdEdit "/set nx AlwaysOff" "NX (DEP) AlwaysOff";Invoke-BcdEdit "/set tpmbootentropy ForceDisable" "TPM Boot Entropy Disabled";Invoke-BcdEdit "/set nointegritychecks on" "Driver Integrity Checks Disabled";Verify-BcdValue 'nx' 'AlwaysOff' 'nx'|Out-Null;Verify-BcdValue 'tpmbootentropy' 'ForceDisable' 'tpmbootentropy'|Out-Null;Verify-BcdValue 'nointegritychecks' 'Yes' 'nointegritychecks'|Out-Null}
    } elseif($bChoice -eq '4'){Restore-BcdBackup $securityValues
    } else {Write-Host "[ERROR] 无效输入：$bChoice 。请输入 0、1、2、3 或 4" -ForegroundColor Red}
    Write-Host "Finished (Part 2 - Advanced BCD)" -ForegroundColor Cyan; Write-Host " OK : $ok  FAIL : $fail  SKIP : $skip"; Request-Restart

} elseif ($choice -eq "3") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 3: 开启测试模式 =======================
    # 独立步骤：开启测试模式 / Enable Test Mode (bcdedit)
    Write-Host ""
    Write-Host "============ [Part 3] 开启测试模式 / Enable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""

    Invoke-BcdEdit "/set testsigning on" "bcdedit /set testsigning on"
    Invoke-BcdEdit "/debug on" "bcdedit /debug on"
    Invoke-BcdEdit "/dbgsettings local" "bcdedit /dbgsettings local"
    Invoke-BcdEdit "/set nointegritychecks on" "bcdedit /set nointegritychecks on"

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 3 - Enable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：开启测试模式后桌面右下角会显示“测试模式”水印，属正常现象。" -ForegroundColor Yellow
    Write-Host "如需关闭测试模式，可运行: bcdedit /set testsigning off" -ForegroundColor Yellow

    Request-Restart

} elseif ($choice -eq "4") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 4: 关闭测试模式 =======================
    # 独立步骤：关闭测试模式 / Disable Test Mode（保留 nointegritychecks）
    Write-Host ""
    Write-Host "============ [Part 4] 关闭测试模式 / Disable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：此操作通过删除 testsigning 和 debug 启动项来关闭测试模式，保留 nointegritychecks。" -ForegroundColor Yellow
    Write-Host ""

    Invoke-BcdEdit "/deletevalue testsigning" "bcdedit /deletevalue testsigning"
    Invoke-BcdEdit "/deletevalue debug" "bcdedit /deletevalue debug"

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 4 - Disable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host '提示：测试模式已关闭，桌面右下角的"测试模式"水印将在重启后消失。' -ForegroundColor Yellow
    Write-Host "如需重新开启测试模式，可运行选项 3。" -ForegroundColor Yellow

    Request-Restart

} elseif ($choice -eq "5") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 5: 关闭安全中心 =======================
    # 独立步骤：关闭 Windows Defender 安全中心 / Disable Security Center
    Write-Host ""
    Write-Host "============ [Part 5] 关闭安全中心 / Disable Security Center ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [WARNING] 此操作将禁用 Windows Defender 实时保护及相关安全服务！" -ForegroundColor Yellow
    Write-Host " [WARNING] This will disable Windows Defender realtime protection and related services!" -ForegroundColor Yellow
    Write-Host ""

    # --- Parent key: Windows Defender ---
    # HKLM\SOFTWARE\Policies\Microsoft\Windows Defender
    $defenderKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

    Set-RegDword $defenderKey "DisableAntiSpyware" 1 "DisableAntiSpyware"
    Set-RegDword $defenderKey "DisableAntiVirus" 1 "DisableAntiVirus"
    Set-RegDword $defenderKey "DisableRealtimeMonitoring" 1 "DisableRealtimeMonitoring"
    Set-RegDword $defenderKey "DisableRoutinelyTakingAction" 1 "DisableRoutinelyTakingAction"
    Set-RegDword $defenderKey "DisableSpecialRunningModes" 1 "DisableSpecialRunningModes"
    Set-RegDword $defenderKey "ServiceKeepAlive" 0 "ServiceKeepAlive"
    Set-RegDword $defenderKey "PUAProtection" 0 "PUAProtection"
    Set-RegDword $defenderKey "AllowFastServiceStartup" 0 "AllowFastServiceStartup"
    Set-RegDword $defenderKey "DisableLocalAdminMerge" 1 "DisableLocalAdminMerge"
    Set-RegDword $defenderKey "RandomizeScheduleTaskTimes" 0 "RandomizeScheduleTaskTimes"

    # --- Subkey: Real-Time Protection ---
    # HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection
    $rtpKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"

    Set-RegDword $rtpKey "DisableAntivirus" 1 "RTP DisableAntivirus"
    Set-RegDword $rtpKey "DisableBehaviorMonitoring" 1 "RTP DisableBehaviorMonitoring"
    Set-RegDword $rtpKey "DisableOnAccessProtection" 1 "RTP DisableOnAccessProtection"
    Set-RegDword $rtpKey "DisableScanOnRealtimeEnable" 1 "RTP DisableScanOnRealtimeEnable"
    Set-RegDword $rtpKey "DisableRealtimeMonitoring" 1 "RTP DisableRealtimeMonitoring"
    Set-RegDword $rtpKey "DisableIOAVProtection" 1 "RTP DisableIOAVProtection"
    Set-RegDword $rtpKey "DisableScriptScanning" 1 "RTP DisableScriptScanning"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableOnAccessProtection" 0 "RTP LSO DisableOnAccessProtection"
    Set-RegDword $rtpKey "LocalSettingOverrideRealtimeScanDirection" 0 "RTP LSO RealtimeScanDirection"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableIOAVProtection" 0 "RTP LSO DisableIOAVProtection"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableBehaviorMonitoring" 0 "RTP LSO DisableBehaviorMonitoring"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableIntrusionPreventionSystem" 0 "RTP LSO DisableIntrusionPreventionSystem"
    Set-RegDword $rtpKey "LocalSettingOverrideDisableRealtimeMonitoring" 0 "RTP LSO DisableRealtimeMonitoring"
    Set-RegDword $rtpKey "RealtimeScanDirection" 2 "RTP RealtimeScanDirection"
    Set-RegDword $rtpKey "DisableInformationProtectionControl" 1 "RTP DisableInformationProtectionControl"
    Set-RegDword $rtpKey "DisableIntrusionPreventionSystem" 1 "RTP DisableIntrusionPreventionSystem"
    Set-RegDword $rtpKey "DisableRawWriteNotification" 1 "RTP DisableRawWriteNotification"

    # --- Subkey: Spynet ---
    $spynetKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"

    Set-RegDword $spynetKey "DisableBlockAtFirstSeen" 1 "Spynet DisableBlockAtFirstSeen"
    Set-RegDword $spynetKey "LocalSettingOverrideSpynetReporting" 0 "Spynet LocalSettingOverrideSpynetReporting"
    Set-RegDword $spynetKey "SpynetReporting" 0 "Spynet SpynetReporting"
    Set-RegDword $spynetKey "SubmitSamplesConsent" 2 "Spynet SubmitSamplesConsent"

    # --- Subkey: Signature Updates ---
    $signatureKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates"

    Set-RegDword $signatureKey "SignatureDisableNotification" 1 "SignatureUpdates SignatureDisableNotification"
    Set-RegDword $signatureKey "RealtimeSignatureDelivery" 0 "SignatureUpdates RealtimeSignatureDelivery"
    Set-RegDword $signatureKey "ForceUpdateFromMU" 0 "SignatureUpdates ForceUpdateFromMU"
    Set-RegDword $signatureKey "DisableScheduledSignatureUpdateOnBattery" 1 "SignatureUpdates DisableScheduledSignatureUpdateOnBattery"
    Set-RegDword $signatureKey "UpdateOnStartUp" 0 "SignatureUpdates UpdateOnStartUp"
    Set-RegDword $signatureKey "SignatureUpdateCatchupInterval" 2 "SignatureUpdates SignatureUpdateCatchupInterval"
    Set-RegDword $signatureKey "DisableUpdateOnStartupWithoutEngine" 1 "SignatureUpdates DisableUpdateOnStartupWithoutEngine"
    Set-RegDword $signatureKey "ScheduleTime" 1440 "SignatureUpdates ScheduleTime"
    Set-RegDword $signatureKey "DisableScanOnUpdate" 1 "SignatureUpdates DisableScanOnUpdate"

    # --- Subkey: Scan ---
    $scanKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan"

    Set-RegDword $scanKey "LowCpuPriority" 1 "Scan LowCpuPriority"
    Set-RegDword $scanKey "DisableRestorePoint" 1 "Scan DisableRestorePoint"
    Set-RegDword $scanKey "DisableArchiveScanning" 0 "Scan DisableArchiveScanning"
    Set-RegDword $scanKey "DisableScanningNetworkFiles" 0 "Scan DisableScanningNetworkFiles"
    Set-RegDword $scanKey "DisableCatchupFullScan" 0 "Scan DisableCatchupFullScan"
    Set-RegDword $scanKey "DisableCatchupQuickScan" 1 "Scan DisableCatchupQuickScan"
    Set-RegDword $scanKey "DisableEmailScanning" 0 "Scan DisableEmailScanning"
    Set-RegDword $scanKey "DisableHeuristics" 1 "Scan DisableHeuristics"
    Set-RegDword $scanKey "DisableReparsePointScanning" 1 "Scan DisableReparsePointScanning"

    # --- Subkey: UX Configuration ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration" "SuppressRebootNotification" 1 "UX SuppressRebootNotification"

    # --- Subkey: Reporting ---
    $reportingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting"

    Set-RegDword $reportingKey "DisableEnhancedNotifications" 1 "Reporting DisableEnhancedNotifications"
    Set-RegDword $reportingKey "DisableGenericRePorts" 1 "Reporting DisableGenericRePorts"
    Set-RegDword $reportingKey "WppTracingLevel" 0 "Reporting WppTracingLevel"
    Set-RegDword $reportingKey "WppTracingComponents" 0 "Reporting WppTracingComponents"

    # --- Subkey: MpEngine ---
    $mpEngineKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine"

    Set-RegDword $mpEngineKey "MpEnablePus" 0 "MpEngine MpEnablePus"
    Set-RegDword $mpEngineKey "MpCloudBlockLevel" 0 "MpEngine MpCloudBlockLevel"
    Set-RegDword $mpEngineKey "MpBafsExtendedTimeout" 0 "MpEngine MpBafsExtendedTimeout"
    Set-RegDword $mpEngineKey "EnableFileHashComputation" 0 "MpEngine EnableFileHashComputation"

    # --- Subkey: NIS Consumers IPS ---
    $nisKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS"

    Set-RegDword $nisKey "ThrottleDetectionEventsRate" 0 "NIS ThrottleDetectionEventsRate"
    Set-RegDword $nisKey "DisableSignatureRetirement" 1 "NIS DisableSignatureRetirement"
    Set-RegDword $nisKey "DisableProtocolRecognition" 1 "NIS DisableProtocolRecognition"

    # --- Subkey: Policy Manager ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" "DisableScanningNetworkFiles" 1 "PolicyManager DisableScanningNetworkFiles"

    # --- Subkey: Exclusions ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions" "DisableAutoExclusions" 1 "Exclusions DisableAutoExclusions"

    # --- Subkey: Exploit Guard ---
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access" "EnableControlledFolderAccess" 0 "ExploitGuard ControlledFolderAccess"
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection" "EnableNetworkProtection" 0 "ExploitGuard NetworkProtection"

    # --- Legacy path: Microsoft Antimalware ---
    $legacyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware"

    Set-RegDword $legacyKey "ServiceKeepAlive" 0 "Legacy ServiceKeepAlive"
    Set-RegDword $legacyKey "AllowFastServiceStartup" 0 "Legacy AllowFastServiceStartup"
    Set-RegDword $legacyKey "DisableRoutinelyTakingAction" 1 "Legacy DisableRoutinelyTakingAction"
    Set-RegDword $legacyKey "DisableAntiSpyware" 1 "Legacy DisableAntiSpyware"
    Set-RegDword $legacyKey "DisableAntiVirus" 1 "Legacy DisableAntiVirus"
    Set-RegDword "$legacyKey\SpyNet" "SpyNetReporting" 0 "Legacy SpyNet SpyNetReporting"
    Set-RegDword "$legacyKey\SpyNet" "LocalSettingOverrideSpyNetReporting" 0 "Legacy SpyNet LocalSettingOverrideSpyNetReporting"

    # --- WOW6432Node (32-bit compatibility) ---
    Set-RegDword "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender" "DisableRoutinelyTakingAction" 1 "WOW6432Node DisableRoutinelyTakingAction"

    # --- Smart App Control state ---
    Set-RegDword "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" "VerifiedAndReputablePolicyState" 0 "SmartAppControl VerifiedAndReputablePolicyState"

    # --- SmartScreen ---
    # HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen
    $smartScreenKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen"

    Set-RegDword $smartScreenKey "Enabled" 0 "SmartScreen Enabled"
    Set-RegDword $smartScreenKey "EnableSmartScreenInShell" 0 "SmartScreen EnableSmartScreenInShell"
    Set-RegDword $smartScreenKey "ConfigureAppInstallControlEnabled" 1 "SmartScreen ConfigureAppInstallControlEnabled"
    Set-RegString $smartScreenKey "ConfigureAppInstallControl" "Anywhere" "SmartScreen ConfigureAppInstallControl"

    # HKLM\SOFTWARE\Policies\Microsoft\Windows\System
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0 "System EnableSmartScreen"

    # HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer
    Set-RegString "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "Explorer SmartScreenEnabled"

    # --- Edge SmartScreen ---
    $edgeSmartScreenKey = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter"
    Set-RegDword $edgeSmartScreenKey "EnabledV9" 0 "Edge SmartScreen EnabledV9"
    Set-RegDword $edgeSmartScreenKey "PreventOverride" 0 "Edge SmartScreen PreventOverride"

    # HKCU Edge SmartScreen
    Set-RegDword "HKCU:\Software\Microsoft\Edge" "SmartScreenEnabled" 0 "HKCU Edge SmartScreenEnabled"

    # HKCU AppHost (Microsoft Store apps SmartScreen)
    $appHostKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost"
    Set-RegDword $appHostKey "EnableWebContentEvaluation" 0 "AppHost EnableWebContentEvaluation"
    Set-RegDword $appHostKey "PreventOverride" 0 "AppHost PreventOverride"

    # PolicyManager SmartScreen defaults
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen" "value" 0 "PolicyManager Browser AllowSmartScreen"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell" "value" 0 "PolicyManager SmartScreen InShell"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl" "value" 0 "PolicyManager SmartScreen AppInstallControl"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell" "value" 0 "PolicyManager SmartScreen PreventOverrideForFiles"

    # --- Security Center notifications ---
    $wdscNotifKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
    Set-RegDword $wdscNotifKey "DisableEnhancedNotifications" 1 "WDSC DisableEnhancedNotifications"
    Set-RegDword $wdscNotifKey "DisableNotifications" 1 "WDSC DisableNotifications"

    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Security Center" "FirstRunDisabled" 1 "SecurityCenter FirstRunDisabled"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Security Center" "AntiVirusOverride" 1 "SecurityCenter AntiVirusOverride"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Security Center" "FirewallOverride" 1 "SecurityCenter FirewallOverride"

    # HKCU Security and Maintenance toast notification
    Set-RegDword "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" "Enabled" 0 "SecurityToast Enabled"

    # --- Stop Windows Defender Service ---
    Write-Host ""
    Write-Host "[Windows Defender Service]" -ForegroundColor Cyan
    $defenderSvc = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    if ($defenderSvc) {
        try {
            Stop-Service -Name "WinDefend" -Force -ErrorAction Stop
            Set-Service -Name "WinDefend" -StartupType Disabled -ErrorAction Stop
            Write-Host "[OK] Windows Defender Service stopped and disabled"
            $ok++
        } catch {
            Write-Host "[FAIL] Windows Defender Service : $($_.Exception.Message)" -ForegroundColor Red
            $fail++
        }
    } else {
        Write-Host "[SKIP] Windows Defender Service not found (already removed or not installed)" -ForegroundColor Yellow
        $skip++
    }

    # --- Optional: Deletion-type optimizations (Y/N) ---
    Write-Host ""
    Write-Host "[删除类优化 / Deletion-type Optimizations]" -ForegroundColor Cyan
    Write-Host " 包括：停止并禁用 Defender 相关服务、删除 Defender 计划任务、" -ForegroundColor Gray
    Write-Host " 删除安全中心自启动项、移除安全中心界面 (SecHealthUI)。" -ForegroundColor Gray
    $delChoice = Read-Host "是否执行删除类优化？Y = 确定 / N = 取消跳过 (Y = yes, N = no)"
    if ($delChoice -eq "Y" -or $delChoice -eq "y") {

        # 1) Stop + disable Defender related services
        Write-Host ""
        Write-Host "[Defender Services: stop + disable]" -ForegroundColor Cyan
        $defenderServices = @(
            "WinDefend","WdNisSvc","WdNisDrv","WdBoot","WdFilter","wscsvc",
            "SgrmAgent","SgrmBroker","MsSecCore","MsSecFlt","MsSecWfp","whesvc",
            "webthreatdefsvc","webthreatdefusersvc","PlutonHsp2","PlutonHeci","Hsp"
        )
        foreach ($svc in $defenderServices) {
            $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($svcObj) {
                try {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                    Write-Host "[OK] Service $svc stopped and disabled"
                    $ok++
                } catch {
                    & sc.exe config $svc start= disabled *> $null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[OK] Service $svc disabled (stop rejected: protected service)"
                        $ok++
                    } else {
                        Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                        $fail++
                    }
                }
            } else {
                Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
                $skip++
            }
        }

        # 2) Delete Defender scheduled tasks
        Write-Host ""
        Write-Host "[Defender Scheduled Tasks]" -ForegroundColor Cyan
        $defenderTasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" -ErrorAction SilentlyContinue
        if ($defenderTasks) {
            foreach ($task in $defenderTasks) {
                try {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Host ("[OK] Task deleted: {0}{1}" -f $task.TaskPath, $task.TaskName)
                    $ok++
                } catch {
                    Write-Host ("[FAIL] Task {0}{1} : {2}" -f $task.TaskPath, $task.TaskName, $_.Exception.Message) -ForegroundColor Red
                    $fail++
                }
            }
        } else {
            Write-Host "[SKIP] No Defender scheduled tasks found" -ForegroundColor Yellow
            $skip++
        }

        # 3) Remove SecurityHealth / Windows Defender startup entries
        Write-Host ""
        Write-Host "[Startup Entries]" -ForegroundColor Cyan
        $startupItems = @(
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "SecurityHealth" },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; Name = "SecurityHealth" },
            @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Windows Defender" },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "WindowsDefender" }
        )
        foreach ($item in $startupItems) {
            $existing = Get-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
            if ($existing) {
                try {
                    Remove-ItemProperty -Path $item.Path -Name $item.Name -Force -ErrorAction Stop
                    Write-Host ("[OK] Startup entry removed: {0} -> {1}" -f $item.Path, $item.Name)
                    $ok++
                } catch {
                    Write-Host ("[FAIL] Startup entry {0} -> {1} : {2}" -f $item.Path, $item.Name, $_.Exception.Message) -ForegroundColor Red
                    $fail++
                }
            } else {
                Write-Host ("[SKIP] Startup entry not found: {0} -> {1}" -f $item.Path, $item.Name) -ForegroundColor Yellow
                $skip++
            }
        }

        # 4) Remove Security Center UI (SecHealthUI)
        Write-Host ""
        Write-Host "[Security Center UI (SecHealthUI)]" -ForegroundColor Cyan
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            try {
                $secApp = Get-AppxPackage -Name "Microsoft.SecHealthUI" -ErrorAction SilentlyContinue
                if ($secApp) {
                    $secApp | Remove-AppxPackage -ErrorAction Stop
                    Write-Host "[OK] SecHealthUI (Windows Security app) removed"
                    $ok++
                } else {
                    Write-Host "[SKIP] SecHealthUI not found" -ForegroundColor Yellow
                    $skip++
                }
            } catch {
                Write-Host "[FAIL] SecHealthUI : $($_.Exception.Message)" -ForegroundColor Red
                $fail++
            }
        } else {
            Write-Host "[SKIP] Appx module not available on this system" -ForegroundColor Yellow
            $skip++
        }

    } else {
        Write-Host "[SKIP] 删除类优化已取消/跳过 / Deletion-type optimizations skipped." -ForegroundColor Yellow
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 5 - Disable Security Center)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：Windows Defender 已被禁用，重启后生效。" -ForegroundColor Yellow
    Write-Host "策略禁用与删除类操作没有统一的自动原始状态回滚；恢复前请根据详情文档检查策略、服务、计划任务和 SecHealthUI 状态。" -ForegroundColor Yellow

    Request-Restart

} elseif ($choice -eq "6") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 6: 优化服务项 =======================
    # 独立步骤：禁用可安全禁用的服务 + 将 Xbox / 蓝牙 / 嵌入模式服务恢复为手动
    Write-Host ""
    Write-Host "============ [Part 6] 优化服务项继续工作 / Service Optimization ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 执行服务优化（A+B 两组共 30 个服务全部处理，另将 7 个服务改为 Manual）" -ForegroundColor White
    Write-Host "  2. 按 service-backup.json 恢复目标服务原始启动类型" -ForegroundColor White
    $serviceChoice = Read-Host "请输入 1 或 2 并回车"
    if ($serviceChoice -eq '2') {
        Restore-ServiceBackup | Out-Null
        Write-Host "[提示] 服务运行状态不强制恢复；如需立即应用启动类型，请重启。" -ForegroundColor Yellow
        Request-Restart
    } elseif ($serviceChoice -eq '1') {

    # 1) Disable service groups
    # A：通常可在不需要对应功能时禁用
    Write-Host "[Service Group A: 通常可禁用 / stop + disable]" -ForegroundColor Cyan
    $groupAServices = @(
        "DialogBlockingService","TrkWks","AppVClient","MsKeyboardFilter",
        "NetTcpPortSharing","CscService","ssh-agent","RemoteRegistry",
        "RemoteAccess","SensorDataService","SensrSvc","shpamsvc",
        "UevAgentService","WalletService","wisvc","WSAIFabricSvc",
        "dmwappushservice","DusmSvc","tzautoupdate","edgeupdate","edgeupdatem"
    )

    # B：按需禁用，可能影响诊断、兼容性、打印、搜索或预读功能
    Write-Host "[Service Group B: 按需禁用 / stop + disable]" -ForegroundColor Cyan
    $groupBServices = @(
        "DPS","WdiServiceHost","WdiSystemHost","diagsvc",
        "PhoneSvc","PcaSvc","Spooler","WSearch","SysMain"
    )

    $disableServices = @($groupAServices + $groupBServices)
    $manualServices = @(
        "XboxGipSvc","XblAuthManager","XboxNetApiSvc","XblGameSave","bthserv","embeddedmode","BITS"
    )
    $allServiceNames = @($disableServices + $manualServices)
    if (-not (Ensure-ServiceBackup $allServiceNames)) {
        Write-Host "[ABORTED] 服务备份不可用，未修改服务" -ForegroundColor Red
    } else {
    foreach ($svc in $disableServices) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            try {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                Write-Host "[OK] Service $svc stopped and disabled"
                $ok++
            } catch {
                & sc.exe config $svc start= disabled *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Service $svc disabled (stop rejected: protected service)"
                    $ok++
                } else {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            }
        } else {
            Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
            $skip++
        }
    }

    # 2) Set Xbox / Bluetooth / Embedded / BITS services to Manual
    Write-Host ""
    Write-Host "[Manual Services: Xbox / Bluetooth / Embedded / BITS]" -ForegroundColor Cyan
    foreach ($svc in $manualServices) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            try {
                Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
                Write-Host "[OK] Service $svc StartupType = Manual"
                $ok++
            } catch {
                & sc.exe config $svc start= demand *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Service $svc StartupType = Manual (sc.exe)"
                    $ok++
                } else {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            }
        } else {
            Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
            $skip++
        }
    }

    Write-Host ""
    Write-Host "[Post-Apply Verification / 服务启动类型验证]" -ForegroundColor Cyan
    foreach ($svc in $groupAServices) {
        Verify-ServiceStartupType $svc "Disabled" "Group A / $svc" | Out-Null
    }
    foreach ($svc in $groupBServices) {
        Verify-ServiceStartupType $svc "Disabled" "Group B / $svc" | Out-Null
    }
    foreach ($svc in $manualServices) {
        Verify-ServiceStartupType $svc "Manual" $svc | Out-Null
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 6 - Service Optimization)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    Request-Restart
    }
    } else {
        Write-Host "[ERROR] 无效输入：$serviceChoice 。请输入 1 或 2" -ForegroundColor Red
    }

} elseif ($choice -eq "7") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 7: 应用超性能电源计划 =======================
    # 独立步骤：备份当前电源计划 -> 导入并应用仓库自带的超性能计划 / 或恢复备份
    Write-Host ""
    Write-Host "============ [Part 7] 应用超性能电源计划 / Ultimate Performance Power Plan ============" -ForegroundColor Cyan
    Write-Host ""

    $planFile   = Join-Path $PSScriptRoot "ultimate-performance.pow"
    $backupFile = Join-Path $PSScriptRoot "power-backup.pow"

    Write-Host "  1. 备份当前电源计划，然后导入并应用超性能电源计划" -ForegroundColor White
    Write-Host "  2. 恢复之前备份的电源计划" -ForegroundColor White
    $pChoice = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"

    if ($pChoice -eq "1") {

        if (-not (Test-Path $planFile)) {
            Write-Host "[FAIL] 未找到 ultimate-performance.pow（需与本脚本放在同一目录）" -ForegroundColor Red
            $fail++
        } else {

            # 1) Backup current active scheme (keep the earliest backup)
            if (Test-Path $backupFile) {
                Write-Host "[SKIP] 备份文件已存在，不覆盖（保护最初的原计划备份）: $backupFile" -ForegroundColor Yellow
                $skip++
            } else {
                try {
                    $activeOut = & powercfg.exe /getactivescheme 2>$null
                    if ($activeOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                        $activeGuid = $Matches[1]
                    } else {
                        throw "无法解析当前电源计划 GUID"
                    }
                    & powercfg.exe /export $backupFile $activeGuid *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /export exit code $LASTEXITCODE" }
                    Write-Host "[OK] 当前电源计划已备份: $backupFile ($activeGuid)"
                    $ok++
                } catch {
                    Write-Host "[FAIL] 备份当前电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            }

            # 2) Import bundled plan and apply
            if (Test-Path $backupFile) {
                try {
                    $importOut = & powercfg.exe /import $planFile 2>$null
                    if ($importOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                        $newGuid = $Matches[1]
                    } else {
                        throw "无法解析导入后的计划 GUID（ultimate-performance.pow 可能已损坏）"
                    }
                    & powercfg.exe /setactive $newGuid *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive exit code $LASTEXITCODE" }
                    Write-Host "[OK] 超性能电源计划已导入并应用 ($newGuid)"
                    $ok++
                    $script:rebootRequired = $true
                } catch {
                    Write-Host "[FAIL] 导入/应用超性能电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                    $fail++
                }
            } else {
                Write-Host "[SKIP] 备份失败，为安全起见跳过应用超性能计划" -ForegroundColor Yellow
                $skip++
            }
        }

    } elseif ($pChoice -eq "2") {

        # Restore previously backed-up scheme
        if (-not (Test-Path $backupFile)) {
            Write-Host "[FAIL] 未找到备份文件 power-backup.pow（请先执行子选项 1 生成备份）" -ForegroundColor Red
            $fail++
        } else {
            try {
                $importOut = & powercfg.exe /import $backupFile 2>$null
                if ($importOut -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                    $newGuid = $Matches[1]
                } else {
                    throw "无法解析导入后的计划 GUID（power-backup.pow 可能已损坏）"
                }
                & powercfg.exe /setactive $newGuid *> $null
                if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive exit code $LASTEXITCODE" }
                Write-Host "[OK] 已恢复备份的电源计划 ($newGuid)"
                $ok++
                $script:rebootRequired = $true
            } catch {
                Write-Host "[FAIL] 恢复备份的电源计划 : $($_.Exception.Message)" -ForegroundColor Red
                $fail++
            }
        }

    } else {
        Write-Host "[ERROR] 无效输入：$pChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 7 - Ultimate Performance Power Plan)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：可用 powercfg /getactivescheme 查看当前电源计划；" -ForegroundColor Yellow
    Write-Host "如需恢复原计划，再次运行本脚本并选择 7 -> 2。" -ForegroundColor Yellow

    Request-Restart

} elseif ($choice -eq "8") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 8: Native NVMe Driver =======================
    # Preferred path: ViVeTool feature IDs 60786016 + 48433719.
    # Legacy registry overrides are retained only for compatibility/inspection and
    # are no longer treated as proof that the native driver is active.
    Write-Host ""
    Write-Host "============ [Part 8] 原生 NVMe 驱动 / Native NVMe Driver (nvmedisk.sys) ============" -ForegroundColor Cyan
    Write-Host ""

    $cvKey = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildNum = [int]($cvKey.GetValue('CurrentBuildNumber'))
    $dispVer = [string]($cvKey.GetValue('DisplayVersion'))
    $nvmeDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'NVMe' })
    $sbGuid = '{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}'
    $fmPath = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
    $legacyIds = @('735209102', '1853569164', '156965516')
    $viVe = Find-ViVeTool

    Write-Host ("系统版本 : $dispVer (build $buildNum)")
    Write-Host ("NVMe 磁盘 : " + $(if ($nvmeDisks.Count -gt 0) { "检测到 $($nvmeDisks.Count) 块" } else { "未检测到" }))
    Write-Host ("ViVeTool : " + $(if ($viVe) { $viVe } else { "未找到" }))
    Write-Host ""

    Write-Host "  0. 查看当前状态（Feature / SafeBoot / Legacy Override / nvmedisk 实际状态）" -ForegroundColor White
    Write-Host "  1. 启用 Native NVMe（ViVeTool 60786016 + 48433719）" -ForegroundColor White
    Write-Host "  2. 还原到启用前快照" -ForegroundColor White
    $nChoice = Read-Host "请输入 0、1 或 2 并回车"

    if ($nChoice -eq '0') {

        if ($viVe) {
            $cfg = Test-NativeNvmeConfigured $viVe
            Write-Host "ViVeTool 60786016 : $($cfg.Feature60786016)"
            Write-Host "ViVeTool 48433719 : $($cfg.Feature48433719)"
        } else {
            Write-Host "ViVeTool 60786016 : <无法查询>"
            Write-Host "ViVeTool 48433719 : <无法查询>"
        }

        $fmItem0 = Get-Item $fmPath -ErrorAction SilentlyContinue
        $legacyText = @()
        foreach ($id in $legacyIds) {
            if ($fmItem0 -and ($fmItem0.GetValueNames() -contains $id)) {
                $kind = $fmItem0.GetValueKind($id).ToString()
                $value = $fmItem0.GetValue($id)
                $legacyText += "$id=$value（$kind）"
            } else {
                $legacyText += "$id=未写入"
            }
        }
        Write-Host ("Legacy Feature Override : " + ($legacyText -join "  "))

        foreach ($mode in @('Minimal','Network')) {
            $sbPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
            if (Test-Path $sbPath) {
                $item = Get-Item $sbPath -ErrorAction SilentlyContinue
                $defaultValue = if ($item -and ($item.GetValueNames() -contains '')) { $item.GetValue('') } else { '<默认值缺失>' }
                Write-Host ("SafeBoot {0} : 已配置，Default={1}" -f $mode, $defaultValue)
            } else {
                Write-Host ("SafeBoot {0} : 未配置" -f $mode)
            }
        }

        $effective = Test-NativeNvmeEffective
        Write-Host ("nvmedisk.sys 文件 : " + $(if ($effective.FileExists) { "存在" } else { "不存在" }))
        Write-Host ("nvmedisk 驱动状态 : $($effective.State)")

        if ($effective.State -eq 'Running') {
            Write-Host "[EFFECTIVE] Native NVMe 已实际生效，当前 nvmedisk 驱动正在运行。" -ForegroundColor Green
        } elseif ($viVe -and (Test-NativeNvmeConfigured $viVe).BothEnabled) {
            Write-Host "[CONFIGURED] 两个 Feature 已启用，但当前尚未确认 nvmedisk 实际运行；请重启后再次执行 8 -> 0。" -ForegroundColor Yellow
        } elseif ($effective.FileExists) {
            Write-Host "[NOT EFFECTIVE] 系统存在 nvmedisk.sys，但当前未确认由它运行。" -ForegroundColor Yellow
        } else {
            Write-Host "[NOT ENABLED] 当前未确认 Native NVMe 生效。" -ForegroundColor Yellow
        }

    } elseif ($nChoice -eq '1') {

        if ($nvmeDisks.Count -eq 0) {
            Write-Host "[SKIP] 未检测到 NVMe 磁盘，本项无作用，不修改。" -ForegroundColor Yellow
        } elseif ($buildNum -lt 26200) {
            Write-Host "[ABORTED] build $buildNum 低于 26200；此模块仅针对 Windows 11 25H2+（26200+）。" -ForegroundColor Red
        } elseif (-not $viVe) {
            Write-Host "[ABORTED] 未找到 ViVeTool.exe。" -ForegroundColor Red
            Write-Host "请从官方 ViVeTool 发布页获取与系统架构匹配的版本，并将 ViVeTool.exe 放在本脚本目录或加入 PATH。" -ForegroundColor Yellow
        } elseif (-not (Ensure-NvmeBackup $sbGuid $viVe $fmPath)) {
            Write-Host "[ABORTED] Native NVMe 备份不可用，未执行修改。" -ForegroundColor Red
        } else {

            Write-Host ""
            Write-Host "[1/3] 启用 Native NVMe Feature：60786016 + 48433719" -ForegroundColor Cyan
            & $viVe /enable /id:60786016,48433719 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[FAIL] ViVeTool 启用 Feature 失败，未继续修改 SafeBoot。" -ForegroundColor Red
                $fail++
            } else {
                $cfgAfter = Test-NativeNvmeConfigured $viVe
                if (-not $cfgAfter.BothEnabled) {
                    Write-Host "[WARN] ViVeTool 命令完成，但查询不到两个 Feature 都为 Enabled；停止后续修改。" -ForegroundColor Yellow
                    $fail++
                } else {
                    Write-Host "[OK] 60786016 + 48433719 = Enabled" -ForegroundColor Green
                    $ok += 2
                    $script:rebootRequired = $true

                    Write-Host ""
                    Write-Host "[2/3] SafeBoot NVMe 加固" -ForegroundColor Cyan
                    $safeBootOk = $true
                    foreach ($mode in @('Minimal','Network')) {
                        $sbReg = Convert-RegExePath "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\$mode\$sbGuid"
                        & reg.exe ADD $sbReg /ve /t REG_SZ /d "Storage Disks" /f *> $null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[OK] SafeBoot $mode = Storage Disks"
                            $script:ok++
                        } else {
                            Write-Host "[FAIL] SafeBoot $mode : reg.exe exit code $LASTEXITCODE" -ForegroundColor Red
                            $script:fail++
                            $safeBootOk = $false
                        }
                    }

                    if (-not $safeBootOk) {
                        Write-Host "[FAIL] SafeBoot 配置未完整完成，正在按启用前 Version 3 快照回滚。" -ForegroundColor Red
                        Restore-NvmeSafeBootBackup $sbGuid $viVe $fmPath | Out-Null
                        $script:rebootRequired = $false
                    } else {
                        Write-Host ""
                        Write-Host "[3/3] Legacy Override 兼容说明" -ForegroundColor Cyan
                        Write-Host "[INFO] 保留现有 735209102 / 1853569164 / 156965516，不再自动写入或删除它们。" -ForegroundColor Yellow
                        Write-Host "[INFO] 这些旧值仍可在 8 -> 0 中查看，但不再作为 Native NVMe 已生效的判断依据。" -ForegroundColor Yellow

                        Write-Host ""
                        Write-Host "配置已完成，但必须重启后才能确认实际驱动。" -ForegroundColor Yellow
                        Write-Host "重启后执行：8 -> 0" -ForegroundColor Yellow
                        Write-Host "真正成功条件：nvmedisk 驱动状态 = Running。" -ForegroundColor Yellow
                        Request-Restart
                    }
                }
            }
        }

    } elseif ($nChoice -eq '2') {

        if (-not $viVe) {
            Write-Host "[ABORTED] 未找到 ViVeTool.exe，无法精确恢复 Feature 状态。" -ForegroundColor Red
            Write-Host "请将与启用时相同的 ViVeTool.exe 放回脚本目录或 PATH，再执行 8 -> 2。" -ForegroundColor Yellow
            $fail++
        } else {
            Restore-NvmeSafeBootBackup $sbGuid $viVe $fmPath | Out-Null
            Request-Restart
        }

    } else {
        Write-Host "[ERROR] 无效输入：$nChoice 。请输入 0、1 或 2" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 8 - Native NVMe Driver)" -ForegroundColor Cyan
    Write-Host " OK : $ok" -ForegroundColor Green
    Write-Host " FAIL : $fail" -ForegroundColor Red
    Write-Host " SKIP : $skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
} elseif ($choice -eq "9") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 9: 清除 Device Guard EFI 锁定 =======================
    # 应对 UEFI 锁定：选项 10 的关闭子项可通过注册表关闭 VBS/HVCI/Credential Guard，
    # 但 安全中心 / msinfo32 仍显示"内存完整性"或"凭据保护"开启时，
    # 用 SecConfig.efi 引导清除 EFI 变量（硬手段，等效于官方 DG_Readiness_Tool）。
    Write-Host ""
    Write-Host "============ [Part 9] 清除 Device Guard EFI 锁定 / Clear DG UEFI Lock (SecConfig.efi) ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 适用场景：UEFI 锁定 —— 已运行选项 10（注册表关闭），但 安全中心/msinfo32 仍显示" -ForegroundColor Yellow
    Write-Host "            内核隔离-内存完整性 或 凭据保护 处于开启状态。" -ForegroundColor Yellow
    Write-Host " 原理：把 SecConfig.efi 设为一次性引导项，开机进入后清除 Device Guard 的 EFI 变量。" -ForegroundColor Yellow
    Write-Host ""

    $dgGuid = '{0cb3b571-2f2e-4343-a879-d86a476d7215}'

    Write-Host "  1. 执行（BitLocker 预检查 -> 挂载 EFI 分区 -> 复制 SecConfig.efi -> 配置一次性引导项）" -ForegroundColor White
    Write-Host "  2. 清理（删除一次性引导项、清空引导序列、卸载 EFI 分区盘符；不重启）" -ForegroundColor White
    $gChoice = Read-Host "请输入 1 或 2 并回车 (Enter 1 or 2)"

    if ($gChoice -eq "1") {

        Write-Host ""
        Write-Host " [WARNING] 执行后重启时，开机会出现一个确认界面，需按屏幕提示按键（通常为 F3）确认" -ForegroundColor Yellow
        Write-Host "           禁用 Credential Guard；错过或拒绝则本次不生效（一次性引导项不会再次出现，可重跑）。" -ForegroundColor Yellow
        Write-Host " [WARNING] 若机器开启了 BitLocker，清除 EFI 变量会改变 TPM 度量值，可能触发恢复模式" -ForegroundColor Yellow
        Write-Host "           （要求输入 48 位恢复密钥）。本选项已内置 BitLocker 预检查，检测到已开启会拒绝执行。" -ForegroundColor Yellow
        $confirmDg = Read-Host "确定执行吗？(Y = 执行 / N = 取消)"
        if ($confirmDg -notin @('Y','y')) {
            Write-Host "[SKIP] 已取消，未做任何修改（不重启）" -ForegroundColor Yellow
        } else {

            # 1) BitLocker 预检查：任一分区保护开启或状态无法确认都拒绝执行
            $blBlocked = $false
            $blCheckFailed = $false
            try {
                $blOn = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' })
                if ($blOn.Count -gt 0) {
                    $blBlocked = $true
                    Write-Host "[FAIL] 检测到 BitLocker 保护已开启，为避免触发恢复模式，已拒绝执行：" -ForegroundColor Red
                    foreach ($v in $blOn) {
                        Write-Host ("        {0}  {1}" -f $v.MountPoint, $v.VolumeStatus) -ForegroundColor Red
                    }
                    Write-Host "        请先暂停保护（Suspend-BitLocker，可维持数次重启）或彻底解密后再运行本选项" -ForegroundColor Yellow
                    $fail++
                } else {
                    Write-Host "[OK] BitLocker 预检查通过（未开启保护，无恢复模式风险）"
                    $ok++
                }
            } catch {
                $blCheckFailed = $true
                Write-Host "[FAIL] 无法查询 BitLocker 状态：$($_.Exception.Message)；已拒绝 EFI 修改" -ForegroundColor Red
                $fail++
            }

            if (-not $blBlocked -and -not $blCheckFailed) {

                # 2) SecConfig.efi 源文件检查
                $secSrc = Join-Path $env:SystemRoot 'System32\SecConfig.efi'
                if (-not (Test-Path $secSrc)) {
                    Write-Host "[FAIL] 未找到 $secSrc，当前系统不带此文件，无法执行" -ForegroundColor Red
                    $fail++
                } else {

                    # 3) 选择空闲盘符并挂载 EFI 分区
                    $efiLetter = $null
                    foreach ($l in @('X','Y','Z','V','W','U')) {
                        if (-not (Test-Path "$($l):\")) { $efiLetter = $l; break }
                    }
                    if (-not $efiLetter) {
                        Write-Host "[FAIL] 找不到空闲盘符（X/Y/Z/V/W/U 均被占用）" -ForegroundColor Red
                        $fail++
                    } else {
                        $mounted = $false
                        try {
                            & mountvol.exe "$($efiLetter):" /s *> $null
                            if ($LASTEXITCODE -ne 0) { throw "mountvol exit code $LASTEXITCODE" }
                            $mounted = $true
                            Write-Host "[OK] EFI 分区已挂载到 $($efiLetter):"
                            $ok++
                        } catch {
                            Write-Host "[FAIL] 挂载 EFI 分区失败（本机可能非 UEFI 启动）：$($_.Exception.Message)" -ForegroundColor Red
                            $fail++
                        }

                        if ($mounted) {

                            # 4) 复制 SecConfig.efi 到 EFI 分区（复制成功才配置引导项）
                            $copyOk = $false
                            try {
                                $bootDir = "$($efiLetter):\EFI\Microsoft\Boot"
                                if (-not (Test-Path $bootDir)) { New-Item -ItemType Directory -Path $bootDir -Force | Out-Null }
                                Copy-Item $secSrc (Join-Path $bootDir 'SecConfig.efi') -Force -ErrorAction Stop
                                $copyOk = $true
                                Write-Host "[OK] SecConfig.efi 已复制到 $bootDir"
                                $ok++
                            } catch {
                                Write-Host "[FAIL] 复制 SecConfig.efi : $($_.Exception.Message)" -ForegroundColor Red
                                $fail++
                            }

                            $efiConfigured = $false
                            if ($copyOk) {

                                # 5) 配置一次性引导项；任一步失败都停止并清理临时项
                                & bcdedit.exe /delete $dgGuid /f *> $null
                                $bcdOk = Invoke-BcdEdit "/create $dgGuid /d DebugTool /application osloader" "创建 BCD 引导项 (DebugTool)"
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid path \EFI\Microsoft\Boot\SecConfig.efi" "引导项路径 SecConfig.efi" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid device partition=$($efiLetter):" "引导项设备分区 $($efiLetter):" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set $dgGuid loadoptions DISABLE-LSA-ISO" "LoadOptions = DISABLE-LSA-ISO" }
                                if ($bcdOk) { $bcdOk = Invoke-BcdEdit "/set {bootmgr} bootsequence $dgGuid" "设为下次开机一次性引导" }
                                if ($bcdOk) {
                                    $efiConfigured = $true
                                } else {
                                    Write-Host "[FAIL] EFI 一次性引导配置未完成，正在清理临时 BCD 项" -ForegroundColor Red
                                    & bcdedit.exe /delete $dgGuid /f *> $null
                                    & bcdedit.exe /deletevalue '{bootmgr}' bootsequence *> $null
                                }
                            }

                            # 6) 卸载 EFI 分区
                            & mountvol.exe "$($efiLetter):" /d *> $null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[OK] EFI 分区已卸载（$($efiLetter):）"
                                $ok++
                            } else {
                                Write-Host "[WARN] EFI 分区卸载失败，可稍后手动执行: mountvol $($efiLetter): /d" -ForegroundColor Yellow
                            }

                            if ($efiConfigured) {
                                $script:rebootRequired = $true
                                # Summary
                                Write-Host ""
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host " Finished (Part 9 - Clear DG UEFI Lock)" -ForegroundColor Cyan
                                Write-Host " OK : $ok" -ForegroundColor Green
                                Write-Host " FAIL : $fail" -ForegroundColor Red
                                Write-Host "============================================================" -ForegroundColor Cyan
                                Write-Host ""
                                Write-Host " 重启开机会出现确认界面，请按屏幕提示按键（通常为 F3）确认禁用！" -ForegroundColor Yellow
                                Write-Host " 重启确认后可用 msinfo32 -> 系统摘要 -> 基于虚拟化的安全性 验证是否已关闭。" -ForegroundColor Yellow

                                                    Request-Restart
                            } else {
                                Write-Host ""
                                Write-Host "[提示] EFI 一次性引导配置未完成，未设置待重启状态" -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }

            if ($blBlocked) {
                Write-Host ""
                Write-Host "[提示] 未做任何修改（不重启）" -ForegroundColor Yellow
            }
        }

    } elseif ($gChoice -eq "2") {

        # 1) 删除一次性引导项（如存在）
        & bcdedit.exe /enum $dgGuid *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-BcdEdit "/delete $dgGuid /f" "删除 BCD 引导项 (DebugTool)"
        } else {
            Write-Host "[SKIP] BCD 引导项不存在（无需删除）" -ForegroundColor Yellow
            $skip++
        }

        # 2) 清空 {bootmgr} 的 bootsequence（如仍指向该引导项）
        $bmEnum = & bcdedit.exe /enum '{bootmgr}' 2>$null
        if ($LASTEXITCODE -eq 0 -and ($bmEnum -join "`n") -match 'bootsequence') {
            Invoke-BcdEdit "/deletevalue {bootmgr} bootsequence" "清空一次性引导序列"
        } else {
            Write-Host "[SKIP] bootsequence 未设置（无需清理）" -ForegroundColor Yellow
            $skip++
        }

        # 3) 卸载残留的 EFI 分区盘符（仅当该盘符下存在脚本复制的 SecConfig.efi）
        $unmounted = 0
        foreach ($l in @('X','Y','Z','V','W','U')) {
            if (Test-Path "$($l):\EFI\Microsoft\Boot\SecConfig.efi") {
                & mountvol.exe "$($l):" /d *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] 已卸载 EFI 分区盘符 $($l):"
                    $ok++
                    $unmounted++
                } else {
                    Write-Host "[FAIL] 卸载 $($l): 失败，可手动执行: mountvol $($l): /d" -ForegroundColor Red
                    $fail++
                    $unmounted++
                }
            }
        }
        if ($unmounted -eq 0) {
            Write-Host "[SKIP] 无残留的 EFI 分区挂载" -ForegroundColor Yellow
            $skip++
        }

        # Summary（无需重启）
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 9 - Cleanup)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "提示：清理完成，无需重启。" -ForegroundColor Yellow

    } else {
        Write-Host "[ERROR] 无效输入：$gChoice 。请输入 1 或 2 / Invalid input. Enter 1 or 2." -ForegroundColor Red
    }

} elseif ($choice -eq "10") {
    $script:moduleFailBaseline = $fail
    Write-Host ""; Write-Host "============ [Part 10] 虚拟化 / VBS / Hyper-V 管理 ============" -ForegroundColor Cyan; Write-Host ""
    $dgRegValues=@(@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity';Name='Enabled'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard';Name='EnableVirtualizationBasedSecurity'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\LSA';Name='LsaCfgFlags'},@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard';Name='EnableVirtualizationBasedSecurity'},@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard';Name='RequirePlatformSecurityFeatures'})
    Write-Host "  0. 查看当前状态";Write-Host "  1. 关闭 VBS/HVCI/Credential Guard + Hyper-V" -ForegroundColor Yellow;Write-Host "  2. 删除脚本覆盖并尝试启用 Hyper-V（不是原始状态精确回滚）"
    $vChoice=Read-Host "请输入 0、1 或 2 并回车"
    if($vChoice -eq '0'){
        $bcEnum=(& bcdedit.exe /enum '{current}' 2>$null)-join "`n";foreach($n in @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')){if($bcEnum -match ('(?m)^\s*'+[regex]::Escape($n)+'\s+(\S+)')){Write-Host ("bcdedit {0,-24} = {1}"-f $n,$Matches[1])}else{Write-Host ("bcdedit {0,-24} = <未设置（系统默认）>"-f $n)}};foreach($v in $dgRegValues){$item=Get-Item $v.Path -ErrorAction SilentlyContinue;if($item -and ($item.GetValueNames()-contains $v.Name)){Write-Host ("注册表 {0} -> {1} = {2}"-f $v.Path,$v.Name,$item.GetValue($v.Name))}};foreach($fn in @('Microsoft-Hyper-V-All','VirtualMachinePlatform','HypervisorPlatform')){$f=Get-WindowsOptionalFeature -Online -FeatureName $fn -ErrorAction SilentlyContinue;if($f){Write-Host ("功能 {0,-26} = {1}"-f $fn,$f.State)}};$cs=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue;if($cs){Write-Host ("运行时 HypervisorPresent = {0}"-f $cs.HypervisorPresent)}
    } elseif($vChoice -eq '1'){
        foreach($v in $dgRegValues){Set-RegDword $v.Path $v.Name 0 ("关闭虚拟化安全 "+$v.Name)}
        try{$hv=Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop;if($hv.State -in @('Enabled','EnablePending')){$null=Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart -ErrorAction Stop;Write-Host '[OK] Hyper-V 功能组件已禁用';$ok++;$script:rebootRequired=$true}else{Write-Host '[SKIP] Hyper-V 功能组件未启用' -ForegroundColor Yellow;$skip++}}catch{Write-Host "[FAIL] Hyper-V 功能组件禁用 : $($_.Exception.Message)" -ForegroundColor Red;$fail++}
        Invoke-BcdEdit "/set hypervisorlaunchtype off" "Hypervisor Launch Type Off";Invoke-BcdEdit "/set isolatedcontext no" "Isolated Context Off";Invoke-BcdEdit "/set vsmlaunchtype off" "VSM Launch Type Off";Verify-BcdValue 'hypervisorlaunchtype' 'Off' 'hypervisorlaunchtype'|Out-Null;Verify-BcdValue 'isolatedcontext' 'No' 'isolatedcontext'|Out-Null;Verify-BcdValue 'vsmlaunchtype' 'Off' 'vsmlaunchtype'|Out-Null;Write-Host '[提示] 重启后再验证 HypervisorPresent / msinfo32 实际运行状态。' -ForegroundColor Yellow
    } elseif($vChoice -eq '2'){
        foreach($v in $dgRegValues){$item=Get-Item $v.Path -ErrorAction SilentlyContinue;if($item -and ($item.GetValueNames()-contains $v.Name)){$regPath=Convert-RegExePath $v.Path;& reg.exe DELETE $regPath /v $v.Name /f *> $null;if($LASTEXITCODE -eq 0){Write-Host ("[OK] 已删除注册表值 {0} -> {1}"-f $v.Path,$v.Name);$ok++;$script:rebootRequired=$true}else{Write-Host ("[FAIL] 删除注册表值 {0} -> {1}"-f $v.Path,$v.Name) -ForegroundColor Red;$fail++}}else{Write-Host ("[SKIP] 注册表值不存在: {0} -> {1}"-f $v.Path,$v.Name) -ForegroundColor Yellow;$skip++}}
        Remove-BcdValue 'hypervisorlaunchtype' '还原 hypervisorlaunchtype';Remove-BcdValue 'vsmlaunchtype' '还原 vsmlaunchtype';Remove-BcdValue 'isolatedcontext' '还原 isolatedcontext';try{$null=Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop;Write-Host '[OK] 已尝试启用 Hyper-V 功能组件（重启后生效）';$ok++;$script:rebootRequired=$true}catch{Write-Host "[FAIL] Hyper-V 功能组件启用 : $($_.Exception.Message)" -ForegroundColor Red;$fail++}
    } else {Write-Host "[ERROR] 无效输入：$vChoice 。请输入 0、1 或 2" -ForegroundColor Red}
    Write-Host "Finished (Part 10 - Virtualization Management)" -ForegroundColor Cyan;Write-Host " OK : $ok  FAIL : $fail  SKIP : $skip";Request-Restart

} elseif ($choice -eq "11") {

    $script:moduleFailBaseline = $fail
    # ======================= Part 11: MPO 设置管理 =======================
    # MPO（Multi-Plane Overlay，多平面叠加）让显卡用独立硬件平面合成画面，异常时
    # 会引起闪屏/黑屏/切屏卡顿（N 卡多屏与 Chromium 系应用高发）。本选项管理四个
    # 注册表值，三个方案互斥（切换方案时自动清除其他方案的值）：
    #   DisableMPO      (GraphicsDrivers) = 1：驱动层禁用（旧方法；Win11 24H2/25H2
    #                                     部分版本已失效；选项 1 会写入本值）
    #   OverlayTestMode (Dwm)            = 5：社区常用的 DWM 层禁用尝试
    #   DisableOverlays (GraphicsDrivers) = 1：更激进的社区排障尝试；个别 DX12 游戏
    #                                     或叠加层可能异常；须与其他值互斥
    #   OverlayMinFPS   (Dwm)            = 0：尝试避免低帧率时撤下 MPO，常用于排查
    #                                     G-Sync/FreeSync 视频播放卡顿
    # 验证：dxdiag -> 保存所有信息 -> 搜索 MPO，仅作辅助判断；最终结合实际应用测试。
    Write-Host ""
    Write-Host "============ [Part 11] MPO 设置管理 / MPO Settings ============" -ForegroundColor Cyan
    Write-Host ""

    $mpoValues = @($script:mpoManagedValues)

    Write-Host "  0. 查看当前 MPO 设置状态（只读：四个注册表值 + dxdiag 验证方法）" -ForegroundColor White
    Write-Host "  1. 禁用 MPO — 方案 A：OverlayTestMode=5 + DisableMPO=1（社区使用较广；" -ForegroundColor White
    Write-Host "     可能影响窗口化 VRR/视频呈现；自动清除方案 B/C 的值）" -ForegroundColor White
    Write-Host "  2. 禁用 MPO — 方案 B：DisableOverlays=1（更激进的社区排障方案；个别 DX12" -ForegroundColor White
    Write-Host "     游戏或叠加层可能异常，仅在方案 A 无效时测试；自动清除方案 A/C 的值）" -ForegroundColor White
    Write-Host "  3. 尝试保持 MPO — 方案 C：OverlayMinFPS=0（常用于 G-Sync/FreeSync 视频卡顿；" -ForegroundColor White
    Write-Host "     实际效果取决于系统和驱动；自动清除方案 A/B 的值）" -ForegroundColor White
    Write-Host "  4. 还原（优先恢复首次修改前备份；无备份时删除四个值恢复系统默认）" -ForegroundColor White
    $mChoice = Read-Host "请输入 0、1、2、3 或 4 并回车 (Enter 0, 1, 2, 3 or 4)"

    if ($mChoice -eq "0") {

        # 只读状态检查，不做任何修改
        Write-Host ""
        $mpoAny = $false
        foreach ($v in $mpoValues) {
            $item = Get-Item $v.Path -ErrorAction SilentlyContinue
            if ($item -and ($item.GetValueNames() -contains $v.Name)) {
                Write-Host ("注册表 {0,-16} = {1}  ({2})" -f $v.Name, $item.GetValue($v.Name), $v.Desc)
                $mpoAny = $true
            } else {
                Write-Host ("注册表 {0,-16} = <未设置（系统默认）>  ({1})" -f $v.Name, $v.Desc)
            }
        }

        Write-Host ""
        if ($mpoAny) {
            Write-Host "结论：存在手动 MPO 设置；选 11 -> 4 可优先恢复首次修改前状态" -ForegroundColor Yellow
        } else {
            Write-Host "结论：MPO 全部为系统默认状态（未做任何修改）" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "验证提示（辅助判断，需重启后检查；不代表所有应用的运行时状态）：" -ForegroundColor Cyan
        Write-Host "  Win+R 运行 dxdiag -> 保存所有信息 -> 打开保存的 txt 搜索 MPO" -ForegroundColor White
        Write-Host "  某些系统中 MPO 条目消失或 MaxPlanes 为 0，可能表示禁用；输出格式因版本/驱动而异" -ForegroundColor White
        Write-Host "  最终请结合浏览器/视频、多显示器、窗口化游戏、DX12、HDR/录屏和覆盖层实测" -ForegroundColor White

    } elseif (($mChoice -eq "1") -or ($mChoice -eq "2") -or ($mChoice -eq "3")) {

        $gdReg = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        $dwmReg = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
        $mpoChanged = $false

        if (Ensure-MpoBackup) {
            if ($mChoice -eq "1") {
                # 方案 A：社区使用较广的禁用组合
                Remove-RegDwordValue $gdReg "DisableOverlays" "清除方案 B DisableOverlays"
                Remove-RegDwordValue $dwmReg "OverlayMinFPS" "清除方案 C OverlayMinFPS"
                Set-RegDword $dwmReg "OverlayTestMode" 5 "OverlayTestMode = 5 (社区排障配置)"
                Set-RegDword $gdReg "DisableMPO" 1 "DisableMPO = 1 (社区排障配置)"
            } elseif ($mChoice -eq "2") {
                # 方案 B：更激进的社区排障配置；与其他值互斥
                Remove-RegDwordValue $dwmReg "OverlayTestMode" "清除方案 A OverlayTestMode"
                Remove-RegDwordValue $dwmReg "OverlayMinFPS" "清除方案 C OverlayMinFPS"
                Remove-RegDwordValue $gdReg "DisableMPO" "清除旧方法 DisableMPO"
                Set-RegDword $gdReg "DisableOverlays" 1 "DisableOverlays = 1 (社区排障配置)"
                Write-Host " [警告] 该方案可能影响 DX12 游戏或叠加层，仅建议在方案 A 无效时测试" -ForegroundColor Yellow
            } else {
                # 方案 C：尝试避免低帧率时撤下 MPO；实际效果取决于系统和驱动
                Remove-RegDwordValue $dwmReg "OverlayTestMode" "清除方案 A OverlayTestMode"
                Remove-RegDwordValue $gdReg "DisableOverlays" "清除方案 B DisableOverlays"
                Remove-RegDwordValue $gdReg "DisableMPO" "清除旧方法 DisableMPO"
                Set-RegDword $dwmReg "OverlayMinFPS" 0 "OverlayMinFPS = 0 (社区排障配置)"
            }
            $mpoChanged = $true
            Write-Host " [提示] 这些是未公开的社区排障配置，不是微软或显卡厂商保证的稳定 API" -ForegroundColor Yellow
        } else {
            Write-Host "[ABORTED] 备份不可用，未修改 MPO，也不会自动重启" -ForegroundColor Red
        }

        # Summary
        $schemeLabel = $(if ($mChoice -eq "1") { "Disable (Scheme A: OverlayTestMode+DisableMPO)" } elseif ($mChoice -eq "2") { "Disable (Scheme B: DisableOverlays)" } else { "Keep MPO (Scheme C: OverlayMinFPS)" })
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 11 - MPO $schemeLabel)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " 重启后可用 dxdiag -> 保存所有信息 -> 搜索 MPO 作辅助判断；最终请结合实际应用测试" -ForegroundColor Yellow
        Write-Host " 原始状态备份：$script:mpoBackupFile；选 11 -> 4 可优先恢复首次修改前状态" -ForegroundColor Yellow

        if ($mpoChanged) { Request-Restart }

    } elseif ($mChoice -eq "4") {

        # 还原：优先恢复首次修改前状态；没有备份时才删除全部值
        Restore-MpoBackup

        # Summary
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Finished (Part 11 - MPO Restore)" -ForegroundColor Cyan
        Write-Host " OK : $ok" -ForegroundColor Green
        Write-Host " FAIL : $fail" -ForegroundColor Red
        Write-Host " SKIP : $skip" -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        if (Test-Path $script:mpoBackupFile) {
            Write-Host " 重启后 MPO 恢复首次修改前状态；备份文件保留在 $script:mpoBackupFile" -ForegroundColor Yellow
        } else {
            Write-Host " 重启后 MPO 恢复系统默认（叠加平面按系统策略自动管理）" -ForegroundColor Yellow
        }

        Request-Restart

    } else {
        Write-Host "[ERROR] 无效输入：$mChoice 。请输入 0、1、2、3 或 4 / Invalid input. Enter 0, 1, 2, 3 or 4." -ForegroundColor Red
    }

 } else {
    Write-Host "[ERROR] 无效输入：$choice 。请输入 0-11 / Invalid input. Enter 0-11." -ForegroundColor Red
}
}
