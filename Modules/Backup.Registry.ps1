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
    @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Desc = 'AllowAutoGameMode' }
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
    @{ Path = 'HKCU:\Control Panel\Accessibility'; Name = 'MessageDuration'; Desc = 'MessageDuration' }
)

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
                    if ($r.Kind -eq 'DWord') { try { $null = [uint32]$r.Data } catch { return $false } }
                    if ($r.Kind -eq 'Binary' -and ([string]$r.Data -notmatch '^(?:[0-9A-Fa-f]{2})*$')) { return $false }
                } elseif ($null -ne $r.Kind -or $null -ne $r.Data) { return $false }
            }
        }
        return $true
    } catch { return $false }
}

function Ensure-RegistryBackup {
    # 清单可注入（测试用 HKCU 临时键做往返验证）；默认用内置清单。一次快照同时覆盖子项 1 与 2。
    param([object[]]$CoreDefinitions = $script:registryCoreValues,
        [object[]]$SystemDefinitions = $script:registrySystemValues)
    try {
        if (Test-Path $script:registryBackupFile) {
            $backup = Get-Content $script:registryBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-RegistryBackupSchema $backup $CoreDefinitions $SystemDefinitions)) { throw 'registry-backup.json 结构不正确或与当前清单不匹配' }
            Write-Host "[OK] 已存在有效的核心/系统优化快照：$script:registryBackupFile" -ForegroundColor Green
            return $true
        }
        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Core      = @($CoreDefinitions | ForEach-Object { Get-MpoValueSnapshot $_ })
            System    = @($SystemDefinitions | ForEach-Object { Get-MpoValueSnapshot $_ })
        }
        if (-not (Test-RegistryBackupSchema $backup $CoreDefinitions $SystemDefinitions)) { throw '生成的注册表备份未通过结构校验' }
        ConvertTo-Json -InputObject $backup -Depth 6 | Set-Content -Path $script:registryBackupFile -Encoding UTF8 -ErrorAction Stop
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
    param([string]$Section = 'All', [object[]]$CoreDefinitions = $script:registryCoreValues,
        [object[]]$SystemDefinitions = $script:registrySystemValues)
    if (-not (Test-Path $script:registryBackupFile)) { Write-Host '[FAIL] 未找到 registry-backup.json，拒绝声称已恢复。' -ForegroundColor Red; $script:fail++; return $false }
    try {
        $backup = Get-Content $script:registryBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-RegistryBackupSchema $backup $CoreDefinitions $SystemDefinitions)) { throw 'registry-backup.json 结构不正确或与当前清单不匹配' }
        $sections = switch ($Section) {
            'Core'   { @(@{ Records = @($backup.Core); Label = '核心游戏优化' }) }
            'System' { @(@{ Records = @($backup.System); Label = '系统行为优化' }) }
            default  { @(
                    @{ Records = @($backup.Core); Label = '核心游戏优化' }
                    @{ Records = @($backup.System); Label = '系统行为优化' }
                ) }
        }
        $allOk = $true
        foreach ($sec in $sections) {
            foreach ($r in $sec.Records) {
                $before = $script:fail
                if (-not [bool]$r.Exists) {
                    Remove-RegDwordValue $r.Path $r.Name ("还原 $($sec.Label) " + $r.Name + "（删除恢复系统默认）")
                } else {
                    try {
                        & reg.exe ADD (Convert-RegExePath $r.Path) /v $r.Name /t (Convert-RegKindForExe ([string]$r.Kind)) /d ([string]$r.Data) /f *> $null
                        if ($LASTEXITCODE -ne 0) { throw "reg.exe exit code $LASTEXITCODE" }
                        Write-Host ("[OK] 已恢复 {0} {1} 原始值 {2}" -f $sec.Label, $r.Name, $r.Data)
                        $script:ok++
                        $script:rebootRequired = $true
                    } catch {
                        Write-Host "[FAIL] 恢复 $($sec.Label) $($r.Name) : $($_.Exception.Message)" -ForegroundColor Red
                        $script:fail++
                    }
                }
                if ($script:fail -gt $before) { $allOk = $false }
            }
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
