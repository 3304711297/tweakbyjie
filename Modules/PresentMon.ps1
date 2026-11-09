# PresentMon.ps1 - 模块 18：随仓库分发的 PresentMon 帧时间采集与基线/变更后对比
# PresentMon 控制台程序位于 tools\PresentMon\PresentMon.exe（Intel 签名，MIT）。
# 本模块不下载任何二进制；缺失时提示使用完整仓库 ZIP。

function Get-PresentMonPath {
    <#
    .SYNOPSIS
        查找 PresentMon.exe：显式路径 → 仓库 tools\PresentMon → 用户目录 → PATH。
    #>
    [CmdletBinding()]
    param([string]$ExplicitPath = '', [string[]]$Candidates = $null)

    $checks = @()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $checks += [pscustomobject]@{ Path = $ExplicitPath; Source = 'explicit' }
    }
    if ($null -ne $Candidates) {
        foreach ($candidate in @($Candidates)) {
            $checks += [pscustomobject]@{ Path = $candidate; Source = 'custom' }
        }
    } else {
        if ($script:PresentMonDir) {
            $checks += [pscustomobject]@{ Path = (Join-Path $script:PresentMonDir 'PresentMon.exe'); Source = 'repo' }
        }
        $userCopy = Join-Path $env:LOCALAPPDATA 'tweakbyjie\bin\PresentMon.exe'
        $checks += [pscustomobject]@{ Path = $userCopy; Source = 'localappdata' }
        $cmd = Get-Command 'PresentMon.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $checks += [pscustomobject]@{ Path = $cmd.Source; Source = 'path' } }
    }

    foreach ($check in $checks) {
        if ([string]::IsNullOrWhiteSpace([string]$check.Path)) { continue }
        if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf)) { continue }
        $full = [System.IO.Path]::GetFullPath($check.Path)
        $version = ''
        $manifestPath = Join-Path (Split-Path -Parent $full) 'presentmon.json'
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try { $version = "$((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).version)" } catch { $version = '' }
        }
        return [pscustomobject]@{ Path = $full; Source = $check.Source; Version = $version }
    }
    return $null
}

function Invoke-PresentMonCapture {
    <#
    .SYNOPSIS
        调用 PresentMon 采集指定进程的帧时间 CSV。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PresentMonPath,
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [Parameter(Mandatory = $true)][int]$Seconds,
        [string]$OutputCsv = ''
    )

    if ([string]::IsNullOrWhiteSpace($OutputCsv)) {
        $OutputCsv = Join-Path ([System.IO.Path]::GetTempPath()) ('presentmon-' + [guid]::NewGuid().ToString('N') + '.csv')
    }
    $stdout = Join-Path ([System.IO.Path]::GetTempPath()) ('presentmon-' + [guid]::NewGuid().ToString('N') + '.out')
    $stderr = Join-Path ([System.IO.Path]::GetTempPath()) ('presentmon-' + [guid]::NewGuid().ToString('N') + '.err')
    $argumentLine = "--process_name `"$ProcessName`" --output_file `"$OutputCsv`" --timed $Seconds --terminate_after_timed --stop_existing_session --no_console_stats"

    $process = Start-Process -FilePath $PresentMonPath -ArgumentList $argumentLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $timedOut = $false
    if (-not $process.WaitForExit(($Seconds + 60) * 1000)) {
        $timedOut = $true
        try { $process.Kill() } catch { }
    }
    $exitCode = $process.ExitCode
    $outText = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue } else { '' }
    $errText = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
        ExitCode = $exitCode
        TimedOut = $timedOut
        CsvPath  = $OutputCsv
        StdOut   = "$outText"
        StdErr   = "$errText"
    }
}

function Get-PercentileValue {
    param([double[]]$Values, [double]$Fraction)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    if ($sorted.Count -eq 1) { return [double]$sorted[0] }
    $position = ($sorted.Count - 1) * $Fraction
    $lower = [math]::Floor($position)
    $upper = [math]::Ceiling($position)
    if ($lower -eq $upper) { return [double]$sorted[$lower] }
    return [double]$sorted[$lower] + (([double]$sorted[$upper] - [double]$sorted[$lower]) * ($position - $lower))
}

function ConvertFrom-PresentMonCsv {
    <#
    .SYNOPSIS
        从 PresentMon CSV 计算平均 FPS、1% Low、P99 帧时间与卡顿次数。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "CSV 不存在：$Path" }
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0) { throw 'CSV 为空' }
    $column = @($rows[0].PSObject.Properties.Name | Where-Object { $_ -ieq 'MsBetweenPresents' }) | Select-Object -First 1
    if (-not $column) { throw 'CSV 缺少 MsBetweenPresents 列' }

    $values = @()
    foreach ($row in $rows) {
        $value = 0.0
        $text = "$($row.$column)"
        if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and $value -gt 0) {
            $values += [double]$value
        }
    }
    if ($values.Count -lt 30) { throw "有效帧数不足（$($values.Count)），请确认采集期间游戏在前台运行" }

    $mean = [double](($values | Measure-Object -Average).Average)
    $median = Get-PercentileValue -Values $values -Fraction 0.5
    $p99 = Get-PercentileValue -Values $values -Fraction 0.99
    $duration = [double](($values | Measure-Object -Sum).Sum) / 1000.0
    $stutterThreshold = 2.0 * $median
    $stutters = @($values | Where-Object { $_ -gt $stutterThreshold }).Count

    [pscustomobject][ordered]@{
        frameCount    = $values.Count
        durationSec   = [math]::Round($duration, 2)
        avgFps        = [math]::Round(1000.0 / $mean, 2)
        fps1Low       = [math]::Round(1000.0 / $p99, 2)
        p99FrameMs    = [math]::Round($p99, 2)
        medianFrameMs = [math]::Round($median, 2)
        stutterCount  = $stutters
        stuttersPerMin = if ($duration -gt 0) { [math]::Round($stutters / ($duration / 60.0), 2) } else { 0 }
    }
}

function Compare-PresentMonMetrics {
    <#
    .SYNOPSIS
        对比基线与变更后指标；单轮 MVP，阈值 5%，并提示重复测量。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Baseline, [Parameter(Mandatory = $true)]$After)

    $delta = {
        param($after, $before)
        if ($null -eq $before -or [double]$before -eq 0) { return $null }
        return (([double]$after - [double]$before) * 100.0 / [math]::Abs([double]$before))
    }
    $avgPct = & $delta $After.avgFps $Baseline.avgFps
    $lowPct = & $delta $After.fps1Low $Baseline.fps1Low
    $p99Pct = & $delta $After.p99FrameMs $Baseline.p99FrameMs
    if ([double]$Baseline.stuttersPerMin -eq 0) {
        $stutterPct = if ([double]$After.stuttersPerMin -eq 0) { 0.0 } else { 100.0 }
    } else {
        $stutterPct = & $delta $After.stuttersPerMin $Baseline.stuttersPerMin
    }

    $verdict = if ($null -eq $avgPct -or $null -eq $lowPct) {
        'inconclusive'
    } elseif ([double]$lowPct -ge 5 -and [double]$avgPct -ge -2 -and [double]$stutterPct -le 20) {
        'improved'
    } elseif ([double]$avgPct -le -4 -or [double]$lowPct -le -5) {
        'regressed'
    } else {
        'inconclusive'
    }

    [pscustomobject][ordered]@{
        verdict            = $verdict
        avgFpsDeltaPct     = if ($null -ne $avgPct) { [math]::Round($avgPct, 2) } else { $null }
        fps1LowDeltaPct    = if ($null -ne $lowPct) { [math]::Round($lowPct, 2) } else { $null }
        p99FrameMsDeltaPct = if ($null -ne $p99Pct) { [math]::Round($p99Pct, 2) } else { $null }
        stutterDeltaPct    = [math]::Round($stutterPct, 2)
        note               = '单轮测量受场景、温度与后台影响；建议同场景重复 3 次再下结论。'
    }
}

function Get-MeasureConfig {
    $config = [pscustomobject]@{ processName = ''; seconds = 120 }
    if ($script:measureConfigFile -and (Test-Path -LiteralPath $script:measureConfigFile -PathType Leaf)) {
        try {
            $saved = Get-Content -LiteralPath $script:measureConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.processName) { $config.processName = "$($saved.processName)" }
            if ($null -ne $saved.seconds) { $config.seconds = [int]$saved.seconds }
        } catch { }
    }
    return $config
}

function Save-MeasureConfig {
    param([string]$ProcessName, [int]$Seconds)
    if (-not $script:measureConfigFile) { return }
    $config = [pscustomobject]@{ processName = $ProcessName; seconds = $Seconds }
    Write-TweakAtomicTextFile -Path $script:measureConfigFile -Content ($config | ConvertTo-Json) -Overwrite
}

function Save-MeasureResult {
    param([string]$Phase, [string]$ProcessName, [int]$Seconds, $PresentMon, $Metrics, [string]$CsvPath)
    $file = if ($Phase -eq 'baseline') { $script:measureBaselineFile } else { $script:measureAfterFile }
    $result = [pscustomobject][ordered]@{
        schemaVersion = 1
        phase         = $Phase
        capturedAt    = (Get-Date).ToString('o')
        processName   = $ProcessName
        seconds       = $Seconds
        presentMon    = [pscustomobject]@{ path = "$($PresentMon.Path)"; version = "$($PresentMon.Version)" }
        metrics       = $Metrics
        csv           = $CsvPath
    }
    Write-TweakAtomicTextFile -Path $file -Content ($result | ConvertTo-Json -Depth 6) -Overwrite
    return $file
}

function Read-MeasureResult {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$data.schemaVersion -ne 1 -or -not $data.metrics) { return $null }
        return $data
    } catch { return $null }
}

function Write-MeasureMetrics {
    param([string]$Title, $Metrics)
    Write-Host ("--- {0} ---" -f $Title) -ForegroundColor White
    Write-Host ("平均 FPS      : {0}" -f $Metrics.avgFps)
    Write-Host ("1% Low        : {0}" -f $Metrics.fps1Low)
    Write-Host ("P99 帧时间    : {0} ms" -f $Metrics.p99FrameMs)
    Write-Host ("中位帧时间    : {0} ms" -f $Metrics.medianFrameMs)
    Write-Host ("卡顿(>2×中位) : {0} 次 / {1} 次/分" -f $Metrics.stutterCount, $Metrics.stuttersPerMin)
    Write-Host ("有效帧 / 时长 : {0} 帧 / {1} 秒" -f $Metrics.frameCount, $Metrics.durationSec)
}

function Invoke-MeasureModule {
    <#
    .SYNOPSIS
        模块 18：PresentMon 检测 + 基线/变更后采集 + 对比。
    #>
    [CmdletBinding()]
    param([string]$Action = '')

    Write-Host ''
    Write-Host '============ [帧率测量] PresentMon 基线 / 变更后 / 对比 ============' -ForegroundColor Cyan
    Write-Host '用仓库内置的 PresentMon 采集同一场景的帧时间，比较平均 FPS、1% Low、P99 与卡顿。' -ForegroundColor Gray
    Write-Host 'PresentMon 位于 tools\PresentMon\PresentMon.exe（Intel 签名，MIT）。' -ForegroundColor Gray
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定测量子操作（1=基线、2=变更后、3=对比、4=PresentMon 状态）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        Write-Host '  1. 采集基线（修改前）'
        Write-Host '  2. 采集变更后（修改后，同场景）'
        Write-Host '  3. 对比基线与变更后'
        Write-Host '  4. 查看 PresentMon'
        Write-Host '  0. 返回'
        $Action = Read-Host '请输入 0-4 并回车'
    }

    if ($Action -eq '0' -or $Action -ieq 'back') {
        Write-Host '[返回] 已返回主菜单。' -ForegroundColor Green
        return $true
    }

    if ($Action -eq '4' -or $Action -ieq 'status') {
        $pm = Get-PresentMonPath
        if ($pm) {
            Write-Host ("[OK] PresentMon：{0}" -f $pm.Path) -ForegroundColor Green
            if ($pm.Version) { Write-Host ("     版本：{0}" -f $pm.Version) -ForegroundColor Gray }
            return $true
        }
        Write-Host '[FAIL] 未找到 PresentMon.exe（应为 tools\PresentMon\PresentMon.exe）。' -ForegroundColor Red
        Write-Host '请使用完整仓库 ZIP 或重新拉取仓库；不要只复制 tweakbyjie.ps1。' -ForegroundColor Yellow
        $script:fail++
        return $false
    }

    if ($Action -eq '3' -or $Action -ieq 'compare') {
        $baseline = Read-MeasureResult -Path $script:measureBaselineFile
        $after = Read-MeasureResult -Path $script:measureAfterFile
        if (-not $baseline -or -not $after) {
            Write-Host '[FAIL] 缺少基线或变更后结果；请先分别执行子操作 1 与 2。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        Write-MeasureMetrics '基线' $baseline.metrics
        Write-Host ''
        Write-MeasureMetrics '变更后' $after.metrics
        Write-Host ''
        $comparison = Compare-PresentMonMetrics -Baseline $baseline.metrics -After $after.metrics
        $color = switch ($comparison.verdict) { 'improved' { 'Green' } 'regressed' { 'Red' } default { 'Yellow' } }
        Write-Host ("结论：{0}" -f $comparison.verdict) -ForegroundColor $color
        Write-Host ("平均 FPS {0}% | 1% Low {1}% | P99 {2}% | 卡顿 {3}%" -f `
            $comparison.avgFpsDeltaPct, $comparison.fps1LowDeltaPct, $comparison.p99FrameMsDeltaPct, $comparison.stutterDeltaPct)
        Write-Host $comparison.note -ForegroundColor Gray
        return [pscustomobject]@{ Baseline = $baseline; After = $after; Comparison = $comparison }
    }

    if ($Action -eq '1' -or $Action -eq '2' -or $Action -ieq 'baseline' -or $Action -ieq 'after') {
        $phase = if ($Action -eq '1' -or $Action -ieq 'baseline') { 'baseline' } else { 'after' }
        $pm = Get-PresentMonPath
        if (-not $pm) {
            Write-Host '[FAIL] 未找到 PresentMon.exe（应为 tools\PresentMon\PresentMon.exe）。' -ForegroundColor Red
            Write-Host '请使用完整仓库 ZIP 或重新拉取仓库；不要只复制 tweakbyjie.ps1。' -ForegroundColor Yellow
            $script:fail++
            return $false
        }

        $config = Get-MeasureConfig
        $processName = $config.processName
        $seconds = [int]$config.seconds
        if ($script:TweakNonInteractive -and [string]::IsNullOrWhiteSpace($processName)) {
            Write-Host '[FAIL] 尚无测量配置；请先以交互方式采集一次，或写入 measure-config.json（processName/seconds）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        if (-not $script:TweakNonInteractive) {
            if ([string]::IsNullOrWhiteSpace($processName)) {
                $processName = Read-Host '请输入游戏进程名（例如 game.exe）'
            } else {
                $inputName = Read-Host ("请输入游戏进程名（回车沿用 {0}）" -f $processName)
                if (-not [string]::IsNullOrWhiteSpace($inputName)) { $processName = $inputName }
            }
            $inputSeconds = Read-Host ("采集秒数（回车沿用 {0} 秒，建议 120）" -f $seconds)
            if ($inputSeconds -match '^\d+$') { $seconds = [int]$inputSeconds }
        }
        $processName = "$processName".Trim()
        if ($processName -notmatch '^[^\\/:*?"<>|]+\.exe$') {
            Write-Host '[FAIL] 进程名必须是带 .exe 的文件名（不要填完整路径）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        if ($seconds -lt 10 -or $seconds -gt 600) {
            Write-Host '[FAIL] 采集秒数需在 10-600 之间。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        Save-MeasureConfig -ProcessName $processName -Seconds $seconds

        Write-Host ("[INFO] 采集 {0} 秒，目标进程 {1}；请保持同一场景、画质与路线。" -f $seconds, $processName) -ForegroundColor Yellow
        if (-not (Test-ConfirmChoice '确认开始采集吗？Y = 开始 / 其他键取消')) {
            Write-Host '[SKIP] 已取消。' -ForegroundColor Yellow
            $script:skip++
            return $false
        }

        $csv = Join-Path $script:RepoRoot ("measure-{0}.csv" -f $phase)
        $capture = Invoke-PresentMonCapture -PresentMonPath $pm.Path -ProcessName $processName -Seconds $seconds -OutputCsv $csv
        if ($capture.TimedOut) {
            Write-Host '[FAIL] PresentMon 超时未退出，已终止；请检查是否有其他采集会话占用。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        if ($capture.ExitCode -ne 0) {
            Write-Host ("[FAIL] PresentMon 退出码 {0}；stderr：{1}" -f $capture.ExitCode, $capture.StdErr.Trim()) -ForegroundColor Red
            $script:fail++
            return $false
        }
        try {
            $metrics = ConvertFrom-PresentMonCsv -Path $csv
        } catch {
            Write-Host ("[FAIL] 解析 PresentMon CSV 失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
            $script:fail++
            return $false
        }
        $saved = Save-MeasureResult -Phase $phase -ProcessName $processName -Seconds $seconds -PresentMon $pm -Metrics $metrics -CsvPath $csv
        Write-MeasureMetrics ("{0}（{1}）" -f $(if ($phase -eq 'baseline') { '基线' } else { '变更后' }), $processName) $metrics
        Write-Host ("[OK] 结果已保存：{0}" -f $saved) -ForegroundColor Green
        return $true
    }

    Write-Host ("[FAIL] 无效输入：{0}。请输入 0-4。" -f $Action) -ForegroundColor Red
    $script:fail++
    return $false
}
