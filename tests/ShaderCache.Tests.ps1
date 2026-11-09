BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'Shader cache scan and clean' {
    BeforeEach {
        $script:cacheRoot = Join-Path $TestDrive ("cache-" + [guid]::NewGuid().ToString('N'))
        $script:d3d = Join-Path $script:cacheRoot 'D3DSCache'
        $script:nv = Join-Path $script:cacheRoot 'NV'
        New-Item -ItemType Directory -Path $script:d3d -Force | Out-Null
        New-Item -ItemType Directory -Path $script:nv -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:d3d 'a.bin') -Value 'abc' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:d3d 'b.bin') -Value 'def' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:nv 'c.bin') -Value 'ghi' -NoNewline
    }

    It 'scans files and totals their size' {
        $r = Get-ShaderCacheFiles -Directories @($script:d3d, $script:nv)
        @($r.Files).Count | Should -Be 3
        $r.TotalBytes | Should -Be 9
        @($r.Rejected).Count | Should -Be 0
    }

    It 'rejects a reparse-point directory instead of following it' {
        $target = Join-Path $script:cacheRoot 'target'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'outside.bin') -Value 'zzz' -NoNewline
        $link = Join-Path $script:cacheRoot 'link'
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null

        $r = Get-ShaderCacheFiles -Directories @($link)
        @($r.Files).Count | Should -Be 0
        @($r.Rejected).Count | Should -Be 1
        (Test-Path -LiteralPath (Join-Path $target 'outside.bin')) | Should -Be $true
    }

    It 'deletes files one by one and keeps the directories' {
        $r = Clear-ShaderCacheFiles -Directories @($script:d3d, $script:nv)
        $r.Deleted | Should -Be 3
        (Test-Path -LiteralPath $script:d3d) | Should -Be $true
        @(Get-ChildItem -LiteralPath $script:d3d -File -Force).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:nv -File -Force).Count | Should -Be 0
    }

    It 'skips a locked file and still deletes the rest' {
        $lockedPath = Join-Path $script:d3d 'a.bin'
        $stream = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $r = Clear-ShaderCacheFiles -Directories @($script:d3d)
            $r.Deleted | Should -Be 1
            $r.Failed | Should -Be 1
            (Test-Path -LiteralPath $lockedPath) | Should -Be $true
        } finally {
            $stream.Dispose()
        }
    }
}

Describe 'Shader cache module contract' {
    It 'rejects an unknown action without touching files' {
        $before = $script:fail
        $result = Invoke-ShaderCacheModule -Action 'bogus'
        $result | Should -Be $false
        $script:fail | Should -BeGreaterThan $before
    }
}
