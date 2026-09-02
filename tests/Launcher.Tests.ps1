BeforeAll {
    $launcherPath = Join-Path $PSScriptRoot '../tweakbyjie.cmd'
    $launcherText = Get-Content -LiteralPath $launcherPath -Raw -Encoding ASCII
}

Describe 'CMD launcher argument forwarding' {
    It 'forwards all launcher arguments to PowerShell 7' {
        $launcherText | Should -Match 'tweakbyjie\.ps1" %\*'
    }

    It 'forwards all launcher arguments to Windows PowerShell 5.1' {
        $matches = [regex]::Matches($launcherText, 'tweakbyjie\.ps1" %\*')
        $matches.Count | Should -Be 2
    }
}
