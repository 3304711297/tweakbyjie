BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Common.ps1 Convert-RegExePath" {
    It "converts PowerShell registry paths to reg.exe syntax" {
        Convert-RegExePath 'HKLM:\SOFTWARE\Policies' | Should -Be 'HKLM\SOFTWARE\Policies'
        Convert-RegExePath 'HKCU:\Software\Microsoft' | Should -Be 'HKCU\Software\Microsoft'
        Convert-RegExePath 'HKEY_LOCAL_MACHINE:\SYSTEM\CurrentControlSet' | Should -Be 'HKLM\SYSTEM\CurrentControlSet'
        Convert-RegExePath 'HKEY_CURRENT_USER:\Control Panel' | Should -Be 'HKCU\Control Panel'
    }

    It "leaves already-converted or non-standard paths untouched" {
        Convert-RegExePath 'HKLM\SOFTWARE\Policies' | Should -Be 'HKLM\SOFTWARE\Policies'
        Convert-RegExePath 'C:\Windows\System32' | Should -Be 'C:\Windows\System32'
    }
}

Describe "Common.ps1 Write-TweakAtomicTextFile" {
    BeforeEach {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) ("Pester_Atomic_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }
    AfterEach {
        if (Test-Path -LiteralPath $testDir) {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "writes text atomically to a new file" {
        $target = Join-Path $testDir 'sub/dir/atomic.json'
        $content = '{"hello":"world"}'
        Write-TweakAtomicTextFile -Path $target -Content $content
        Test-Path -LiteralPath $target | Should -Be $true
        $read = Get-Content -LiteralPath $target -Raw
        $read | Should -Be $content
    }

    It "cleans up temporary file if move fails" {
        $target = Join-Path $testDir 'existing.txt'
        Set-Content -LiteralPath $target -Value 'initial'
        # File.Move to existing path without overwrite will throw in .NET
        { Write-TweakAtomicTextFile -Path $target -Content 'new' } | Should -Throw
        # Temp files starting with '.' should be cleaned up by finally block
        $temps = Get-ChildItem -Path $testDir -Filter '.*.tmp'
        $temps.Count | Should -Be 0
    }
}

Describe "Common.ps1 Test-ConfirmChoice and Test-HighRiskConfirmation" {
    BeforeEach {
        $script:fail = 0
        $script:ok = 0
        $script:TweakAcceptDefaults = $false
        $script:TweakNonInteractive = $false
    }

    It "auto-accepts confirmation when TweakAcceptDefaults is true" {
        $script:TweakAcceptDefaults = $true
        Test-ConfirmChoice 'Proceed?' | Should -Be $true
        Test-HighRiskConfirmation 'Dangerous action?' | Should -Be $true
    }

    It "fails closed when non-interactive and AcceptDefaults is missing" {
        $script:TweakNonInteractive = $true
        Test-ConfirmChoice 'Proceed?' | Should -Be $false
        $script:fail | Should -Be 1

        Test-HighRiskConfirmation 'Dangerous action?' | Should -Be $false
        $script:fail | Should -Be 2
    }
}

Describe "Common.ps1 Verification Helpers" {
    BeforeEach {
        $script:fail = 0
        $script:skip = 0
        $script:ok = 0
    }

    It "Verify-TrimEnabled parses fsutil output correctly" {
        Mock fsutil.exe {
            $global:LASTEXITCODE = 0
            return "DisableDeleteNotify = 0"
        }
        Verify-TrimEnabled | Should -Be $true
        $script:fail | Should -Be 0
    }

    It "Verify-TrimEnabled fails closed when fsutil fails" {
        Mock fsutil.exe {
            $global:LASTEXITCODE = 1
            return "Error"
        }
        Verify-TrimEnabled | Should -Be $false
        $script:fail | Should -Be 1
    }

    It "Verify-HypervisorRuntime handles HypervisorPresent boolean" {
        Mock Get-CimInstance {
            return [pscustomobject]@{ HypervisorPresent = $false }
        }
        Verify-HypervisorRuntime | Should -Be $true
    }

    It "Verify-RegDword succeeds when registry value matches expected DWORD" {
        $testRegPath = 'HKCU:\Software\TweakByjieTest\CommonVerify'
        New-Item -Path $testRegPath -Force | Out-Null
        Set-ItemProperty -Path $testRegPath -Name 'TestDword' -Value 123 -Type DWord
        try {
            Verify-RegDword $testRegPath 'TestDword' 123 'Test Verification' | Should -Be $true
            Verify-RegDword $testRegPath 'TestDword' 999 'Test Verification Fail' | Should -Be $false
        } finally {
            Remove-Item -Path $testRegPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Verify-ServiceStartupType verifies service StartMode via CimInstance" {
        Mock Get-CimInstance {
            return [pscustomobject]@{ StartMode = 'Manual' }
        }
        Verify-ServiceStartupType 'TestSvc' 'Manual' 'Test Service' | Should -Be $true
        Verify-ServiceStartupType 'TestSvc' 'Disabled' 'Test Service Mismatch' | Should -Be $false
    }

    It "Verify-MemoryCompressionDisabled verifies MMAgent output" {
        Mock Get-MMAgent {
            return [pscustomobject]@{ MemoryCompression = $false }
        }
        Verify-MemoryCompressionDisabled | Should -Be $true

        Mock Get-MMAgent {
            return [pscustomobject]@{ MemoryCompression = $true }
        }
        Verify-MemoryCompressionDisabled | Should -Be $false
    }

    It "Remove-BcdValue deletes present value and skips absent value" {
        Mock bcdedit.exe {
            $global:LASTEXITCODE = 0
            return @('testsigning          Yes')
        }
        Mock Invoke-BcdEdit { return $true }
        Remove-BcdValue 'testsigning' 'Delete testsigning'
        Should -Invoke Invoke-BcdEdit -Times 1

        Remove-BcdValue 'absentkey' 'Delete absent'
        Should -Invoke Invoke-BcdEdit -Times 1
    }
}

Describe "Registry.ps1 Invoke-RegistryStepSequence" {
    BeforeEach {
        $script:fail = 0
    }

    It "returns true when all steps succeed without errors" {
        $script:step1Executed = $false
        $script:step2Executed = $false
        $steps = @(
            { $script:step1Executed = $true },
            { $script:step2Executed = $true }
        )
        Invoke-RegistryStepSequence $steps | Should -Be $true
        $script:step1Executed | Should -Be $true
        $script:step2Executed | Should -Be $true
    }

    It "fails closed and aborts sequence when a step throws exception" {
        $script:step2Executed = $false
        $steps = @(
            { throw 'simulated step failure' },
            { $script:step2Executed = $true }
        )
        Invoke-RegistryStepSequence $steps | Should -Be $false
        $script:step2Executed | Should -Be $false
        $script:fail | Should -Be 1
    }

    It "aborts sequence when a step increments fail counter" {
        $script:step2Executed = $false
        $steps = @(
            { $script:fail++ },
            { $script:step2Executed = $true }
        )
        Invoke-RegistryStepSequence $steps | Should -Be $false
        $script:step2Executed | Should -Be $false
    }
}
