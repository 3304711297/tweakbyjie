#Requires -Version 7.0
<#
.SYNOPSIS
    核查人工清单 docs/reference/XOS-PLAYBOOK-INVENTORY.md 是否仍与上游 xos-playbook 一致（只读）。

.DESCRIPTION
    数据源：imribiy/xos-playbook 的 Configuration/custom.yml（默认 dev 分支）。
    基线：tools/xos-playbook-inventory.json（动作级 type/key/fingerprint/line 指纹）。

    默认行为是**纯核查**：
      1. 取上游 head（gh api；失败回退 raw.githubusercontent，均带 UA）与 custom.yml；
      2. 按 playbook 语法解析全部动作，算出 key 与 fingerprint；
      3. 与基线比对，得到 added / removed / changed（changed = 同 key 但 fingerprint 不同）；
      4. 结论写进 xos-inventory-check.md（供 issue 正文追加），并打印到 stdout；
      5. 不修改清单文档、不修改基线 JSON、不提交任何东西。

    需要更新清单时由人显式执行 -Apply：写回文档的「上游变动」区块并重建基线 JSON。
    工作流里不得调用 -Apply —— 是否承认上游变更由人决定。

    设计取舍：
      - 只读：默认路径零写入（测试用文件哈希前后比对来证明）；
      - 幂等：同一 head 重复 -Apply，区块与 JSON 逐字节不变（时间戳沿用上次生成值）；
      - 人工门槛：reviewed_head / reviewed_at 只由人修改，脚本永不推进；
      - 复核标记：head 等于 reviewed_head 时条目统一 reviewed，否则指纹未变的沿用原标记、新/变条目标 pending；
      - 离线：-OfflinePath 只读本地文件，不发起任何 gh / HTTP 请求（供 Pester 使用）。

.PARAMETER Apply
    显式人工确认后使用：写回文档区块与基线 JSON。绝不能出现在 CI 工作流里。

.PARAMETER OfflinePath
    本地 custom.yml 路径。给出时不访问网络；head 取 -HeadSha，未给出则用内容哈希（blob-xxxxxxxxxxxx）。

.PARAMETER ReportPath
    核查报告路径，默认仓库根目录 xos-inventory-check.md。

.EXAMPLE
    pwsh tools/check-xos-inventory.ps1
    只核查；0=清单仍准确，10=需要更新，20=自身异常。

.NOTES
    退出码：0=清单仍准确（0 变动），10=清单需更新（有变动），20=核查异常（拉取失败/基线损坏）。
#>
[CmdletBinding()]
param(
    [string]$Repo = 'imribiy/xos-playbook',
    [string]$Branch = 'dev',
    [string]$ConfigPath = 'Configuration/custom.yml',
    [string]$ManifestPath,
    [string]$DocumentPath,
    [string]$ReportPath,
    [string]$OfflinePath,
    [string]$HeadSha,
    [switch]$Apply,
    [switch]$NoReport,
    [switch]$SkipFileHash
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ManifestPath) { $ManifestPath = Join-Path $PSScriptRoot 'xos-playbook-inventory.json' }
if (-not $DocumentPath) { $DocumentPath = Join-Path $script:RepoRoot 'docs/reference/XOS-PLAYBOOK-INVENTORY.md' }
if (-not $ReportPath) { $ReportPath = Join-Path $script:RepoRoot 'xos-inventory-check.md' }

$script:UserAgent = 'tweakbyjie-xos-inventory/1.0'
$script:StartMarker = '<!-- XOS-INVENTORY:DELTA:START -->'
$script:EndMarker = '<!-- XOS-INVENTORY:DELTA:END -->'
$script:CommandKeyLength = 120

function Get-Sha256Hex {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-BytesSha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    # 统一去掉 UTF-8 BOM，保证「在线取原始字节」与「离线读文本再编码」得到同一指纹。
    $offset = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $offset = 3 }
    $stream = [System.IO.MemoryStream]::new($Bytes, $offset, $Bytes.Length - $offset)
    try {
        $hash = [System.Security.Cryptography.SHA256]::HashData($stream)
    } finally {
        $stream.Dispose()
    }
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-NormalizedText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace '\s+', ' ').Trim()
}

function Get-ManifestString {
    <#
        读回 JSON 时防「隐式日期转换」：ConvertFrom-Json 会把 "2026-11-20T07:38:45Z" 转成 DateTime，
        直接 [string] 会变成区域化格式（中文环境是 11/20/2026 07:38:45），既破坏幂等也污染清单。
    #>
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

function Split-YamlFlowItem {
    <#
        按深度 0 的逗号切分 flow mapping 内容；引号内的逗号/花括号原样保留
        （注册表路径里的 {GUID} 与命令里的逗号都靠这段活下来）。
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $items = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $quote = [char]0
    $depth = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($quote -ne [char]0) {
            [void]$current.Append($c)
            if ($c -eq $quote) {
                if ($quote -eq [char]39 -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq [char]39) {
                    # YAML 单引号转义：'' -> '
                    [void]$current.Append($Text[$i + 1])
                    $i++
                } elseif ($quote -eq [char]34 -and $i -gt 0 -and $Text[$i - 1] -eq [char]92) {
                    # 双引号内的 \" 不结束字符串
                } else {
                    $quote = [char]0
                }
            }
            continue
        }
        if ($c -eq [char]39 -or $c -eq [char]34) { $quote = $c; [void]$current.Append($c); continue }
        if ($c -eq [char]123 -or $c -eq [char]91 -or $c -eq [char]40) { $depth++; [void]$current.Append($c); continue }
        if ($c -eq [char]125 -or $c -eq [char]93 -or $c -eq [char]41) { $depth--; [void]$current.Append($c); continue }
        if ($c -eq [char]44 -and $depth -eq 0) {
            $items.Add($current.ToString())
            [void]$current.Clear()
            continue
        }
        [void]$current.Append($c)
    }
    if (-not [string]::IsNullOrWhiteSpace($current.ToString())) { $items.Add($current.ToString()) }
    return $items
}

function Get-YamlSeparatorIndex {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [char]$Separator)
    $quote = [char]0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($quote -ne [char]0) {
            if ($c -eq $quote) {
                if ($quote -eq [char]39 -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq [char]39) { $i++; continue }
                if ($quote -eq [char]34 -and $i -gt 0 -and $Text[$i - 1] -eq [char]92) { continue }
                $quote = [char]0
            }
            continue
        }
        if ($c -eq [char]39 -or $c -eq [char]34) { $quote = $c; continue }
        if ($c -eq $Separator) { return $i }
    }
    return -1
}

function ConvertFrom-YamlScalar {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text.Trim()
    if ($t.Length -ge 2 -and $t[0] -eq [char]39 -and $t[$t.Length - 1] -eq [char]39) {
        return $t.Substring(1, $t.Length - 2).Replace("''", "'")
    }
    if ($t.Length -ge 2 -and $t[0] -eq [char]34 -and $t[$t.Length - 1] -eq [char]34) {
        return $t.Substring(1, $t.Length - 2).Replace('\"', '"')
    }
    return $t
}

function ConvertFrom-YamlFlowMap {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $t = $Text.Trim()
    if ($t.StartsWith('{')) { $t = $t.Substring(1) }
    if ($t.EndsWith('}')) { $t = $t.Substring(0, $t.Length - 1) }
    $map = [ordered]@{}
    foreach ($item in (Split-YamlFlowItem -Text $t)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $index = Get-YamlSeparatorIndex -Text $item -Separator ':'
        if ($index -lt 1) { continue }
        $name = $item.Substring(0, $index).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $map[$name] = ConvertFrom-YamlScalar -Text $item.Substring($index + 1)
    }
    return $map
}

function ConvertFrom-YamlBlockMap {
    <#
        读取 `- !powerShell:` 之后的缩进块（key: value / key: >- 折叠标量）。
    #>
    param(
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][int]$StartIndex,
        [Parameter(Mandatory)][int]$ParentIndent
    )
    $map = [ordered]@{}
    $keyPattern = [regex]'^(?<indent>\s*)(?<name>[A-Za-z_][\w-]*):(?<rest>.*)$'
    $i = $StartIndex
    while ($i -lt $Lines.Length) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { $i++; continue }
        $indent = $line.Length - $line.TrimStart().Length
        if ($indent -le $ParentIndent) { break }
        $match = $keyPattern.Match($line)
        if (-not $match.Success) { $i++; continue }
        $name = $match.Groups['name'].Value
        $rest = $match.Groups['rest'].Value.Trim()
        if ($rest -eq '' -or $rest -eq '>-' -or $rest -eq '>' -or $rest -eq '|' -or $rest -eq '|-') {
            $parts = [System.Collections.Generic.List[string]]::new()
            $i++
            while ($i -lt $Lines.Length) {
                $inner = $Lines[$i]
                if ([string]::IsNullOrWhiteSpace($inner)) { $i++; continue }
                $innerIndent = $inner.Length - $inner.TrimStart().Length
                if ($innerIndent -le $indent) { break }
                $parts.Add($inner.Trim())
                $i++
            }
            $joiner = if ($rest.StartsWith('|')) { "`n" } else { ' ' }
            $map[$name] = ($parts -join $joiner)
        } else {
            $map[$name] = ConvertFrom-YamlScalar -Text $rest
            $i++
        }
    }
    return $map
}

function ConvertFrom-CustomYml {
    <#
        逐行匹配 ^\s*-\s*!type: 得到一个动作；块内缩进归该动作。
        口径与人工清单第 0 节一致（dev @0ed60c3 = 808 条）。
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $normalized = ($Text -replace "`r`n", "`n").TrimStart([char]0xFEFF)
    $lines = $normalized -split "`n"
    $pattern = [regex]'^(?<indent>\s*)-\s*!(?<type>[A-Za-z]+):(?<rest>.*)$'
    $actions = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $match = $pattern.Match($lines[$i])
        if (-not $match.Success) { continue }
        $indent = $match.Groups['indent'].Value.Length
        $rest = $match.Groups['rest'].Value.Trim()
        if ($rest.StartsWith('{')) {
            $fields = ConvertFrom-YamlFlowMap -Text $rest
        } elseif ($rest.Length -gt 0) {
            $fields = [ordered]@{ value = ConvertFrom-YamlScalar -Text $rest }
        } else {
            $fields = ConvertFrom-YamlBlockMap -Lines $lines -StartIndex ($i + 1) -ParentIndent $indent
        }
        $actions.Add([pscustomobject]@{
                Type   = $match.Groups['type'].Value
                Fields = $fields
                Line   = $i + 1
            })
    }
    return $actions
}

function Get-ActionField {
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = ''
    )
    if ($Action.Fields.Contains($Name)) { return [string]$Action.Fields[$Name] }
    return $Default
}

function Get-CommandHead {
    # powerShell / cmd 的 key：命令首行前 120 字符（空白折叠，避免折叠块与内联写法产生不同 key）。
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $first = (($Text -replace "`r`n", "`n").Trim() -split "`n")[0]
    $head = Get-NormalizedText -Text $first
    if ($head.Length -gt $script:CommandKeyLength) { return $head.Substring(0, $script:CommandKeyLength) }
    return $head
}

function Get-ActionKey {
    param([Parameter(Mandatory)]$Action)
    $type = $Action.Type
    switch ($type) {
        'registryValue' { return ((Get-ActionField -Action $Action -Name 'path') + '|' + (Get-ActionField -Action $Action -Name 'value')).ToLowerInvariant() }
        'service' { return Get-NormalizedText -Text (Get-ActionField -Action $Action -Name 'name') }
        'run' { return Get-NormalizedText -Text ((Get-ActionField -Action $Action -Name 'exe') + '|' + (Get-ActionField -Action $Action -Name 'args')) }
        'registryKey' { return Get-NormalizedText -Text (Get-ActionField -Action $Action -Name 'path') }
        'taskKill' { return Get-NormalizedText -Text (Get-ActionField -Action $Action -Name 'name') }
        'appx' { return Get-NormalizedText -Text (Get-ActionField -Action $Action -Name 'name') }
        'file' { return Get-NormalizedText -Text (Get-ActionField -Action $Action -Name 'path') }
        'powerShell' { return Get-CommandHead -Text (Get-ActionField -Action $Action -Name 'command') }
        'cmd' { return Get-CommandHead -Text (Get-ActionField -Action $Action -Name 'command') }
        'writeStatus' { return Get-NormalizedText -Text (Get-ActionField -Action $Action -Name 'status') }
        default {
            $names = @($Action.Fields.Keys | Sort-Object)
            if ($names.Count -eq 0) { return '' }
            return Get-NormalizedText -Text ([string]$Action.Fields[$names[0]])
        }
    }
}

function Get-ActionFingerprint {
    # 规范化文本 = type + 排序后的 key=value；不含行号，行号漂移不算变更。
    param([Parameter(Mandatory)]$Action)
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append($Action.Type)
    foreach ($name in @($Action.Fields.Keys | Sort-Object)) {
        [void]$builder.Append("`n")
        [void]$builder.Append($name)
        [void]$builder.Append('=')
        [void]$builder.Append((Get-NormalizedText -Text ([string]$Action.Fields[$name])))
    }
    return Get-Sha256Hex -Text $builder.ToString()
}

function Get-InventoryRecord {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$YmlText)
    $records = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($action in (ConvertFrom-CustomYml -Text $YmlText)) {
        $key = Get-ActionKey -Action $action
        $baseId = (Get-Sha256Hex -Text ($action.Type + '|' + $key)).Substring(0, 16)
        $ordinal = 0
        if ($seen.ContainsKey($baseId)) { $ordinal = $seen[$baseId] + 1 }
        $seen[$baseId] = $ordinal
        $id = if ($ordinal -eq 0) { $baseId } else { "$baseId-$ordinal" }
        $records.Add([pscustomobject]@{
                id          = $id
                type        = $action.Type
                key         = $key
                fingerprint = Get-ActionFingerprint -Action $action
                line        = $action.Line
            })
    }
    return $records
}

function Compare-InventoryRecord {
    <#
        同类同 key 视为同一动作族；族内先按指纹配对（未变），剩余按行序配对（changed），
        多出来的才算 added / removed。返回排序后的三张表，保证渲染幂等。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Baseline,
        [Parameter(Mandatory)][AllowEmptyCollection()]$Current
    )
    $added = [System.Collections.Generic.List[object]]::new()
    $removed = [System.Collections.Generic.List[object]]::new()
    $changed = [System.Collections.Generic.List[object]]::new()

    $baselineGroups = @{}
    foreach ($record in $Baseline) {
        $groupKey = $record.type + '|' + $record.key
        if (-not $baselineGroups.ContainsKey($groupKey)) { $baselineGroups[$groupKey] = [System.Collections.Generic.List[object]]::new() }
        $baselineGroups[$groupKey].Add($record)
    }
    $currentGroups = @{}
    foreach ($record in $Current) {
        $groupKey = $record.type + '|' + $record.key
        if (-not $currentGroups.ContainsKey($groupKey)) { $currentGroups[$groupKey] = [System.Collections.Generic.List[object]]::new() }
        $currentGroups[$groupKey].Add($record)
    }

    foreach ($groupKey in $baselineGroups.Keys) {
        $remaining = [System.Collections.Generic.List[object]]::new()
        if ($currentGroups.ContainsKey($groupKey)) {
            foreach ($record in $currentGroups[$groupKey]) { $remaining.Add($record) }
        }
        $unmatched = [System.Collections.Generic.List[object]]::new()
        foreach ($baseRecord in $baselineGroups[$groupKey]) {
            $hit = $null
            foreach ($candidate in $remaining) {
                if ($candidate.fingerprint -eq $baseRecord.fingerprint) { $hit = $candidate; break }
            }
            if ($null -eq $hit) {
                $unmatched.Add($baseRecord)
            } else {
                [void]$remaining.Remove($hit)
            }
        }
        $oldList = @($unmatched | Sort-Object -Property line, fingerprint)
        $newList = @($remaining | Sort-Object -Property line, fingerprint)
        $pairCount = [Math]::Min($oldList.Count, $newList.Count)
        for ($i = 0; $i -lt $pairCount; $i++) {
            $changed.Add([pscustomobject]@{
                    type            = $newList[$i].type
                    key             = $newList[$i].key
                    line            = $newList[$i].line
                    base_line       = $oldList[$i].line
                    old_fingerprint = $oldList[$i].fingerprint
                    new_fingerprint = $newList[$i].fingerprint
                })
        }
        for ($i = $pairCount; $i -lt $oldList.Count; $i++) {
            $removed.Add([pscustomobject]@{
                    type        = $oldList[$i].type
                    key         = $oldList[$i].key
                    line        = $oldList[$i].line
                    fingerprint = $oldList[$i].fingerprint
                })
        }
        for ($i = $pairCount; $i -lt $newList.Count; $i++) {
            $added.Add([pscustomobject]@{
                    type        = $newList[$i].type
                    key         = $newList[$i].key
                    line        = $newList[$i].line
                    fingerprint = $newList[$i].fingerprint
                })
        }
    }

    foreach ($groupKey in $currentGroups.Keys) {
        if ($baselineGroups.ContainsKey($groupKey)) { continue }
        foreach ($record in $currentGroups[$groupKey]) {
            $added.Add([pscustomobject]@{
                    type        = $record.type
                    key         = $record.key
                    line        = $record.line
                    fingerprint = $record.fingerprint
                })
        }
    }

    return [pscustomobject]@{
        Added   = @($added | Sort-Object -Property type, key, line)
        Removed = @($removed | Sort-Object -Property type, key, line)
        Changed = @($changed | Sort-Object -Property type, key, line)
    }
}

function Get-ShortHash {
    param([AllowNull()][AllowEmptyString()][string]$Hash)
    $value = [string]$Hash
    if ($value.Length -gt 12) { return $value.Substring(0, 12) }
    return $value
}

function Format-DeltaBlock {
    param(
        [Parameter(Mandatory)]$Delta,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Head,
        [Parameter(Mandatory)][string]$ReviewedHead,
        [Parameter(Mandatory)][string]$ReviewedAt,
        [Parameter(Mandatory)][string]$Timestamp,
        [Parameter(Mandatory)][int]$ActionCount
    )
    $added = @($Delta.Added)
    $removed = @($Delta.Removed)
    $changed = @($Delta.Changed)
    $total = $added.Count + $removed.Count + $changed.Count

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($script:StartMarker)
    $lines.Add('## 上游变动（自动维护，勿手改）')
    $lines.Add('')
    $lines.Add("> 本节由 ``tools/check-xos-inventory.ps1 -Apply`` 在人工确认后刷新：对比 ``tools/xos-playbook-inventory.json`` 基线与上游 ``$Branch`` 当前 ``$ConfigPath``。CI 只核查、不写文件；人工结论请写在区块之外的章节。")
    $lines.Add('')
    $lines.Add('| 项目 | 值 |')
    $lines.Add('| --- | --- |')
    $lines.Add("| 基准 head（人工审阅） | ``$(Get-ShortHash $ReviewedHead)``（$ReviewedAt） |")
    $lines.Add("| 本次 head | ``$(Get-ShortHash $Head)`` |")
    $lines.Add("| 检测时间 | ``$Timestamp`` |")
    $lines.Add("| 动作总数 | $ActionCount |")
    $lines.Add("| 新增 / 删除 / 变更 | $($added.Count) / $($removed.Count) / $($changed.Count) |")
    $lines.Add('')
    if ($total -eq 0) {
        $lines.Add("**结论**：上游 ``$Branch`` 相对基准无动作级变动，$ActionCount 条动作的类型与指纹全部一致。")
    } else {
        $lines.Add("**结论**：检测到 **$total** 项动作级变动，新增与变更项均需人工复核后再决定是否吸收。")
    }

    if ($added.Count -gt 0) {
        $lines.Add('')
        $lines.Add("### 新增（待复核）$($added.Count) 项")
        $lines.Add('')
        $lines.Add('| 类型 | key | 行号 |')
        $lines.Add('| --- | --- | --- |')
        foreach ($row in $added) {
            $lines.Add("| ``$($row.type)`` | $(([string]$row.key).Replace('|', '\|')) | $($row.line) |")
        }
    }
    if ($removed.Count -gt 0) {
        $lines.Add('')
        $lines.Add("### 删除（待复核）$($removed.Count) 项")
        $lines.Add('')
        $lines.Add('| 类型 | key | 原行号 |')
        $lines.Add('| --- | --- | --- |')
        foreach ($row in $removed) {
            $lines.Add("| ``$($row.type)`` | $(([string]$row.key).Replace('|', '\|')) | $($row.line) |")
        }
    }
    if ($changed.Count -gt 0) {
        $lines.Add('')
        $lines.Add("### 变更（待复核）$($changed.Count) 项")
        $lines.Add('')
        $lines.Add('| 类型 | key | 行号 | 原行号 | 旧指纹 | 新指纹 |')
        $lines.Add('| --- | --- | --- | --- | --- | --- |')
        foreach ($row in $changed) {
            $lines.Add("| ``$($row.type)`` | $(([string]$row.key).Replace('|', '\|')) | $($row.line) | $($row.base_line) | ``$(Get-ShortHash $row.old_fingerprint)`` | ``$(Get-ShortHash $row.new_fingerprint)`` |")
        }
    }
    $lines.Add($script:EndMarker)
    return ($lines -join "`n")
}

function Merge-DeltaBlock {
    # 已有区块则整段替换；否则插在第一个 '## ' 之前（没有二级标题时追加到末尾）。
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Block)
    $start = $Text.IndexOf($script:StartMarker, [StringComparison]::Ordinal)
    if ($start -ge 0) {
        $end = $Text.IndexOf($script:EndMarker, $start, [StringComparison]::Ordinal)
        if ($end -lt 0) { throw '清单文档区块标记不完整：找到 START 但缺少 END' }
        $tail = $Text.Substring($end + $script:EndMarker.Length)
        return $Text.Substring(0, $start) + $Block + $tail
    }
    $match = [regex]::Match($Text, '(?m)^## ')
    if ($match.Success) {
        return $Text.Substring(0, $match.Index) + $Block + "`n`n" + $Text.Substring($match.Index)
    }
    return $Text.TrimEnd() + "`n`n" + $Block + "`n"
}

function Get-DocumentText {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "清单文档不存在：$Path" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    $usesCrLf = $text.Contains("`r`n")
    if ($usesCrLf) { $text = $text.Replace("`r`n", "`n") }
    return [pscustomobject]@{ Text = $text; HasBom = $hasBom; UsesCrLf = $usesCrLf }
}

function Set-DocumentText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [bool]$HasBom = $false,
        [bool]$UsesCrLf = $false
    )
    $payload = if ($UsesCrLf) { $Text.Replace("`n", "`r`n") } else { $Text }
    $encoding = [System.Text.UTF8Encoding]::new($HasBom)
    [System.IO.File]::WriteAllText($Path, $payload, $encoding)
}

function Get-GitHubBranchHead {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Branch)
    $sha = & gh api "repos/$Repo/branches/$Branch" --jq '.commit.sha' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($sha -join ''))) { return '' }
    return ([string]($sha | Select-Object -First 1)).Trim()
}

function Get-GitHubFileContent {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Ref)
    $encodedPath = (($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    # 变量名里 '?' 合法（PowerShell 会把 $encodedPath?ref 当成一个变量），必须用 ${} 界定
    $raw = & gh api "repos/$Repo/contents/${encodedPath}?ref=$Ref" --jq '.content' 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $raw) { return $null }
    $base64 = ($raw -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($base64)) { return $null }
    try {
        return , [Convert]::FromBase64String($base64)
    } catch {
        return $null
    }
}

function Get-RawFileText {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Branch, [Parameter(Mandatory)][string]$Path)
    $encodedPath = (($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $url = "https://raw.githubusercontent.com/$Repo/$Branch/$encodedPath"
    try {
        $response = Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = $script:UserAgent } -TimeoutSec 30
        return [string]$response.Content
    } catch {
        Write-Warning "raw.githubusercontent 拉取失败：$url（$($_.Exception.Message)）"
        return $null
    }
}

function Get-UpstreamConfig {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$ConfigPath,
        [string]$OfflinePath,
        [string]$HeadSha
    )
    if (-not [string]::IsNullOrWhiteSpace($OfflinePath)) {
        # 离线：绝不触网，也不调用 gh（Pester 依赖这条保证）
        if (-not (Test-Path -LiteralPath $OfflinePath -PathType Leaf)) { throw "离线清单文件不存在：$OfflinePath" }
        $text = [System.IO.File]::ReadAllText($OfflinePath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $head = if (-not [string]::IsNullOrWhiteSpace($HeadSha)) { $HeadSha } else { 'blob-' + (Get-Sha256Hex -Text $text).Substring(0, 12) }
        return [pscustomobject]@{ Text = $text; Bytes = [System.Text.Encoding]::UTF8.GetBytes($text); Head = $head; Origin = 'offline' }
    }

    $head = if (-not [string]::IsNullOrWhiteSpace($HeadSha)) { $HeadSha } else { Get-GitHubBranchHead -Repo $Repo -Branch $Branch }
    $bytes = $null
    if (-not [string]::IsNullOrWhiteSpace($head)) {
        $bytes = Get-GitHubFileContent -Repo $Repo -Path $ConfigPath -Ref $head
        if ($null -eq $bytes) {
            Write-Warning "gh api 取 $ConfigPath@$head 失败，回退 raw.githubusercontent"
            $head = ''
        }
    }
    if ($null -eq $bytes) {
        $text = Get-RawFileText -Repo $Repo -Branch $Branch -Path $ConfigPath
        if ([string]::IsNullOrWhiteSpace($text)) { throw "无法获取上游 $Repo/$Branch/$ConfigPath（gh api 与 raw 均失败）" }
        $text = $text.TrimStart([char]0xFEFF)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $head = 'blob-' + (Get-BytesSha256Hex -Bytes $bytes).Substring(0, 12)
    } else {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    }
    return [pscustomobject]@{ Text = $text; Bytes = $bytes; Head = $head; Origin = 'remote' }
}

function Get-UpstreamFileHash {
    <#
        基线 file_hashes：custom.yml + playbook.conf + Executables/*（仅文件，跳过目录项）。
        只在 -Apply 且未 -SkipFileHash 时执行：30 次 gh api，人工刷新时跑一次足够。
    #>
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][byte[]]$ConfigBytes,
        [hashtable]$Existing = @{}
    )
    $hashes = [ordered]@{}
    $hashes[$ConfigPath] = Get-BytesSha256Hex -Bytes $ConfigBytes

    $confPath = 'playbook.conf'
    $confBytes = Get-GitHubFileContent -Repo $Repo -Path $confPath -Ref $Ref
    if ($null -ne $confBytes) { $hashes[$confPath] = Get-BytesSha256Hex -Bytes $confBytes }

    $listing = & gh api "repos/$Repo/contents/Executables?ref=$Ref" --jq '.[] | select(.type=="file") | .path' 2>$null
    if ($LASTEXITCODE -eq 0 -and $null -ne $listing) {
        foreach ($path in @($listing | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $fileBytes = Get-GitHubFileContent -Repo $Repo -Path ([string]$path).Trim() -Ref $Ref
            if ($null -ne $fileBytes) { $hashes[([string]$path).Trim()] = Get-BytesSha256Hex -Bytes $fileBytes }
        }
    }
    foreach ($name in @($Existing.Keys)) {
        if (-not $hashes.Contains($name)) { $hashes[$name] = [string]$Existing[$name] }
    }
    return $hashes
}

function ConvertTo-ManifestText {
    param([Parameter(Mandatory)]$Manifest)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('{')
    $lines.Add('  "source": ' + (ConvertTo-Json -InputObject ([string]$Manifest.source) -Compress) + ',')
    $lines.Add('  "branch": ' + (ConvertTo-Json -InputObject ([string]$Manifest.branch) -Compress) + ',')
    $lines.Add('  "reviewed_head": ' + (ConvertTo-Json -InputObject (Get-ManifestString $Manifest.reviewed_head) -Compress) + ',')
    $lines.Add('  "reviewed_at": ' + (ConvertTo-Json -InputObject (Get-ManifestString $Manifest.reviewed_at) -Compress) + ',')
    $lines.Add('  "last_seen_head": ' + (ConvertTo-Json -InputObject (Get-ManifestString $Manifest.last_seen_head) -Compress) + ',')
    $lines.Add('  "generated_at": ' + (ConvertTo-Json -InputObject (Get-ManifestString $Manifest.generated_at) -Compress) + ',')
    $lines.Add('  "action_count": ' + [int]$Manifest.action_count + ',')
    $lines.Add('  "file_hashes": {')
    $names = @($Manifest.file_hashes.Keys | Sort-Object)
    for ($i = 0; $i -lt $names.Count; $i++) {
        $comma = if ($i -lt $names.Count - 1) { ',' } else { '' }
        $name = ConvertTo-Json -InputObject ([string]$names[$i]) -Compress
        $value = ConvertTo-Json -InputObject ([string]$Manifest.file_hashes[$names[$i]]) -Compress
        $lines.Add("    $name`: $value$comma")
    }
    $lines.Add('  },')
    $lines.Add('  "actions": [')
    $actions = @($Manifest.actions)
    for ($i = 0; $i -lt $actions.Count; $i++) {
        $comma = if ($i -lt $actions.Count - 1) { ',' } else { '' }
        $lines.Add('    ' + (ConvertTo-Json -InputObject $actions[$i] -Compress -Depth 5) + $comma)
    }
    $lines.Add('  ]')
    $lines.Add('}')
    return ($lines -join "`n") + "`n"
}

function Read-InventoryManifest {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "基线清单不存在：$Path（先人工执行 -Apply 建库）" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "基线清单为空：$Path" }
    try {
        $manifest = ConvertFrom-Json -InputObject $raw
    } catch {
        throw "基线清单 JSON 损坏：$Path（$($_.Exception.Message)）"
    }
    if ($null -eq $manifest.actions -or @($manifest.actions).Count -eq 0) { throw "基线清单没有动作条目：$Path" }
    $declared = 0
    if ($null -ne $manifest.action_count) { $declared = [int]$manifest.action_count }
    if ($declared -gt 0 -and $declared -ne @($manifest.actions).Count) {
        throw "基线清单自相矛盾：action_count=$declared 但 actions 有 $(@($manifest.actions).Count) 条"
    }
    return $manifest
}

function Test-XosInventory {
    <#
        主流程：取上游 -> 解析 -> 与基线比对 -> 渲染区块/报告 ->（仅 -Apply）落盘。
        返回结果对象，不调用 exit；异常由调用方映射为退出码 20。
    #>
    param(
        [string]$Repo,
        [string]$Branch,
        [string]$ConfigPath,
        [string]$ManifestPath,
        [string]$DocumentPath,
        [string]$OfflinePath,
        [string]$HeadSha,
        [switch]$Apply,
        [switch]$SkipFileHash
    )
    $upstream = Get-UpstreamConfig -Repo $Repo -Branch $Branch -ConfigPath $ConfigPath -OfflinePath $OfflinePath -HeadSha $HeadSha
    $records = @(Get-InventoryRecord -YmlText $upstream.Text)
    if ($records.Count -eq 0) { throw "上游 $ConfigPath 未解析出任何动作，疑似格式变更：拒绝给出核查结论" }

    $manifestExists = Test-Path -LiteralPath $ManifestPath -PathType Leaf
    if ($manifestExists) {
        $manifest = Read-InventoryManifest -Path $ManifestPath
    } elseif ($Apply) {
        # 建库：-Apply 允许基线缺失，此时当前 head 即人工审阅基线，不制造 N 条「新增」
        $manifest = $null
    } else {
        throw "基线清单不存在：$ManifestPath（只读核查无法进行；先人工执行 -Apply 建库）"
    }
    $baseline = if ($null -ne $manifest) { @($manifest.actions) } else { @() }
    $reviewedHead = if ($null -ne $manifest -and -not [string]::IsNullOrWhiteSpace((Get-ManifestString $manifest.reviewed_head))) { Get-ManifestString $manifest.reviewed_head } else { $upstream.Head }
    $reviewedAt = if ($null -ne $manifest -and -not [string]::IsNullOrWhiteSpace((Get-ManifestString $manifest.reviewed_at))) { Get-ManifestString $manifest.reviewed_at } else { (Get-Date).ToString('yyyy-MM-dd') }
    $lastSeenHead = if ($null -ne $manifest) { Get-ManifestString $manifest.last_seen_head } else { '' }
    $previousGeneratedAt = if ($null -ne $manifest) { Get-ManifestString $manifest.generated_at } else { '' }

    if ($baseline.Count -eq 0) {
        $delta = [pscustomobject]@{ Added = @(); Removed = @(); Changed = @() }
    } else {
        $delta = Compare-InventoryRecord -Baseline $baseline -Current $records
    }
    $changeCount = @($delta.Added).Count + @($delta.Removed).Count + @($delta.Changed).Count
    $headChanged = $lastSeenHead -ne $upstream.Head
    $timestamp = if ($changeCount -gt 0 -or $headChanged -or [string]::IsNullOrWhiteSpace($previousGeneratedAt)) {
        (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    } else {
        $previousGeneratedAt
    }

    $block = Format-DeltaBlock -Delta $delta -Branch $Branch -Head $upstream.Head -ReviewedHead $reviewedHead `
        -ReviewedAt $reviewedAt -Timestamp $timestamp -ActionCount $records.Count

    $documentChanged = $false
    $manifestChanged = $false
    if ($Apply) {
        $document = Get-DocumentText -Path $DocumentPath
        $merged = Merge-DeltaBlock -Text $document.Text -Block $block
        if ($merged -ne $document.Text) {
            Set-DocumentText -Path $DocumentPath -Text $merged -HasBom $document.HasBom -UsesCrLf $document.UsesCrLf
            $documentChanged = $true
        }

        # 复核标记：head == reviewed_head 时全部视为已审阅；否则指纹未变的沿用原标记，新/变条目标 pending。
        $knownStates = @{}
        foreach ($entry in $baseline) {
            if ($null -eq $entry.review_state) { continue }
            $knownStates[([string]$entry.id + '|' + [string]$entry.fingerprint)] = [string]$entry.review_state
        }
        $headReviewed = $upstream.Head -eq $reviewedHead
        $manifestActions = [System.Collections.Generic.List[object]]::new()
        foreach ($record in $records) {
            $state = 'pending'
            if ($headReviewed) {
                $state = 'reviewed'
            } else {
                $knownKey = $record.id + '|' + $record.fingerprint
                if ($knownStates.ContainsKey($knownKey)) { $state = $knownStates[$knownKey] }
            }
            $manifestActions.Add([ordered]@{
                    id           = $record.id
                    type         = $record.type
                    key          = $record.key
                    fingerprint  = $record.fingerprint
                    line         = [int]$record.line
                    review_state = $state
                })
        }

        $existingHashes = @{}
        if ($null -ne $manifest.file_hashes) {
            foreach ($property in $manifest.file_hashes.PSObject.Properties) { $existingHashes[$property.Name] = [string]$property.Value }
        }
        $fileHashes = $existingHashes
        if (-not $SkipFileHash -and $upstream.Origin -eq 'remote') {
            $fileHashes = Get-UpstreamFileHash -Repo $Repo -Ref $upstream.Head -ConfigPath $ConfigPath -ConfigBytes $upstream.Bytes -Existing $existingHashes
        } elseif ($null -ne $upstream.Bytes) {
            $fileHashes = @{}
            foreach ($name in @($existingHashes.Keys)) { $fileHashes[$name] = $existingHashes[$name] }
            $fileHashes[$ConfigPath] = Get-BytesSha256Hex -Bytes $upstream.Bytes
        }

        $manifestObject = [ordered]@{
            source         = $Repo
            branch         = $Branch
            reviewed_head  = $reviewedHead
            reviewed_at    = $reviewedAt
            last_seen_head = $upstream.Head
            generated_at   = $timestamp
            action_count   = $records.Count
            file_hashes    = $fileHashes
            actions        = $manifestActions
        }
        $manifestText = ConvertTo-ManifestText -Manifest $manifestObject
        $existingText = ''
        if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
            $existingText = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8
        }
        if ($null -ne $existingText) { $existingText = $existingText.Replace("`r`n", "`n").TrimStart([char]0xFEFF) }
        if ($existingText -ne $manifestText) {
            Set-DocumentText -Path $ManifestPath -Text $manifestText
            $manifestChanged = $true
        }
    }

    return [pscustomobject]@{
        Head            = $upstream.Head
        Branch          = $Branch
        ReviewedHead    = $reviewedHead
        ReviewedAt      = $reviewedAt
        ActionCount     = $records.Count
        BaselineCount   = $baseline.Count
        Added           = @($delta.Added).Count
        Removed         = @($delta.Removed).Count
        Changed         = @($delta.Changed).Count
        ChangeCount     = $changeCount
        Timestamp       = $timestamp
        Delta           = $delta
        Block           = $block
        DocumentChanged = $documentChanged
        ManifestChanged = $manifestChanged
        Applied         = [bool]$Apply
        ExitCode        = if ($changeCount -gt 0) { 10 } else { 0 }
    }
}

function Format-CheckReport {
    <#
        供 issue 正文追加的核查结论（首行即机器可读的口径）。
    #>
    param(
        [Parameter(Mandatory)]$Result,
        [string]$ManifestRelativePath = 'tools/xos-playbook-inventory.json',
        [string]$DocumentRelativePath = 'docs/reference/XOS-PLAYBOOK-INVENTORY.md'
    )
    $head = Get-ShortHash $Result.Head
    $reviewed = Get-ShortHash $Result.ReviewedHead
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('### 🧾 xos-playbook 清单核查')
    $lines.Add('')
    if ($Result.ChangeCount -gt 0) {
        $lines.Add("清单核查：⚠️ 需要更新（新增 $($Result.Added) / 删除 $($Result.Removed) / 变更 $($Result.Changed)，基准 $reviewed → $head）")
    } else {
        $lines.Add("清单核查：✅ 清单仍与上游一致（$($Result.ActionCount) 条，0 变动）")
    }
    $lines.Add('')
    $lines.Add("- 清单文档：``$DocumentRelativePath``（人工结论不受影响；是否改文档由人决定）")
    $lines.Add("- 基线：``$ManifestRelativePath``（$($Result.BaselineCount) 条动作，人工审阅 head ``$reviewed``）")
    $lines.Add("- 本次上游：``$($Result.Branch)`` @ ``$head``；核查时间 ``$($Result.Timestamp)``")
    if ($Result.ChangeCount -gt 0) {
        $lines.Add('- 本步骤只读：未修改文档与基线。确认后人工执行 `pwsh tools/check-xos-inventory.ps1 -Apply` 刷新文档区块与基线')
    } elseif ($Result.Head -ne $Result.ReviewedHead) {
        $lines.Add('- 结论：head 已前移，但 808 条动作的类型与指纹与基线逐条一致，无需改文档')
    } else {
        $lines.Add('- 结论：上游 head 与人工审阅 head 相同，无需任何动作')
    }

    $added = @($Result.Delta.Added)
    $removed = @($Result.Delta.Removed)
    $changed = @($Result.Delta.Changed)
    if ($added.Count -gt 0) {
        $lines.Add('')
        $lines.Add("<details><summary>新增（待复核）$($added.Count) 项</summary>")
        $lines.Add('')
        $lines.Add('| 类型 | key | 行号 |')
        $lines.Add('| --- | --- | --- |')
        foreach ($row in $added) {
            $lines.Add("| ``$($row.type)`` | $(([string]$row.key).Replace('|', '\|')) | $($row.line) |")
        }
        $lines.Add('')
        $lines.Add('</details>')
    }
    if ($removed.Count -gt 0) {
        $lines.Add('')
        $lines.Add("<details><summary>删除（待复核）$($removed.Count) 项</summary>")
        $lines.Add('')
        $lines.Add('| 类型 | key | 原行号 |')
        $lines.Add('| --- | --- | --- |')
        foreach ($row in $removed) {
            $lines.Add("| ``$($row.type)`` | $(([string]$row.key).Replace('|', '\|')) | $($row.line) |")
        }
        $lines.Add('')
        $lines.Add('</details>')
    }
    if ($changed.Count -gt 0) {
        $lines.Add('')
        $lines.Add("<details><summary>变更（待复核）$($changed.Count) 项</summary>")
        $lines.Add('')
        $lines.Add('| 类型 | key | 行号 | 原行号 | 旧指纹 | 新指纹 |')
        $lines.Add('| --- | --- | --- | --- | --- | --- |')
        foreach ($row in $changed) {
            $lines.Add("| ``$($row.type)`` | $(([string]$row.key).Replace('|', '\|')) | $($row.line) | $($row.base_line) | ``$(Get-ShortHash $row.old_fingerprint)`` | ``$(Get-ShortHash $row.new_fingerprint)`` |")
        }
        $lines.Add('')
        $lines.Add('</details>')
    }
    return ($lines -join "`n") + "`n"
}

function Format-CheckReportForError {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Head = '',
        [string]$ReviewedHead = ''
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('### 🧾 xos-playbook 清单核查')
    $lines.Add('')
    $lines.Add("清单核查：❌ 核查失败（$Message）")
    $lines.Add('')
    $lines.Add('- 本次未给出「一致 / 需要更新」结论：拉取失败或基线损坏时不得假装核对过')
    if ($Head) { $lines.Add("- 本次 head：``$(Get-ShortHash $Head)``") }
    if ($ReviewedHead) { $lines.Add("- 基线 head：``$(Get-ShortHash $ReviewedHead)``") }
    return ($lines -join "`n") + "`n"
}

if ($MyInvocation.InvocationName -eq '.') { return }

$exitCode = 20
$report = $null
try {
    $result = Test-XosInventory -Repo $Repo -Branch $Branch -ConfigPath $ConfigPath -ManifestPath $ManifestPath `
        -DocumentPath $DocumentPath -OfflinePath $OfflinePath -HeadSha $HeadSha -Apply:$Apply -SkipFileHash:$SkipFileHash
    $report = Format-CheckReport -Result $result
    $exitCode = $result.ExitCode
    Write-Host ("[INFO] 上游 {0}/{1} head={2}（基准 {3}）" -f $Repo, $Branch, $result.Head, $result.ReviewedHead)
    Write-Host ("[INFO] 动作总数 {0}；新增 {1} / 删除 {2} / 变更 {3}" -f $result.ActionCount, $result.Added, $result.Removed, $result.Changed)
    if ($Apply) {
        Write-Host ("[INFO] -Apply：文档{0}；基线 JSON{1}" -f $(if ($result.DocumentChanged) { '已更新' } else { '无变化' }), $(if ($result.ManifestChanged) { '已更新' } else { '无变化' }))
    } else {
        Write-Host '[INFO] 只读核查：未写入文档与基线'
        Write-Host $result.Block
    }
    if ($env:GITHUB_OUTPUT) {
        $output = @(
            "head=$($result.Head)",
            "reviewed_head=$($result.ReviewedHead)",
            "action_count=$($result.ActionCount)",
            "added=$($result.Added)",
            "removed=$($result.Removed)",
            "changed=$($result.Changed)",
            "delta_count=$($result.ChangeCount)",
            "needs_update=$(if ($result.ChangeCount -gt 0) { 'true' } else { 'false' })"
        )
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ($output -join "`n") -Encoding utf8
    }
} catch {
    $report = Format-CheckReportForError -Message $_.Exception.Message
    Write-Host ("[ERROR] xos 清单核查失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
    $exitCode = 20
}

if (-not $NoReport) {
    try {
        Set-DocumentText -Path $ReportPath -Text $report
        Write-Host "[INFO] 核查报告：$ReportPath"
    } catch {
        Write-Warning "核查报告写入失败：$($_.Exception.Message)"
    }
}

exit $exitCode
