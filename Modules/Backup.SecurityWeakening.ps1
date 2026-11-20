# Backup.SecurityWeakening.ps1 - 菜单 20 安全削弱项的逐值快照与还原
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired
#
# 设计边界：
#   - 每个被写入的值先落「原本是否存在 / 原类型 / 原值」，还原时「原本不存在 → 删值」、
#     「原本存在 → 按原类型写回原值」；
#   - 首次快照不覆盖：快照已存在时只追加新发现的目标，绝不重写已有记录；
#   - 进程缓解（B13）额外保存 Get-ProcessMitigation -RegistryConfigFilePath 导出的 XML，
#     还原走文档化的 Set-ProcessMitigation -PolicyFilePath，不靠手工拼注册表位掩码。

$script:securityWeakeningBackupKinds = @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')

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
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        if ($null -eq $Backup.Entries) { return $false }
        foreach ($entry in @($Backup.Entries)) {
            if ([string]::IsNullOrWhiteSpace([string]$entry.Path)) { return $false }
            if ([string]::IsNullOrWhiteSpace([string]$entry.Name)) { return $false }
            if ($null -eq $entry.Existed) { return $false }
            if ([bool]$entry.Existed) {
                $kind = [string]$entry.Kind
                if ([string]::IsNullOrWhiteSpace($kind)) { return $false }
                if ($script:securityWeakeningBackupKinds -notcontains $kind) { return $false }
                if ($null -eq $entry.Value) { return $false }
            } elseif ($null -ne $entry.Value) { return $false }
        }
        if ($null -ne $Backup.PSObject.Properties['ProcessMitigationXml'] -and
            $null -ne $Backup.ProcessMitigationXml -and $Backup.ProcessMitigationXml -isnot [string]) { return $false }
        return $true
    } catch { return $false }
}

function Ensure-SecurityWeakeningBackup {
    <# 落 security-weakening-backup.json；已存在时只追加新目标，绝不覆盖首次快照。 #>
    param(
        [string]$BackupFile = $script:securityWeakeningBackupFile,
        [object]$Plan,
        [string]$ProcessMitigationXml
    )
    try {
        if ([string]::IsNullOrWhiteSpace($BackupFile)) { throw '未指定安全削弱备份文件路径' }
        if (-not $Plan) { throw '缺少写入计划，拒绝创建不完整快照' }

        $entries = [System.Collections.Generic.List[object]]::new()
        $existing = $null
        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-SecurityWeakeningBackupSchema $existing)) { throw 'security-weakening-backup.json 结构或机器绑定不正确' }
            foreach ($entry in @($existing.Entries)) { $entries.Add($entry) }
        }

        $seen = @{}
        foreach ($entry in $entries) {
            $seen[(('{0}|{1}' -f $entry.Path, $entry.Name).ToLowerInvariant())] = $true
        }

        $added = 0
        foreach ($op in @($Plan.Operations)) {
            $key = ('{0}|{1}' -f $op.Path, $op.Name).ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $current = Get-TweakRegistryValue -Path $op.Path -Name $op.Name
            $entries.Add([pscustomobject]@{
                Path    = [string]$op.Path
                Name    = [string]$op.Name
                Existed = [bool]$current.Exists
                Kind    = [string]$current.Kind
                Value   = $current.Value
            })
            $seen[$key] = $true
            $added++
        }

        # 首次快照保护：已记录过进程缓解 XML 时，后续调用不得覆盖它
        $xml = ''
        if ($existing -and $existing.PSObject.Properties['ProcessMitigationXml'] -and
            -not [string]::IsNullOrWhiteSpace([string]$existing.ProcessMitigationXml)) {
            $xml = [string]$existing.ProcessMitigationXml
        } elseif (-not [string]::IsNullOrWhiteSpace($ProcessMitigationXml)) {
            $xml = $ProcessMitigationXml
        }

        if ($null -ne $existing -and $added -eq 0 -and [string]$existing.ProcessMitigationXml -eq [string]$xml) {
            Write-Host "[OK] 已存在有效的安全削弱快照（$($entries.Count) 项）：$BackupFile" -ForegroundColor Green
            return $true
        }

        $backup = [pscustomobject]@{
            Version              = 1
            Binding              = (Get-BackupMachineId)
            CreatedAt            = (Get-Date).ToString('o')
            ProcessMitigationXml = $xml
            Entries              = @($entries)
        }
        if (-not (Test-SecurityWeakeningBackupSchema $backup)) { throw '生成的安全削弱备份未通过结构校验' }

        $json = ConvertTo-Json -InputObject $backup -Depth 6
        Write-TweakAtomicTextFile -Path $BackupFile -Content $json -Overwrite:($null -ne $existing)

        $check = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-SecurityWeakeningBackupSchema $check)) { throw '写入后的安全削弱备份校验失败' }
        Write-Host "[OK] 安全削弱原始状态已备份（共 $($entries.Count) 项）：$BackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] 安全削弱原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-SecurityWeakeningBackup {
    <# 按快照逐值还原；若快照含进程缓解 XML，则最后整体还原进程缓解配置。 #>
    param([string]$BackupFile = $script:securityWeakeningBackupFile)
    if ([string]::IsNullOrWhiteSpace($BackupFile) -or -not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
        Write-Host '[FAIL] 未找到 security-weakening-backup.json，拒绝声称已恢复。' -ForegroundColor Red
        $script:fail++
        return $false
    }

    try {
        $backup = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-SecurityWeakeningBackupSchema $backup)) { throw 'security-weakening-backup.json 结构不正确或与本机绑定不匹配' }

        $allOk = $true
        foreach ($entry in @($backup.Entries)) {
            try {
                if ([bool]$entry.Existed) {
                    Set-TweakRegistryTypedValue -Path ([string]$entry.Path) -Name ([string]$entry.Name) -Kind ([string]$entry.Kind) -Value $entry.Value
                    Write-Host ("[OK] 恢复 {0} -> {1} = {2}（{3}）" -f $entry.Path, $entry.Name, $entry.Value, $entry.Kind) -ForegroundColor Green
                } else {
                    $removed = Remove-TweakRegistryValue -Path ([string]$entry.Path) -Name ([string]$entry.Name)
                    if ($removed) { Write-Host ("[OK] 删除 {0} -> {1}（原本不存在）" -f $entry.Path, $entry.Name) -ForegroundColor Green }
                    else { Write-Host ("[SKIP] {0} -> {1} 已不存在，无需删除" -f $entry.Path, $entry.Name) -ForegroundColor Yellow }
                }
            } catch {
                Write-Host ("[FAIL] 恢复 {0} -> {1} 失败：{2}" -f $entry.Path, $entry.Name, $_.Exception.Message) -ForegroundColor Red
                $script:fail++
                $allOk = $false
            }
        }

        $xml = ''
        if ($backup.PSObject.Properties['ProcessMitigationXml'] -and -not [string]::IsNullOrWhiteSpace([string]$backup.ProcessMitigationXml)) {
            $xml = [string]$backup.ProcessMitigationXml
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

        if ($allOk) { Write-Host '[OK] 安全削弱项已按快照完整恢复。' -ForegroundColor Green }
        else { Write-Host '[WARN] 安全削弱项恢复未完全成功，请复查错误。' -ForegroundColor Yellow }
        return $allOk
    } catch {
        Write-Host "[FAIL] 安全削弱恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
