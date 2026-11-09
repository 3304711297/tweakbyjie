# ShaderCache.ps1 - 模块 16：着色器缓存扫描与清理（维护项，不可还原）
# 缓存是可再生数据：清理后由驱动/游戏自动重建，因此本项目不为它生成快照。
# 只清理系统与显卡驱动的缓存目录，不触碰任何游戏安装目录。

function Format-ByteSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Get-ShaderCacheDirectories {
    <#
    .SYNOPSIS
        返回系统与三大显卡厂商的着色器缓存目录（只列路径，不保证存在）。
    #>
    $local = $env:LOCALAPPDATA
    $programData = $env:ProgramData
    @(
        [pscustomobject]@{ Label = 'DirectX 着色器缓存'; Path = (Join-Path $local 'D3DSCache') }
        [pscustomobject]@{ Label = 'NVIDIA DX 缓存'; Path = (Join-Path $local 'NVIDIA\DXCache') }
        [pscustomobject]@{ Label = 'NVIDIA GL 缓存'; Path = (Join-Path $local 'NVIDIA\GLCache') }
        [pscustomobject]@{ Label = 'NVIDIA 全局缓存'; Path = (Join-Path $programData 'NVIDIA Corporation\NV_Cache') }
        [pscustomobject]@{ Label = 'AMD DX 缓存'; Path = (Join-Path $local 'AMD\DxCache') }
        [pscustomobject]@{ Label = 'AMD DXC 缓存'; Path = (Join-Path $local 'AMD\DxcCache') }
        [pscustomobject]@{ Label = 'Intel 着色器缓存'; Path = (Join-Path $local 'Intel\ShaderCache') }
    )
}

function Test-CachePathReparsePoint {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    } catch {
        return $false
    }
}

function Get-ShaderCacheFiles {
    <#
    .SYNOPSIS
        安全枚举缓存文件：不跟随目录联接/符号链接，避免越界删除。
    .DESCRIPTION
        Directories 可注入（测试用临时目录）。返回 Files / Rejected / TotalBytes。
    #>
    [CmdletBinding()]
    param([string[]]$Directories = $null)

    if ($null -eq $Directories) {
        $Directories = @(Get-ShaderCacheDirectories | ForEach-Object Path)
    }

    $files = [System.Collections.Generic.List[object]]::new()
    $rejected = [System.Collections.Generic.List[string]]::new()

    foreach ($root in @($Directories)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        if (Test-CachePathReparsePoint $root) { $rejected.Add($root); continue }

        $stack = [System.Collections.Generic.Stack[string]]::new()
        $stack.Push($root)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            foreach ($file in @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)) {
                if ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $rejected.Add($file.FullName)
                } else {
                    $files.Add($file)
                }
            }
            foreach ($sub in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $rejected.Add($sub.FullName)
                } else {
                    $stack.Push($sub.FullName)
                }
            }
        }
    }

    $total = 0L
    foreach ($file in $files) { $total += [int64]$file.Length }
    [pscustomobject][ordered]@{
        Files      = @($files)
        Rejected   = @($rejected)
        TotalBytes = $total
    }
}

function Clear-ShaderCacheFiles {
    <#
    .SYNOPSIS
        逐文件删除缓存；目录本身保留（可能被驱动持有）。
    .DESCRIPTION
        不删目录、不跟随联接、不因单个文件被占用而中断其余删除。
        返回 Deleted / Failed / FreedBytes / Rejected。
    #>
    [CmdletBinding()]
    param([string[]]$Directories = $null)

    $scan = Get-ShaderCacheFiles -Directories $Directories
    $deleted = 0
    $failed = 0
    $freed = 0L
    foreach ($file in @($scan.Files)) {
        try {
            $length = [int64]$file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $deleted++
            $freed += $length
        } catch {
            $failed++
        }
    }
    [pscustomobject][ordered]@{
        Deleted    = $deleted
        Failed     = $failed
        FreedBytes = $freed
        Rejected   = @($scan.Rejected)
    }
}

function Invoke-ShaderCacheModule {
    <#
    .SYNOPSIS
        模块 16：扫描/清理着色器缓存。
    .DESCRIPTION
        维护项：缓存为可再生数据，不产生备份，也无法“还原”；
        清理后首次进游戏会重新编译着色器，头一两局可能更卡。
    #>
    [CmdletBinding()]
    param([string]$Action = '')

    Write-Host ''
    Write-Host '============ [着色器缓存] 扫描与清理（维护项，不可还原） ============' -ForegroundColor Cyan
    Write-Host '缓存是可再生数据，清理后由驱动/游戏自动重建；本模块不生成快照。' -ForegroundColor Gray
    Write-Host '只清理系统与显卡驱动缓存目录，不触碰任何游戏安装目录。' -ForegroundColor Gray
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定着色器缓存子操作（1=扫描、2=清理）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host '请输入 1（扫描）、2（清理）或 0（返回）并回车'
    }

    if ($Action -eq '0' -or $Action -ieq 'back') {
        Write-Host '[返回] 已返回主菜单。' -ForegroundColor Green
        return $true
    }

    if ($Action -eq '1' -or $Action -ieq 'scan') {
        $scan = Get-ShaderCacheFiles
        Write-Host '--- [缓存占用] ---' -ForegroundColor White
        foreach ($entry in @(Get-ShaderCacheDirectories)) {
            if (-not (Test-Path -LiteralPath $entry.Path -PathType Container)) { continue }
            $dirScan = Get-ShaderCacheFiles -Directories @($entry.Path)
            Write-Host ("  {0}：{1} 个文件，{2}" -f $entry.Label, @($dirScan.Files).Count, (Format-ByteSize $dirScan.TotalBytes))
        }
        Write-Host ("合计：{0} 个文件，{1}" -f @($scan.Files).Count, (Format-ByteSize $scan.TotalBytes)) -ForegroundColor Yellow
        if (@($scan.Rejected).Count -gt 0) {
            Write-Host ("[INFO] 跳过 {0} 个重解析点（目录联接/符号链接），不会越界删除。" -f @($scan.Rejected).Count) -ForegroundColor DarkGray
        }
        return [pscustomobject]@{ Scan = $scan }
    }

    if ($Action -eq '2' -or $Action -ieq 'clean') {
        $scan = Get-ShaderCacheFiles
        if (@($scan.Files).Count -eq 0) {
            Write-Host '[SKIP] 未发现可清理的缓存文件。' -ForegroundColor Yellow
            $script:skip++
            return $true
        }
        Write-Host ("准备清理 {0} 个文件，约 {1}。" -f @($scan.Files).Count, (Format-ByteSize $scan.TotalBytes)) -ForegroundColor Yellow
        Write-Host '注意：清理后首次进游戏会重新编译着色器，头一两局可能比现在更卡；若掉帧不是从游戏更新后才开始的，本项大概率无效。' -ForegroundColor Yellow
        if (-not (Test-ConfirmChoice '确定清理着色器缓存吗？Y = 清理 / 其他键取消')) {
            Write-Host '[SKIP] 已取消，未删除任何文件。' -ForegroundColor Yellow
            $script:skip++
            return $true
        }
        $result = Clear-ShaderCacheFiles
        Write-Host ("[OK] 已删除 {0} 个文件，释放 {1}。" -f $result.Deleted, (Format-ByteSize $result.FreedBytes)) -ForegroundColor Green
        if ($result.Failed -gt 0) {
            Write-Host ("[WARN] {0} 个文件被占用或无法删除（关闭游戏/驱动面板后可重试）；这不影响其余文件。" -f $result.Failed) -ForegroundColor Yellow
        }
        $script:ok++
        return [pscustomobject]@{ Scan = $scan; Clean = $result }
    }

    Write-Host ("[FAIL] 无效输入：{0}。请输入 1、2 或 0。" -f $Action) -ForegroundColor Red
    $script:fail++
    return $false
}
