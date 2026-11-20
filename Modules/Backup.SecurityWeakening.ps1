# Backup.SecurityWeakening.ps1 - 菜单 20 专用：进程缓解 XML 快照 + 通用逐值快照的薄包装
# 通用逻辑在 Modules/Backup.TypedValues.ps1；本文件只承载 B13 不能逐值表达的系统级进程缓解配置。
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Save-ProcessMitigationPolicyXml {
    <# 导出当前全部进程缓解配置（系统级 + 逐应用）为 XML 文本，供快照与回滚使用。 #>
    param([string]$Path)
    if (-not (Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue)) {
        throw '当前系统缺少 ProcessMitigations 模块（Get-ProcessMitigation 不可用）'
    }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw '未指定进程缓解快照文件路径' }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
    Get-ProcessMitigation -RegistryConfigFilePath $Path -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "进程缓解配置未导出：$Path" }
    $xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($xml)) { throw "导出的进程缓解配置为空：$Path" }
    return $xml
}

function Restore-ProcessMitigationPolicyXml {
    <# 按导出的 XML 还原进程缓解配置（文档化入口，不直接写 MitigationOptions 位掩码）。 #>
    param([string]$Xml)
    if ([string]::IsNullOrWhiteSpace($Xml)) { return $false }
    if (-not (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue)) {
        throw '当前系统缺少 ProcessMitigations 模块（Set-ProcessMitigation 不可用）'
    }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('tweakbyjie-process-mitigation-{0}.xml' -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($path, $Xml, [System.Text.UTF8Encoding]::new($false))
        Set-ProcessMitigation -PolicyFilePath $path -ErrorAction Stop
        return $true
    } finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

function Test-SecurityWeakeningBackupSchema {
    param([object]$Backup)
    return (Test-TypedValueBackupSchema $Backup)
}

function Ensure-SecurityWeakeningBackup {
    <# 落 security-weakening-backup.json；B13 的进程缓解 XML 一并写入 ExtraXml。 #>
    param(
        [string]$BackupFile = $script:securityWeakeningBackupFile,
        [object]$Plan,
        [string]$ProcessMitigationXml
    )
    return (Ensure-TypedValueBackup -BackupFile $BackupFile -Plan $Plan -ExtraXml $ProcessMitigationXml -Label '安全削弱')
}

function Restore-SecurityWeakeningBackup {
    <# 先按快照逐值还原；若快照含进程缓解 XML，再整体还原进程缓解配置。 #>
    param([string]$BackupFile = $script:securityWeakeningBackupFile)
    $allOk = Restore-TypedValueBackup -BackupFile $BackupFile -Label '安全削弱'
    if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) { return $false }

    try {
        $backup = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $false
    }

    $xml = ''
    if ($backup.PSObject.Properties['ExtraXml'] -and -not [string]::IsNullOrWhiteSpace([string]$backup.ExtraXml)) {
        $xml = [string]$backup.ExtraXml
    }
    if ($xml) {
        try {
            Restore-ProcessMitigationPolicyXml -Xml $xml | Out-Null
            Write-Host '[OK] 进程缓解配置已按快照 XML 还原。' -ForegroundColor Green
            $script:rebootRequired = $true
        } catch {
            Write-Host "[FAIL] 进程缓解配置还原失败：$($_.Exception.Message)" -ForegroundColor Red
            $script:fail++
            $allOk = $false
        }
    }
    return $allOk
}
