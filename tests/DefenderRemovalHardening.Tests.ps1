BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '../defender-removal.ps1'
    $scriptText = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Defender removal safety and hardening contract" {
    It "strictly excludes Action Center GUID {BB64F8A7-BEE7-4E1A-AB8D-7D8273F7FDB6} to prevent system corruption" {
        $scriptText | Should -Not -Match 'BB64F8A7-BEE7-4E1A-AB8D-7D8273F7FDB6'
    }

    It "includes SecurityHealthService in the service list" {
        $scriptText | Should -Match 'SecurityHealthService'
    }

    It "merges SettingsPageVisibility idempotently without destroying existing hide rules" {
        Get-MergedSettingsPageVisibility $null | Should -Be 'hide:windowsdefender'
        Get-MergedSettingsPageVisibility '' | Should -Be 'hide:windowsdefender'
        Get-MergedSettingsPageVisibility 'hide:network-wifi;bluetooth' | Should -Match 'hide:network-wifi;bluetooth;windowsdefender'
        Get-MergedSettingsPageVisibility 'hide:windowsdefender;display' | Should -Be 'hide:windowsdefender;display'
    }

    It "preserves existing showonly and malformed policy rules as read-only" {
        Get-MergedSettingsPageVisibility 'showonly:display;sound' | Should -Be 'showonly:display;sound'
        Get-MergedSettingsPageVisibility 'invalid_format_rule' | Should -Be 'invalid_format_rule'
    }

    It "honors abortDestructive gate before writing SettingsPageVisibility" {
        $scriptText | Should -Match 'if\s*\(\s*-not\s+\$script:abortDestructive\s*\)\s*\{[\s\S]*?SettingsPageVisibility'
    }

    It "uses DISM nonremovable policy unlock with explicit exit code check in Defender module" {
        $defModulePath = Join-Path $PSScriptRoot '../Modules/Defender.ps1'
        $defModuleText = Get-Content -LiteralPath $defModulePath -Raw -Encoding UTF8
        $defModuleText | Should -Match 'set-nonremovableapppolicy'
        $defModuleText | Should -Match '\$LASTEXITCODE\s+-ne\s+0[\s\S]*?throw'
    }

    It "verifies SecHealthUI removal with live readback before marking success" {
        $defModulePath = Join-Path $PSScriptRoot '../Modules/Defender.ps1'
        $defModuleText = Get-Content -LiteralPath $defModulePath -Raw -Encoding UTF8
        $defModuleText | Should -Match 'live-readback verification'
        $defModuleText | Should -Match 'Remove-AppxProvisionedPackage[\s\S]*?-ErrorAction Stop'
        $defModuleText | Should -Match 'Get-AppxPackage[\s\S]*?-AllUsers\s+-ErrorAction Stop'
        $defModuleText | Should -Match 'Deprovisioned marker creation verification failed'
    }
}
