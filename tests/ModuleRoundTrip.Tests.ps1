BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

# 服务清单单一事实源契约：执行分组（Service.ps1 引用）与恢复校验（Restore-ServiceBackup）
# 必须出自同一份定义（Modules/Backup.Service.ps1），防止两份手抄清单漂移
Describe "Service list single-source contract" {
    It "managed names equal the unique union of the three groups" {
        $union = @($script:serviceGroupA + $script:serviceGroupB + $script:serviceManualGroup)
        $union.Count | Should -Be 37
        @($union | Sort-Object -Unique).Count | Should -Be $union.Count
        @($script:serviceManagedNames | Sort-Object) | Should -Be (@($union | Sort-Object))
    }

    It "every group member is covered by restore validation" {
        foreach ($name in @($script:serviceGroupA + $script:serviceGroupB + $script:serviceManualGroup)) {
            $script:serviceManagedNames | Should -Contain $name
        }
    }
}

# MPO：备份/恢复完全走 HKCU 沙盒真实往返（快照走注册表提供程序，恢复走 reg.exe）
Describe "MPO backup/restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $key = 'HKCU:\Software\TweakByjieTest\Mpo'
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'OverlayTestMode' -PropertyType DWord -Value 5 -Force | Out-Null
        # OverlayMinFPS 留空，覆盖"原始不存在"分支

        $script:origMpoValues = $script:mpoManagedValues
        $script:mpoManagedValues = @(
            @{ Path = $key; Name = 'OverlayTestMode'; Desc = 'rt present' },
            @{ Path = $key; Name = 'OverlayMinFPS';   Desc = 'rt absent' }
        )
        $script:origMpoFile = $script:mpoBackupFile
        $script:mpoBackupFile = Join-Path $TestDrive 'mpo-backup.json'
    }

    AfterAll {
        Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:origMpoValues) { $script:mpoManagedValues = $script:origMpoValues }
        if ($script:origMpoFile) { $script:mpoBackupFile = $script:origMpoFile }
    }

    It "Ensure captures present dword and absence" {
        Ensure-MpoBackup | Should -Be $true
        $backup = Get-Content $script:mpoBackupFile -Raw | ConvertFrom-Json
        @($backup.Values).Count | Should -Be 2
        $present = $backup.Values | Where-Object { $_.Name -eq 'OverlayTestMode' }
        $present.Exists | Should -Be $true
        [uint32]$present.Data | Should -Be 5
        ($backup.Values | Where-Object { $_.Name -eq 'OverlayMinFPS' }).Exists | Should -Be $false
    }

    It "Restore brings back original value and removes new value via reg.exe" {
        Set-ItemProperty -Path $key -Name 'OverlayTestMode' -Value 9
        New-ItemProperty -Path $key -Name 'OverlayMinFPS' -PropertyType DWord -Value 7 -Force | Out-Null

        Restore-MpoBackup | Should -Be $true

        $item = Get-Item $key
        [int]$item.GetValue('OverlayTestMode') | Should -Be 5
        $item.GetValueNames() | Should -Not -Contain 'OverlayMinFPS'
    }
}

# NVMe：ViVeTool 用桩 .cmd（记录调用参数、固定退出码），SafeBoot/Legacy 走真实 reg.exe
# 的删除-不存在分支（不产生任何 HKLM 写入）；不触碰真实 Feature 状态。
Describe "NVMe backup/restore round-trip (stubbed ViVeTool)" {
    BeforeAll {
        $stub = Join-Path $TestDrive 'vivetool-stub.cmd'
        # %* 记录到日志供断言；/query 固定回答 Enabled (2)；括号按 cmd 规则转义
        [IO.File]::WriteAllText($stub, "@echo off`r`necho %* >> `"%TWEAK_VIVE_LOG%`"`r`nif /i `"%1`"==`"/query`" echo State: Enabled ^(2^)`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
        $script:viveLog = Join-Path $TestDrive 'vive-calls.log'
        $env:TWEAK_VIVE_LOG = $script:viveLog

        $script:origNvmeFile = $script:nvmeBackupFile
        $script:nvmeBackupFile = Join-Path $TestDrive 'nvme-backup.json'
        $script:legacyKey = 'HKCU:\Software\TweakByjieTest\NvmeLegacy'
        New-Item -Path $script:legacyKey -Force | Out-Null
        # 与 Modules/Nvme.ps1 生产调用一致：GUID 必须显式传入,
        # 否则快照路径(空 GUID)与 schema 默认 GUID 不一致,结构校验必然失败
        $script:sbGuid = '{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}'
    }

    AfterAll {
        Remove-Item Env:TWEAK_VIVE_LOG -ErrorAction SilentlyContinue
        Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:origNvmeFile) { $script:nvmeBackupFile = $script:origNvmeFile }
    }

    It "Ensure snapshots feature states via ViVeTool query and passes schema" {
        Ensure-NvmeBackup -Guid $script:sbGuid -ViVeTool $stub -LegacyPath $script:legacyKey | Should -Be $true
        $backup = Get-Content $script:nvmeBackupFile -Raw | ConvertFrom-Json
        @($backup.Features).Count | Should -Be 2
        ($backup.Features | Where-Object { $_.Id -eq '60786016' }).BeforeState | Should -Be 'Enabled'
        @($backup.SafeBoot).Count | Should -Be 2
        @($backup.SafeBoot | ForEach-Object { $_.Mode } | Sort-Object -Unique).Count | Should -Be 2
        @($backup.LegacyOverrides).Count | Should -Be 3
    }

    It "Restore replays BeforeState via ViVeTool (Enabled→/enable, Default→/reset)" {
        # 手工构造 Present=false 的确定性快照：恢复只会对不存在的键执行 DELETE（跳过），
        # 绝不产生真实 HKLM 写入，也不依赖本机是否应用过 NVMe 优化
        $backup = [pscustomobject]@{
            Version = 3
            Binding = (Get-BackupMachineId)
            CreatedAt = '2026-08-28T00:00:00.0000000Z'
            Features = @(
                [pscustomobject]@{ Id = '60786016'; BeforeState = 'Enabled' },
                [pscustomobject]@{ Id = '48433719'; BeforeState = 'Default' }
            )
            SafeBoot = @(
                [pscustomobject]@{ Mode = 'Minimal'; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Minimal\$($script:sbGuid)"; Present = $false; Kind = $null; Data = $null },
                [pscustomobject]@{ Mode = 'Network'; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Network\$($script:sbGuid)"; Present = $false; Kind = $null; Data = $null }
            )
            LegacyOverrides = @(
                [pscustomobject]@{ Name = '735209102'; Present = $false; Kind = $null; Data = $null },
                [pscustomobject]@{ Name = '1853569164'; Present = $false; Kind = $null; Data = $null },
                [pscustomobject]@{ Name = '156965516'; Present = $false; Kind = $null; Data = $null }
            )
        }
        ConvertTo-Json $backup -Depth 6 | Set-Content $script:nvmeBackupFile -Encoding UTF8

        Remove-Item $script:viveLog -ErrorAction SilentlyContinue
        Restore-NvmeSafeBootBackup -Guid $script:sbGuid -ViVeTool $stub -LegacyPath $script:legacyKey | Should -Be $true

        $calls = Get-Content $script:viveLog -Raw
        $calls | Should -Match '/enable /id:60786016'
        $calls | Should -Match '/reset /id:48433719'
    }

    It "Restore fails closed for Unknown BeforeState" {
        $backup = Get-Content $script:nvmeBackupFile -Raw | ConvertFrom-Json
        ($backup.Features | Where-Object { $_.Id -eq '60786016' }).BeforeState = 'Unknown'
        ConvertTo-Json $backup -Depth 6 | Set-Content $script:nvmeBackupFile -Encoding UTF8

        Restore-NvmeSafeBootBackup -Guid $script:sbGuid -ViVeTool $stub -LegacyPath $script:legacyKey | Should -Be $false
    }
}

# Service：Ensure 用 Pester mock 模拟 CIM 快照；Restore 的 Set-Service 可 mock，
# delayed-auto 分支依赖真实 sc.exe（不 mock 原生命令），对不存在的服务必然失败关闭。
# 真实服务的创建/恢复验证留待隔离 VM（见 docs/isolated-vm-verification.md）。
Describe "Service backup/restore round-trip (mocked CIM/Set-Service)" {
    BeforeAll {
        $script:origSvcFile = $script:serviceBackupFile
        $script:serviceBackupFile = Join-Path $TestDrive 'service-backup.json'
        $script:origSvcNames = $script:serviceManagedNames
    }

    AfterAll {
        if ($script:origSvcFile) { $script:serviceBackupFile = $script:origSvcFile }
        if ($script:origSvcNames) { $script:serviceManagedNames = $script:origSvcNames }
    }

    It "Ensure snapshots StartMode/State/DelayedAutostart and absence via CIM" {
        Mock Get-CimInstance -ParameterFilter { $Filter -match 'TweakRtAuto' } {
            [pscustomobject]@{ Name = 'TweakRtAuto'; StartMode = 'Manual'; State = 'Stopped'; DelayedAutostart = $false }
        }
        Mock Get-CimInstance -ParameterFilter { $Filter -match 'TweakRtDelayed' } {
            [pscustomobject]@{ Name = 'TweakRtDelayed'; StartMode = 'Auto'; State = 'Stopped'; DelayedAutostart = $true }
        }
        Mock Get-CimInstance -ParameterFilter { $Filter -match 'TweakRtAbsent' } { $null }

        Ensure-ServiceBackup -ServiceNames @('TweakRtAuto', 'TweakRtDelayed', 'TweakRtAbsent') | Should -Be $true

        $backup = Get-Content $script:serviceBackupFile -Raw | ConvertFrom-Json
        @($backup.Services).Count | Should -Be 3
        ($backup.Services | Where-Object { $_.Name -eq 'TweakRtDelayed' }).DelayedAutostart | Should -Be $true
        ($backup.Services | Where-Object { $_.Name -eq 'TweakRtAbsent' }).StartMode | Should -BeNullOrEmpty
    }

    It "Restore applies Set-Service for non-delayed and skips originally-absent services" {
        $script:serviceManagedNames = @('TweakRtAuto', 'TweakRtAbsent')
        $backup = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            Services = @(
                [pscustomobject]@{ Name = 'TweakRtAuto'; StartMode = 'Manual'; State = 'Stopped'; DelayedAutostart = $false },
                [pscustomobject]@{ Name = 'TweakRtAbsent'; StartMode = $null; State = $null; DelayedAutostart = $null }
            )
        }
        ConvertTo-Json $backup -Depth 5 | Set-Content $script:serviceBackupFile -Encoding UTF8

        Mock Set-Service { }
        Restore-ServiceBackup | Should -Be $true

        Should -Invoke Set-Service -Times 1 -ParameterFilter { $Name -eq 'TweakRtAuto' -and $StartupType -eq 'Manual' }
    }

    It "Restore uses sc.exe (not Set-Service) for delayed-auto and fails closed for nonexistent services" {
        $script:serviceManagedNames = @('TweakRtDelayed')
        $backup = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            Services = @(
                [pscustomobject]@{ Name = 'TweakRtDelayed'; StartMode = 'Auto'; State = 'Stopped'; DelayedAutostart = $true }
            )
        }
        ConvertTo-Json $backup -Depth 5 | Set-Content $script:serviceBackupFile -Encoding UTF8

        Mock Set-Service { }
        Restore-ServiceBackup | Should -Be $false

        # delayed-auto 必须走 sc.exe 路径，Set-Service 不参与
        Should -Invoke Set-Service -Times 0
    }
}
