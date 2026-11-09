# Diagnostics.ps1 - 只读硬件与运行库体检
# 被 Module 15（系统体检与虚拟内存建议）调用。
# 绝对原则：只查询、只报告；不写注册表、不改任何系统设置、不安装运行库。

function New-HealthResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'Attention', 'Info', 'N/A')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [string]$Detail = '',
        [hashtable]$Extra = @{}
    )
    $result = [pscustomobject][ordered]@{
        Name    = $Name
        Status  = $Status
        Summary = $Summary
        Detail  = $Detail
    }
    foreach ($key in @($Extra.Keys)) {
        $result | Add-Member -NotePropertyName $key -NotePropertyValue $Extra[$key]
    }
    return $result
}

function Get-PcieLinkStatus {
    <#
    .SYNOPSIS
        读取独显 PCIe 链路的最大能力与当前档位（只读）。
    .DESCRIPTION
        优先用 nvidia-smi（NVIDIA 驱动自带）。A 卡/核显或未安装驱动时返回 N/A。
        笔记本与中端卡的 x8 属正常配置，只记为 Info；x4 及以下才提示检查插槽/延长线。
    #>
    [CmdletBinding()]
    param([object]$NvidiaSmiOutput = $null)

    if ($null -eq $NvidiaSmiOutput) {
        $candidates = @(
            (Join-Path $env:WINDIR 'System32\nvidia-smi.exe'),
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')
        )
        $exe = @($candidates | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
        if (-not $exe) {
            return New-HealthResult 'PCIe 链路' 'N/A' '未找到 nvidia-smi（A 卡/核显或未安装 NVIDIA 驱动）'
        }
        try {
            $query = '--query-gpu=pcie.link.gen.max,pcie.link.width.max,pcie.link.gen.current,pcie.link.width.current'
            $NvidiaSmiOutput = (& $exe $query --format=csv,noheader,nounits 2>$null) -join "`n"
        } catch {
            return New-HealthResult 'PCIe 链路' 'N/A' ("nvidia-smi 调用失败：{0}" -f $_.Exception.Message)
        }
    }

    $line = @($NvidiaSmiOutput -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -First 1
    if (-not $line) { return New-HealthResult 'PCIe 链路' 'N/A' '未获取到 PCIe 链路信息' }

    $parts = @($line -split ',' | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 4 -or $parts[0] -notmatch '^\d+$' -or $parts[1] -notmatch '^\d+$') {
        return New-HealthResult 'PCIe 链路' 'N/A' ("无法解析 nvidia-smi 输出：{0}" -f $line)
    }

    $maxGen = [int]$parts[0]
    $maxWidth = [int]$parts[1]
    $curGen = if ($parts[2] -match '^\d+$') { [int]$parts[2] } else { $null }
    $curWidth = if ($parts[3] -match '^\d+$') { [int]$parts[3] } else { $null }
    $idle = ($null -ne $curWidth -and $curWidth -lt $maxWidth) -or ($null -ne $curGen -and $curGen -lt $maxGen)
    $idleText = if ($idle) { '；空闲时当前链路降档属正常省电，负载下会回到上限' } else { '' }
    $detail = "max=Gen$maxGen x$maxWidth; current=Gen$curGen x$curWidth"
    $extra = @{ MaxGen = $maxGen; MaxWidth = $maxWidth; CurrentGen = $curGen; CurrentWidth = $curWidth }

    if ($maxWidth -lt 8) {
        return New-HealthResult 'PCIe 链路' 'Attention' `
            ("上限仅 x{0}（Gen{1}），请检查插槽、延长线与主板通道分配{2}" -f $maxWidth, $maxGen, $idleText) $detail $extra
    }
    if ($maxWidth -eq 8) {
        return New-HealthResult 'PCIe 链路' 'Info' `
            ("上限 x8（Gen{0}）；笔记本与中端卡常见，属正常{1}" -f $maxGen, $idleText) $detail $extra
    }
    return New-HealthResult 'PCIe 链路' 'OK' ("上限 Gen{0} x{1}{2}" -f $maxGen, $maxWidth, $idleText) $detail $extra
}

function Get-VcRedistStatus {
    <#
    .SYNOPSIS
        检查 VC++ 2015-2022（v14）x64/x86 运行库是否缺失（只读）。
    .DESCRIPTION
        只有“缺失某个/全部架构”才算问题。x64 与 x86 是两套独立运行库，
        版本不同步通常无害，只做中性提示。
    #>
    [CmdletBinding()]
    param([hashtable]$RuntimeKeys = $null)

    $rows = @{}
    foreach ($arch in @('x64', 'x86')) {
        if ($null -ne $RuntimeKeys) {
            $key = $RuntimeKeys[$arch]
        } else {
            $path = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch"
            $key = $null
            if (Test-Path -LiteralPath $path) {
                try { $key = Get-ItemProperty -LiteralPath $path -ErrorAction Stop } catch { $key = $null }
            }
        }
        $installed = $false
        $version = ''
        if ($null -ne $key) {
            if ($null -ne $key.Installed) { $installed = ([int]$key.Installed -eq 1) }
            $version = "$($key.Version)"
        }
        $rows[$arch] = [pscustomobject]@{ Installed = $installed; Version = $version }
    }

    $missing = @($rows.Keys | Where-Object { -not $rows[$_].Installed } | Sort-Object)
    if ($missing.Count -gt 0) {
        return New-HealthResult 'VC++ v14 运行库' 'Attention' `
            ("缺少 {0} 运行库；依赖它的游戏可能无法启动，请从微软官网安装" -f ($missing -join '/')) `
            ("x64={0} {1}; x86={2} {3}" -f $rows['x64'].Installed, $rows['x64'].Version, $rows['x86'].Installed, $rows['x86'].Version)
    }
    if ($rows['x64'].Version -ne $rows['x86'].Version) {
        return New-HealthResult 'VC++ v14 运行库' 'Info' `
            ("x64 与 x86 版本不同步（{0} / {1}）；两套运行库相互独立，通常无害" -f $rows['x64'].Version, $rows['x86'].Version) `
            '版本不同步本身不是故障；只有缺失架构或反复闪退且排除其他原因时才需要处理'
    }
    return New-HealthResult 'VC++ v14 运行库' 'OK' ("x64 与 x86 均已安装：{0}" -f $rows['x64'].Version)
}

function Get-MemoryFrequencyStatus {
    <#
    .SYNOPSIS
        比较内存当前频率与 SMBIOS 标称频率（只读）。
    .DESCRIPTION
        不读取 SPD，不做“某档位一定存在”的推断；只在当前频率低于标称时提示
        可能未开启 XMP/EXPO/DOCP。平台不提供 ConfiguredClockSpeed 时返回 N/A。
    #>
    [CmdletBinding()]
    param([object[]]$Modules = $null)

    if ($null -eq $Modules) {
        try {
            $Modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        } catch {
            return New-HealthResult '内存频率' 'N/A' ("无法读取内存信息：{0}" -f $_.Exception.Message)
        }
    }
    $Modules = @($Modules)
    if ($Modules.Count -eq 0) { return New-HealthResult '内存频率' 'N/A' '未读取到内存条信息' }

    $pairs = @()
    foreach ($module in $Modules) {
        $rated = if ($null -ne $module.Speed) { [int]$module.Speed } else { 0 }
        $configured = if ($null -ne $module.ConfiguredClockSpeed) { [int]$module.ConfiguredClockSpeed } else { 0 }
        $pairs += [pscustomobject]@{ Rated = $rated; Configured = $configured }
    }
    $known = @($pairs | Where-Object { $_.Configured -gt 0 -and $_.Rated -gt 0 })
    if ($known.Count -eq 0) {
        return New-HealthResult '内存频率' 'N/A' '平台未提供 ConfiguredClockSpeed，无法判断是否开启 XMP/EXPO'
    }

    $below = @($known | Where-Object { $_.Configured -lt $_.Rated })
    if ($below.Count -gt 0) {
        $minConfigured = ($below | Measure-Object -Property Configured -Minimum).Minimum
        $maxRated = ($below | Measure-Object -Property Rated -Maximum).Maximum
        return New-HealthResult '内存频率' 'Attention' `
            ("当前 {0} MT/s 低于标称 {1} MT/s；可能未开启 XMP/EXPO/DOCP，或内存正在降频运行" -f $minConfigured, $maxRated)
    }
    $sample = $known | Select-Object -First 1
    return New-HealthResult '内存频率' 'OK' ("当前 {0} MT/s 已达到标称 {1} MT/s" -f $sample.Configured, $sample.Rated)
}

function Get-NvidiaAppAutoOptStatus {
    <#
    .SYNOPSIS
        检查 NVIDIA App「自动优化游戏设置」是否开启（只读）。
    .DESCRIPTION
        只读取 NvBackend\config.xml 的 EnableAutomaticApplyOPS，不写用户配置文件。
    #>
    [CmdletBinding()]
    param([object]$ConfigXml = $null)

    if ($null -eq $ConfigXml) {
        $path = Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NVIDIA App\NvBackend\config.xml'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return New-HealthResult 'NVIDIA App 自动优化' 'N/A' '未检测到 NVIDIA App 配置（A 卡/核显或未安装）'
        }
        try {
            $ConfigXml = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
        } catch {
            return New-HealthResult 'NVIDIA App 自动优化' 'N/A' ("读取配置失败：{0}" -f $_.Exception.Message)
        }
    }
    if ([string]::IsNullOrWhiteSpace($ConfigXml)) {
        return New-HealthResult 'NVIDIA App 自动优化' 'N/A' '未检测到 NVIDIA App 配置'
    }

    $match = [regex]::Match($ConfigXml, 'EnableAutomaticApplyOPS[^>]*>\s*(?<v>true|false|1|0)\s*<', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        $match = [regex]::Match($ConfigXml, 'EnableAutomaticApplyOPS\s*=\s*"(?<v>true|false|1|0)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if (-not $match.Success) {
        return New-HealthResult 'NVIDIA App 自动优化' 'N/A' '配置中未找到 EnableAutomaticApplyOPS'
    }

    $enabled = $match.Groups['v'].Value -in @('true', '1')
    if ($enabled) {
        return New-HealthResult 'NVIDIA App 自动优化' 'Attention' '「自动优化游戏设置」已开启，会在游戏启动时覆盖画质设置；建议在 NVIDIA App 内手动关闭'
    }
    return New-HealthResult 'NVIDIA App 自动优化' 'OK' '「自动优化游戏设置」已关闭'
}

function Get-SystemHealthReport {
    <#
    .SYNOPSIS
        汇总四项只读体检，返回结构化结果与 Attention 计数。
    #>
    [CmdletBinding()]
    param(
        [object]$PcieOutput = $null,
        [hashtable]$RuntimeKeys = $null,
        [object[]]$MemoryModules = $null,
        [object]$NvidiaConfigXml = $null
    )

    $results = @(
        Get-PcieLinkStatus -NvidiaSmiOutput $PcieOutput
        Get-VcRedistStatus -RuntimeKeys $RuntimeKeys
        Get-MemoryFrequencyStatus -Modules $MemoryModules
        Get-NvidiaAppAutoOptStatus -ConfigXml $NvidiaConfigXml
    )
    [pscustomobject][ordered]@{
        Results        = @($results)
        AttentionCount = @($results | Where-Object { $_.Status -eq 'Attention' }).Count
    }
}

function Invoke-SystemHealthReport {
    <#
    .SYNOPSIS
        运行并打印只读体检；返回结构化报告供调用方复用。
    #>
    [CmdletBinding()]
    param()

    $report = Get-SystemHealthReport
    Write-Host ''
    Write-Host '--- [硬件与运行库体检（只读）] ---' -ForegroundColor White
    foreach ($result in @($report.Results)) {
        $color = switch ($result.Status) {
            'OK' { 'Green' }
            'Attention' { 'Red' }
            'Info' { 'Yellow' }
            default { 'DarkGray' }
        }
        $tag = switch ($result.Status) {
            'OK' { '[OK]' }
            'Attention' { '[!]' }
            'Info' { '[INFO]' }
            default { '[N/A]' }
        }
        Write-Host ("{0} {1}：{2}" -f $tag, $result.Name, $result.Summary) -ForegroundColor $color
        if ($result.Detail) { Write-Host ("       {0}" -f $result.Detail) -ForegroundColor DarkGray }
    }
    if ($report.AttentionCount -gt 0) {
        Write-Host ("[!] 体检发现 {0} 项需要处理；以上均为只读检查，未修改任何设置。" -f $report.AttentionCount) -ForegroundColor Yellow
    } else {
        Write-Host '[OK] 体检未发现需要处理的硬件/运行库问题。' -ForegroundColor Green
    }
    return $report
}

function Get-TweakDetectReport {
    <#
    .SYNOPSIS
        只读检测报告：系统、CPU、GPU、内存与四项体检，输出稳定 JSON 结构。
    .DESCRIPTION
        参数可注入（测试用）；默认全部走 CIM/注册表/nvidia-smi 只读查询。
        不写注册表、不启动 transcript、不需要管理员。
    #>
    [CmdletBinding()]
    param(
        [object]$OSInfo = $null,
        [object]$CPUInfo = $null,
        [object[]]$GpuInfo = $null,
        [object[]]$MemoryModules = $null,
        [object]$Health = $null
    )

    if ($null -eq $OSInfo) {
        try { $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { $OSInfo = $null }
    }
    if ($null -eq $CPUInfo) {
        try { $CPUInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { $CPUInfo = $null }
    }
    if ($null -eq $GpuInfo) {
        try { $GpuInfo = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop) } catch { $GpuInfo = @() }
    }
    if ($null -eq $MemoryModules) {
        try { $MemoryModules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop) } catch { $MemoryModules = @() }
    }
    if ($null -eq $Health) { $Health = Get-SystemHealthReport }

    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $totalBytes = 0L
    $memoryRows = @()
    foreach ($module in @($MemoryModules)) {
        if ($null -eq $module) { continue }
        $capacity = if ($null -ne $module.Capacity) { [int64]$module.Capacity } else { 0 }
        $totalBytes += $capacity
        $memoryRows += [pscustomobject][ordered]@{
            capacityGB    = [math]::Round($capacity / 1GB, 2)
            ratedMTs      = if ($null -ne $module.Speed) { [int]$module.Speed } else { 0 }
            configuredMTs = if ($null -ne $module.ConfiguredClockSpeed) { [int]$module.ConfiguredClockSpeed } else { 0 }
            manufacturer  = "$($module.Manufacturer)"
            partNumber    = "$($module.PartNumber)"
        }
    }

    $healthRows = @()
    if ($null -ne $Health) {
        foreach ($result in @($Health.Results)) {
            if ($null -eq $result) { continue }
            $healthRows += [pscustomobject][ordered]@{
                name    = "$($result.Name)"
                status  = "$($result.Status)"
                summary = "$($result.Summary)"
                detail  = "$($result.Detail)"
            }
        }
    }

    [pscustomobject][ordered]@{
        schemaVersion = 1
        generatedAt   = (Get-Date).ToString('o')
        appVersion    = "$script:TweakVersion"
        isAdmin       = [bool]$admin
        os            = [pscustomobject][ordered]@{
            caption = "$($OSInfo.Caption)"
            version = "$($OSInfo.Version)"
            build   = "$($OSInfo.BuildNumber)"
        }
        cpu           = [pscustomobject][ordered]@{
            name    = "$($CPUInfo.Name)"
            cores   = if ($null -ne $CPUInfo.NumberOfCores) { [int]$CPUInfo.NumberOfCores } else { 0 }
            threads = if ($null -ne $CPUInfo.NumberOfLogicalProcessors) { [int]$CPUInfo.NumberOfLogicalProcessors } else { 0 }
        }
        gpu           = @($GpuInfo | Where-Object { $_ } | ForEach-Object {
            [pscustomobject][ordered]@{ name = "$($_.Name)"; driverVersion = "$($_.DriverVersion)" }
        })
        memory        = [pscustomobject][ordered]@{
            totalGB = [math]::Round($totalBytes / 1GB, 2)
            modules = @($memoryRows)
        }
        health        = [pscustomobject][ordered]@{
            attentionCount = if ($null -ne $Health) { [int]$Health.AttentionCount } else { 0 }
            results        = @($healthRows)
        }
    }
}

function Write-TweakDetectReportText {
    <#
    .SYNOPSIS
        -Detect 非 JSON 模式下的人类可读摘要。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Report)

    Write-Host ("tweakbyjie {0} | {1}" -f $Report.appVersion, $Report.generatedAt) -ForegroundColor Cyan
    Write-Host ("OS   : {0} (build {1})" -f $Report.os.caption, $Report.os.build)
    Write-Host ("CPU  : {0}  {1}C/{2}T" -f $Report.cpu.name, $Report.cpu.cores, $Report.cpu.threads)
    $gpuNames = @($Report.gpu | ForEach-Object { $_.name }) -join ' / '
    Write-Host ("GPU  : {0}" -f $(if ($gpuNames) { $gpuNames } else { '<未检测到>' }))
    Write-Host ("RAM  : {0} GB" -f $Report.memory.totalGB)
    Write-Host ("权限 : {0}" -f $(if ($Report.isAdmin) { '管理员' } else { '普通用户（检测无需提权）' }))
    Write-Host ''
    Write-Host '--- [硬件与运行库体检（只读）] ---' -ForegroundColor White
    foreach ($result in @($Report.health.results)) {
        $color = switch ($result.status) {
            'OK' { 'Green' }
            'Attention' { 'Red' }
            'Info' { 'Yellow' }
            default { 'DarkGray' }
        }
        $tag = switch ($result.status) {
            'OK' { '[OK]' }
            'Attention' { '[!]' }
            'Info' { '[INFO]' }
            default { '[N/A]' }
        }
        Write-Host ("{0} {1}：{2}" -f $tag, $result.name, $result.summary) -ForegroundColor $color
        if ($result.detail) { Write-Host ("       {0}" -f $result.detail) -ForegroundColor DarkGray }
    }
    if ($Report.health.attentionCount -gt 0) {
        Write-Host ("[!] 体检发现 {0} 项需要处理；本次检测未修改任何设置。" -f $Report.health.attentionCount) -ForegroundColor Yellow
    } else {
        Write-Host '[OK] 体检未发现需要处理的硬件/运行库问题。' -ForegroundColor Green
    }
}
