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


Describe "Non-interactive action contract" {
    It "requires explicit actions for every menu with a sub-operation" {
        @((Get-TweakActionRequiredModules)) | Should -Be @('1','2','3','4','5','6','7','8','9','10','11','12')
    }

    It "parses module actions without allowing duplicates or out-of-range modules" {
        $map = ConvertTo-TweakActionMap '1=3-2,12=1'
        $map['1'] | Should -Be '3-2'
        $map['12'] | Should -Be '1'
        { ConvertTo-TweakActionMap '1=1,1=2' } | Should -Throw
        { ConvertTo-TweakActionMap '13=1' } | Should -Throw
    }

    It "does not ask for a module action in non-interactive menu mode" {
        $script:TweakNonInteractive = $true
        Mock Read-Host { throw 'unexpected hidden prompt' }
        try {
            { Show-TweakMenu -RunModules '0' -Actions @{} -NonInteractive } | Should -Not -Throw
            { Show-TweakMenu -NonInteractive } | Should -Throw
        } finally {
            $script:TweakNonInteractive = $false
        }
    }

    It "allows starting without -RunModule or -NonInteractive in interactive loader mode" {
        $scriptPath = "$PSScriptRoot/../tweakbyjie.ps1"
        $scriptContent = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
        $scriptContent | Should -Match 'if\s*\(\$__requested\.Count\s+-eq\s+0\)\s*\{\s*try\s*\{\s*Show-TweakMenu'
    }

    It "stops an unattended module queue after a module failure" {
        $beforeFail = $script:fail
        Mock Get-TweakPreflight {
            [pscustomobject]@{
                WindowsBuild = 26000; VbsEnabled = $false; BitLockerOn = $false
                SecureBoot = $false; ThirdPartyAv = $false; ViVeTool = $true
            }
        }
        Mock Invoke-GameQosModule { $script:fail++; return $false }
        Mock Invoke-PowerModule { throw 'a later queued module must not run' }
        try {
            { Show-TweakMenu -RunModules '12,7' -Actions @{ '12' = '1'; '7' = '1' } -NonInteractive } | Should -Not -Throw
            Should -Invoke Invoke-GameQosModule -Times 1
            Should -Invoke Invoke-PowerModule -Times 0
        } finally {
            $script:fail = $beforeFail
        }
    }
}
