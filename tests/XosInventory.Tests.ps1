BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    $script:toolPath = Join-Path $script:repoRoot 'tools/check-xos-inventory.ps1'
    . $script:toolPath
    $script:manifestPath = Join-Path $script:repoRoot 'tools/xos-playbook-inventory.json'
    $script:docPath = Join-Path $script:repoRoot 'docs/reference/XOS-PLAYBOOK-INVENTORY.md'
    # 子进程调用真实的 pwsh，保证退出码与「零写入」结论和 CI 一致（dot-source 会跳过 main）
    $script:pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $script:scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('xos-inventory-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $script:scratch -Force | Out-Null
    $script:docTemplate = @'
# 清单

> 人工结论：A 组 431 条。

## 0. 计数口径

六组之和 = 808。

## 1. 总览

正文。
'@
    $script:baselineYml = @'
actions:
  - !writeStatus: {status: 'Start'}
  - !registryValue: {path: 'HKLM\SOFTWARE\Test', value: 'Keep', type: REG_DWORD, data: '1'}
  - !service: {name: 'DiagTrack', operation: change, startup: 4}
  - !powerShell: {command: '.\Run.ps1 -Mode Apply', exeDir: true, wait: true}
'@
    $script:driftYml = @'
actions:
  - !writeStatus: {status: 'Start'}
  - !registryValue: {path: 'HKLM\SOFTWARE\Test', value: 'Keep', type: REG_DWORD, data: '0'}
  - !registryValue: {path: 'HKLM\SOFTWARE\Test', value: 'Brand', type: REG_DWORD, data: '1'}
  - !powerShell: {command: '.\Run.ps1 -Mode Apply', exeDir: true, wait: true}
'@

    function New-ScratchFile {
        param([string]$Name, [string]$Content)
        $path = Join-Path $script:scratch $Name
        [System.IO.File]::WriteAllText($path, $Content, [System.Text.UTF8Encoding]::new($false))
        return $path
    }

    function Get-FileDigest {
        param([string]$Path)
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
    }

    function New-CheckWorkspace {
        # 建一份临时文档 + 基线的隔离工作区，任何测试都不会碰仓库里的真文件
        param([string]$Name, [string]$BaselineYml = $script:baselineYml)
        $dir = Join-Path $script:scratch $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $doc = Join-Path $dir 'INVENTORY.md'
        [System.IO.File]::WriteAllText($doc, $script:docTemplate, [System.Text.UTF8Encoding]::new($false))
        $yml = Join-Path $dir 'custom.yml'
        [System.IO.File]::WriteAllText($yml, $BaselineYml, [System.Text.UTF8Encoding]::new($false))
        $manifest = Join-Path $dir 'inventory.json'
        $report = Join-Path $dir 'check.md'
        $apply = Invoke-CheckTool -OfflinePath $yml -HeadSha ('a' * 40) -DocumentPath $doc -ManifestPath $manifest -ReportPath $report -Apply
        if ($apply.ExitCode -ne 0) { throw "建库失败（exit=$($apply.ExitCode)）：$($apply.Output)" }
        return [pscustomobject]@{
            Dir      = $dir
            Doc      = $doc
            Yml      = $yml
            Manifest = $manifest
            Report   = $report
        }
    }

    function Invoke-CheckTool {
        param(
            [string]$OfflinePath,
            [string]$HeadSha,
            [string]$DocumentPath,
            [string]$ManifestPath,
            [string]$ReportPath,
            [switch]$Apply,
            [switch]$NoReport
        )
        $arguments = @('-NoProfile', '-File', $script:toolPath)
        if ($OfflinePath) { $arguments += @('-OfflinePath', $OfflinePath) }
        if ($HeadSha) { $arguments += @('-HeadSha', $HeadSha) }
        if ($DocumentPath) { $arguments += @('-DocumentPath', $DocumentPath) }
        if ($ManifestPath) { $arguments += @('-ManifestPath', $ManifestPath) }
        if ($ReportPath) { $arguments += @('-ReportPath', $ReportPath) }
        if ($Apply) { $arguments += '-Apply' }
        if ($NoReport) { $arguments += '-NoReport' }
        $output = & $script:pwshExe @arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    if ($script:scratch -and (Test-Path -LiteralPath $script:scratch)) {
        Remove-Item -LiteralPath $script:scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'XOS playbook 动作解析' {
    It '解析内联与折叠块两种写法，计数一致' {
        $yml = @'
actions:
  - !writeStatus: {status: 'A'}
  - !powerShell: {command: '.\A.ps1', exeDir: true}
  - !powerShell:
      wait: true
      command: >-
        Set-Thing -Name x;
        Set-Other -Name y
  - !registryValue: {path: 'HKLM\X', value: 'Y', type: REG_DWORD, data: '1'}
'@
        $actions = @(ConvertFrom-CustomYml -Text $yml)
        $actions.Count | Should -Be 4
        $actions[2].Type | Should -Be 'powerShell'
        $actions[2].Fields['command'] | Should -Be 'Set-Thing -Name x; Set-Other -Name y'
        $actions[3].Line | Should -Be 9
    }

    It '忽略非动作行与 --- 文档头' {
        $yml = @'
---
actions:
  # 注释
  - !taskKill: {name: 'explorer'}
  -   !service: {name: 'X', operation: change, startup: 4}
'@
        $actions = @(ConvertFrom-CustomYml -Text $yml)
        @($actions).Count | Should -Be 2
        $actions[0].Type | Should -Be 'taskKill'
        $actions[1].Type | Should -Be 'service'
    }

    It 'flow mapping 里带花括号的注册表路径与含逗号的命令不被切坏' {
        $yml = @'
actions:
  - !registryValue: {path: 'HKLM\SOFTWARE\Classes\CLSID\{018D5C66-4533}', value: 'System.IsPinned', type: REG_DWORD, data: '0'}
  - !run: {exe: 'cmd.exe', args: '/c echo a, b, c', wait: true}
'@
        $actions = @(ConvertFrom-CustomYml -Text $yml)
        $actions[0].Fields['path'] | Should -Be 'HKLM\SOFTWARE\Classes\CLSID\{018D5C66-4533}'
        $actions[1].Fields['args'] | Should -Be '/c echo a, b, c'
    }

    It 'dev @0ed60c3 的 custom.yml 解析出 808 条动作（上游文件不入库，CI 跳过；本地用 XOS_PLAYBOOK_CUSTOM_YML 复核）' {
        if ([string]::IsNullOrWhiteSpace($env:XOS_PLAYBOOK_CUSTOM_YML)) {
            Set-ItResult -Skipped -Because '未提供 XOS_PLAYBOOK_CUSTOM_YML（上游文件不入库，避免复制未授权内容）'
        }
        $records = @(Get-InventoryRecord -YmlText (Get-Content -LiteralPath $env:XOS_PLAYBOOK_CUSTOM_YML -Raw))
        $records.Count | Should -Be 808
        ($records | Group-Object type | ForEach-Object { "$($_.Name)=$($_.Count)" } | Sort-Object) |
            Should -Be @('appx=1', 'cmd=17', 'file=13', 'powerShell=84', 'registryKey=42', 'registryValue=475', 'run=50', 'service=50', 'taskKill=17', 'writeStatus=59')
    }
}

Describe 'XOS 清单 key 规则' {
    BeforeAll {
        $script:keyYml = @'
actions:
  - !registryValue: {path: 'HKLM\SOFTWARE\Test', value: 'MixedCase', type: REG_DWORD, data: '1'}
  - !service: {name: 'DiagTrack', operation: change, startup: 4}
  - !run: {exe: 'tool.exe', args: '--a 1', wait: true}
  - !registryKey: {path: 'HKLM\SOFTWARE\Delete\Me', operation: delete}
  - !taskKill: {name: 'explorer'}
  - !appx: {operation: clearCache, name: '*SecHealthUI*'}
  - !file: {path: 'C:\Temp\x.lnk'}
  - !powerShell: {command: 'Get-Foo -Bar; Set-Baz', exeDir: true}
  - !cmd: {command: 'echo hello'}
'@
        $script:keyActions = @(ConvertFrom-CustomYml -Text $script:keyYml)
    }

    It 'registryValue 用 path|value 且小写' {
        Get-ActionKey -Action $script:keyActions[0] | Should -Be 'hklm\software\test|mixedcase'
    }

    It 'service 用 name（保留大小写）' {
        Get-ActionKey -Action $script:keyActions[1] | Should -Be 'DiagTrack'
    }

    It 'run 用 exe|args' {
        Get-ActionKey -Action $script:keyActions[2] | Should -Be 'tool.exe|--a 1'
    }

    It 'registryKey 用 path，taskKill/appx/file 用主参数' {
        Get-ActionKey -Action $script:keyActions[3] | Should -Be 'HKLM\SOFTWARE\Delete\Me'
        Get-ActionKey -Action $script:keyActions[4] | Should -Be 'explorer'
        Get-ActionKey -Action $script:keyActions[5] | Should -Be '*SecHealthUI*'
        Get-ActionKey -Action $script:keyActions[6] | Should -Be 'C:\Temp\x.lnk'
    }

    It 'powerShell/cmd 用命令首行' {
        Get-ActionKey -Action $script:keyActions[7] | Should -Be 'Get-Foo -Bar; Set-Baz'
        Get-ActionKey -Action $script:keyActions[8] | Should -Be 'echo hello'
    }

    It '命令 key 截断到 120 字符' {
        $long = 'Get-Thing -Name ' + ('x' * 200)
        $yml = "actions:`n  - !powerShell: {command: '$long', exeDir: true}`n"
        $action = @(ConvertFrom-CustomYml -Text $yml)[0]
        $key = Get-ActionKey -Action $action
        $key.Length | Should -Be 120
        $key | Should -Be $long.Substring(0, 120)
    }

    It '折叠块与内联写法对同一命令产生同一个 key' {
        $inline = @'
actions:
  - !powerShell: {command: 'Set-A; Set-B', wait: true}
'@
        $block = @"
actions:
  - !powerShell:
      wait: true
      command: >-
        Set-A;
        Set-B
"@
        $a = @(ConvertFrom-CustomYml -Text $inline)[0]
        $b = @(ConvertFrom-CustomYml -Text $block)[0]
        (Get-ActionKey -Action $a) | Should -Be (Get-ActionKey -Action $b)
    }
}

Describe 'XOS 清单指纹' {
    It '同一条动作重复解析得到同一指纹' {
        $yml = "actions:`n  - !registryValue: {path: 'HKLM\X', value: 'Y', type: REG_DWORD, data: '1'}`n"
        $first = @(Get-InventoryRecord -YmlText $yml)[0]
        $second = @(Get-InventoryRecord -YmlText $yml)[0]
        $first.fingerprint | Should -Be $second.fingerprint
        $first.fingerprint.Length | Should -Be 64
    }

    It '行号漂移不改变指纹' {
        $before = "actions:`n  - !service: {name: 'X', operation: change, startup: 4}`n"
        $after = "actions:`n`n`n  - !service: {name: 'X', operation: change, startup: 4}`n"
        $a = @(Get-InventoryRecord -YmlText $before)[0]
        $b = @(Get-InventoryRecord -YmlText $after)[0]
        $a.line | Should -Not -Be $b.line
        $a.fingerprint | Should -Be $b.fingerprint
    }

    It '字段顺序与空白变化不改变指纹，值变化才改变指纹' {
        $a = @(Get-InventoryRecord -YmlText "actions:`n  - !registryValue: {path: 'HKLM\X', value: 'Y', type: REG_DWORD, data: '1'}`n")[0]
        $b = @(Get-InventoryRecord -YmlText "actions:`n  - !registryValue: {data: '1', value: 'Y', type: REG_DWORD, path: 'HKLM\X'}`n")[0]
        $c = @(Get-InventoryRecord -YmlText "actions:`n  - !registryValue: {path: 'HKLM\X', value: 'Y', type: REG_DWORD, data: '2'}`n")[0]
        $a.fingerprint | Should -Be $b.fingerprint
        $a.fingerprint | Should -Not -Be $c.fingerprint
    }

    It '同一 type/key 的重复动作得到不同 id 后缀' {
        $yml = @'
actions:
  - !taskKill: {name: 'explorer'}
  - !taskKill: {name: 'explorer'}
'@
        $records = @(Get-InventoryRecord -YmlText $yml)
        $records[0].id | Should -Not -Be $records[1].id
        $records[1].id | Should -BeLike '*-1'
    }
}

Describe 'XOS 清单差异比对' {
    BeforeAll {
        $script:baselineRecords = @(Get-InventoryRecord -YmlText $script:baselineYml)
        $script:driftRecords = @(Get-InventoryRecord -YmlText $script:driftYml)
    }

    It '识别新增 / 删除 / 变更三类' {
        $delta = Compare-InventoryRecord -Baseline $script:baselineRecords -Current $script:driftRecords
        @($delta.Added).Count | Should -Be 1
        @($delta.Removed).Count | Should -Be 1
        @($delta.Changed).Count | Should -Be 1
        $delta.Added[0].key | Should -Be 'hklm\software\test|brand'
        $delta.Removed[0].key | Should -Be 'DiagTrack'
        $delta.Changed[0].key | Should -Be 'hklm\software\test|keep'
        $delta.Changed[0].old_fingerprint | Should -Not -Be $delta.Changed[0].new_fingerprint
    }

    It '同一份输入比对为零差异' {
        $delta = Compare-InventoryRecord -Baseline $script:baselineRecords -Current $script:baselineRecords
        @($delta.Added).Count | Should -Be 0
        @($delta.Removed).Count | Should -Be 0
        @($delta.Changed).Count | Should -Be 0
    }
}

Describe 'XOS 变动区块渲染' {
    BeforeAll {
        $script:emptyDelta = [pscustomobject]@{ Added = @(); Removed = @(); Changed = @() }
        $script:driftDelta = Compare-InventoryRecord `
            -Baseline @(Get-InventoryRecord -YmlText $script:baselineYml) `
            -Current @(Get-InventoryRecord -YmlText $script:driftYml)
        $script:renderArgs = @{
            Branch       = 'dev'
            Head         = 'b' * 40
            ReviewedHead = 'a' * 40
            ReviewedAt   = '2026-11-20'
            Timestamp    = '2026-11-21T00:00:00Z'
            ActionCount  = 4
        }
    }

    It '无变动时给出 0/0/0 结论' {
        $render = $script:renderArgs
        $block = Format-DeltaBlock -Delta $script:emptyDelta @render
        $block | Should -BeLike '*<!-- XOS-INVENTORY:DELTA:START -->*'
        $block | Should -BeLike '*<!-- XOS-INVENTORY:DELTA:END -->*'
        $block | Should -BeLike '*| 新增 / 删除 / 变更 | 0 / 0 / 0 |*'
        $block | Should -BeLike '*无动作级变动*'
    }

    It '有变动时三类都列出且标待复核' {
        $render = $script:renderArgs
        $block = Format-DeltaBlock -Delta $script:driftDelta @render
        $block | Should -BeLike '*| 新增 / 删除 / 变更 | 1 / 1 / 1 |*'
        $block | Should -BeLike '*### 新增（待复核）1 项*'
        $block | Should -BeLike '*### 删除（待复核）1 项*'
        $block | Should -BeLike '*### 变更（待复核）1 项*'
        $block | Should -BeLike '*hklm\software\test\|brand*'
    }

    It '同一输入重复渲染逐字节一致（幂等）' {
        $render = $script:renderArgs
        $first = Format-DeltaBlock -Delta $script:driftDelta @render
        $second = Format-DeltaBlock -Delta $script:driftDelta @render
        $first | Should -Be $second
    }

    It '重复合并同一区块不改变文档（幂等）' {
        $render = $script:renderArgs
        $block = Format-DeltaBlock -Delta $script:emptyDelta @render
        $once = Merge-DeltaBlock -Text $script:docTemplate -Block $block
        $twice = Merge-DeltaBlock -Text $once -Block $block
        $once | Should -Be $twice
    }

    It '区块插在第一个二级标题之前' {
        $render = $script:renderArgs
        $block = Format-DeltaBlock -Delta $script:emptyDelta @render
        $merged = Merge-DeltaBlock -Text $script:docTemplate -Block $block
        $merged.IndexOf('<!-- XOS-INVENTORY:DELTA:START -->') | Should -BeLessThan $merged.IndexOf('## 0. 计数口径')
        $merged | Should -BeLike '*# 清单*'
        $merged | Should -BeLike '*正文。*'
    }

    It '已有区块时原地替换，正文不动' {
        $render = $script:renderArgs
        $emptyBlock = Format-DeltaBlock -Delta $script:emptyDelta @render
        $driftBlock = Format-DeltaBlock -Delta $script:driftDelta @render
        $first = Merge-DeltaBlock -Text $script:docTemplate -Block $emptyBlock
        $second = Merge-DeltaBlock -Text $first -Block $driftBlock
        $second | Should -BeLike '*### 新增（待复核）1 项*'
        ($second.Split('<!-- XOS-INVENTORY:DELTA:START -->').Count - 1) | Should -Be 1
        $second | Should -BeLike '*## 0. 计数口径*'
        $second | Should -BeLike '*正文。*'
    }
}

Describe 'XOS 清单核查（CI 路径只读）' {
    It '无变动时退出码 0，且文档与基线逐字节不变' {
        $ws = New-CheckWorkspace -Name 'clean'
        $docBefore = Get-FileDigest $ws.Doc
        $manifestBefore = Get-FileDigest $ws.Manifest
        $run = Invoke-CheckTool -OfflinePath $ws.Yml -HeadSha ('a' * 40) -DocumentPath $ws.Doc -ManifestPath $ws.Manifest -ReportPath $ws.Report
        $run.ExitCode | Should -Be 0
        Get-FileDigest $ws.Doc | Should -Be $docBefore
        Get-FileDigest $ws.Manifest | Should -Be $manifestBefore
        (Get-Content -LiteralPath $ws.Report -Raw) | Should -BeLike '*清单核查：✅ 清单仍与上游一致（4 条，0 变动）*'
    }

    It '有变动时退出码 10、报告点名三类计数，但仍不写文档与基线' {
        $ws = New-CheckWorkspace -Name 'drift'
        $docBefore = Get-FileDigest $ws.Doc
        $manifestBefore = Get-FileDigest $ws.Manifest
        $drift = New-ScratchFile -Name 'drift-custom.yml' -Content $script:driftYml
        $run = Invoke-CheckTool -OfflinePath $drift -HeadSha ('b' * 40) -DocumentPath $ws.Doc -ManifestPath $ws.Manifest -ReportPath $ws.Report
        $run.ExitCode | Should -Be 10
        Get-FileDigest $ws.Doc | Should -Be $docBefore
        Get-FileDigest $ws.Manifest | Should -Be $manifestBefore
        $report = Get-Content -LiteralPath $ws.Report -Raw
        $report | Should -BeLike '*清单核查：⚠️ 需要更新（新增 1 / 删除 1 / 变更 1*'
        $report | Should -BeLike '*docs/reference/XOS-PLAYBOOK-INVENTORY.md*'
        # 子进程 stdout 的中文会受控制台代码页影响，这里用 ASCII 标记证明 dry-run 只打印不落盘
        $run.Output | Should -BeLike '*XOS-INVENTORY:DELTA:START*'
    }

    It '基线缺失时退出码 20（不得假装核对过）' {
        $dir = Join-Path $script:scratch 'missing-baseline'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $doc = Join-Path $dir 'INVENTORY.md'
        [System.IO.File]::WriteAllText($doc, $script:docTemplate, [System.Text.UTF8Encoding]::new($false))
        $yml = New-ScratchFile -Name 'missing-baseline.yml' -Content $script:baselineYml
        $run = Invoke-CheckTool -OfflinePath $yml -HeadSha ('a' * 40) -DocumentPath $doc `
            -ManifestPath (Join-Path $dir 'nope.json') -ReportPath (Join-Path $dir 'report.md')
        $run.ExitCode | Should -Be 20
        (Get-Content -LiteralPath (Join-Path $dir 'report.md') -Raw) | Should -BeLike '*清单核查：❌ 核查失败*'
    }

    It '基线 JSON 损坏时退出码 20' {
        $ws = New-CheckWorkspace -Name 'broken-baseline'
        [System.IO.File]::WriteAllText($ws.Manifest, '{ "actions": [', [System.Text.UTF8Encoding]::new($false))
        $run = Invoke-CheckTool -OfflinePath $ws.Yml -HeadSha ('a' * 40) -DocumentPath $ws.Doc -ManifestPath $ws.Manifest -ReportPath $ws.Report
        $run.ExitCode | Should -Be 20
    }

    It '解析不出动作时退出码 20' {
        $ws = New-CheckWorkspace -Name 'garbage-yml'
        $bad = New-ScratchFile -Name 'garbage.yml' -Content "not-a-playbook: true`n"
        $run = Invoke-CheckTool -OfflinePath $bad -HeadSha ('a' * 40) -DocumentPath $ws.Doc -ManifestPath $ws.Manifest -ReportPath $ws.Report
        $run.ExitCode | Should -Be 20
    }

    It '仓库内真文档与真基线在只读核查后不变' {
        $docBefore = Get-FileDigest $script:docPath
        $manifestBefore = Get-FileDigest $script:manifestPath
        $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $script:manifestPath -Raw)
        $firstAction = @($manifest.actions)[0]
        # 用仓库真基线做对照：离线喂回基线自身解析出的最小样本不可行，这里只验证只读性
        $run = Invoke-CheckTool -OfflinePath $script:docPath -HeadSha ('a' * 40) -DocumentPath $script:docPath `
            -ManifestPath $script:manifestPath -ReportPath (Join-Path $script:scratch 'repo-check.md')
        $run.ExitCode | Should -Be 20
        Get-FileDigest $script:docPath | Should -Be $docBefore
        Get-FileDigest $script:manifestPath | Should -Be $manifestBefore
        $firstAction.review_state | Should -Not -BeNullOrEmpty
    }
}

Describe 'XOS 清单产物' {
    BeforeAll {
        $script:manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $script:manifestPath -Raw)
        $script:actions = @($script:manifest.actions)
    }

    It '基线记录 808 条动作与类型分布' {
        $script:manifest.action_count | Should -Be 808
        $script:actions.Count | Should -Be 808
        ($script:actions | Group-Object type | ForEach-Object { "$($_.Name)=$($_.Count)" } | Sort-Object) |
            Should -Be @('appx=1', 'cmd=17', 'file=13', 'powerShell=84', 'registryKey=42', 'registryValue=475', 'run=50', 'service=50', 'taskKill=17', 'writeStatus=59')
    }

    It '每条都有稳定 id、非空 key 与 64 位指纹' {
        @($script:actions | Where-Object { $_.id -notmatch '^[0-9a-f]{16}(-[0-9]+)?$' }).Count | Should -Be 0
        @($script:actions | Where-Object { [string]::IsNullOrWhiteSpace($_.key) }).Count | Should -Be 0
        @($script:actions | Where-Object { $_.fingerprint -notmatch '^[0-9a-f]{64}$' }).Count | Should -Be 0
        @($script:actions.id | Sort-Object -Unique).Count | Should -Be 808
    }

    It '顶层记录 source/branch/reviewed_head/reviewed_at/generated_at/file_hashes' {
        $script:manifest.source | Should -Be 'imribiy/xos-playbook'
        $script:manifest.branch | Should -Be 'dev'
        $script:manifest.reviewed_head | Should -Match '^[0-9a-f]{40}$'
        $script:manifest.reviewed_at | Should -Not -BeNullOrEmpty
        # 落盘格式必须是 ISO-8601（ConvertFrom-Json 会把 ISO 串转成 DateTime，故校验原文）
        $rawManifest = Get-Content -LiteralPath $script:manifestPath -Raw
        $rawManifest | Should -Match '"generated_at": "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        $rawManifest | Should -Match '"reviewed_at": "\d{4}-\d{2}-\d{2}"'
        $script:manifest.last_seen_head | Should -Match '^[0-9a-f]{40}$'
    }

    It 'file_hashes 覆盖 custom.yml、playbook.conf 与全部 Executables 文件' {
        $names = @($script:manifest.file_hashes.PSObject.Properties.Name)
        $names | Should -Contain 'Configuration/custom.yml'
        $names | Should -Contain 'playbook.conf'
        @($names | Where-Object { $_ -like 'Executables/*' }).Count | Should -BeGreaterThan 20
        foreach ($name in $names) {
            [string]$script:manifest.file_hashes.$name | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It '清单文档保留 A-E 分组、候选节与自检节' {
        $doc = Get-Content -LiteralPath $script:docPath -Raw
        $doc | Should -BeLike '*### 3.1 A. 破坏性修改*'
        $doc | Should -BeLike '*### 3.2 B. 安全削弱*'
        $doc | Should -BeLike '*### 3.3 C. 范围外*'
        $doc | Should -BeLike '*### 3.4 D. 无依据/重复/无效*'
        $doc | Should -BeLike '*### 3.5 E. 本轮用户未选*'
        $doc | Should -BeLike '*## 4. 未覆盖但可考虑的候选*'
        $doc | Should -BeLike '*### 5.4 自检*'
        $doc | Should -BeLike '*六组之和 = 808*'
        $doc | Should -BeLike '*tools/check-xos-inventory.ps1*'
        $doc | Should -BeLike '*<!-- XOS-INVENTORY:DELTA:START -->*'
        $doc | Should -BeLike '*<!-- XOS-INVENTORY:DELTA:END -->*'
    }
}

Describe 'XOS 清单 -Apply（人工路径）' {
    It '写回区块与基线，但保留 reviewed_head 并把新条目置 pending' {
        $ws = New-CheckWorkspace -Name 'apply-drift'
        $manifestBefore = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ws.Manifest -Raw)
        $drift = New-ScratchFile -Name 'apply-drift.yml' -Content $script:driftYml
        $run = Invoke-CheckTool -OfflinePath $drift -HeadSha ('b' * 40) -DocumentPath $ws.Doc -ManifestPath $ws.Manifest -ReportPath $ws.Report -Apply
        $run.ExitCode | Should -Be 10
        $doc = Get-Content -LiteralPath $ws.Doc -Raw
        $doc | Should -BeLike '*### 新增（待复核）1 项*'
        $doc | Should -BeLike '*| 新增 / 删除 / 变更 | 1 / 1 / 1 |*'
        $manifestAfter = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ws.Manifest -Raw)
        $manifestAfter.reviewed_head | Should -Be $manifestBefore.reviewed_head
        $manifestAfter.last_seen_head | Should -Be ('b' * 40)
        $manifestAfter.action_count | Should -Be 4
        $brand = @($manifestAfter.actions | Where-Object { $_.key -like '*|brand' })
        $brand.Count | Should -Be 1
        $brand[0].review_state | Should -Be 'pending'
        $keep = @($manifestAfter.actions | Where-Object { $_.key -like '*|keep' })
        $keep[0].review_state | Should -Be 'pending'
        @($manifestAfter.actions | Where-Object { $_.review_state -eq 'reviewed' }).Count | Should -Be 2
    }

    It '同一 head 重复 -Apply 不产生任何字节变化（幂等）' {
        $ws = New-CheckWorkspace -Name 'apply-idempotent'
        $docBefore = Get-FileDigest $ws.Doc
        $manifestBefore = Get-FileDigest $ws.Manifest
        $run = Invoke-CheckTool -OfflinePath $ws.Yml -HeadSha ('a' * 40) -DocumentPath $ws.Doc -ManifestPath $ws.Manifest -ReportPath $ws.Report -Apply
        $run.ExitCode | Should -Be 0
        Get-FileDigest $ws.Doc | Should -Be $docBefore
        Get-FileDigest $ws.Manifest | Should -Be $manifestBefore
    }
}
