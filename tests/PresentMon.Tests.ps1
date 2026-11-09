BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'PresentMon CSV metrics' {
    BeforeAll {
        $script:csv = Join-Path $TestDrive 'presentmon.csv'
        $lines = @('Application,ProcessID,MsBetweenPresents')
        for ($i = 0; $i -lt 98; $i++) { $lines += 'game.exe,1234,10.0' }
        for ($i = 0; $i -lt 2; $i++) { $lines += 'game.exe,1234,30.0' }
        Set-Content -LiteralPath $script:csv -Value $lines -Encoding ASCII
        $script:metrics = ConvertFrom-PresentMonCsv -Path $script:csv
    }

    It 'computes frame count, average FPS and 1% low' {
        $script:metrics.frameCount | Should -Be 100
        $script:metrics.avgFps | Should -BeGreaterThan 95
        $script:metrics.avgFps | Should -BeLessThan 97
        $script:metrics.p99FrameMs | Should -Be 30
        $script:metrics.fps1Low | Should -BeGreaterThan 33
        $script:metrics.fps1Low | Should -BeLessThan 34
    }

    It 'counts stutters above twice the median frame time' {
        $script:metrics.medianFrameMs | Should -Be 10
        $script:metrics.stutterCount | Should -Be 2
        $script:metrics.stuttersPerMin | Should -BeGreaterThan 100
    }

    It 'rejects a CSV without the frame-time column' {
        $bad = Join-Path $TestDrive 'bad.csv'
        Set-Content -LiteralPath $bad -Value @('Application,ProcessID', 'game.exe,1') -Encoding ASCII
        { ConvertFrom-PresentMonCsv -Path $bad } | Should -Throw
    }
}

Describe 'PresentMon metric comparison' {
    It 'marks a clear 1% low improvement as improved' {
        $baseline = [pscustomobject]@{ avgFps = 100; fps1Low = 60; p99FrameMs = 16.67; stutterCount = 2; stuttersPerMin = 10 }
        $after = [pscustomobject]@{ avgFps = 101; fps1Low = 66; p99FrameMs = 15.15; stutterCount = 2; stuttersPerMin = 10 }
        $r = Compare-PresentMonMetrics -Baseline $baseline -After $after
        $r.verdict | Should -Be 'improved'
        $r.fps1LowDeltaPct | Should -BeGreaterThan 9
    }

    It 'marks a 1% low regression as regressed' {
        $baseline = [pscustomobject]@{ avgFps = 100; fps1Low = 60; p99FrameMs = 16.67; stutterCount = 2; stuttersPerMin = 10 }
        $after = [pscustomobject]@{ avgFps = 99; fps1Low = 54; p99FrameMs = 18.5; stutterCount = 3; stuttersPerMin = 15 }
        (Compare-PresentMonMetrics -Baseline $baseline -After $after).verdict | Should -Be 'regressed'
    }

    It 'marks a tiny change as inconclusive' {
        $baseline = [pscustomobject]@{ avgFps = 100; fps1Low = 60; p99FrameMs = 16.67; stutterCount = 2; stuttersPerMin = 10 }
        $after = [pscustomobject]@{ avgFps = 100.5; fps1Low = 61; p99FrameMs = 16.5; stutterCount = 2; stuttersPerMin = 10 }
        (Compare-PresentMonMetrics -Baseline $baseline -After $after).verdict | Should -Be 'inconclusive'
    }
}

Describe 'PresentMon vendoring' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:exe = Join-Path $script:repoRoot 'tools\PresentMon\PresentMon.exe'
        $script:manifestPath = Join-Path $script:repoRoot 'tools\PresentMon\presentmon.json'
    }

    It 'ships PresentMon and the manifest hash matches the binary' {
        (Test-Path -LiteralPath $script:exe) | Should -Be $true
        $manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
        $manifest.version | Should -Be 'v2.6.0'
        (Get-FileHash -LiteralPath $script:exe -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $manifest.sha256
    }

    It 'keeps the Intel signature intact' {
        $signature = Get-AuthenticodeSignature -LiteralPath $script:exe
        $signature.Status | Should -Not -Be 'NotSigned'
        $signature.Status | Should -Not -Be 'HashMismatch'
        $signature.SignerCertificate.Subject | Should -Match 'CN=Intel Corporation'
    }

    It 'finds the vendored binary without an explicit path' {
        $found = Get-PresentMonPath
        $found | Should -Not -BeNullOrEmpty
        $found.Path | Should -Be $script:exe
        $found.Version | Should -Be 'v2.6.0'
    }

    It 'still supports an injected candidate list' {
        $found = Get-PresentMonPath -Candidates @($script:exe)
        $found.Path | Should -Be $script:exe
    }
}

Describe 'Measure module contract' {
    It 'rejects an unknown action' {
        $before = $script:fail
        (Invoke-MeasureModule -Action 'bogus') | Should -Be $false
        $script:fail | Should -BeGreaterThan $before
    }
}
