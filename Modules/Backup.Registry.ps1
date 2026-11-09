# Backup.Registry.ps1 - Part 1 核心游戏 / 系统行为优化的注册表快照与恢复
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired
# 复用 Backup.Mpo.ps1 的 Get-MpoValueSnapshot / Convert-RegKindForExe 通用逻辑。
# Memory Compression（Disable-MMAgent）与 TRIM（fsutil）不是注册表值，不在快照范围内。

$script:registryCoreValues = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Desc = 'GameDVR AppCaptureEnabled' },
    @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Desc = 'GameDVR_Enabled' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.Gamebar.PresenceServer.Internal.PresenceWriter'; Name = 'ActivationType'; Desc = 'ActivationType（受保护键）' },
    @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'UseNexusForGameBarEnabled'; Desc = 'GameBar UseNexusForGameBarEnabled' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Desc = 'NetworkThrottlingIndex' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Desc = 'SystemResponsiveness' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Desc = 'Win32PrioritySeparation' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Desc = 'HwSchMode / HAGS' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Affinity'; Desc = 'Games Affinity' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Background Only'; Desc = 'Games Background Only' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Clock Rate'; Desc = 'Games Clock Rate' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Desc = 'Games GPU Priority' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Desc = 'Games Priority' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Desc = 'Games Scheduling Category' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Desc = 'Games SFIO Priority' },
    @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Desc = 'AutoGameModeEnabled' },
    @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Desc = 'AllowAutoGameMode' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'TdrDelay'; Desc = 'GPU TdrDelay (放宽 TDR 超时阈值至 10 秒防崩溃)' }
)

$script:registrySystemValues = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Desc = 'BingSearchEnabled' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'AllowSearchToUseLocation'; Desc = 'AllowSearchToUseLocation' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Desc = 'CortanaConsent' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnablePrefetcher'; Desc = 'EnablePrefetcher' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisable8dot3NameCreation'; Desc = 'NtfsDisable8dot3NameCreation' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Desc = 'VisualFXSetting' },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'FontSmoothing'; Desc = 'FontSmoothing' },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'FontSmoothingType'; Desc = 'FontSmoothingType' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAnimations'; Desc = 'TaskbarAnimations' },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'UserPreferencesMask'; Desc = 'UserPreferencesMask（Binary）' },
    @{ Path = 'HKCU:\Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Desc = 'MinAnimate' },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'DragFullWindows'; Desc = 'DragFullWindows' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewAlphaSelect'; Desc = 'ListviewAlphaSelect' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewShadow'; Desc = 'ListviewShadow' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'IconsOnly'; Desc = 'IconsOnly' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\DWM'; Name = 'AlwaysHibernateThumbnails'; Desc = 'AlwaysHibernateThumbnails' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Desc = 'EnableTransparency' },
    @{ Path = 'HKCU:\Control Panel\Accessibility'; Name = 'DynamicScrollbars'; Desc = 'DynamicScrollbars' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'AnimationEffects'; Desc = 'AnimationEffects' },
    @{ Path = 'HKCU:\Control Panel\Accessibility'; Name = 'MessageDuration'; Desc = 'MessageDuration' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name = 'DisableWpbtExecution'; Desc = 'DisableWpbtExecution (阻止 WPBT 固件自动注入)' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name = 'TaskbarEndTask'; Desc = 'TaskbarEndTask (任务栏右键直接结束任务)' },
    @{ Path = 'HKLM:\Software\Policies\Microsoft\PowerShellCore'; Name = 'EnableTelemetry'; Desc = 'PowerShellCore EnableTelemetry (关闭遥测)' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'; Name = 'EnableActiveProbing'; Desc = 'EnableActiveProbing (关闭 NCSI 主动探测)' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'; Name = 'DontOfferThroughWUAU'; Desc = 'DontOfferThroughWUAU (禁止 WUAU 推送恶删工具 MRT)' },
    @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Desc = 'DisableSearchBoxSuggestions (禁用文件资源管理器搜索建议)' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\EventLog-System\{b675ec37-bdb6-4648-bc92-f3fdc74d3ca2}'; Name = 'Enabled'; Desc = 'EventLog-System Kernel-EventTracing Enabled = 0 (抑制 0xC0000035 错误)' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisableLastAccessUpdate'; Desc = 'NtfsDisableLastAccessUpdate (禁用 NTFS 上次访问时间更新)' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'TimerCoalescing'; Desc = 'TimerCoalescing (禁用定时器合并)' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'CoalescingTimerInterval'; Desc = 'CoalescingTimerInterval (定时器合并间隔归零)' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\BrokerInfrastructure\Parameters'; Name = 'DisableTriggerCoalescing'; Desc = 'DisableTriggerCoalescing (禁用触发器合并)' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'DisablePageCombining'; Desc = 'DisablePageCombining (禁用内存页合并去重)' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'MousewheelAnimationDurationMs'; Desc = 'MousewheelAnimationDurationMs (DWM 鼠标滚轮零延迟即时响应)' }
)

# 还原统计：Restore-RegistryBackup 会重置；直接调用 Records 的测试/工具也必须有可写对象
$script:registryRestoreStats = [ordered]@{ Restored = 0; AlreadyOriginal = 0; Conflict = 0; Forced = 0; Legacy = 0; Failed = 0 }

function Test-RegistryBackupSchema {
    # CoreDefinitions/SystemDefinitions 可注入自定义清单（测试用 HKCU 临时键做往返验证）；默认用内置清单
    param([object]$Backup, [object[]]$CoreDefinitions = $script:registryCoreValues,
        [object[]]$SystemDefinitions = $script:registrySystemValues)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        if ([string]$Backup.Binding -ine (Get-BackupMachineId)) { return $false }
        foreach ($pair in @(
                @{ Actual = @($Backup.Core); Expected = $CoreDefinitions },
                @{ Actual = @($Backup.System); Expected = $SystemDefinitions }
            )) {
            $expectedKeys = @($pair.Expected | ForEach-Object { "$($_.Path)|$($_.Name)" })
            $actualKeys = @($pair.Actual | ForEach-Object { "$($_.Path)|$($_.Name)" })
            if ($pair.Actual.Count -ne $expectedKeys.Count) { return $false }
            if (@($actualKeys | Sort-Object -Unique).Count -ne $expectedKeys.Count) { return $false }
            if (@($actualKeys | Where-Object { $expectedKeys -notcontains $_ }).Count -gt 0) { return $false }
            foreach ($r in $pair.Actual) {
                if ($null -eq $r.Exists -or $r.Exists -isnot [bool]) { return $false }
                if ([bool]$r.Exists) {
                    if ([string]::IsNullOrWhiteSpace([string]$r.Kind) -or $null -eq $r.Data) { return $false }
                    try { $null = Convert-RegKindForExe ([string]$r.Kind) } catch { return $false }
                    if ($r.Kind -eq 'DWord') {
                        try {
                            if ([int64]$r.Data -lt 0) {
                                $r.Data = [uint32]([int64]$r.Data -band 0xFFFFFFFFL)
                            }
                            $null = [uint32]$r.Data
                        } catch { return $false }
                    }
                    if ($r.Kind -eq 'Binary' -and ([string]$r.Data -notmatch '^(?:[0-9A-Fa-f]{2})*$')) { return $false }
                } elseif ($null -ne $r.Kind -or $null -ne $r.Data) { return $false }
            }
        }
        return $true
    } catch { return $false }
}

function Migrate-RegistryBackupIfNeeded {
    param(
        [object]$Backup,
        [object[]]$CoreDefinitions = $script:registryCoreValues,
        [object[]]$SystemDefinitions = $script:registrySystemValues
    )
    if ($null -eq $Backup) { return $null }
    $migrated = $false

    foreach ($pair in @(
        @{ Section = 'Core'; Definitions = $CoreDefinitions }
        @{ Section = 'System'; Definitions = $SystemDefinitions }
    )) {
        $propName = $pair.Section
        $currentRecords = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $Backup.$propName) {
            foreach ($item in $Backup.$propName) { $currentRecords.Add($item) }
        }
        $existingKeys = @($currentRecords | ForEach-Object { "$($_.Path)|$($_.Name)" })
        foreach ($def in $pair.Definitions) {
            $key = "$($def.Path)|$($def.Name)"
            if ($existingKeys -notcontains $key) {
                $snapshot = Get-MpoValueSnapshot $def
                $keyExisted = Test-Path -LiteralPath $def.Path
                $snapshot = Add-Member -InputObject $snapshot -NotePropertyName 'KeyExists' -NotePropertyValue $keyExisted -PassThru
                $currentRecords.Add($snapshot)
                $migrated = $true
            }
        }
        $Backup.$propName = @($currentRecords)
    }

    return $Backup
}

function Test-RegistryValueDataEqual {
    # 比较快照/账本里的值数据；DWord 走数值，Binary 走十六进制串，MultiString 逐项比较。
    param([string]$Kind, $Left, $Right)
    switch ($Kind) {
        'DWord' {
            try { return ([uint32]$Left) -eq ([uint32]$Right) } catch { return $false }
        }
        'QWord' {
            try { return ([uint64]$Left) -eq ([uint64]$Right) } catch { return $false }
        }
        'Binary' {
            return (([string]$Left -replace '\s', '') -ieq ([string]$Right -replace '\s', ''))
        }
        'MultiString' {
            $leftItems = @($Left)
            $rightItems = @($Right)
            if ($leftItems.Count -ne $rightItems.Count) { return $false }
            for ($i = 0; $i -lt $leftItems.Count; $i++) {
                if ("$($leftItems[$i])" -cne "$($rightItems[$i])") { return $false }
            }
            return $true
        }
        default { return ("$Left" -ceq "$Right") }
    }
}

function Test-RegistrySnapshotEqualsOriginal {
    param([object]$Current, [object]$Original)
    if ([bool]$Current.Exists -ne [bool]$Original.Exists) { return $false }
    if (-not [bool]$Original.Exists) { return $true }
    if ("$($Current.Kind)" -ne "$($Original.Kind)") { return $false }
    return (Test-RegistryValueDataEqual $Current.Kind $Current.Data $Original.Data)
}

function Test-RegistrySnapshotMatchesApplied {
    param([object]$Current, [object]$Applied)
    if (-not [bool]$Current.Exists) { return $false }
    if ("$($Current.Kind)" -ne "$($Applied.Kind)") { return $false }
    return (Test-RegistryValueDataEqual $Current.Kind $Current.Data $Applied.Data)
}

function Test-RegistryAppliedSchema {
    # registry-applied.json 只记录“本工具最后一次写入的值”，用于还原前检测后续修改。
    param([object]$Ledger)
    try {
        if ($null -eq $Ledger -or [int]$Ledger.Version -ne 1) { return $false }
        if ([string]$Ledger.Binding -ine (Get-BackupMachineId)) { return $false }
        if ($null -eq $Ledger.Entries) { return $false }
        $seen = @{}
        foreach ($entry in @($Ledger.Entries)) {
            if ($null -eq $entry) { return $false }
            foreach ($field in @('Path', 'Name', 'Kind', 'Data', 'Section', 'AppliedAt')) {
                if (-not $entry.PSObject.Properties[$field]) { return $false }
            }
            if ([string]::IsNullOrWhiteSpace([string]$entry.Path) -or [string]::IsNullOrWhiteSpace([string]$entry.Name)) { return $false }
            if ([string]::IsNullOrWhiteSpace([string]$entry.Kind)) { return $false }
            try { $null = Convert-RegKindForExe ([string]$entry.Kind) } catch { return $false }
            if ([string]$entry.Section -notin @('Core', 'System')) { return $false }
            $key = "$($entry.Path)|$($entry.Name)"
            if ($seen.ContainsKey($key)) { return $false }
            $seen[$key] = $true
        }
        return $true
    } catch { return $false }
}

function Read-RegistryAppliedLedger {
    # 账本缺失或损坏时退回旧版行为（按快照盲恢复），并明确告知无法检测后续修改。
    if (-not (Test-Path -LiteralPath $script:registryAppliedFile -PathType Leaf)) { return $null }
    try {
        $ledger = Get-Content -LiteralPath $script:registryAppliedFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-RegistryAppliedSchema $ledger)) {
            Write-Host "[WARN] registry-applied.json 结构或机器绑定校验失败；本次按快照恢复，无法检测优化后的后续修改。" -ForegroundColor Yellow
            return $null
        }
        return $ledger
    } catch {
        Write-Host "[WARN] registry-applied.json 读取失败：$($_.Exception.Message)；本次按快照恢复。" -ForegroundColor Yellow
        return $null
    }
}

function Get-RegistryAppliedEntryMap {
    param([object]$Ledger)
    $map = @{}
    if ($null -eq $Ledger) { return $map }
    foreach ($entry in @($Ledger.Entries)) { $map["$($entry.Path)|$($entry.Name)"] = $entry }
    return $map
}

function Save-RegistryAppliedState {
    # 在一节（Core/System）全部写入并验证成功后调用：把当前值记成“工具写入值”。
    # 只记实际存在的值；原本不存在的值由“删除”动作处理，不需要账本。
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Core', 'System')][string]$Section,
        [Parameter(Mandatory = $true)][object[]]$Definitions
    )
    try {
        $existing = @()
        if (Test-Path -LiteralPath $script:registryAppliedFile -PathType Leaf) {
            try {
                $current = Get-Content -LiteralPath $script:registryAppliedFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if (Test-RegistryAppliedSchema $current) { $existing = @($current.Entries) }
            } catch { $existing = @() }
        }
        $map = @{}
        foreach ($entry in $existing) { $map["$($entry.Path)|$($entry.Name)"] = $entry }
        $now = (Get-Date).ToString('o')
        foreach ($def in $Definitions) {
            $snapshot = Get-MpoValueSnapshot $def
            if (-not [bool]$snapshot.Exists) { continue }
            $key = "$($snapshot.Path)|$($snapshot.Name)"
            $data = if ($snapshot.Kind -eq 'DWord') { [string][uint32]$snapshot.Data } else { [string]$snapshot.Data }
            $map[$key] = [pscustomobject][ordered]@{
                Path      = $snapshot.Path
                Name      = $snapshot.Name
                Kind      = $snapshot.Kind
                Data      = $data
                Section   = $Section
                Label     = "$($def.Desc)"
                AppliedAt = $now
            }
        }
        $ledger = [pscustomobject][ordered]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            UpdatedAt = $now
            Entries   = @($map.Values | Sort-Object Path, Name)
        }
        if (-not (Test-RegistryAppliedSchema $ledger)) { throw '生成的写入账本未通过结构校验' }
        Write-TweakAtomicTextFile -Path $script:registryAppliedFile -Content ($ledger | ConvertTo-Json -Depth 6) -Overwrite
        return $true
    } catch {
        Write-Host "[WARN] 记录本次写入值失败：$($_.Exception.Message)；下次还原将退回快照盲恢复。" -ForegroundColor Yellow
        return $false
    }
}

function Restore-RegistryBackupRecords {
    param([object[]]$Records, [string]$SectionLabel = '注册表', [hashtable]$AppliedMap = @{}, [switch]$Force)
    if ($null -eq $script:registryRestoreStats) {
        $script:registryRestoreStats = [ordered]@{ Restored = 0; AlreadyOriginal = 0; Conflict = 0; Forced = 0; Legacy = 0; Failed = 0 }
    }
    $allOk = $true
    foreach ($r in $Records) {
        $before = $script:fail
        $key = "$($r.Path)|$($r.Name)"
        $current = Get-MpoValueSnapshot @{ Path = $r.Path; Name = $r.Name }
        if (Test-RegistrySnapshotEqualsOriginal $current $r) {
            Write-Host ("[SKIP] {0} {1} 已处于原始值，无需恢复。" -f $SectionLabel, $r.Name) -ForegroundColor DarkGray
            $script:skip++
            $script:registryRestoreStats.AlreadyOriginal++
            continue
        }
        $hasApplied = $AppliedMap.ContainsKey($key)
        if ($hasApplied -and -not $Force) {
            $applied = $AppliedMap[$key]
            if (-not (Test-RegistrySnapshotMatchesApplied $current $applied)) {
                Write-Host ("[SKIP] {0} {1}：优化后又被用户或其他程序修改（当前 {2}，工具写入 {3}）；为不覆盖后续修改，本次不还原。需要强制覆盖请加 -Force。" -f `
                    $SectionLabel, $r.Name, $current.Data, $applied.Data) -ForegroundColor Yellow
                $script:skip++
                $script:registryRestoreStats.Conflict++
                continue
            }
        }
        if ($hasApplied -and $Force) { $script:registryRestoreStats.Forced++ }
        if (-not $hasApplied) { $script:registryRestoreStats.Legacy++ }
        if (-not [bool]$r.Exists) {
            Remove-RegDwordValue $r.Path $r.Name ("还原 $SectionLabel " + $r.Name + "（删除恢复系统默认）")
            # P1-4: 若父键原本不存在，且删除该值后父键变为空键（无值且无子键），安全清理该空键
            if ($r.PSObject.Properties['KeyExists'] -and $r.KeyExists -eq $false) {
                try {
                    if (Test-Path -LiteralPath $r.Path) {
                        $item = Get-Item -LiteralPath $r.Path -ErrorAction Stop
                        if ($item.ValueCount -eq 0 -and $item.SubKeyCount -eq 0) {
                            Remove-Item -LiteralPath $r.Path -Force -ErrorAction SilentlyContinue
                        }
                    }
                } catch { }
            }
        } else {
            try {
                $regData = if ($r.Kind -eq 'DWord') { [string][uint32]([int64]$r.Data -band 0xFFFFFFFFL) } else { [string]$r.Data }
                & reg.exe ADD (Convert-RegExePath $r.Path) /v $r.Name /t (Convert-RegKindForExe ([string]$r.Kind)) /d $regData /f *> $null
                if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
                Write-Host ("[OK] 已恢复 {0} {1} 原始值 {2}" -f $SectionLabel, $r.Name, $r.Data)
                $script:ok++
                $script:rebootRequired = $true
            } catch {
                Write-Host "[FAIL] 恢复 $SectionLabel $($r.Name) : $($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
            }
        }
        if ($script:fail -gt $before) {
            $allOk = $false
            $script:registryRestoreStats.Failed++
            break
        }
        $script:registryRestoreStats.Restored++
    }
    return $allOk
}

function Ensure-RegistryBackup {
    # 清单可注入（测试用 HKCU 临时键做往返验证）；默认用内置清单。一次快照同时覆盖子项 1 与 2。
    param([object[]]$CoreDefinitions = $script:registryCoreValues,
        [object[]]$SystemDefinitions = $script:registrySystemValues)
    try {
        if (Test-Path $script:registryBackupFile) {
            $backup = Get-Content $script:registryBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-RegistryBackupSchema $backup $CoreDefinitions $SystemDefinitions)) {
                $upgraded = Migrate-RegistryBackupIfNeeded $backup $CoreDefinitions $SystemDefinitions
                if ($null -ne $upgraded -and (Test-RegistryBackupSchema $upgraded $CoreDefinitions $SystemDefinitions)) {
                    $json = ConvertTo-Json -InputObject $upgraded -Depth 6
                    Write-TweakAtomicTextFile -Path $script:registryBackupFile -Content $json -Overwrite
                    $backup = $upgraded
                    Write-Host "[INFO] 已按新清单平滑迁移增量注册表快照：$script:registryBackupFile" -ForegroundColor Yellow
                } else {
                    throw 'registry-backup.json 结构不正确或与当前清单不匹配'
                }
            }
            Write-Host "[OK] 已存在有效的核心/系统优化快照：$script:registryBackupFile" -ForegroundColor Green
            return $true
        }
        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Core      = @($CoreDefinitions | ForEach-Object {
                $s = Get-MpoValueSnapshot $_
                $keyExisted = Test-Path -LiteralPath $_.Path
                Add-Member -InputObject $s -NotePropertyName 'KeyExists' -NotePropertyValue $keyExisted -PassThru
            })
            System    = @($SystemDefinitions | ForEach-Object {
                $s = Get-MpoValueSnapshot $_
                $keyExisted = Test-Path -LiteralPath $_.Path
                Add-Member -InputObject $s -NotePropertyName 'KeyExists' -NotePropertyValue $keyExisted -PassThru
            })
        }
        if (-not (Test-RegistryBackupSchema $backup $CoreDefinitions $SystemDefinitions)) { throw '生成的注册表备份未通过结构校验' }
        $json = ConvertTo-Json -InputObject $backup -Depth 6
        Write-TweakAtomicTextFile -Path $script:registryBackupFile -Content $json
        $check = Get-Content $script:registryBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-RegistryBackupSchema $check $CoreDefinitions $SystemDefinitions)) { throw '写入后的注册表备份校验失败' }
        Write-Host "[OK] 核心/系统优化原始状态已备份：$script:registryBackupFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAIL] 核心/系统优化原始状态备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red
        $script:fail++
        return $false
    }
}

function Restore-RegistryBackup {
    # Section：Core=子项1 的值，System=子项2 的值，All=两者
    # Force：忽略“优化后被其他程序修改”的冲突，强制写回首次快照
    param([string]$Section = 'All', [object[]]$CoreDefinitions = $script:registryCoreValues,
        [object[]]$SystemDefinitions = $script:registrySystemValues, [switch]$Force)
    $script:registryRestoreStats = [ordered]@{ Restored = 0; AlreadyOriginal = 0; Conflict = 0; Forced = 0; Legacy = 0; Failed = 0 }
    if (-not (Test-Path $script:registryBackupFile)) { Write-Host '[FAIL] 未找到 registry-backup.json，拒绝声称已恢复。' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:registryBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-RegistryBackupSchema $backup $CoreDefinitions $SystemDefinitions)) {
            $upgraded = Migrate-RegistryBackupIfNeeded $backup $CoreDefinitions $SystemDefinitions
            if ($null -ne $upgraded -and (Test-RegistryBackupSchema $upgraded $CoreDefinitions $SystemDefinitions)) {
                $backup = $upgraded
                $json = ConvertTo-Json -InputObject $upgraded -Depth 6
                Write-TweakAtomicTextFile -Path $script:registryBackupFile -Content $json -Overwrite
            } else {
                throw 'registry-backup.json 结构不正确或与当前清单不匹配'
            }
        }
        $sections = switch ($Section) {
            'Core'   { @(@{ Records = @($backup.Core); Label = '核心游戏优化' }) }
            'System' { @(@{ Records = @($backup.System); Label = '系统行为优化' }) }
            default  { @(
                    @{ Records = @($backup.Core); Label = '核心游戏优化' }
                    @{ Records = @($backup.System); Label = '系统行为优化' }
                ) }
        }
        $ledger = Read-RegistryAppliedLedger
        $appliedMap = Get-RegistryAppliedEntryMap $ledger
        $allOk = $true
        foreach ($sec in $sections) {
            $secOk = Restore-RegistryBackupRecords -Records $sec.Records -SectionLabel $sec.Label -AppliedMap $appliedMap -Force:$Force
            if (-not $secOk) {
                $allOk = $false
                break
            }
        }
        $stats = $script:registryRestoreStats
        Write-Host ("[INFO] 注册表还原统计：恢复 {0} 项，已为原值 {1} 项，冲突跳过 {2} 项，强制覆盖 {3} 项，旧版无账本 {4} 项。" -f `
            $stats.Restored, $stats.AlreadyOriginal, $stats.Conflict, $stats.Forced, $stats.Legacy) -ForegroundColor Cyan
        if ($stats.Conflict -gt 0) {
            Write-Host ("[WARN] 有 {0} 项在优化后被用户或其他程序修改，已保留当前值；确认要覆盖时请用 -Force 重新执行。" -f $stats.Conflict) -ForegroundColor Yellow
        }
        if ($allOk) { Write-Host '[OK] 核心/系统优化已按修改前快照恢复；Memory Compression 与 TRIM 不在本快照范围内。' -ForegroundColor Green }
        else { Write-Host '[WARN] 注册表恢复未完全成功，请复查输出中的 FAIL 项。' -ForegroundColor Yellow }
        return $allOk
    } catch {
        Write-Host "[FAIL] 注册表快照恢复失败：$($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
        return $false
    }
}
