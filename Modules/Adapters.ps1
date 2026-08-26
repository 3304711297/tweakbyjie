# Adapters.ps1 - 可替换的系统副作用边界
# 默认实现保持生产行为；测试可用 Set-TweakAdapters 注入脚本块，不触碰真实系统。

function Initialize-TweakAdapters {
    $script:TweakAdapters = @{
        SetRegistryDword = {
            param($Path, $Name, $Value)
            $regPath = Convert-RegExePath $Path
            $valueText = [string]$Value
            if ($valueText -match '^\d+$') {
                [uint64]$n = [uint64]$Value
                if ($n -le 0xFFFFFFFF) { $valueText = "0x{0:X8}" -f $n }
            }
            & reg.exe ADD $regPath /v $Name /t REG_DWORD /d $valueText /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
            return $valueText
        }
        SetRegistryString = {
            param($Path, $Name, $Value)
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        SetRegistryBinary = {
            param($Path, $Name, $Hex)
            & reg.exe ADD (Convert-RegExePath $Path) /v $Name /t REG_BINARY /d $Hex /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        }
        RemoveRegistryValue = {
            param($Path, $Name)
            & reg.exe DELETE (Convert-RegExePath $Path) /v $Name /f *> $null
            if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        }
        InvokeBcd = {
            param($Arguments)
            $outFile = [IO.Path]::GetTempFileName()
            $errFile = [IO.Path]::GetTempFileName()
            try {
                $process = Start-Process -FilePath 'bcdedit.exe' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
                if ($process.ExitCode -ne 0) {
                    $errText = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
                    if ([string]::IsNullOrWhiteSpace($errText)) { $errText = Get-Content $outFile -Raw -ErrorAction SilentlyContinue }
                    throw "Exit code $($process.ExitCode)$(if ($errText) { ' ：' + $errText.Trim() })"
                }
            } finally { Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue }
            return $true
        }
        Confirm = { param($Prompt) return ((Read-Host $Prompt) -match '^[Yy]$') }
        Restart = { Restart-Computer -Force }
    }
}

function Set-TweakAdapters {
    param([scriptblock]$SetRegistryDword, [scriptblock]$SetRegistryString,
        [scriptblock]$SetRegistryBinary, [scriptblock]$RemoveRegistryValue,
        [scriptblock]$InvokeBcd, [scriptblock]$Confirm, [scriptblock]$Restart)
    if (-not $script:TweakAdapters) { Initialize-TweakAdapters }
    foreach ($entry in @{
        SetRegistryDword = $SetRegistryDword; SetRegistryString = $SetRegistryString
        SetRegistryBinary = $SetRegistryBinary; RemoveRegistryValue = $RemoveRegistryValue
        InvokeBcd = $InvokeBcd; Confirm = $Confirm; Restart = $Restart
    }.GetEnumerator()) {
        if ($null -ne $entry.Value) { $script:TweakAdapters[$entry.Key] = $entry.Value }
    }
}

if (-not $script:TweakAdapters) { Initialize-TweakAdapters }
