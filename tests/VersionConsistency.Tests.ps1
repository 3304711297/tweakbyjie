BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'Version constant consistency' {
    It 'TweakVersion matches the highest v* tag when tags are available locally' {
        $versions = @(git tag -l 'v*' 2>$null | ForEach-Object { $_ -replace '^v', '' } | Sort-Object { [version]$_ })
        if ($versions.Count -eq 0) {
            # CI shallow checkout has no tags; the guard lives in the release workflow instead.
            Set-ItResult -Skipped
            return
        }
        $script:TweakVersion | Should -Be $versions[-1]
    }
}
