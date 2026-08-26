BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Tweak side-effect adapters" {
    It "initializes the default adapter set" {
        $script:TweakAdapters | Should -Not -BeNullOrEmpty
        $script:TweakAdapters.Keys | Should -Contain 'SetRegistryDword'
        $script:TweakAdapters.Keys | Should -Contain 'SetRegistryString'
        $script:TweakAdapters.Keys | Should -Contain 'SetRegistryBinary'
        $script:TweakAdapters.Keys | Should -Contain 'RemoveRegistryValue'
        $script:TweakAdapters.Keys | Should -Contain 'InvokeBcd'
        $script:TweakAdapters.Keys | Should -Contain 'Confirm'
        $script:TweakAdapters.Keys | Should -Contain 'Restart'
    }

    It "routes registry DWORD writes through an injected adapter" {
        $calls = [System.Collections.Generic.List[object]]::new()
        Set-TweakAdapters -SetRegistryDword {
            param($Path, $Name, $Value)
            $calls.Add(@($Path, $Name, $Value))
            return $true
        }
        $script:ok = 0; $script:fail = 0; $script:rebootRequired = $false
        Set-RegDword 'HKCU:\AdapterTest' 'Value' 7 'adapter test'
        $calls.Count | Should -Be 1
        $calls[0][1] | Should -Be 'Value'
        $calls[0][2] | Should -Be 7
        $script:ok | Should -Be 1
        $script:rebootRequired | Should -Be $true
        Initialize-TweakAdapters
    }

    It "routes BCD execution through an injected adapter and preserves failure accounting" {
        $calls = [System.Collections.Generic.List[string]]::new()
        Set-TweakAdapters -InvokeBcd {
            param($Arguments)
            $calls.Add($Arguments)
            return $false
        }
        $script:ok = 0; $script:fail = 0
        Invoke-BcdEdit '/set testvalue No' 'adapter bcd test' | Should -Be $false
        $calls.Count | Should -Be 1
        $script:fail | Should -Be 1
        Initialize-TweakAdapters
    }

    It "routes confirmation and restart through injected adapters" {
        $confirmed = [System.Collections.Generic.List[bool]]::new()
        $restarted = [System.Collections.Generic.List[bool]]::new()
        Set-TweakAdapters -Confirm { param($Prompt) $confirmed.Add($true); return $true } -Restart { $restarted.Add($true) }
        Test-ConfirmChoice 'adapter confirmation' | Should -Be $true
        $script:rebootRequired = $true
        Invoke-FinalRestartPrompt
        $confirmed.Count | Should -BeGreaterThan 0
        $restarted.Count | Should -Be 1
        Initialize-TweakAdapters
    }
}

AfterAll {
    Initialize-TweakAdapters
}
