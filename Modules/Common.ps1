# Common.ps1 - 通用注册表/BCD/验证与重启辅助
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok / $script:fail / $script:skip / $script:rebootRequired

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
