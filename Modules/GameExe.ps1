# GameExe.ps1 - 模块 17：按游戏 exe 应用三项配置
# 1) 禁用全屏优化（HKCU AppCompatFlags\Layers）
# 2) 高性能 GPU 首选项（HKCU DirectX\UserGpuPreferences）
# 3) IFEO PerfOptions CpuPriorityClass=3（仅 CPU 优先级；IFEO 的 IoPriority 只支持 Normal 及以下）
# 写入前保存三项原值；还原时逐项写回，原本不存在的值删除。

function Resolve-GameExePath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { throw '游戏 exe 路径不能为空' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "文件不存在：$Path" }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ([System.IO.Path]::GetExtension($full) -ine '.exe') { throw '必须选择 .exe 文件' }
    $windowsRoot = [System.IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')
    if ($full.StartsWith($windowsRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw '拒绝操作系统目录内的可执行文件'
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw '拒绝重解析点路径' }
    return $full
}

function Get-GameExeTargets {
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [string]$FsoKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
        [string]$GpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences',
        [string]$IfeoRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )
    $exeName = Split-Path -Leaf $GamePath
    @(
        [pscustomobject]@{ Path = $FsoKey; Name = $GamePath; Value = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'; Kind = 'String'; Label = '禁用全屏优化' }
        [pscustomobject]@{ Path = $GpuKey; Name = $GamePath; Value = 'GpuPreference=2;'; Kind = 'String'; Label = '高性能 GPU 首选项' }
        [pscustomobject]@{ Path = (Join-Path $IfeoRoot "$exeName\PerfOptions"); Name = 'CpuPriorityClass'; Value = 3; Kind = 'DWord'; Label = '进程 CPU 优先级=高' }
    )
}

function Test-GameExeBackupSchema {
    param([object]$Backup)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$Backup.GamePath) -or [System.IO.Path]::GetExtension([string]$Backup.GamePath) -ine '.exe') { return $false }
        $values = @($Backup.Values)
        if ($values.Count -ne 3) { return $false }
        foreach ($value in $values) {
            if ([string]::IsNullOrWhiteSpace([string]$value.Path) -or [string]::IsNullOrWhiteSpace([string]$value.Name)) { return $false }
            if ($null -eq $value.Exists) { return $false }
            if ([bool]$value.Exists) {
                if ([string]::IsNullOrWhiteSpace([string]$value.Kind) -or $null -eq $value.Data) { return $false }
                try { $null = Convert-RegKindForExe ([string]$value.Kind) } catch { return $false }
            } elseif ($null -ne $value.Kind -or $null -ne $value.Data) { return $false }
        }
        return $true
    } catch { return $false }
}

function Set-GameExeTarget {
    param([Parameter(Mandatory = $true)][object]$Target)
    $before = $script:fail
    if ($Target.Kind -eq 'DWord') {
        Set-RegDword $Target.Path $Target.Name $Target.Value $Target.Label
        if ($script:fail -gt $before) { return $false }
        return [bool](Verify-RegDword $Target.Path $Target.Name ([uint32]$Target.Value) $Target.Label)
    }
    Set-RegString $Target.Path $Target.Name $Target.Value $Target.Label
    if ($script:fail -gt $before) { return $false }
    try {
        $item = Get-Item -LiteralPath $Target.Path -ErrorAction Stop
        $actual = [string]$item.GetValue($Target.Name)
        if ($actual -ceq [string]$Target.Value) {
            Write-Host ("[VERIFY OK] {0} = {1}" -f $Target.Label, $actual) -ForegroundColor Green
            return $true
        }
        Write-Host ("[VERIFY FAIL] {0}：实际={1}，目标={2}" -f $Target.Label, $actual, $Target.Value) -ForegroundColor Red
        $script:fail++
        return $false
    } catch {
        Write-Host ("[VERIFY FAIL] {0}：{1}" -f $Target.Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Invoke-GameExeApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [string]$FsoKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
        [string]$GpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences',
        [string]$IfeoRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options',
        [string]$BackupFile = $script:gameExeBackupFile
    )

    $resolved = Resolve-GameExePath $GamePath
    $targets = @(Get-GameExeTargets -GamePath $resolved -FsoKey $FsoKey -GpuKey $GpuKey -IfeoRoot $IfeoRoot)

    $backup = $null
    if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
        try {
            $backup = Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "现有 game-exe-backup.json 读取失败：$($_.Exception.Message)"
        }
        if (-not (Test-GameExeBackupSchema $backup)) { throw 'game-exe-backup.json 结构或机器绑定校验失败' }
        if ([string]$backup.GamePath -ne $resolved) {
            throw "已有其他游戏的备份（$($backup.GamePath)）；请先还原再切换。"
        }
    } else {
        $values = @()
        foreach ($target in $targets) {
            $snapshot = Get-MpoValueSnapshot @{ Path = $target.Path; Name = $target.Name }
            $keyExisted = Test-Path -LiteralPath $target.Path
            $values += Add-Member -InputObject $snapshot -NotePropertyName 'KeyExists' -NotePropertyValue $keyExisted -PassThru
        }
        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            GamePath  = $resolved
            Values    = @($values)
        }
        if (-not (Test-GameExeBackupSchema $backup)) { throw '生成的游戏 exe 备份未通过结构校验' }
        Write-TweakAtomicTextFile -Path $BackupFile -Content ($backup | ConvertTo-Json -Depth 6)
        Write-Host ("[OK] 已保存三项原值：{0}" -f $BackupFile) -ForegroundColor Green
    }

    $allOk = $true
    foreach ($target in $targets) {
        if (-not (Set-GameExeTarget $target)) { $allOk = $false; break }
    }
    if (-not $allOk) {
        Write-Host '[FAIL] 有一项未写入成功，正在按原始值回滚。' -ForegroundColor Red
        Invoke-GameExeRestore -BackupFile $BackupFile | Out-Null
        return $false
    }
    Write-Host '[OK] 已为游戏应用：禁用全屏优化、高性能 GPU 首选项、CPU 高优先级（重启游戏后生效）。' -ForegroundColor Green
    return $true
}

function Invoke-GameExeRestore {
    [CmdletBinding()]
    param([string]$BackupFile = $script:gameExeBackupFile)

    if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
        Write-Host '[FAIL] 未找到 game-exe-backup.json，拒绝声称已恢复。' -ForegroundColor Red
        $script:fail++
        return $false
    }
    try {
        $backup = Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host ("[FAIL] game-exe-backup.json 读取失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:fail++
        return $false
    }
    if (-not (Test-GameExeBackupSchema $backup)) {
        Write-Host '[FAIL] game-exe-backup.json 结构或机器绑定校验失败，拒绝恢复。' -ForegroundColor Red
        $script:fail++
        return $false
    }

    $allOk = $true
    foreach ($value in @($backup.Values)) {
        $before = $script:fail
        if ([bool]$value.Exists) {
            $data = if ($value.Kind -eq 'DWord') { [string][uint32]([int64]$value.Data -band 0xFFFFFFFFL) } else { [string]$value.Data }
            & reg.exe ADD (Convert-RegExePath $value.Path) /v $value.Name /t (Convert-RegKindForExe ([string]$value.Kind)) /d $data /f *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("[FAIL] 恢复 {0} : reg.exe exit code {1}" -f $value.Name, $LASTEXITCODE) -ForegroundColor Red
                $script:fail++
            } else {
                Write-Host ("[OK] 已恢复 {0} 原始值" -f $value.Name) -ForegroundColor Green
                $script:ok++
            }
        } else {
            $item = Get-Item -LiteralPath $value.Path -ErrorAction SilentlyContinue
            if ($item -and ($item.GetValueNames() -contains $value.Name)) {
                & reg.exe DELETE (Convert-RegExePath $value.Path) /v $value.Name /f *> $null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host ("[FAIL] 删除 {0} : reg.exe exit code {1}" -f $value.Name, $LASTEXITCODE) -ForegroundColor Red
                    $script:fail++
                } else {
                    Write-Host ("[OK] 已删除新增值 {0}" -f $value.Name) -ForegroundColor Green
                    $script:ok++
                }
            } else {
                Write-Host ("[SKIP] {0} 未设置，无需删除" -f $value.Name) -ForegroundColor Yellow
                $script:skip++
            }
            if ($value.PSObject.Properties['KeyExists'] -and -not [bool]$value.KeyExists) {
                $keyItem = Get-Item -LiteralPath $value.Path -ErrorAction SilentlyContinue
                if ($keyItem -and $keyItem.ValueCount -eq 0 -and $keyItem.SubKeyCount -eq 0) {
                    Remove-Item -LiteralPath $value.Path -Force -ErrorAction SilentlyContinue
                }
            }
        }
        if ($script:fail -gt $before) { $allOk = $false }
    }
    if ($allOk) { Write-Host '[OK] 游戏 exe 三项配置已按原始值恢复。' -ForegroundColor Green }
    else { Write-Host '[WARN] 恢复未完全成功，请复查 FAIL 项。' -ForegroundColor Yellow }
    return $allOk
}

function Get-GameExeStatus {
    param(
        [string]$GamePath,
        [string]$FsoKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
        [string]$GpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences',
        [string]$IfeoRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )
    $targets = @(Get-GameExeTargets -GamePath $GamePath -FsoKey $FsoKey -GpuKey $GpuKey -IfeoRoot $IfeoRoot)
    foreach ($target in $targets) {
        $snapshot = Get-MpoValueSnapshot @{ Path = $target.Path; Name = $target.Name }
        [pscustomobject]@{
            Label   = $target.Label
            Current = $(if ($snapshot.Exists) { "$($snapshot.Data)" } else { '<未设置>' })
            Target  = "$($target.Value)"
            Applied = ($snapshot.Exists -and "$($snapshot.Data)" -eq "$($target.Value)")
        }
    }
}

function Invoke-GameExeModule {
    [CmdletBinding()]
    param([string]$Action = '')

    Write-Host ''
    Write-Host '============ [游戏 exe 配置] 全屏优化 / GPU 首选项 / CPU 优先级 ============' -ForegroundColor Cyan
    Write-Host '仅为选定游戏写入三项；写入前保存原值，可按快照还原。' -ForegroundColor Gray
    Write-Host 'IFEO 只设置 CPU 优先级；IoPriority 经 IFEO 只支持 Normal 及以下，故不写入。' -ForegroundColor Gray
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定子操作（1=查看、2=应用、3=还原）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        Write-Host '  1. 查看当前三项状态'
        Write-Host '  2. 选择游戏 exe 并应用'
        Write-Host '  3. 按快照还原'
        Write-Host '  0. 返回'
        $Action = Read-Host '请输入 0-3 并回车'
    }

    if ($Action -eq '0' -or $Action -ieq 'back') {
        Write-Host '[返回] 已返回主菜单。' -ForegroundColor Green
        return $true
    }

    $backupPath = $script:gameExeBackupFile
    $recordedPath = $null
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (Test-GameExeBackupSchema $existing) { $recordedPath = [string]$existing.GamePath }
        } catch {}
    }

    if ($Action -eq '1' -or $Action -ieq 'status') {
        $gamePath = $recordedPath
        if (-not $gamePath) {
            if ($script:TweakNonInteractive) {
                Write-Host '[FAIL] 尚无已记录的游戏路径；请先以交互方式应用一次。' -ForegroundColor Red
                $script:fail++
                return $false
            }
            $gamePath = Read-Host '请输入游戏主程序完整路径（.exe）'
        }
        $resolved = Resolve-GameExePath $gamePath
        Write-Host ("游戏：{0}" -f $resolved) -ForegroundColor White
        foreach ($row in @(Get-GameExeStatus -GamePath $resolved)) {
            $mark = if ($row.Applied) { '[已生效]' } else { '[未生效]' }
            Write-Host ("  {0} {1}：当前={2}，目标={3}" -f $mark, $row.Label, $row.Current, $row.Target)
        }
        return $true
    }

    if ($Action -eq '2' -or $Action -ieq 'apply') {
        $gamePath = $recordedPath
        if (-not $gamePath) {
            if ($script:TweakNonInteractive) {
                Write-Host '[FAIL] 尚无已记录的游戏路径；请先以交互方式应用一次，或先运行子操作 1 设置路径。' -ForegroundColor Red
                $script:fail++
                return $false
            }
            $gamePath = Read-Host '请输入游戏主程序完整路径（.exe）'
        }
        $resolved = Resolve-GameExePath $gamePath
        Write-Host ("将应用：{0}" -f $resolved) -ForegroundColor Yellow
        foreach ($row in @(Get-GameExeStatus -GamePath $resolved)) {
            Write-Host ("  - {0}：{1} -> {2}" -f $row.Label, $row.Current, $row.Target)
        }
        if (-not (Test-ConfirmChoice '确认写入这三项吗？Y = 应用 / 其他键取消')) {
            Write-Host '[SKIP] 已取消，未做任何修改。' -ForegroundColor Yellow
            $script:skip++
            return $true
        }
        return (Invoke-GameExeApply -GamePath $resolved -BackupFile $backupPath)
    }

    if ($Action -eq '3' -or $Action -ieq 'restore') {
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Write-Host '[SKIP] 未找到游戏 exe 备份，无需还原。' -ForegroundColor Yellow
            $script:skip++
            return $true
        }
        if (-not (Test-ConfirmChoice '确认按快照还原这三项吗？Y = 还原 / 其他键取消')) {
            Write-Host '[SKIP] 已取消，未做任何修改。' -ForegroundColor Yellow
            $script:skip++
            return $true
        }
        return (Invoke-GameExeRestore -BackupFile $backupPath)
    }

    Write-Host ("[FAIL] 无效输入：{0}。请输入 0-3。" -f $Action) -ForegroundColor Red
    $script:fail++
    return $false
}
