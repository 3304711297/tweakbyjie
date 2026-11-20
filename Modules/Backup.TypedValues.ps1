# Backup.TypedValues.ps1 - 通用逐值快照与还原（菜单 20 / 21 共用）
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired
#
# 设计边界：
#   - 每个被写入的值先落「原本是否存在 / 原类型 / 原值」，还原时「原本不存在 → 删值」、
#     「原本存在 → 按原类型写回原值」；
#   - 首次快照不覆盖：快照已存在时只追加新发现的目标，绝不重写已有记录；
#   - 结构损坏或跨机（MachineGuid 绑定不匹配）直接失败并阻止写入；
#   - 可选 ExtraXml 字段承载不能逐值表达的状态（当前只有菜单 20 的进程缓解配置）。

$script:typedValueBackupKinds = @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')

function Test-TypedValueBackupSchema {
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
                if ($script:typedValueBackupKinds -notcontains $kind) { return $false }
                if ($null -eq $entry.Value) { return $false }
            } elseif ($null -ne $entry.Value) { return $false }
        }
        if ($null -ne $Backup.PSObject.Properties['ExtraXml'] -and
            $null -ne $Backup.ExtraXml -and $Backup.ExtraXml -isnot [string]) { return $false }
        return $true
    } catch { return $false }
}

function Ensure-TypedValueBackup {
    <# 落指定快照文件；已存在时只追加新目标，绝不覆盖首次快照。 #>
    param(
        [string]$BackupFile,
        [object]$Plan,
        [string]$ExtraXml,
        [string]$Label = '注册表'
    )
    try {
        if ([string]::IsNullOrWhiteSpace($BackupFile)) { throw '未指定备份文件路径' }
        if (-not $Plan) { throw '缺少写入计划，拒绝创建不完整快照' }

        $entries = [System.Collections.Generic.List[object]]::new()
        $existing = $null
        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-TypedValueBackupSchema $existing)) { throw "$([System.IO.Path]::GetFileName($BackupFile)) 结构或机器绑定不正确" }
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

        # 首次快照保护：已记录过 ExtraXml 时，后续调用不得覆盖它
        $xml = ''
        if ($existing -and $existing.PSObject.Properties['ExtraXml'] -and
            -not [string]::IsNullOrWhiteSpace([string]$existing.ExtraXml)) {
            $xml = [string]$existing.ExtraXml
        } elseif (-not [string]::IsNullOrWhiteSpace($ExtraXml)) {
            $xml = $ExtraXml
        }

        if ($null -ne $existing -and $added -eq 0 -and [string]$existing.ExtraXml -eq [string]$xml) {
            Write-Host ("[OK] 已存在有效的{0}快照（{1} 项）：{2}" -f $Label, $entries.Count, $BackupFile) -ForegroundColor Green
            return $true
        }

        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            ExtraXml  = $xml
            Entries   = @($entries)
        }
        if (-not (Test-TypedValueBackupSchema $backup)) { throw "生成的$Label 备份未通过结构校验" }

        $json = ConvertTo-Json -InputObject $backup -Depth 6
        Write-TweakAtomicTextFile -Path $BackupFile -Content $json -Overwrite:($null -ne $existing)

        $check = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-TypedValueBackupSchema $check)) { throw "写入后的$Label 备份校验失败" }
        Write-Host "[OK] $Label 原始状态已备份（共 $($entries.Count) 项）：$BackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] $Label 原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-TypedValueBackup {
    <# 按快照逐值还原；缺少/损坏/跨机快照一律失败关闭。 #>
    param([string]$BackupFile, [string]$Label = '注册表')
    if ([string]::IsNullOrWhiteSpace($BackupFile) -or -not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
        Write-Host "[FAIL] 未找到 $([System.IO.Path]::GetFileName($BackupFile))，拒绝声称已恢复。" -ForegroundColor Red
        $script:fail++
        return $false
    }

    try {
        $backup = Get-Content -LiteralPath $BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-TypedValueBackupSchema $backup)) { throw "$([System.IO.Path]::GetFileName($BackupFile)) 结构不正确或与本机绑定不匹配" }

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

        if ($allOk) { Write-Host ("[OK] {0}已按快照完整恢复。" -f $Label) -ForegroundColor Green }
        else { Write-Host ("[WARN] {0}恢复未完全成功，请复查错误。" -f $Label) -ForegroundColor Yellow }
        return $allOk
    } catch {
        Write-Host "[FAIL] $Label 恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
