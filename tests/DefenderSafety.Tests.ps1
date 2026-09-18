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

    It 'has an explicit non-interactive confirmation path without hidden prompts' {
        $scriptText | Should -Match '\[switch\]\$NonInteractive'
        $scriptText | Should -Match '\[switch\]\$ConfirmIrreversible'
        $scriptText | Should -Match '非交互执行不可省略不可逆确认'
        $scriptText | Should -Match 'if\s*\(-not\s*\$NonInteractive\)\s*\{\s*Read-Host'
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
