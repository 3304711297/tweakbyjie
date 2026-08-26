BeforeAll {
    $loaderText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../tweakbyjie.ps1') -Raw -Encoding UTF8
    $serviceText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Modules/Service.ps1') -Raw -Encoding UTF8
}

Describe 'Loader strict error handling contract' {
    It 'runs with a strict error preference' {
        $loaderText | Should -Match '\$ErrorActionPreference\s*=\s*"Stop"'
    }

    It 'blocks the menu when a module fails to load' {
        $loaderText | Should -Match 'try\s*\{[^}]*?\. \$__p'
        $loaderText | Should -Match 'exit 3'
    }

    It 'converts unexpected terminating errors into a counted failure exit' {
        $loaderText | Should -Match 'try\s*\{\s*Show-TweakMenu'
        $loaderText | Should -Match '\}\s*catch\s*\{[\s\S]*?Get-TweakExitCode'
    }
}

Describe 'Service optimization status reporting contract' {
    It 'distinguishes still-running services from stopped ones' {
        $serviceText | Should -Match 'still running'
    }

    It 'marks restart required after successful startup-type changes' {
        $matches = [regex]::Matches($serviceText, 'rebootRequired\s*=\s*\$true')
        $matches.Count | Should -BeGreaterOrEqual 4
    }
}
