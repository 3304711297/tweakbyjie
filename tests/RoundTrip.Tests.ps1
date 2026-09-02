BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "SecurityMitigation backup/restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $key = 'HKCU:\Software\TweakByjieTest\SM'
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'FeatureSettingsOverride' -PropertyType DWord -Value 7 -Force | Out-Null
        # FeatureSettingsOverrideMask intentionally left absent to cover the not-present branch

        $defs = @(
            @{ Path = $key; Name = 'FeatureSettingsOverride' },
            @{ Path = $key; Name = 'FeatureSettingsOverrideMask' }
        )
        $script:origSmFile = $script:securityMitigationBackupFile
        $script:securityMitigationBackupFile = Join-Path $TestDrive 'sm-backup.json'
    }

    AfterAll {
        Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:origSmFile) { $script:securityMitigationBackupFile = $script:origSmFile }
    }

    It "Ensure captures present value and absence" {
        Ensure-SecurityMitigationBackup -Definitions $defs | Should -Be $true
        $backup = Get-Content $script:securityMitigationBackupFile -Raw | ConvertFrom-Json
        $r1 = $backup.Values | Where-Object { $_.Name -eq 'FeatureSettingsOverride' }
        $r2 = $backup.Values | Where-Object { $_.Name -eq 'FeatureSettingsOverrideMask' }
        $r1.Present | Should -Be $true
        [uint32]$r1.Value | Should -Be 7
        $r2.Present | Should -Be $false
    }

    It "Restore brings back original value and removes new value" {
        Set-ItemProperty -Path $key -Name 'FeatureSettingsOverride' -Value 3
        New-ItemProperty -Path $key -Name 'FeatureSettingsOverrideMask' -PropertyType DWord -Value 3 -Force | Out-Null

        Restore-SecurityMitigationBackup -Definitions $defs | Should -Be $true

        $item = Get-Item $key
        [int]$item.GetValue('FeatureSettingsOverride') | Should -Be 7
        $item.GetValueNames() | Should -Not -Contain 'FeatureSettingsOverrideMask'
    }
}

Describe "Defender policy backup/restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $key = 'HKCU:\Software\TweakByjieTest\Def'
        $runKey = 'HKCU:\Software\TweakByjieTest\DefRun'
        New-Item -Path $key -Force | Out-Null
        New-Item -Path $runKey -Force | Out-Null
        New-ItemProperty -Path $key -Name 'TestDword' -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $key -Name 'TestString' -PropertyType String -Value 'Original' -Force | Out-Null
        New-ItemProperty -Path $key -Name 'TestBinary' -PropertyType Binary -Value ([byte[]](0xDE, 0xAD)) -Force | Out-Null
        New-ItemProperty -Path $runKey -Name 'StartupPresent' -PropertyType Binary -Value ([byte[]](0x03, 0x00, 0x00, 0x00)) -Force | Out-Null

        $policyDefs = @(
            @{ Path = $key; Name = 'TestDword'; Type = 'DWord'; Value = 1; Desc = 'rt dword' },
            @{ Path = $key; Name = 'TestString'; Type = 'String'; Value = 'Original'; Desc = 'rt string' },
            @{ Path = $key; Name = 'TestBinary'; Type = 'Binary'; Value = ''; Desc = 'rt binary' },
            @{ Path = $key; Name = 'TestAbsent'; Type = 'DWord'; Value = 0; Desc = 'rt absent' }
        )
        $startupDefs = @(
            @{ Path = $runKey; Name = 'StartupPresent' },
            @{ Path = $runKey; Name = 'StartupAbsent' }
        )
        $script:origDefFile = $script:defenderPolicyBackupFile
        $script:defenderPolicyBackupFile = Join-Path $TestDrive 'defender-policy-backup.json'
    }

    AfterAll {
        Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:origDefFile) { $script:defenderPolicyBackupFile = $script:origDefFile }
    }

    It "Ensure snapshots values with actual registry kinds" {
        Ensure-DefenderPolicyBackup -Definitions $policyDefs -StartupDefinitions $startupDefs | Should -Be $true
        $backup = Get-Content $script:defenderPolicyBackupFile -Raw | ConvertFrom-Json
        ($backup.Values | Where-Object { $_.Name -eq 'TestBinary' }).Type | Should -Be 'Binary'
        ($backup.Values | Where-Object { $_.Name -eq 'TestString' }).Type | Should -Be 'String'
        ($backup.Values | Where-Object { $_.Name -eq 'TestAbsent' }).Present | Should -Be $false
        ($backup.StartupValues | Where-Object { $_.Name -eq 'StartupPresent' }).Present | Should -Be $true
    }

    It "Restore returns every value to original state and type" {
        Set-ItemProperty -Path $key -Name 'TestDword' -Value 9
        Set-ItemProperty -Path $key -Name 'TestString' -Value 'Changed'
        Set-ItemProperty -Path $key -Name 'TestBinary' -Value ([byte[]](0x01, 0x02))
        New-ItemProperty -Path $key -Name 'TestAbsent' -PropertyType DWord -Value 5 -Force | Out-Null
        Remove-ItemProperty -Path $runKey -Name 'StartupPresent' -Force
        New-ItemProperty -Path $runKey -Name 'StartupAbsent' -PropertyType DWord -Value 1 -Force | Out-Null

        Restore-DefenderPolicyBackup -Definitions $policyDefs -StartupDefinitions $startupDefs | Should -Be $true

        $item = Get-Item $key
        [int]$item.GetValue('TestDword') | Should -Be 1
        [string]$item.GetValue('TestString') | Should -Be 'Original'
        $item.GetValueKind('TestString') | Should -Be 'String'
        $item.GetValue('TestBinary') | Should -Be ([byte[]](0xDE, 0xAD))
        $item.GetValueKind('TestBinary') | Should -Be 'Binary'
        $item.GetValueNames() | Should -Not -Contain 'TestAbsent'
        $runItem = Get-Item $runKey
        $runItem.GetValueNames() | Should -Contain 'StartupPresent'
        $runItem.GetValueNames() | Should -Not -Contain 'StartupAbsent'
    }
}
