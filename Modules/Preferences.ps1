# Preferences.ps1 - Part 21 XOS 清单第 4 节「未覆盖但可考虑的候选」6 项
# 来源：docs/reference/XOS-PLAYBOOK-INVENTORY.md 第 4 节（imribiy/xos-playbook dev @0ed60c3）
#
# 定位：低风险可选偏好与系统能力开关，默认什么都不做；逐项执行，写入前落 preferences-backup.json。
# 第 4 节末尾「明确不建议纳入的疑似候选」（SvcHostSplit*、MiracastForceDisable、WarpSupportsResourceResidency、
# DisableProjectedShadows/DisableGlobalAnimations、NoLazyMode）按原判据继续不纳入。

$script:preferenceItems = @(
    [pscustomobject]@{
        Id         = 'P1'
        Name       = '关闭鼠标加速（提高指针精确度）'
        Note       = '去掉指针加速度曲线，指针位移与手移动 1:1；三项都是 HKCU 偏好，需重新登录或重启 explorer。'
        Operations = @(
            @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Kind = 'String'; Value = '0' }
            @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Kind = 'String'; Value = '0' }
            @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Kind = 'String'; Value = '0' }
        )
    }
    [pscustomobject]@{
        Id         = 'P2'
        Name       = '关闭 Fault Tolerant Heap（FTH）'
        Note       = 'FTH 会在进程反复崩溃后被强制启用并注入 shim；只写 HKLM\SOFTWARE\Microsoft\FTH\Enabled=0，不跑 rundll32 fthsvc 重初始化。'
        Operations = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\FTH'; Name = 'Enabled'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'P3'
        Name       = '启用长路径支持（LongPathsEnabled=1）'
        Note       = '解除 260 字符路径限制，微软官方支持；属系统能力开关，不是性能项，应用还需 manifest 声明 longPathAware。'
        Operations = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'LongPathsEnabled'; Kind = 'DWord'; Value = 1 }
        )
    }
    [pscustomobject]@{
        Id         = 'P4'
        Name       = 'PrintScreen 直接全屏截图'
        Note       = 'PrtSc 直接把全屏放进剪贴板，而不是弹截图工具；纯 HKCU 偏好。'
        Operations = @(
            @{ Path = 'HKCU:\Control Panel\Keyboard'; Name = 'PrintScreenKeyForSnippingEnabled'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'P5'
        Name       = '关闭输入应用预加载'
        Note       = '只写 HKCU 侧（不影响其他用户）；关掉输入法/输入应用的常驻预加载，对低内存机器有实际收益。'
        Operations = @(
            @{ Path = 'HKCU:\Software\Microsoft\Input'; Name = 'IsInputAppPreloadEnabled'; Kind = 'DWord'; Value = 0 }
        )
    }
    [pscustomobject]@{
        Id         = 'P6'
        Name       = '关闭壁纸主色自动提取'
        Note       = '换壁纸时不再计算主色刷新强调色，强调色固定；收益小但零风险。'
        Operations = @(
            @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'AutoColorization'; Kind = 'DWord'; Value = 0 }
        )
    }
)

function Get-PreferenceItems {
    return $script:preferenceItems
}

function Get-PreferencePlan {
    <# 展开指定项的写入目标；备份与应用共用同一份计划。 #>
    param([string[]]$ItemIds)
    if ($null -eq $ItemIds -or @($ItemIds).Count -eq 0) { throw '必须指定至少一个候选项' }
    $known = @{}
    foreach ($item in $script:preferenceItems) { $known[$item.Id] = $item }

    $operations = [System.Collections.Generic.List[object]]::new()
    $ids = @()
    foreach ($id in @($ItemIds)) {
        if (-not $known.ContainsKey($id)) { throw "未知的候选项：$id" }
        $item = $known[$id]
        $ids += $id
        foreach ($op in @($item.Operations)) {
            $operations.Add([pscustomobject]@{ Scope = $id; Path = [string]$op.Path; Name = [string]$op.Name; Kind = [string]$op.Kind; Value = $op.Value })
        }
    }

    $unique = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($op in $operations) {
        $key = ('{0}|{1}' -f $op.Path, $op.Name).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($op)
    }
    return [pscustomobject]@{ ItemIds = @($ids); Operations = @($unique) }
}

function Show-PreferenceStatus {
    foreach ($item in $script:preferenceItems) {
        Write-Host ("[{0}] {1}" -f $item.Id, $item.Name) -ForegroundColor Cyan
        foreach ($op in @($item.Operations)) {
            $current = Get-TweakRegistryValue -Path $op.Path -Name $op.Name
            $state = if ($current.Exists) { "{0}（{1}）" -f $current.Value, $current.Kind } else { '<未设置（系统默认）>' }
            Write-Host ("  {0} -> {1} = {2}" -f $op.Path, $op.Name, $state)
        }
    }
    if (Test-Path -LiteralPath $script:preferencesBackupFile -PathType Leaf) {
        Write-Host "可选偏好备份文件就绪：$($script:preferencesBackupFile)" -ForegroundColor Yellow
    } else {
        Write-Host "尚未创建可选偏好备份文件：$($script:preferencesBackupFile)" -ForegroundColor Gray
    }
}

function Invoke-PreferenceModule {
    param(
        [string]$Action = '',
        [string]$BackupFile = $script:preferencesBackupFile
    )

    Write-Host ""
    Write-Host "============ [Part 21] 可选偏好与系统行为（XOS 第 4 节候选） / Preferences ============" -ForegroundColor Cyan
    Write-Host " 本节为低风险可选偏好，默认什么都不做；逐项执行，写入前落 preferences-backup.json。" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   0. 查看 6 项当前状态（只读）" -ForegroundColor White
    $index = 0
    foreach ($item in $script:preferenceItems) {
        $index++
        Write-Host ("  {0,2}. [{1}] {2}" -f $index, $item.Id, $item.Name) -ForegroundColor White
    }
    Write-Host "   r. 按快照恢复全部（preferences-backup.json）" -ForegroundColor White
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定子操作（0=status、1-6=逐项应用、r=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host '请输入 0-6 或 r 并回车'
    }

    if ($Action -in @('0', 'status')) {
        Show-PreferenceStatus
        return $true
    }
    if ($Action -in @('r', 'restore', 'reset')) {
        return (Restore-TypedValueBackup -BackupFile $BackupFile -Label '可选偏好')
    }

    $item = $null
    if ($Action -match '^(?<idx>[1-6])$') {
        $item = $script:preferenceItems[[int]$Matches['idx'] - 1]
    } elseif ($Action -match '^P(?<num>[1-6])$') {
        $item = $script:preferenceItems | Where-Object { $_.Id -eq ('P' + $Matches['num']) } | Select-Object -First 1
    }
    if (-not $item) {
        Write-Host "[FAIL] 无效的子操作：$Action（可用 0、1-6、r）" -ForegroundColor Red
        $script:fail++
        return $false
    }

    Write-Host ""
    Write-Host ("[{0}] {1}" -f $item.Id, $item.Name) -ForegroundColor Yellow
    Write-Host $item.Note -ForegroundColor Gray

    $plan = Get-PreferencePlan -ItemIds @($item.Id)
    if (-not (Ensure-TypedValueBackup -BackupFile $BackupFile -Plan $plan -Label '可选偏好')) {
        Write-Host '[FAIL] 无法备份原始状态，已阻止修改。' -ForegroundColor Red
        return $false
    }

    $beforeFail = $script:fail
    try {
        foreach ($op in @($plan.Operations)) {
            Set-TweakRegistryTypedValue -Path $op.Path -Name $op.Name -Kind $op.Kind -Value $op.Value
            Write-Host ("  [+] {0} -> {1} = {2}（{3}）" -f $op.Path, $op.Name, $op.Value, $op.Kind) -ForegroundColor Green
            $script:ok++
            $script:rebootRequired = $true
        }
        if ($script:fail -gt $beforeFail) { throw '写入过程中出现失败项' }
        Write-Host ("[OK] {0} 已应用。" -f $item.Id) -ForegroundColor Green
    } catch {
        Write-Host ("[FAIL] {0} 应用失败：{1}；正在按快照回滚。" -f $item.Id, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
        Restore-TypedValueBackup -BackupFile $BackupFile -Label '可选偏好' | Out-Null
        return $false
    }

    Request-Restart
    return $true
}
