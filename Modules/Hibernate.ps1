# Hibernate.ps1 - Part 14 系统休眠与快速启动管理
# 支持查看状态、关闭休眠释放 C:\hiberfil.sys 空间、根据原始快照精确恢复
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

if (-not (Get-Command Get-BackupMachineId -ErrorAction SilentlyContinue)) {
    $commonPath = Join-Path $PSScriptRoot 'Common.ps1'
    if (Test-Path -LiteralPath $commonPath) { . $commonPath }
}
if (-not (Get-Command Initialize-TweakAdapters -ErrorAction SilentlyContinue)) {
    $adaptersPath = Join-Path $PSScriptRoot 'Adapters.ps1'
    if (Test-Path -LiteralPath $adaptersPath) { . $adaptersPath }
}

if (-not $script:hibernateBackupFile) {
    $script:hibernateBackupFile = if ($script:RepoRoot) {
        Join-Path $script:RepoRoot 'hibernate-backup.json'
    } else {
        Join-Path (Split-Path -Parent $PSScriptRoot) 'hibernate-backup.json'
    }
}

function Get-HibernateStatus {
    <#
        .SYNOPSIS
        获取当前系统休眠、快速启动及 hiberfil.sys 文件状态。
    #>
    [CmdletBinding()]
    param(
        [string]$HiberfilePath = 'C:\hiberfil.sys',
        [string]$PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power',
        [string]$SessionPowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    )

    $hibEnabled = 0
    try {
        $pItem = Get-ItemProperty -Path $PowerKey -ErrorAction SilentlyContinue
        if ($pItem -and $null -ne $pItem.PSObject.Properties['HibernateEnabled']) {
            $hibEnabled = [int]$pItem.HibernateEnabled
        }
    } catch {
        $hibEnabled = 0
    }

    $bootEnabled = 0
    try {
        $spItem = Get-ItemProperty -Path $SessionPowerKey -ErrorAction SilentlyContinue
        if ($spItem -and $null -ne $spItem.PSObject.Properties['HiberbootEnabled']) {
            $bootEnabled = [int]$spItem.HiberbootEnabled
        }
    } catch {
        $bootEnabled = 0
    }

    $exists = $false
    [int64]$sizeBytes = 0
    try {
        if (Test-Path -LiteralPath $HiberfilePath -PathType Leaf) {
            $item = Get-Item -LiteralPath $HiberfilePath -Force -ErrorAction Stop
            $exists = $true
            $sizeBytes = [int64]$item.Length
        }
    } catch {
        $exists = $false
        $sizeBytes = 0
    }

    $sizeGB = if ($sizeBytes -gt 0) { [Math]::Round($sizeBytes / 1GB, 2) } else { 0.0 }
    $sizeMB = if ($sizeBytes -gt 0) { [Math]::Round($sizeBytes / 1MB, 2) } else { 0.0 }
    $sizeFormatted = if ($exists) {
        if ($sizeBytes -ge 1GB) { "{0:N2} GB" -f ($sizeBytes / 1GB) } else { "{0:N2} MB" -f ($sizeBytes / 1MB) }
    } else {
        "0 MB"
    }

    return [pscustomobject]@{
        HibernateEnabled      = $hibEnabled
        HiberbootEnabled      = $bootEnabled
        HiberfilExists        = $exists
        HiberfilSizeBytes     = $sizeBytes
        HiberfilSizeMB        = $sizeMB
        HiberfilSizeGB        = $sizeGB
        HiberfilSizeFormatted = $sizeFormatted
        HiberfilePath         = $HiberfilePath
    }
}

function Test-HibernateBackupSchema {
    <#
        .SYNOPSIS
        验证休眠快照结构（Version=1, Binding=Get-BackupMachineId, State 包含合规属性）。
    #>
    [CmdletBinding()]
    param([object]$Backup)

    try {
        if ($null -eq $Backup) { return $false }
        if ([int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }

        $state = $Backup.State
        if ($null -eq $state) { return $false }

        $hibProp = $state.PSObject.Properties['HibernateEnabled']
        $bootProp = $state.PSObject.Properties['HiberbootEnabled']
        if ($null -eq $hibProp -or $null -eq $hibProp.Value) { return $false }
        if ($null -eq $bootProp -or $null -eq $bootProp.Value) { return $false }

        [int]$hibVal = [int]$hibProp.Value
        [int]$bootVal = [int]$bootProp.Value
        if ($hibVal -notin @(0, 1)) { return $false }
        if ($bootVal -notin @(0, 1)) { return $false }

        return $true
    } catch {
        return $false
    }
}

function Ensure-HibernateBackup {
    <#
        .SYNOPSIS
        创建系统休眠与快速启动原始状态快照，已有有效快照幂等复用。
    #>
    [CmdletBinding()]
    param([string]$BackupFile = '')

    try {
        if ([string]::IsNullOrWhiteSpace($BackupFile)) {
            $BackupFile = if ($script:hibernateBackupFile) {
                $script:hibernateBackupFile
            } elseif ($script:RepoRoot) {
                Join-Path $script:RepoRoot 'hibernate-backup.json'
            } else {
                Join-Path (Split-Path -Parent $PSScriptRoot) 'hibernate-backup.json'
            }
        }

        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-HibernateBackupSchema $existing)) {
                Write-Host "[FAIL] 已有休眠快照结构或机器绑定不正确，拒绝覆盖：$BackupFile" -ForegroundColor Red
                return $false
            }
            Write-Host "[OK] 已存在有效的休眠与快速启动原始快照（不会覆盖）：$BackupFile" -ForegroundColor Green
            return $true
        }

        $current = Get-HibernateStatus
        $snapshot = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
            State     = [pscustomobject]@{
                HibernateEnabled  = [int]$current.HibernateEnabled
                HiberbootEnabled  = [int]$current.HiberbootEnabled
                HiberfilExists    = [bool]$current.HiberfilExists
                HiberfilSizeBytes = [int64]$current.HiberfilSizeBytes
            }
        }

        $json = ConvertTo-Json -InputObject $snapshot -Depth 5
        $null = Write-TweakAtomicTextFile -Path $BackupFile -Content $json

        $check = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-HibernateBackupSchema $check)) {
            throw "写入后的休眠快照未通过 schema 校验：$BackupFile"
        }
        Write-Host "[OK] 休眠与快速启动原始状态已备份：$BackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] 备份休眠状态失败：$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Restore-HibernateBackup {
    <#
        .SYNOPSIS
        根据原始快照恢复系统休眠状态（powercfg -h on/off）与注册表设置。
    #>
    [CmdletBinding()]
    param([string]$BackupFile = '')

    try {
        if ([string]::IsNullOrWhiteSpace($BackupFile)) {
            $BackupFile = if ($script:hibernateBackupFile) {
                $script:hibernateBackupFile
            } elseif ($script:RepoRoot) {
                Join-Path $script:RepoRoot 'hibernate-backup.json'
            } else {
                Join-Path (Split-Path -Parent $PSScriptRoot) 'hibernate-backup.json'
            }
        }

        if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
            Write-Host "[FAIL] 未找到休眠快照文件：$BackupFile" -ForegroundColor Red
            $script:fail++
            return $false
        }

        $backup = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-HibernateBackupSchema $backup)) {
            Write-Host "[FAIL] 休眠快照结构或机器绑定不正确：$BackupFile" -ForegroundColor Red
            $script:fail++
            return $false
        }

        $targetHib = [int]$backup.State.HibernateEnabled
        $targetBoot = [int]$backup.State.HiberbootEnabled

        if ($targetHib -eq 1) {
            $pcfgOut = (& powercfg.exe -h on 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[FAIL] 恢复休眠功能失败 (exit code $LASTEXITCODE)：$pcfgOut" -ForegroundColor Red
                $script:fail++
                return $false
            }
            Write-Host "[OK] 已恢复休眠功能 (powercfg -h on)" -ForegroundColor Green
            $script:ok++
            $script:rebootRequired = $true
        } else {
            $pcfgOut = (& powercfg.exe -h off 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[FAIL] 恢复休眠为关闭状态失败 (exit code $LASTEXITCODE)：$pcfgOut" -ForegroundColor Red
                $script:fail++
                return $false
            }
            Write-Host "[OK] 已恢复休眠为关闭状态 (powercfg -h off)" -ForegroundColor Green
            $script:ok++
            $script:rebootRequired = $true

            $hiberPath = 'C:\hiberfil.sys'
            if (Test-Path -LiteralPath $hiberPath) {
                try {
                    $null = Remove-Item -LiteralPath $hiberPath -Force -ErrorAction Stop
                } catch {
                    Write-Host "[WARN] 清理休眠文件遇到提示：$($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        try {
            $null = Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' $targetBoot "快速启动 (HiberbootEnabled = $targetBoot)"
        } catch {
            Write-Host "[FAIL] 恢复快速启动设置失败：$($_.Exception.Message)" -ForegroundColor Red
            $script:fail++
            return $false
        }

        return $true
    } catch {
        Write-Host "[FAIL] 恢复休眠配置异常：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Invoke-HibernateModule {
    <#
        .SYNOPSIS
        系统休眠与快速启动管理调度入口。
    #>
    [CmdletBinding()]
    param([string]$Action = '')

    Write-Host ""
    Write-Host "============ [Part 14] 系统休眠与快速启动管理 / Hibernate & Fast Startup ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  0. 查看当前系统休眠与快速启动状态（只读）" -ForegroundColor White
    Write-Host "  1. 备份并关闭休眠释放 C 盘空间（powercfg -h off 并删除 C:\hiberfil.sys）" -ForegroundColor White
    Write-Host "  2. 按快照恢复系统休眠与快速启动原始状态（hibernate-backup.json）" -ForegroundColor White
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定休眠子操作（0=status，1=disable，2=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入 0、1 或 2 并回车"
    }

    switch ($Action.ToString().Trim().ToLowerInvariant()) {
        { $_ -in @('0', 'status') } {
            Write-Host "`n--- [系统休眠与快速启动当前状态] ---" -ForegroundColor Cyan
            $status = Get-HibernateStatus
            $hibText = if ($status.HibernateEnabled -eq 1) { "已启用 (Enabled)" } else { "已禁用 (Disabled)" }
            $bootText = if ($status.HiberbootEnabled -eq 1) { "已启用 (Enabled)" } else { "已禁用 (Disabled)" }
            $fileText = if ($status.HiberfilExists) { "存在 ($($status.HiberfilSizeFormatted))" } else { "不存在" }
            Write-Host ("  休眠状态 (HibernateEnabled) : {0}" -f $hibText)
            Write-Host ("  快速启动 (HiberbootEnabled) : {0}" -f $bootText)
            Write-Host ("  休眠文件 (C:\hiberfil.sys)  : {0}" -f $fileText)

            $backupFile = if ($script:hibernateBackupFile) {
                $script:hibernateBackupFile
            } elseif ($script:RepoRoot) {
                Join-Path $script:RepoRoot 'hibernate-backup.json'
            } else {
                Join-Path (Split-Path -Parent $PSScriptRoot) 'hibernate-backup.json'
            }

            if (Test-Path -LiteralPath $backupFile -PathType Leaf) {
                Write-Host ("  休眠备份文件就绪            : {0}" -f $backupFile) -ForegroundColor Yellow
            } else {
                Write-Host "  休眠备份文件                : 未备份" -ForegroundColor Gray
            }
            return $true
        }

        { $_ -in @('1', 'disable', 'apply') } {
            Write-Host "[Hibernate & Fast Startup Optimization]" -ForegroundColor Cyan
            $backupOk = Ensure-HibernateBackup
            if (-not $backupOk) {
                Write-Host "[FAIL] 备份原始休眠状态失败，已安全阻止修改。" -ForegroundColor Red
                return $false
            }

            $pcfgOut = (& powercfg.exe -h off 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[FAIL] 关闭系统休眠失败 (exit code $LASTEXITCODE)：$pcfgOut" -ForegroundColor Red
                $script:fail++
                return $false
            }
            Write-Host "[OK] 已执行 powercfg -h off 关闭系统休眠" -ForegroundColor Green
            $script:ok++
            $script:rebootRequired = $true

            try {
                $null = Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 '快速启动 (HiberbootEnabled = 0)'
            } catch {
                Write-Host "[WARN] 配置 HiberbootEnabled 遇到异常：$($_.Exception.Message)" -ForegroundColor Yellow
            }

            $hiberPath = 'C:\hiberfil.sys'
            if (Test-Path -LiteralPath $hiberPath) {
                try {
                    $null = Remove-Item -LiteralPath $hiberPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[OK] 已清理并释放休眠文件：$hiberPath" -ForegroundColor Green
                    $script:ok++
                } catch {
                    Write-Host "[WARN] 清理休眠文件遇到提示：$($_.Exception.Message)" -ForegroundColor Yellow
                }
            }

            if (Get-Command Request-Restart -ErrorAction SilentlyContinue) {
                Request-Restart
            }
            return $true
        }

        { $_ -in @('2', 'restore') } {
            $restoreResult = Restore-HibernateBackup
            if ($restoreResult -and (Get-Command Request-Restart -ErrorAction SilentlyContinue)) {
                Request-Restart
            }
            return $restoreResult
        }

        default {
            Write-Host "[FAIL] 无效输入：$Action 。请输入 0、1 或 2" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }
}
