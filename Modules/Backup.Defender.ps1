# Backup.Defender.ps1 - Part 5 Defender/SmartScreen 策略快照与恢复
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired
# 快照、写入与恢复共用 $script:defenderPolicyValues 同一份定义，避免清单漂移。
# Type 记录注册表实际类型：DWord / String / ExpandString / QWord / Binary

$script:defenderPolicyValues = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableAntiSpyware'; Type = 'DWord'; Value = 1; Desc = 'DisableAntiSpyware' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableAntiVirus'; Type = 'DWord'; Value = 1; Desc = 'DisableAntiVirus' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableRealtimeMonitoring'; Type = 'DWord'; Value = 1; Desc = 'DisableRealtimeMonitoring' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableRoutinelyTakingAction'; Type = 'DWord'; Value = 1; Desc = 'DisableRoutinelyTakingAction' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableSpecialRunningModes'; Type = 'DWord'; Value = 1; Desc = 'DisableSpecialRunningModes' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'ServiceKeepAlive'; Type = 'DWord'; Value = 0; Desc = 'ServiceKeepAlive' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'PUAProtection'; Type = 'DWord'; Value = 0; Desc = 'PUAProtection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'AllowFastServiceStartup'; Type = 'DWord'; Value = 0; Desc = 'AllowFastServiceStartup' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableLocalAdminMerge'; Type = 'DWord'; Value = 1; Desc = 'DisableLocalAdminMerge' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'RandomizeScheduleTaskTimes'; Type = 'DWord'; Value = 0; Desc = 'RandomizeScheduleTaskTimes' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableAntivirus'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableAntivirus' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableBehaviorMonitoring'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableBehaviorMonitoring' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableOnAccessProtection'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableOnAccessProtection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableScanOnRealtimeEnable'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableScanOnRealtimeEnable' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRealtimeMonitoring'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableRealtimeMonitoring' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableIOAVProtection'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableIOAVProtection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableScriptScanning'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableScriptScanning' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'LocalSettingOverrideDisableOnAccessProtection'; Type = 'DWord'; Value = 0; Desc = 'RTP LSO DisableOnAccessProtection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'LocalSettingOverrideRealtimeScanDirection'; Type = 'DWord'; Value = 0; Desc = 'RTP LSO RealtimeScanDirection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'LocalSettingOverrideDisableIOAVProtection'; Type = 'DWord'; Value = 0; Desc = 'RTP LSO DisableIOAVProtection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'LocalSettingOverrideDisableBehaviorMonitoring'; Type = 'DWord'; Value = 0; Desc = 'RTP LSO DisableBehaviorMonitoring' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'LocalSettingOverrideDisableIntrusionPreventionSystem'; Type = 'DWord'; Value = 0; Desc = 'RTP LSO DisableIntrusionPreventionSystem' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'LocalSettingOverrideDisableRealtimeMonitoring'; Type = 'DWord'; Value = 0; Desc = 'RTP LSO DisableRealtimeMonitoring' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'RealtimeScanDirection'; Type = 'DWord'; Value = 2; Desc = 'RTP RealtimeScanDirection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableInformationProtectionControl'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableInformationProtectionControl' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableIntrusionPreventionSystem'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableIntrusionPreventionSystem' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRawWriteNotification'; Type = 'DWord'; Value = 1; Desc = 'RTP DisableRawWriteNotification' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'DisableBlockAtFirstSeen'; Type = 'DWord'; Value = 1; Desc = 'Spynet DisableBlockAtFirstSeen' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'LocalSettingOverrideSpynetReporting'; Type = 'DWord'; Value = 0; Desc = 'Spynet LocalSettingOverrideSpynetReporting' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'SpynetReporting'; Type = 'DWord'; Value = 0; Desc = 'Spynet SpynetReporting' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'SubmitSamplesConsent'; Type = 'DWord'; Value = 2; Desc = 'Spynet SubmitSamplesConsent' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'SignatureDisableNotification'; Type = 'DWord'; Value = 1; Desc = 'SignatureUpdates SignatureDisableNotification' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'RealtimeSignatureDelivery'; Type = 'DWord'; Value = 0; Desc = 'SignatureUpdates RealtimeSignatureDelivery' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'ForceUpdateFromMU'; Type = 'DWord'; Value = 0; Desc = 'SignatureUpdates ForceUpdateFromMU' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'DisableScheduledSignatureUpdateOnBattery'; Type = 'DWord'; Value = 1; Desc = 'SignatureUpdates DisableScheduledSignatureUpdateOnBattery' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'UpdateOnStartUp'; Type = 'DWord'; Value = 0; Desc = 'SignatureUpdates UpdateOnStartUp' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'SignatureUpdateCatchupInterval'; Type = 'DWord'; Value = 2; Desc = 'SignatureUpdates SignatureUpdateCatchupInterval' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'DisableUpdateOnStartupWithoutEngine'; Type = 'DWord'; Value = 1; Desc = 'SignatureUpdates DisableUpdateOnStartupWithoutEngine' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'ScheduleTime'; Type = 'DWord'; Value = 1440; Desc = 'SignatureUpdates ScheduleTime' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates'; Name = 'DisableScanOnUpdate'; Type = 'DWord'; Value = 1; Desc = 'SignatureUpdates DisableScanOnUpdate' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'LowCpuPriority'; Type = 'DWord'; Value = 1; Desc = 'Scan LowCpuPriority' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableRestorePoint'; Type = 'DWord'; Value = 1; Desc = 'Scan DisableRestorePoint' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableArchiveScanning'; Type = 'DWord'; Value = 0; Desc = 'Scan DisableArchiveScanning' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableScanningNetworkFiles'; Type = 'DWord'; Value = 0; Desc = 'Scan DisableScanningNetworkFiles' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableCatchupFullScan'; Type = 'DWord'; Value = 0; Desc = 'Scan DisableCatchupFullScan' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableCatchupQuickScan'; Type = 'DWord'; Value = 1; Desc = 'Scan DisableCatchupQuickScan' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableEmailScanning'; Type = 'DWord'; Value = 0; Desc = 'Scan DisableEmailScanning' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableHeuristics'; Type = 'DWord'; Value = 1; Desc = 'Scan DisableHeuristics' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'; Name = 'DisableReparsePointScanning'; Type = 'DWord'; Value = 1; Desc = 'Scan DisableReparsePointScanning' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration'; Name = 'SuppressRebootNotification'; Type = 'DWord'; Value = 1; Desc = 'UX SuppressRebootNotification' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting'; Name = 'DisableEnhancedNotifications'; Type = 'DWord'; Value = 1; Desc = 'Reporting DisableEnhancedNotifications' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting'; Name = 'DisableGenericRePorts'; Type = 'DWord'; Value = 1; Desc = 'Reporting DisableGenericRePorts' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting'; Name = 'WppTracingLevel'; Type = 'DWord'; Value = 0; Desc = 'Reporting WppTracingLevel' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting'; Name = 'WppTracingComponents'; Type = 'DWord'; Value = 0; Desc = 'Reporting WppTracingComponents' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine'; Name = 'MpEnablePus'; Type = 'DWord'; Value = 0; Desc = 'MpEngine MpEnablePus' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine'; Name = 'MpCloudBlockLevel'; Type = 'DWord'; Value = 0; Desc = 'MpEngine MpCloudBlockLevel' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine'; Name = 'MpBafsExtendedTimeout'; Type = 'DWord'; Value = 0; Desc = 'MpEngine MpBafsExtendedTimeout' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine'; Name = 'EnableFileHashComputation'; Type = 'DWord'; Value = 0; Desc = 'MpEngine EnableFileHashComputation' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS'; Name = 'ThrottleDetectionEventsRate'; Type = 'DWord'; Value = 0; Desc = 'NIS ThrottleDetectionEventsRate' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS'; Name = 'DisableSignatureRetirement'; Type = 'DWord'; Value = 1; Desc = 'NIS DisableSignatureRetirement' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS'; Name = 'DisableProtocolRecognition'; Type = 'DWord'; Value = 1; Desc = 'NIS DisableProtocolRecognition' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager'; Name = 'DisableScanningNetworkFiles'; Type = 'DWord'; Value = 1; Desc = 'PolicyManager DisableScanningNetworkFiles' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'; Name = 'DisableAutoExclusions'; Type = 'DWord'; Value = 1; Desc = 'Exclusions DisableAutoExclusions' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access'; Name = 'EnableControlledFolderAccess'; Type = 'DWord'; Value = 0; Desc = 'ExploitGuard ControlledFolderAccess' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection'; Name = 'EnableNetworkProtection'; Type = 'DWord'; Value = 0; Desc = 'ExploitGuard NetworkProtection' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware'; Name = 'ServiceKeepAlive'; Type = 'DWord'; Value = 0; Desc = 'Legacy ServiceKeepAlive' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware'; Name = 'AllowFastServiceStartup'; Type = 'DWord'; Value = 0; Desc = 'Legacy AllowFastServiceStartup' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware'; Name = 'DisableRoutinelyTakingAction'; Type = 'DWord'; Value = 1; Desc = 'Legacy DisableRoutinelyTakingAction' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware'; Name = 'DisableAntiSpyware'; Type = 'DWord'; Value = 1; Desc = 'Legacy DisableAntiSpyware' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware'; Name = 'DisableAntiVirus'; Type = 'DWord'; Value = 1; Desc = 'Legacy DisableAntiVirus' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet'; Name = 'SpyNetReporting'; Type = 'DWord'; Value = 0; Desc = 'Legacy SpyNet SpyNetReporting' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet'; Name = 'LocalSettingOverrideSpyNetReporting'; Type = 'DWord'; Value = 0; Desc = 'Legacy SpyNet LocalSettingOverrideSpyNetReporting' },
    @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender'; Name = 'DisableRoutinelyTakingAction'; Type = 'DWord'; Value = 1; Desc = 'WOW6432Node DisableRoutinelyTakingAction' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'; Name = 'VerifiedAndReputablePolicyState'; Type = 'DWord'; Value = 0; Desc = 'SmartAppControl VerifiedAndReputablePolicyState' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'Enabled'; Type = 'DWord'; Value = 0; Desc = 'SmartScreen Enabled' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'EnableSmartScreenInShell'; Type = 'DWord'; Value = 0; Desc = 'SmartScreen EnableSmartScreenInShell' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'ConfigureAppInstallControlEnabled'; Type = 'DWord'; Value = 1; Desc = 'SmartScreen ConfigureAppInstallControlEnabled' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen'; Name = 'ConfigureAppInstallControl'; Type = 'String'; Value = 'Anywhere'; Desc = 'SmartScreen ConfigureAppInstallControl' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableSmartScreen'; Type = 'DWord'; Value = 0; Desc = 'System EnableSmartScreen' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'SmartScreenEnabled'; Type = 'String'; Value = 'Off'; Desc = 'Explorer SmartScreenEnabled' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter'; Name = 'EnabledV9'; Type = 'DWord'; Value = 0; Desc = 'Edge SmartScreen EnabledV9' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter'; Name = 'PreventOverride'; Type = 'DWord'; Value = 0; Desc = 'Edge SmartScreen PreventOverride' },
    @{ Path = 'HKCU:\Software\Microsoft\Edge'; Name = 'SmartScreenEnabled'; Type = 'DWord'; Value = 0; Desc = 'HKCU Edge SmartScreenEnabled' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost'; Name = 'EnableWebContentEvaluation'; Type = 'DWord'; Value = 0; Desc = 'AppHost EnableWebContentEvaluation' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost'; Name = 'PreventOverride'; Type = 'DWord'; Value = 0; Desc = 'AppHost PreventOverride' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen'; Name = 'value'; Type = 'DWord'; Value = 0; Desc = 'PolicyManager Browser AllowSmartScreen' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell'; Name = 'value'; Type = 'DWord'; Value = 0; Desc = 'PolicyManager SmartScreen InShell' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl'; Name = 'value'; Type = 'DWord'; Value = 0; Desc = 'PolicyManager SmartScreen AppInstallControl' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell'; Name = 'value'; Type = 'DWord'; Value = 0; Desc = 'PolicyManager SmartScreen PreventOverrideForFiles' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'; Name = 'DisableEnhancedNotifications'; Type = 'DWord'; Value = 1; Desc = 'WDSC DisableEnhancedNotifications' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'; Name = 'DisableNotifications'; Type = 'DWord'; Value = 1; Desc = 'WDSC DisableNotifications' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Security Center'; Name = 'FirstRunDisabled'; Type = 'DWord'; Value = 1; Desc = 'SecurityCenter FirstRunDisabled' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Security Center'; Name = 'AntiVirusOverride'; Type = 'DWord'; Value = 1; Desc = 'SecurityCenter AntiVirusOverride' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Security Center'; Name = 'FirewallOverride'; Type = 'DWord'; Value = 1; Desc = 'SecurityCenter FirewallOverride' },
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance'; Name = 'Enabled'; Type = 'DWord'; Value = 0; Desc = 'SecurityToast Enabled' }
)

# 删除类优化会移除的自启动项（快照后可在恢复时重建）
$script:defenderStartupValues = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'SecurityHealth' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name = 'SecurityHealth' },
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'Windows Defender' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'WindowsDefender' }
)

function Get-DefenderValueSnapshot {
    param([hashtable]$Definition)
    $item = Get-Item $Definition.Path -ErrorAction SilentlyContinue
    $present = $item -and ($item.GetValueNames() -contains $Definition.Name)
    if (-not $present) {
        return [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Type = $Definition.Type; Present = $false; Value = $null; Desc = $Definition.Desc }
    }
    $kind = $item.GetValueKind($Definition.Name).ToString()
    $value = $null
    switch ($kind) {
        'DWord'  { $value = [uint32]$item.GetValue($Definition.Name) }
        'QWord'  { $value = [uint64]$item.GetValue($Definition.Name) }
        'Binary' { $value = [BitConverter]::ToString([byte[]]$item.GetValue($Definition.Name)).Replace('-', '') }
        default  { $value = [string]$item.GetValue($Definition.Name) }
    }
    [pscustomobject]@{ Path = $Definition.Path; Name = $Definition.Name; Type = $kind; Present = $true; Value = $value; Desc = $Definition.Desc }
}

function Test-DefenderBackupSchema {
    # Definitions/StartupDefinitions 可注入自定义清单（测试用 HKCU 临时键做往返验证）；默认用内置清单
    param([object]$Backup, [object[]]$PolicyDefinitions = $script:defenderPolicyValues, [object[]]$StartupDefinitions = $script:defenderStartupValues)
    try {
        if ($null -eq $Backup -or [int]$Backup.Version -ne 1) { return $false }
        $records = @($Backup.Values)
        $startup = @($Backup.StartupValues)
        if ($records.Count -eq 0 -or $startup.Count -eq 0) { return $false }
        foreach ($pair in @(
                @{ Actual = $records; Expected = $PolicyDefinitions },
                @{ Actual = $startup; Expected = $StartupDefinitions }
            )) {
            $expectedKeys = @($pair.Expected | ForEach-Object { "$($_.Path)|$($_.Name)" })
            $actualKeys = @($pair.Actual | ForEach-Object { "$($_.Path)|$($_.Name)" })
            if ($actualKeys.Count -ne $expectedKeys.Count) { return $false }
            if (@($actualKeys | Sort-Object -Unique).Count -ne $expectedKeys.Count) { return $false }
            if (@($actualKeys | Where-Object { $expectedKeys -notcontains $_ }).Count -gt 0) { return $false }
        }
        foreach ($r in $records) {
            if ($null -eq $r.Present -or $r.Present -isnot [bool]) { return $false }
            if ([bool]$r.Present) {
                if ($null -eq $r.Value -or $null -eq $r.Type) { return $false }
                if ([string]$r.Type -eq 'DWord') {
                    # 注意：PS 5.1 中 0xFFFFFFFF 字面量是 Int32 的 -1，必须用 [uint32]::MaxValue 比较
                    try { if ([uint64]$r.Value -gt [uint32]::MaxValue) { return $false } } catch { return $false }
                }
            } elseif ($null -ne $r.Value) { return $false }
        }
        foreach ($r in $startup) {
            if ($null -eq $r.Present -or $r.Present -isnot [bool]) { return $false }
        }
        return $true
    } catch { return $false }
}

function Ensure-DefenderPolicyBackup {
    # Definitions/StartupDefinitions 可注入自定义清单（测试用 HKCU 临时键做往返验证）；默认用内置清单
    param([object[]]$Definitions = $script:defenderPolicyValues, [object[]]$StartupDefinitions = $script:defenderStartupValues)
    try {
        if (Test-Path $script:defenderPolicyBackupFile) {
            $backup = Get-Content $script:defenderPolicyBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-DefenderBackupSchema $backup $Definitions $StartupDefinitions)) { throw 'defender-policy-backup.json 结构不正确或与当前清单不匹配' }
            Write-Host "[OK] 已存在有效的 Defender 策略快照：$script:defenderPolicyBackupFile" -ForegroundColor Green
            return $true
        }
        $backup = [pscustomobject]@{
            Version       = 1
            CreatedAt     = (Get-Date).ToString('o')
            Values        = @($Definitions | ForEach-Object { Get-DefenderValueSnapshot $_ })
            StartupValues = @($StartupDefinitions | ForEach-Object { Get-DefenderValueSnapshot $_ })
        }
        if (-not (Test-DefenderBackupSchema $backup $Definitions $StartupDefinitions)) { throw '生成的 Defender 策略备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 5 | Set-Content -Path $script:defenderPolicyBackupFile -Encoding UTF8 -ErrorAction Stop
        $check = Get-Content $script:defenderPolicyBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-DefenderBackupSchema $check $Definitions $StartupDefinitions)) { throw '写入后的 Defender 策略备份校验失败' }
        Write-Host "[OK] Defender 策略原始状态已备份：$script:defenderPolicyBackupFile" -ForegroundColor Green
        return $true
    } catch { Write-Host "[FAIL] Defender 策略备份失败：$($_.Exception.Message)；已阻止修改" -ForegroundColor Red; $script:fail++; return $false }
}

function Invoke-DefenderPolicyWrites {
    foreach ($d in $script:defenderPolicyValues) {
        if ([string]$d.Type -eq 'String') { Set-RegString $d.Path $d.Name ([string]$d.Value) $d.Desc }
        else { Set-RegDword $d.Path $d.Name $d.Value $d.Desc }
    }
}

function Restore-DefenderRegistryValue {
    param([string]$Path, [string]$Name, [string]$Type, [object]$Value, [string]$Label)
    try {
        switch ($Type) {
            'DWord'        { Set-RegDword $Path $Name ([uint32]$Value) $Label; return }
            'String'       { Set-RegString $Path $Name ([string]$Value) $Label; return }
            'ExpandString' { & reg.exe ADD (Convert-RegExePath $Path) /v $Name /t REG_EXPAND_SZ /d ([string]$Value) /f *> $null }
            'QWord'        { & reg.exe ADD (Convert-RegExePath $Path) /v $Name /t REG_QWORD /d ([string]([uint64]$Value)) /f *> $null }
            'Binary'       { & reg.exe ADD (Convert-RegExePath $Path) /v $Name /t REG_BINARY /d ([string]$Value) /f *> $null }
            default        { throw "不支持的注册表类型 $Type" }
        }
        if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
        Write-Host ("[OK] {0} = {1} ({2})" -f $Label, $Value, $Type)
        $script:ok++
        $script:rebootRequired = $true
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

function Restore-DefenderStartupValue {
    param([object]$Record)
    $label = "恢复启动项 {0} -> {1}" -f $Record.Path, $Record.Name
    try {
        if (-not [bool]$Record.Present) {
            $existing = Get-ItemProperty -Path $Record.Path -Name $Record.Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                Write-Host "[SKIP] $label：原始状态不存在，当前也不存在，无需处理" -ForegroundColor Yellow
                $script:skip++
                return
            }
            Remove-ItemProperty -Path $Record.Path -Name $Record.Name -Force -ErrorAction Stop
            Write-Host "[OK] $label（删除快照后新增的值，恢复原始未设置状态）"
            $script:ok++
            return
        }
        if (-not (Test-Path $Record.Path)) { New-Item -Path $Record.Path -Force -ErrorAction Stop | Out-Null }
        $propType = switch ([string]$Record.Type) {
            'DWord'        { 'DWord' }
            'String'       { 'String' }
            'ExpandString' { 'ExpandString' }
            'QWord'        { 'QWord' }
            'Binary'       { 'Binary' }
            default        { throw "不支持的注册表类型 $([string]$Record.Type)" }
        }
        $value = $Record.Value
        if ($propType -eq 'Binary') {
            $hex = [string]$Record.Value
            $bytes = for ($i = 0; $i -lt $hex.Length; $i += 2) { [Convert]::ToByte($hex.Substring($i, 2), 16) }
            $value = [byte[]]$bytes
        }
        New-ItemProperty -Path $Record.Path -Name $Record.Name -PropertyType $propType -Value $value -Force -ErrorAction Stop | Out-Null
        Write-Host "[OK] $label"
        $script:ok++
        $script:rebootRequired = $true
    } catch {
        Write-Host ("[FAIL] {0} : {1}" -f $label, $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}

function Restore-DefenderPolicyBackup {
    param([object[]]$Definitions = $script:defenderPolicyValues, [object[]]$StartupDefinitions = $script:defenderStartupValues)
    if (-not (Test-Path $script:defenderPolicyBackupFile)) { Write-Host '[FAIL] 未找到 defender-policy-backup.json，拒绝声称已恢复。' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:defenderPolicyBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-DefenderBackupSchema $backup $Definitions $StartupDefinitions)) { throw 'defender-policy-backup.json 结构不正确或与当前清单不匹配' }
        $allOk = $true
        foreach ($r in @($backup.Values)) {
            $before = $script:fail
            if ([bool]$r.Present) { Restore-DefenderRegistryValue $r.Path $r.Name ([string]$r.Type) $r.Value ("恢复 " + $r.Desc) }
            else { Remove-RegDwordValue $r.Path $r.Name ("删除 " + $r.Desc + "（恢复原始未设置状态）") }
            if ($script:fail -gt $before) { $allOk = $false }
        }
        foreach ($r in @($backup.StartupValues)) {
            $before = $script:fail
            Restore-DefenderStartupValue $r
            if ($script:fail -gt $before) { $allOk = $false }
        }
        if ($allOk) { Write-Host '[OK] Defender 策略已按修改前快照恢复；服务/计划任务/SecHealthUI 不在本快照范围内。' -ForegroundColor Green }
        else { Write-Host '[WARN] Defender 策略恢复未完全成功，请复查输出中的 FAIL 项。' -ForegroundColor Yellow }
        return $allOk
    } catch { Write-Host "[FAIL] Defender 策略恢复失败：$($_.Exception.Message)" -ForegroundColor Red; $script:fail++; return $false }
}
