BeforeAll {
    $env:TWEAK_SKIP_ADMIN_CHECK = '1'
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null

    function New-SecWeakTestKey {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
    }

    function Set-SecWeakTestValue {
        param([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord')
        New-SecWeakTestKey $Path
        Set-TweakRegistryTypedValue -Path $Path -Name $Name -Kind $Kind -Value $Value
    }
}

Describe "Security weakening item table" {
    BeforeAll {
        $script:Items = @(Get-SecurityWeakeningItems)
    }

    It "defines exactly 13 items with sequential Bxx ids" {
        $script:Items.Count | Should -Be 13
        $expected = @(1..13 | ForEach-Object { 'B{0:D2}' -f $_ })
        @($script:Items | ForEach-Object Id) | Should -Be $expected
    }

    It "gives every item a name, a warning and a supported kind" {
        foreach ($item in $script:Items) {
            [string]::IsNullOrWhiteSpace($item.Name) | Should -BeFalse
            [string]::IsNullOrWhiteSpace($item.Warning) | Should -BeFalse
            $item.Kind | Should -BeIn @('Registry', 'Reference')
        }
    }

    It "declares registry operations with valid path, name, kind and value" {
        foreach ($item in @($script:Items | Where-Object { $_.Kind -eq 'Registry' })) {
            @($item.Operations).Count | Should -BeGreaterThan 0 -Because "$($item.Id) 是 Registry 项，必须有写入目标"
            foreach ($op in @($item.Operations)) {
                $op.Path | Should -Match '^HK(LM|CU):\\'
                [string]::IsNullOrWhiteSpace($op.Name) | Should -BeFalse
                $op.Kind | Should -BeIn @('DWord', 'String')
                if ($op.Kind -eq 'DWord') { $op.Value | Should -BeOfType [int] }
                else { $op.Value | Should -BeOfType [string] }
            }
        }
    }

    It "never duplicates a path/value pair across the static table" {
        $keys = @($script:Items | ForEach-Object { $_.Operations } |
            Where-Object { $_ } |
            ForEach-Object { ('{0}|{1}' -f $_.Path, $_.Name).ToLowerInvariant() })
        @($keys | Sort-Object -Unique).Count | Should -Be $keys.Count
    }

    It "leaves the HVCI value to Part 10 and points B07 at menu 1-3" {
        $paths = @($script:Items | ForEach-Object { $_.Operations } | Where-Object { $_ } | ForEach-Object Path)
        @($paths | Where-Object { $_ -match 'HypervisorEnforcedCodeIntegrity' }).Count | Should -Be 0

        $b07 = $script:Items | Where-Object { $_.Id -eq 'B07' }
        $b07.Kind | Should -Be 'Reference'
        @($b07.Operations).Count | Should -Be 0
        $b07.Reference | Should -Match '菜单 1'
    }

    It "keeps a documented DEFAULT backup file name" {
        $script:securityWeakeningBackupFile | Should -Match 'security-weakening-backup\.json$'
    }
}

Describe "Security weakening plan builder" {
    It "orders B05 so EnableLUA is written last" {
        $plan = Get-SecurityWeakeningPlan -ItemIds @('B05')
        @($plan.Operations).Count | Should -Be 3
        @($plan.Operations)[-1].Name | Should -Be 'EnableLUA'
    }

    It "rejects unknown item ids instead of silently skipping them" {
        { Get-SecurityWeakeningPlan -ItemIds @('B99') } | Should -Throw
        { Get-SecurityWeakeningPlan -ItemIds @() } | Should -Throw
    }

    It "expands DMA remapping targets from the supplied services root" {
        $base = 'HKCU:\Software\TweakByjieTest\SecWeakPlan'
        if (Test-Path $base) { Remove-Item -Path $base -Recurse -Force -ErrorAction SilentlyContinue }
        $svcRoot = Join-Path $base 'Services'
        Set-SecWeakTestValue (Join-Path $svcRoot 'stornvme\Parameters') 'DmaRemappingCompatible' 1 'DWord'
        Set-SecWeakTestValue (Join-Path $svcRoot 'usbhub3\Parameters') 'DmaRemappingCompatible' 1 'DWord'
        Set-SecWeakTestValue (Join-Path $svcRoot 'legacy\Parameters') 'DmaRemappingCompatible' '1' 'String'

        try {
            $plan = Get-SecurityWeakeningPlan -ItemIds @('B12') -Roots @{ Services = $svcRoot }
            $ops = @($plan.Operations | Where-Object { $_.Name -eq 'DmaRemappingCompatible' })
            $ops.Count | Should -Be 2
            $ops | ForEach-Object { $_.Value | Should -Be 0 }
            @($plan.Skips | Where-Object { $_.Name -eq 'DmaRemappingCompatible' }).Count | Should -Be 1
        } finally {
            if (Test-Path $base) { Remove-Item -Path $base -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It "skips Defender log-service Start values when the service key is missing" {
        Mock Test-SecurityWeakeningKeyPresent { return $false }
        $plan = Get-SecurityWeakeningPlan -ItemIds @('B04')
        @($plan.Operations | Where-Object { $_.Name -eq 'Start' }).Count | Should -Be 0
        @($plan.Skips | Where-Object { $_.Name -eq 'Start' }).Count | Should -Be 2
        @($plan.Operations | Where-Object { $_.Name -eq 'ConfigureAppInstallControl' }).Count | Should -Be 1
    }

    It "flags B13 as touching process mitigation settings" {
        (Get-SecurityWeakeningPlan -ItemIds @('B13')).IncludeProcessMitigations | Should -BeTrue
        (Get-SecurityWeakeningPlan -ItemIds @('B01')).IncludeProcessMitigations | Should -BeFalse
    }
}

Describe "Security weakening backup schema" {
    It "rejects null, wrong version, foreign binding and malformed entries" {
        Test-SecurityWeakeningBackupSchema $null | Should -BeFalse
        Test-SecurityWeakeningBackupSchema ([pscustomobject]@{ Version = 2; Binding = (Get-BackupMachineId); Entries = @() }) | Should -BeFalse
        Test-SecurityWeakeningBackupSchema ([pscustomobject]@{ Version = 1; Binding = 'foreign'; Entries = @() }) | Should -BeFalse
        Test-SecurityWeakeningBackupSchema ([pscustomobject]@{ Version = 1; Binding = (Get-BackupMachineId); Entries = $null }) | Should -BeFalse
        Test-SecurityWeakeningBackupSchema ([pscustomobject]@{
            Version = 1; Binding = (Get-BackupMachineId)
            Entries = @([pscustomobject]@{ Path = ''; Name = 'EnableLUA'; Existed = $false; Kind = ''; Value = $null })
        }) | Should -BeFalse
        Test-SecurityWeakeningBackupSchema ([pscustomobject]@{
            Version = 1; Binding = (Get-BackupMachineId)
            Entries = @([pscustomobject]@{ Path = 'HKLM:\X'; Name = 'EnableLUA'; Existed = $true; Kind = 'Nope'; Value = 1 })
        }) | Should -BeFalse
        Test-SecurityWeakeningBackupSchema ([pscustomobject]@{
            Version = 1; Binding = (Get-BackupMachineId)
            Entries = @([pscustomobject]@{ Path = 'HKLM:\X'; Name = 'ExecutionPolicy'; Existed = $true; Kind = 'String'; Value = $null })
        }) | Should -BeFalse
    }

    It "accepts existing and missing values plus an optional mitigation XML" {
        $valid = [pscustomobject]@{
            Version               = 1
            Binding               = (Get-BackupMachineId)
            CreatedAt             = (Get-Date).ToString('o')
            ProcessMitigationXml  = '<root />'
            Entries               = @(
                [pscustomobject]@{ Path = 'HKLM:\X'; Name = 'EnableLUA'; Existed = $true; Kind = 'DWord'; Value = 1 },
                [pscustomobject]@{ Path = 'HKLM:\Y'; Name = 'ExecutionPolicy'; Existed = $true; Kind = 'String'; Value = 'RemoteSigned' },
                [pscustomobject]@{ Path = 'HKLM:\Z'; Name = 'DisableTelemetry'; Existed = $false; Kind = ''; Value = $null }
            )
        }
        Test-SecurityWeakeningBackupSchema $valid | Should -BeTrue
    }
}

Describe "Security weakening backup and restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $script:RtBase = 'HKCU:\Software\TweakByjieTest\SecWeakRoundTrip'
        if (Test-Path $script:RtBase) { Remove-Item -Path $script:RtBase -Recurse -Force -ErrorAction SilentlyContinue }
        $script:RtDwordPath = Join-Path $script:RtBase 'Policy'
        $script:RtStringPath = Join-Path $script:RtBase 'PowerShell'
        $script:RtMissingPath = Join-Path $script:RtBase 'Missing'

        Set-SecWeakTestValue $script:RtDwordPath 'EnableLUA' 1 'DWord'
        Set-SecWeakTestValue $script:RtStringPath 'ExecutionPolicy' 'RemoteSigned' 'String'

        $script:RtOps = @(
            [pscustomobject]@{ Scope = 'B05'; Path = $script:RtDwordPath; Name = 'EnableLUA'; Kind = 'DWord'; Value = 0 },
            [pscustomobject]@{ Scope = 'B10'; Path = $script:RtStringPath; Name = 'ExecutionPolicy'; Kind = 'String'; Value = 'Unrestricted' },
            [pscustomobject]@{ Scope = 'B09'; Path = $script:RtMissingPath; Name = 'DisableTelemetry'; Kind = 'DWord'; Value = 1 }
        )
    }

    BeforeEach {
        $script:RtBackup = Join-Path $env:TEMP ("security-weakening-" + [guid]::NewGuid().ToString('N') + ".json")
        Set-TweakRegistryTypedValue -Path $script:RtDwordPath -Name 'EnableLUA' -Kind 'DWord' -Value 1
        Set-TweakRegistryTypedValue -Path $script:RtStringPath -Name 'ExecutionPolicy' -Kind 'String' -Value 'RemoteSigned'
        Remove-TweakRegistryValue -Path $script:RtMissingPath -Name 'DisableTelemetry' | Out-Null
    }

    AfterAll {
        if (Test-Path $script:RtBase) { Remove-Item -Path $script:RtBase -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "records Existed / Kind / Value before any write" {
        $plan = [pscustomobject]@{ Operations = $script:RtOps; Skips = @(); IncludeProcessMitigations = $false }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue

        $backup = Get-Content -LiteralPath $script:RtBackup -Raw | ConvertFrom-Json
        $backup.Version | Should -Be 1
        $backup.Binding | Should -Be (Get-BackupMachineId)
        @($backup.Entries).Count | Should -Be 3
        (@($backup.Entries | Where-Object { $_.Name -eq 'EnableLUA' })[0]).Value | Should -Be 1
        (@($backup.Entries | Where-Object { $_.Name -eq 'ExecutionPolicy' })[0]).Kind | Should -Be 'String'
        (@($backup.Entries | Where-Object { $_.Name -eq 'DisableTelemetry' })[0]).Existed | Should -BeFalse
    }

    It "restores typed values and deletes values that did not exist" {
        $plan = [pscustomobject]@{ Operations = $script:RtOps; Skips = @(); IncludeProcessMitigations = $false }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue

        foreach ($op in $script:RtOps) { Set-TweakRegistryTypedValue -Path $op.Path -Name $op.Name -Kind $op.Kind -Value $op.Value }

        Restore-SecurityWeakeningBackup -BackupFile $script:RtBackup | Should -BeTrue

        (Get-TweakRegistryValue -Path $script:RtDwordPath -Name 'EnableLUA').Value | Should -Be 1
        (Get-TweakRegistryValue -Path $script:RtStringPath -Name 'ExecutionPolicy').Value | Should -Be 'RemoteSigned'
        (Get-TweakRegistryValue -Path $script:RtMissingPath -Name 'DisableTelemetry').Exists | Should -BeFalse
    }

    It "keeps the first snapshot and appends newly discovered targets" {
        $plan = [pscustomobject]@{ Operations = $script:RtOps; Skips = @(); IncludeProcessMitigations = $false }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue

        Set-TweakRegistryTypedValue -Path $script:RtDwordPath -Name 'EnableLUA' -Kind 'DWord' -Value 0
        Set-SecWeakTestValue $script:RtBase 'LateValue' 7 'DWord'
        $late = [pscustomobject]@{ Scope = 'B12'; Path = $script:RtBase; Name = 'LateValue'; Kind = 'DWord'; Value = 0 }
        $plan2 = [pscustomobject]@{ Operations = @($script:RtOps + $late); Skips = @(); IncludeProcessMitigations = $false }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan2 | Should -BeTrue

        $backup = Get-Content -LiteralPath $script:RtBackup -Raw | ConvertFrom-Json
        @($backup.Entries).Count | Should -Be 4
        (@($backup.Entries | Where-Object { $_.Name -eq 'EnableLUA' })[0]).Value | Should -Be 1
        (@($backup.Entries | Where-Object { $_.Name -eq 'LateValue' })[0]).Value | Should -Be 7
    }

    It "stores the process mitigation XML once and restores it through the documented cmdlet" {
        $plan = [pscustomobject]@{ Operations = @(); Skips = @(); IncludeProcessMitigations = $true }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan -ProcessMitigationXml '<mitigation />' | Should -BeTrue

        $plan2 = [pscustomobject]@{ Operations = $script:RtOps; Skips = @(); IncludeProcessMitigations = $true }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan2 -ProcessMitigationXml '<changed />' | Should -BeTrue
        $backup = Get-Content -LiteralPath $script:RtBackup -Raw | ConvertFrom-Json
        $backup.ProcessMitigationXml | Should -Be '<mitigation />'

        Mock Set-ProcessMitigation { }
        Restore-SecurityWeakeningBackup -BackupFile $script:RtBackup | Should -BeTrue
        Should -Invoke Set-ProcessMitigation -Times 1 -Exactly
    }

    It "fails closed when the snapshot is missing or corrupt" {
        $beforeFail = $script:fail
        Restore-SecurityWeakeningBackup -BackupFile $script:RtBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail

        [System.IO.File]::WriteAllText($script:RtBackup, '{"Version": 999}', [System.Text.UTF8Encoding]::new($false))
        $beforeFail = $script:fail
        Restore-SecurityWeakeningBackup -BackupFile $script:RtBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
    }

    It "aborts the snapshot when the file is corrupt" {
        [System.IO.File]::WriteAllText($script:RtBackup, 'not-json', [System.Text.UTF8Encoding]::new($false))
        $beforeFail = $script:fail
        $plan = [pscustomobject]@{ Operations = $script:RtOps; Skips = @(); IncludeProcessMitigations = $false }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
    }

    It "reports failure when a restore write fails" {
        $plan = [pscustomobject]@{ Operations = $script:RtOps; Skips = @(); IncludeProcessMitigations = $false }
        Ensure-SecurityWeakeningBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue
        Mock Set-TweakRegistryTypedValue { throw '模拟恢复写入失败' }
        $beforeFail = $script:fail
        Restore-SecurityWeakeningBackup -BackupFile $script:RtBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
    }
}

Describe "Security weakening dispatcher" {
    BeforeEach {
        Mock Request-Restart { }
        $script:TweakAcceptDefaults = $false
        $script:TweakNonInteractive = $false
    }

    AfterEach {
        $script:TweakAcceptDefaults = $false
        $script:TweakNonInteractive = $false
    }

    It "status is read-only" {
        Mock Set-TweakRegistryTypedValue { throw '状态查询不应写入注册表' }
        Invoke-SecurityWeakeningModule -Action '0' | Should -BeTrue
    }

    It "rejects unknown actions and missing actions in non-interactive mode" {
        $beforeFail = $script:fail
        $script:TweakNonInteractive = $true
        try {
            Invoke-SecurityWeakeningModule -Action 'bogus' | Should -BeFalse
            Invoke-SecurityWeakeningModule -Action '' | Should -BeFalse
        } finally {
            $script:TweakNonInteractive = $false
        }
        $script:fail | Should -BeGreaterThan $beforeFail
    }

    It "reference-only item performs no writes" {
        Mock Test-HighRiskConfirmation { return $true }
        Mock Set-TweakRegistryTypedValue { throw '参考项不应写入注册表' }
        Invoke-SecurityWeakeningModule -Action '7' | Should -BeTrue
    }

    It "aborts without writing when the snapshot cannot be created" {
        Mock Test-HighRiskConfirmation { return $true }
        Mock Ensure-SecurityWeakeningBackup { return $false }
        Mock Set-TweakRegistryTypedValue { throw '快照失败时不应写入' }
        Invoke-SecurityWeakeningModule -Action '2' | Should -BeFalse
    }

    It "rolls back when a write fails" {
        Mock Test-HighRiskConfirmation { return $true }
        Mock Ensure-SecurityWeakeningBackup { return $true }
        Mock Set-TweakRegistryTypedValue { throw '模拟写入失败' }
        Mock Restore-SecurityWeakeningBackup { return $true }
        $beforeFail = $script:fail
        Invoke-SecurityWeakeningModule -Action '2' | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
        Should -Invoke Restore-SecurityWeakeningBackup -Times 1 -Exactly
    }

    It "requires the extra phrase before touching B13 process mitigations" {
        Mock Test-HighRiskConfirmation { return $false }
        Invoke-SecurityWeakeningModule -Action '13' | Should -BeFalse
        Should -Invoke Test-HighRiskConfirmation -ParameterFilter { $Phrase -eq 'I-UNDERSTAND-MITIGATIONS-OFF' } -Times 1 -Exactly
    }

    It "restore action delegates to the snapshot restore" {
        Mock Restore-SecurityWeakeningBackup { return $true }
        Invoke-SecurityWeakeningModule -Action 'r' | Should -BeTrue
        Should -Invoke Restore-SecurityWeakeningBackup -Times 1 -Exactly
    }
}
