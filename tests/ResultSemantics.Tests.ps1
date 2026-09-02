BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'Stable execution result exit codes' {
    It 'returns success for a clean session' {
        Get-TweakExitCode -SuccessCount 0 -FailureCount 0 | Should -Be 0
    }

    It 'returns execution failure when all requested work fails' {
        Get-TweakExitCode -SuccessCount 0 -FailureCount 1 | Should -Be 4
    }

    It 'returns partial failure when some work succeeded and some failed' {
        Get-TweakExitCode -SuccessCount 1 -FailureCount 1 | Should -Be 5
    }

    It 'returns invalid-input code when requested explicitly' {
        Get-TweakExitCode -InvalidInput | Should -Be 2
    }
}
