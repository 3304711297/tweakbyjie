BeforeAll {
    $env:TWEAK_SKIP_ADMIN_CHECK = '1'
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Preference item table" {
    BeforeAll {
        $script:Items = @(Get-PreferenceItems)
    }

    It "defines exactly 6 items with sequential Px ids" {
        $script:Items.Count | Should -Be 6
        @($script:Items | ForEach-Object Id) | Should -Be @('P1', 'P2', 'P3', 'P4', 'P5', 'P6')
    }

    It "gives every item a name, a note and at least one write target" {
        foreach ($item in $script:Items) {
            [string]::IsNullOrWhiteSpace($item.Name) | Should -BeFalse
            [string]::IsNullOrWhiteSpace($item.Note) | Should -BeFalse
            @($item.Operations).Count | Should -BeGreaterThan 0
        }
    }

    It "declares valid registry targets with correct value types" {
        foreach ($item in $script:Items) {
            foreach ($op in @($item.Operations)) {
                $op.Path | Should -Match '^HK(LM|CU):\\'
                [string]::IsNullOrWhiteSpace($op.Name) | Should -BeFalse
                $op.Kind | Should -BeIn @('DWord', 'String')
            }
        }
    }

    It "pins the documented targets and types" {
        $ops = @($script:Items | ForEach-Object { $_.Operations } | ForEach-Object { $_ })
        foreach ($name in @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2')) {
            $hit = @($ops | Where-Object { $_.Name -eq $name })
            $hit.Count | Should -Be 1
            $hit[0].Path | Should -Be 'HKCU:\Control Panel\Mouse'
            $hit[0].Kind | Should -Be 'String'
            $hit[0].Value | Should -Be '0'
        }
        $fth = @($ops | Where-Object { $_.Name -eq 'Enabled' })
        $fth.Count | Should -Be 1
        $fth[0].Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\FTH'
        $fth[0].Kind | Should -Be 'DWord'
        (@($ops | Where-Object { $_.Name -eq 'LongPathsEnabled' })[0]).Value | Should -Be 1
        (@($ops | Where-Object { $_.Name -eq 'PrintScreenKeyForSnippingEnabled' })[0]).Kind | Should -Be 'DWord'
        (@($ops | Where-Object { $_.Name -eq 'IsInputAppPreloadEnabled' })[0]).Path | Should -Be 'HKCU:\Software\Microsoft\Input'
        (@($ops | Where-Object { $_.Name -eq 'AutoColorization' })[0]).Path | Should -Be 'HKCU:\Control Panel\Desktop'
    }

    It "never duplicates a path/value pair" {
        $keys = @($script:Items | ForEach-Object { $_.Operations } | ForEach-Object { ('{0}|{1}' -f $_.Path, $_.Name).ToLowerInvariant() })
        @($keys | Sort-Object -Unique).Count | Should -Be $keys.Count
    }

    It "does not include the explicitly rejected suspicious candidates" {
        $names = @($script:Items | ForEach-Object { $_.Operations } | ForEach-Object Name)
        foreach ($rejected in @('SvcHostSplitThresholdInKB', 'SvcHostSplitDisable', 'MiracastForceDisable', 'WarpSupportsResourceResidency', 'DisableProjectedShadows', 'NoLazyMode')) {
            $names | Should -Not -Contain $rejected
        }
    }

    It "keeps a documented DEFAULT backup file name" {
        $script:preferencesBackupFile | Should -Match 'preferences-backup\.json$'
    }
}

Describe "Preference plan builder" {
    It "expands one item into its declared writes" {
        $plan = Get-PreferencePlan -ItemIds @('P1')
        @($plan.Operations).Count | Should -Be 3
        @($plan.Operations | ForEach-Object Scope) | Should -Be @('P1', 'P1', 'P1')
    }

    It "rejects unknown or empty item ids" {
        { Get-PreferencePlan -ItemIds @('P9') } | Should -Throw
        { Get-PreferencePlan -ItemIds @() } | Should -Throw
    }

    It "deduplicates repeated targets across items" {
        $plan = Get-PreferencePlan -ItemIds @('P1', 'P1')
        @($plan.Operations).Count | Should -Be 3
    }
}

Describe "Preference dispatcher" {
    BeforeEach {
        Mock Request-Restart { }
        $script:TweakNonInteractive = $false
        $script:PrefBackup = Join-Path $env:TEMP ("preferences-test-" + [guid]::NewGuid().ToString('N') + ".json")
    }

    AfterEach {
        $script:TweakNonInteractive = $false
        if (Test-Path -LiteralPath $script:PrefBackup) { Remove-Item -LiteralPath $script:PrefBackup -Force -ErrorAction SilentlyContinue }
    }

    It "status is read-only" {
        Mock Set-TweakRegistryTypedValue { throw '状态查询不应写入注册表' }
        Invoke-PreferenceModule -Action '0' -BackupFile $script:PrefBackup | Should -BeTrue
    }

    It "rejects unknown actions and missing actions in non-interactive mode" {
        $beforeFail = $script:fail
        $script:TweakNonInteractive = $true
        try {
            Invoke-PreferenceModule -Action 'bogus' -BackupFile $script:PrefBackup | Should -BeFalse
            Invoke-PreferenceModule -Action '' -BackupFile $script:PrefBackup | Should -BeFalse
        } finally {
            $script:TweakNonInteractive = $false
        }
        $script:fail | Should -BeGreaterThan $beforeFail
    }

    It "applies every planned write for the selected item" {
        Mock Ensure-TypedValueBackup { return $true }
        Mock Set-TweakRegistryTypedValue { }
        $beforeOk = $script:ok
        Invoke-PreferenceModule -Action '3' -BackupFile $script:PrefBackup | Should -BeTrue
        $script:ok | Should -BeGreaterThan $beforeOk
        Should -Invoke Set-TweakRegistryTypedValue -Times 1 -Exactly
        Should -Invoke Set-TweakRegistryTypedValue -ParameterFilter { $Name -eq 'LongPathsEnabled' -and $Value -eq 1 } -Times 1
    }

    It "aborts without writing when the snapshot cannot be created" {
        Mock Ensure-TypedValueBackup { return $false }
        Mock Set-TweakRegistryTypedValue { throw '快照失败时不应写入' }
        Invoke-PreferenceModule -Action '2' -BackupFile $script:PrefBackup | Should -BeFalse
    }

    It "rolls back when a write fails" {
        Mock Ensure-TypedValueBackup { return $true }
        Mock Set-TweakRegistryTypedValue { throw '模拟写入失败' }
        Mock Restore-TypedValueBackup { return $true }
        $beforeFail = $script:fail
        Invoke-PreferenceModule -Action '2' -BackupFile $script:PrefBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
        Should -Invoke Restore-TypedValueBackup -Times 1 -Exactly
    }

    It "restore action delegates to the typed-value restore" {
        Mock Restore-TypedValueBackup { return $true }
        Invoke-PreferenceModule -Action 'r' -BackupFile $script:PrefBackup | Should -BeTrue
        Should -Invoke Restore-TypedValueBackup -Times 1 -Exactly
    }
}
