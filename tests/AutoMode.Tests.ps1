BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Non-interactive module execution" {
    It "Show-TweakMenu auto-executes queue and exits cleanly via module 0" {
        { Show-TweakMenu -RunModules '0' } | Should -Not -Throw
    }
    It "Show-TweakMenu accepts multi-module queue syntax" {
        { Show-TweakMenu -RunModules '0,0' } | Should -Not -Throw
    }
}
