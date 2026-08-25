BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '../defender-removal.ps1'
    $scriptText = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
}

Describe 'Defender removal safety contract' {
    It 'requires an explicit Execute switch and supports dry-run mode' {
        $scriptText | Should -Match '\[switch\]\$Execute'
        $scriptText | Should -Match '\[switch\]\$DryRun'
        $scriptText | Should -Match 'if\s*\(\s*-not\s*\$Execute\s*\)'
    }

    It 'supports disabling restart by default' {
        $scriptText | Should -Match '\[switch\]\$NoRestart'
        $scriptText | Should -Match '\$Execute\s+-and\s+\$Restart\s+-and\s+-not\s+\$NoRestart'
    }

    It 'does not invoke SYSTEM retry in the normal execution path' {
        $scriptText | Should -Not -Match 'Invoke-SystemRetry'
        $scriptText | Should -Not -Match 'Register-ScheduledTask'
    }

    It 'guards destructive commands behind explicit execution mode' {
        $scriptText | Should -Match 'if\s*\(\s*-not\s*\$Execute\s*\)\s*\{[\s\S]*?exit\s+0'
        $scriptText | Should -Match '\$fail\s+-gt\s+0'
    }

    It 'does not force restart after a failed or partial removal' {
        $scriptText | Should -Match 'if\s*\(\s*\$fail\s+-gt\s+0\s*\)[\s\S]*?exit\s+4'
        $scriptText | Should -Match '\$fail\s+-eq\s+0'
    }
}
