# Pagefile.ps1 - 虚拟内存 (Pagefile) 只读诊断与个性化配置建议指引模块
# 绝对原则：严格只读诊断与个性化设置建议指南，绝不自动化修改系统虚拟内存/页面文件！
# 避免破坏不同机型、物理内存容量与磁盘分区的个性化差异。

function Get-PagefileStatus {
    <#
    .SYNOPSIS
        只读探测系统物理内存容量、系统托管状态、各盘符页面文件及磁盘分区分布。
    .DESCRIPTION
        探测当前物理 RAM 容量（GB/MB）、Win32_ComputerSystem 的 AutomaticManagedPagefile 状态、
        各盘符 pagefile.sys 路径与 InitialSize/MaximumSize。支持通过参数注入模拟对象以支持独立单元测试。
    #>
    [CmdletBinding()]
    param(
        [object]$ComputerSystem = $null,
        [object[]]$PageFileSettings = $null,
        [object[]]$PageFileUsage = $null,
        [object[]]$Volumes = $null,
        [object]$RegistryPagingFiles = $null
    )

    # 1. 物理内存与自动托管状态
    $cs = $ComputerSystem
    if ($null -eq $cs) {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    }

    [uint64]$totalBytes = 0
    $autoManaged = $true
    if ($cs) {
        if ($null -ne $cs.TotalPhysicalMemory) {
            $totalBytes = [uint64]$cs.TotalPhysicalMemory
        }
        if ($null -ne $cs.AutomaticManagedPagefile) {
            $autoManaged = [bool]$cs.AutomaticManagedPagefile
        }
    }

    $totalMB = [math]::Round($totalBytes / 1MB, 2)
    $totalGB = [math]::Round($totalBytes / 1GB, 2)

    # 2. 磁盘驱动器探测
    $vols = $Volumes
    if ($null -eq $vols) {
        $vols = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
    }

    $sysDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\') } else { 'C:' }
    $parsedVolumes = [System.Collections.Generic.List[object]]::new()
    foreach ($v in @($vols)) {
        if ($null -eq $v) { continue }
        $dl = if ($v.DeviceID) { [string]$v.DeviceID } elseif ($v.DriveLetter) { [string]$v.DriveLetter } else { [string]$v.Name }
        $dl = $dl.TrimEnd('\')
        $fs = [string]$v.FileSystem
        $freeBytes = if ($null -ne $v.FreeSpace) { [uint64]$v.FreeSpace } else { [uint64]0 }
        $sizeBytes = if ($null -ne $v.Size) { [uint64]$v.Size } else { [uint64]0 }

        $parsedVolumes.Add([pscustomobject]@{
            DriveLetter   = $dl
            FreeSpaceGB   = [math]::Round($freeBytes / 1GB, 2)
            TotalSizeGB   = [math]::Round($sizeBytes / 1GB, 2)
            FileSystem    = $fs
            IsSystemDrive = ($dl -ieq $sysDrive)
            DriveType     = 'Fixed'
        })
    }

    # 3. 页面文件探测（Win32_PageFileSetting / Win32_PageFileUsage / 注册表）
    $settings = $PageFileSettings
    if ($null -eq $settings) {
        $settings = @(Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue)
    }

    $usages = $PageFileUsage
    if ($null -eq $usages) {
        $usages = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue)
    }

    $regPaging = $RegistryPagingFiles
    if ($null -eq $regPaging) {
        $mmKey = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -ErrorAction SilentlyContinue
        if ($mmKey -and $mmKey.PagingFiles) {
            $regPaging = $mmKey.PagingFiles
        }
    }

    $pageFilesList = [System.Collections.Generic.List[object]]::new()
    $processedDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 优先从 Win32_PageFileSetting 提取已配置项
    foreach ($s in @($settings)) {
        if ($null -eq $s -or [string]::IsNullOrWhiteSpace($s.Name)) { continue }
        $p = [string]$s.Name
        $drv = if ($p.Length -ge 2 -and $p[1] -eq ':') { $p.Substring(0, 2).ToUpper() } else { '' }
        $initSize = if ($null -ne $s.InitialSize) { [int]$s.InitialSize } else { 0 }
        $maxSize = if ($null -ne $s.MaximumSize) { [int]$s.MaximumSize } else { 0 }

        # 关联运行时使用量
        $matchedUsage = @($usages | Where-Object { $_.Name -and $_.Name -ieq $p }) | Select-Object -First 1
        $allocSize = if ($matchedUsage -and $null -ne $matchedUsage.AllocatedBaseSize) { [int]$matchedUsage.AllocatedBaseSize } else { $initSize }
        $curUsage = if ($matchedUsage -and $null -ne $matchedUsage.CurrentUsage) { [int]$matchedUsage.CurrentUsage } else { 0 }
        $peakUsage = if ($matchedUsage -and $null -ne $matchedUsage.PeakUsage) { [int]$matchedUsage.PeakUsage } else { 0 }

        $pageFilesList.Add([pscustomobject]@{
            Path                = $p
            Drive               = $drv
            InitialSizeMB       = $initSize
            MaximumSizeMB       = $maxSize
            AllocatedBaseSizeMB = $allocSize
            CurrentUsageMB      = $curUsage
            PeakUsageMB         = $peakUsage
            IsSystemDrive       = ($drv -ieq $sysDrive)
        })
        if ($drv) { [void]$processedDrives.Add($drv) }
    }

    # 若 PageFileSetting 为空（如系统托管模式），从 PageFileUsage 提取
    foreach ($u in @($usages)) {
        if ($null -eq $u -or [string]::IsNullOrWhiteSpace($u.Name)) { continue }
        $p = [string]$u.Name
        $drv = if ($p.Length -ge 2 -and $p[1] -eq ':') { $p.Substring(0, 2).ToUpper() } else { '' }
        if ($drv -and $processedDrives.Contains($drv)) { continue }

        $allocSize = if ($null -ne $u.AllocatedBaseSize) { [int]$u.AllocatedBaseSize } else { 0 }
        $curUsage = if ($null -ne $u.CurrentUsage) { [int]$u.CurrentUsage } else { 0 }
        $peakUsage = if ($null -ne $u.PeakUsage) { [int]$u.PeakUsage } else { 0 }

        $pageFilesList.Add([pscustomobject]@{
            Path                = $p
            Drive               = $drv
            InitialSizeMB       = 0
            MaximumSizeMB       = 0
            AllocatedBaseSizeMB = $allocSize
            CurrentUsageMB      = $curUsage
            PeakUsageMB         = $peakUsage
            IsSystemDrive       = ($drv -ieq $sysDrive)
        })
        if ($drv) { [void]$processedDrives.Add($drv) }
    }

    # 若仍为空，尝试解析注册表
    if ($pageFilesList.Count -eq 0 -and $regPaging) {
        foreach ($line in @($regPaging)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -ge 1) {
                $p = $parts[0]
                $drv = if ($p.Length -ge 2 -and $p[1] -eq ':') { $p.Substring(0, 2).ToUpper() } else { '' }
                $initSize = if ($parts.Count -ge 2 -and $parts[1] -match '^\d+$') { [int]$parts[1] } else { 0 }
                $maxSize = if ($parts.Count -ge 3 -and $parts[2] -match '^\d+$') { [int]$parts[2] } else { 0 }

                $pageFilesList.Add([pscustomobject]@{
                    Path                = $p
                    Drive               = $drv
                    InitialSizeMB       = $initSize
                    MaximumSizeMB       = $maxSize
                    AllocatedBaseSizeMB = $initSize
                    CurrentUsageMB      = 0
                    PeakUsageMB         = 0
                    IsSystemDrive       = ($drv -ieq $sysDrive)
                })
            }
        }
    }

    return [pscustomobject]@{
        TotalPhysicalMemoryBytes = $totalBytes
        TotalPhysicalMemoryMB    = $totalMB
        TotalPhysicalMemoryGB    = $totalGB
        AutomaticManagedPagefile = $autoManaged
        PageFiles                = @($pageFilesList)
        Volumes                  = @($parsedVolumes)
        RawRegistryPagingFiles   = @($regPaging)
    }
}

function Get-PagefileRecommendations {
    <#
    .SYNOPSIS
        根据当前系统的物理 RAM 容量和驱动器分区分布计算只读个性化配置建议。
    .DESCRIPTION
        遵循核心阶梯规则：
          - RAM <= 16GB: 建议固定初始 1.5x RAM，最大 2.0x~3.0x RAM。
          - RAM 24GB~32GB: 建议固定初始 1.0x~1.5x RAM，最大 1.5x~2.0x RAM（或固定 32GB~48GB 防碎片）。
          - RAM >= 64GB: 建议固定 16GB~24GB，最大 32GB~48GB。
          - 盘符规划：优先放置在高速 SSD/NVMe 非系统盘（如 D:），关闭系统 C: 盘托管以防碎片与写入放大。
          - 防碎片建议：初始大小与最大大小设为相同数值，彻底消除页面文件动态扩展碎片。
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    param(
        [double]$TotalPhysicalMemoryGB = 0,
        [object[]]$Volumes = $null,
        [object]$CurrentStatus = $null
    )

    # 若未直接传参，则从 CurrentStatus 或实时获取
    $status = $CurrentStatus
    if ($TotalPhysicalMemoryGB -le 0 -and $status) {
        $TotalPhysicalMemoryGB = $status.TotalPhysicalMemoryGB
    }
    if ($TotalPhysicalMemoryGB -le 0) {
        $status = Get-PagefileStatus
        $TotalPhysicalMemoryGB = $status.TotalPhysicalMemoryGB
    }
    if ($null -eq $Volumes -and $status) {
        $Volumes = $status.Volumes
    }

    # 规范化标称容量（避免 23.78GB 这种硬件保留造成的浮点漂移）
    $normGB = $TotalPhysicalMemoryGB
    if ($normGB -gt 0) {
        $commonCaps = @(4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 256)
        foreach ($cap in $commonCaps) {
            if ([math]::Abs($normGB - $cap) -lt 1.5) {
                $normGB = [double]$cap
                break
            }
        }
    }

    # 1. 计算内存容量阶梯推荐
    $tier = ''
    $tierDesc = ''
    $rationale = ''
    [int]$initMB = 0
    [int]$maxMB = 0
    [int]$antiFragMB = 0

    if ($normGB -le 16.0) {
        $tier = '<=16GB'
        $tierDesc = '小内存配置 (<=16GB)'
        $initMB = [int][math]::Round($normGB * 1024 * 1.5)
        $maxMB = [int][math]::Round($normGB * 1024 * 3.0)
        $antiFragMB = $initMB
        $rationale = '物理内存容量较紧凑，高负载多任务或大型游戏时极易发生内存溢出，建议初始设为 1.5x RAM，最大设为 2.0x~3.0x RAM。为彻底消除碎片，建议初始与最大均固定为 ' + $antiFragMB + ' MB。'
    }
    elseif ($normGB -lt 64.0) {
        # 24GB~32GB (含 48GB 等中等内存阶梯)
        $tier = '24GB~32GB'
        $tierDesc = '中等内存配置 (24GB~32GB)'
        $initMB = [int][math]::Round($normGB * 1024 * 1.0)
        $maxMB = [int][math]::Round($normGB * 1024 * 2.0)
        # 固定 32GB~48GB 防碎片
        $antiFragMB = if ($normGB -le 24.0) {
            32768 # 32 GB 固定
        } elseif ($normGB -le 32.0) {
            32768 # 32 GB 固定
        } else {
            49152 # 48 GB 固定
        }
        $rationale = '物理内存充裕，日常与绝大多数 3A 游戏无需频繁换页。建议固定初始 1.0x~1.5x RAM，最大 1.5x~2.0x RAM；或初始与最大均固定为 ' + $antiFragMB + ' MB（' + ($antiFragMB / 1024) + ' GB）以彻底杜绝碎片化。'
    }
    else {
        # RAM >= 64GB
        $tier = '>=64GB'
        $tierDesc = '大内存配置 (>=64GB)'
        $initMB = 16384 # 16 GB
        $maxMB = 32768  # 32 GB
        $antiFragMB = 16384
        $rationale = '大容量物理内存极少产生内存压力，保留页面文件主要为兼容强依赖虚拟内存的特定专业软件/游戏引擎，并保留系统发生异常蓝屏时的转储（Memory Dump）空间。建议固定 16GB~24GB，最大 32GB~48GB。'
    }

    # 2. 盘符与分区选择规划
    $sysDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\') } else { 'C:' }
    $recDrive = $sysDrive
    $disableSysDrive = $false
    $driveAdvice = ''

    # 筛选候选非系统驱动器（固态优先，剩余空间大于最大需求 + 10GB 缓冲）
    $minFreeSpaceRequiredGB = [math]::Ceiling($maxMB / 1024.0) + 10.0
    $candidates = @()
    if ($Volumes) {
        $candidates = @($Volumes | Where-Object {
            $dl = if ($_.DriveLetter) { $_.DriveLetter } elseif ($_.DeviceID) { $_.DeviceID } else { '' }
            $dl = $dl.TrimEnd('\')
            $free = if ($null -ne $_.FreeSpaceGB) { [double]$_.FreeSpaceGB } else { ([double]$_.FreeSpace / 1GB) }
            ($dl -ine $sysDrive) -and ($free -ge $minFreeSpaceRequiredGB)
        })
    }

    if ($candidates.Count -gt 0) {
        $selectedVol = $candidates[0]
        $recDrive = if ($selectedVol.DriveLetter) { $selectedVol.DriveLetter.TrimEnd('\') } else { $selectedVol.DeviceID.TrimEnd('\') }
        $disableSysDrive = $true
        $driveAdvice = "检测到可用非系统驱动器 $recDrive`:`（可用空间充足），建议将页面文件迁移至高速 SSD/NVMe 非系统盘 $recDrive`:`，并彻底关闭系统盘 $sysDrive`:` 的分页文件以消除系统盘空间挤占与写入碎片。"
    } else {
        $recDrive = $sysDrive
        $disableSysDrive = $false
        $driveAdvice = "当前未检测到具备充裕可用空间的非系统盘，建议保留在系统盘 $sysDrive`:`，但务必将初始大小与最大大小设为相同数值，消除动态扩展带来的磁盘碎片。"
    }

    $antiFragAdvice = "建议将初始大小（Initial Size）与最大大小（Maximum Size）设为相同数值（推荐 $antiFragMB MB），彻底消除页面文件动态扩容产生的磁盘碎片与寻道延迟。"

    # 3. 构造标准 Windows 系统属性 GUI 设置指引
    $guiSteps = [System.Collections.Generic.List[string]]::new()
    $guiSteps.Add('1. 按 Win + R 快捷键打开“运行”对话框，输入 sysdm.cpl 并按回车。')
    $guiSteps.Add('2. 在弹出的“系统属性”窗口中，切换到顶部【高级】选项卡。')
    $guiSteps.Add('3. 在“性能”分组框中，点击【设置】按钮打开“性能选项”。')
    $guiSteps.Add('4. 在“性能选项”窗口中，切换到【高级】选项卡。')
    $guiSteps.Add('5. 在“虚拟内存”分组框中，点击【更改】按钮。')
    $guiSteps.Add('6. 取消勾选顶部的【自动管理所有驱动器的分页文件大小】。')
    if ($disableSysDrive) {
        $guiSteps.Add("7. 在驱动器列表中选中系统盘（$sysDrive），单选下方【无分页文件】，点击【设置】按钮确认。")
        $guiSteps.Add("8. 选中推荐驱动器（$recDrive），单选【自定义大小】，初始大小输入 $antiFragMB，最大大小输入 $antiFragMB，点击【设置】按钮。")
    } else {
        $guiSteps.Add("7. 选中驱动器（$sysDrive），单选【自定义大小】，初始大小输入 $antiFragMB，最大大小输入 $antiFragMB，点击【设置】按钮。")
    }
    $guiSteps.Add('9. 连续点击【确定】退出全部对话框，并在系统弹出重启提示时重启计算机使其生效。')

    $guiGuide = [pscustomobject]@{
        RunCommand  = 'sysdm.cpl'
        Navigation  = '系统属性 (sysdm.cpl) -> 高级 -> 性能设置 -> 高级 -> 虚拟内存'
        Steps       = ($guiSteps -join "`r`n")
    }

    # 4. 构造用于高级用户手动执行的 PowerShell 命令参考（仅供展示，绝不自动执行）
    $psLines = [System.Collections.Generic.List[string]]::new()
    $psLines.Add('# === 虚拟内存手动配置 PowerShell 参考命令（管理员身份运行）===')
    $psLines.Add('# 步骤 1：关闭全盘自动托管')
    $psLines.Add('Set-CimInstance -Query "Select * from Win32_ComputerSystem" -Property @{AutomaticManagedPagefile = $false}')
    if ($disableSysDrive) {
        $psLines.Add("# 步骤 2：移除系统盘 ($sysDrive) 页面文件")
        $psLines.Add("Get-CimInstance Win32_PageFileSetting | Where-Object { `$_.Name -like '$sysDrive*' } | Remove-CimInstance")
        $psLines.Add("# 步骤 3：在目标盘 ($recDrive) 建立固定防碎片页面文件")
        $psLines.Add("New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name = '$($recDrive)\pagefile.sys'; InitialSize = $antiFragMB; MaximumSize = $antiFragMB}")
    } else {
        $psLines.Add("# 步骤 2：设置系统盘 ($sysDrive) 固定防碎片页面文件")
        $psLines.Add("Get-CimInstance Win32_PageFileSetting | Where-Object { `$_.Name -like '$sysDrive*' } | Remove-CimInstance")
        $psLines.Add("New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name = '$($sysDrive)\pagefile.sys'; InitialSize = $antiFragMB; MaximumSize = $antiFragMB}")
    }
    $psLines.Add('# 步骤 4：重启计算机生效')
    $psLines.Add('# Restart-Computer')
    $manualPs = ($psLines -join "`r`n")

    return [pscustomobject]@{
        TotalPhysicalMemoryGB      = $TotalPhysicalMemoryGB
        NormalizedRAM_GB           = $normGB
        Tier                       = $tier
        TierDescription            = $tierDesc
        RecommendedInitialMB       = $initMB
        RecommendedMaximumMB       = $maxMB
        AntiFragmentationInitialMB = $antiFragMB
        AntiFragmentationMaximumMB = $antiFragMB
        RecommendedDrive           = $recDrive
        DisableSystemDrivePagefile = $disableSysDrive
        Rationale                  = $rationale
        DriveAdvice                = $driveAdvice
        AntiFragmentationAdvice    = $antiFragAdvice
        GuiGuide                   = $guiGuide
        ManualPowerShellCommand    = $manualPs
    }
}

function Invoke-PagefileModule {
    <#
    .SYNOPSIS
        纯只读展示当前系统虚拟内存状态、个性化设置建议与手动配置指南。
    .DESCRIPTION
        绝对只读原则：任何情况下均不执行写入，不自动化修改系统页面文件。
    #>
    [CmdletBinding()]
    param([string]$Action = '')

    # 保持与其他模块在非交互/自动化调度下的参数兼容
    if ($Action -and $Action -ne '0' -and $Action -ne 'status') {
        Write-Host ("[INFO] 虚拟内存模块仅支持只读诊断与建议 (Action: {0})" -f $Action) -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "============ [虚拟内存] 只读诊断与个性化配置建议指引 ============" -ForegroundColor Cyan
    Write-Host "【重要声明】本模块严格遵循只读原则，绝不自动化修改系统虚拟内存/页面文件！" -ForegroundColor Yellow
    Write-Host "            尊重不同机型硬件配置与个人分区习惯，提供权威指引与手动参考。" -ForegroundColor Gray
    Write-Host ""

    # 1. 采集状态
    $status = Get-PagefileStatus
    $rec = Get-PagefileRecommendations -CurrentStatus $status

    # 2. 当前状态报告
    Write-Host "--- [当前系统内存与页面文件状态] ---" -ForegroundColor White
    Write-Host ("物理内存容量 : {0} GB ({1} MB)" -f $status.TotalPhysicalMemoryGB, $status.TotalPhysicalMemoryMB)
    Write-Host ("自动托管状态 : {0}" -f $(if ($status.AutomaticManagedPagefile) { "已启用 (系统自动管理所有驱动器)" } else { "已禁用 (自定义/手动配置)" }))

    if ($status.PageFiles.Count -gt 0) {
        Write-Host "当前页面文件 :"
        foreach ($pf in $status.PageFiles) {
            Write-Host ("  - 路径: {0} | 初始: {1} MB | 最大: {2} MB | 当前分配: {3} MB | 当前使用: {4} MB" -f `
                $pf.Path, $pf.InitialSizeMB, $pf.MaximumSizeMB, $pf.AllocatedBaseSizeMB, $pf.CurrentUsageMB)
        }
    } else {
        Write-Host "当前页面文件 : 未检测到活跃的独立页面文件定义（完全由 Windows 动态内核托管）"
    }

    if ($status.Volumes.Count -gt 0) {
        Write-Host "检测到本地磁盘分区 :"
        foreach ($vol in $status.Volumes) {
            $isSys = if ($vol.IsSystemDrive) { " [系统盘]" } else { "" }
            Write-Host ("  - 盘符: {0} | 文件系统: {1} | 剩余: {2} GB / 总计: {3} GB{4}" -f `
                $vol.DriveLetter, $vol.FileSystem, $vol.FreeSpaceGB, $vol.TotalSizeGB, $isSys)
        }
    }
    Write-Host ""

    # 3. 个性化推荐与分析
    Write-Host "--- [根据硬件配置的个性化建议] ---" -ForegroundColor White
    Write-Host ("内存容量档位 : {0} (标称约 {1} GB)" -f $rec.TierDescription, $rec.NormalizedRAM_GB)
    Write-Host ("推荐初始大小 : {0} MB" -f $rec.RecommendedInitialMB)
    Write-Host ("推荐最大大小 : {0} MB" -f $rec.RecommendedMaximumMB)
    Write-Host ("防碎片推荐值 : 初始与最大均固定为 {0} MB (彻底消除碎片)" -f $rec.AntiFragmentationInitialMB) -ForegroundColor Green
    Write-Host ("推荐目标驱动器 : {0}" -f $rec.RecommendedDrive)
    Write-Host ""
    Write-Host ("规划理由 : {0}" -f $rec.Rationale) -ForegroundColor Gray
    Write-Host ("盘符规划 : {0}" -f $rec.DriveAdvice) -ForegroundColor Gray
    Write-Host ("碎片消除 : {0}" -f $rec.AntiFragmentationAdvice) -ForegroundColor Gray
    Write-Host ""

    # 4. Windows 官方 GUI 图形化手动设置指引
    Write-Host "--- [图形化设置指引 (推荐手工操作)] ---" -ForegroundColor Yellow
    Write-Host ("设置入口 : 快捷键 Win+R 输入 {0} 并回车" -f $rec.GuiGuide.RunCommand) -ForegroundColor Cyan
    Write-Host $rec.GuiGuide.Steps
    Write-Host ""

    # 5. 高级用户 PowerShell 手动设置参考
    Write-Host "--- [高级用户 PowerShell 手动设置参考 (仅供查阅，未执行)] ---" -ForegroundColor White
    Write-Host "如需以脚本方式应用以上推荐值，可复制以下命令在管理员终端中手动运行：" -ForegroundColor Gray
    Write-Host $rec.ManualPowerShellCommand -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "[OK] 只读诊断与配置建议完成；未对系统做任何变更。" -ForegroundColor Green

    return [pscustomobject]@{
        Status          = $status
        Recommendations = $rec
    }
}
