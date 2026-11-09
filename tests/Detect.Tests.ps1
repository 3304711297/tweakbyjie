BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'Detect report' {
    BeforeAll {
        $script:fakeHealth = [pscustomobject]@{
            Results = @(
                [pscustomobject]@{ Name = 'PCIe 链路'; Status = 'Info'; Summary = '上限 x8'; Detail = 'max=Gen4 x8' }
                [pscustomobject]@{ Name = 'VC++ v14 运行库'; Status = 'Attention'; Summary = '缺少 x86'; Detail = '' }
            )
            AttentionCount = 1
        }
        $script:report = Get-TweakDetectReport `
            -OSInfo ([pscustomobject]@{ Caption = 'Windows 11 Pro'; Version = '10.0.26200'; BuildNumber = '26200' }) `
            -CPUInfo ([pscustomobject]@{ Name = 'Test CPU'; NumberOfCores = 8; NumberOfLogicalProcessors = 16 }) `
            -GpuInfo @([pscustomobject]@{ Name = 'Test GPU'; DriverVersion = '1.2.3' }) `
            -MemoryModules @([pscustomobject]@{ Capacity = 17179869184; Speed = 6400; ConfiguredClockSpeed = 6400 }) `
            -Health $script:fakeHealth
    }

    It 'exposes a stable schema and core fields' {
        $script:report.schemaVersion | Should -Be 1
        $script:report.os.caption | Should -Be 'Windows 11 Pro'
        $script:report.os.build | Should -Be '26200'
        $script:report.cpu.cores | Should -Be 8
        $script:report.cpu.threads | Should -Be 16
        @($script:report.gpu).Count | Should -Be 1
        $script:report.gpu[0].name | Should -Be 'Test GPU'
        $script:report.memory.totalGB | Should -Be 16
        $script:report.health.attentionCount | Should -Be 1
        @($script:report.health.results).Count | Should -Be 2
    }

    It 'serializes to JSON without losing fields' {
        $json = $script:report | ConvertTo-Json -Depth 8
        $round = $json | ConvertFrom-Json
        $round.schemaVersion | Should -Be 1
        $round.health.results[1].status | Should -Be 'Attention'
    }

    It 'escapes non-ASCII so stdout capture survives any code page' {
        $ascii = ConvertTo-TweakJsonAscii ([pscustomobject]@{ x = '中文'; n = 1 })
        $ascii | Should -Match '^[\x00-\x7F]+$'
        ($ascii | ConvertFrom-Json).x | Should -Be '中文'
        ($ascii | ConvertFrom-Json).n | Should -Be 1
    }
}

Describe 'Detect CLI contract' {
    BeforeAll {
        $script:pwshExe = (Get-Process -Id $PID).Path
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:entry = Join-Path $script:repoRoot 'tweakbyjie.ps1'
    }

    It 'emits pure JSON for -Detect -Json' {
        $out = & $script:pwshExe -NoProfile -File $script:entry -Detect -Json 2>$null
        $report = ($out -join "`n") | ConvertFrom-Json
        $report.schemaVersion | Should -Be 1
        $report.os.build | Should -Not -BeNullOrEmpty
        @($report.health.results).Count | Should -BeGreaterThan 0
    }

    It 'rejects -Json without -Detect with exit code 2' {
        & $script:pwshExe -NoProfile -File $script:entry -Json 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 2
    }

    It 'rejects -Detect combined with -RunModule with exit code 2' {
        & $script:pwshExe -NoProfile -File $script:entry -Detect -RunModule 15 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 2
    }

    It 'emits ASCII-safe JSON from Windows PowerShell 5.1' {
        $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps51)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not available'
            return
        }
        $file = Join-Path $TestDrive 'detect51.json'
        $errFile = Join-Path $TestDrive 'detect51.err'
        $process = Start-Process -FilePath $ps51 -ArgumentList "-NoProfile -File `"$($script:entry)`" -Detect -Json" `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $file -RedirectStandardError $errFile
        $process.ExitCode | Should -Be 0
        $text = [System.IO.File]::ReadAllText($file, [System.Text.UTF8Encoding]::new($false))
        $text | Should -Match '^[\x00-\x7F]+$'
        ($text | ConvertFrom-Json).schemaVersion | Should -Be 1
    }
}
