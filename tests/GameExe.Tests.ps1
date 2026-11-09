BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'Game exe path validation' {
    It 'rejects a non-exe path' {
        { Resolve-GameExePath -Path (Join-Path $TestDrive 'note.txt') } | Should -Throw
    }

    It 'rejects a missing file' {
        { Resolve-GameExePath -Path (Join-Path $TestDrive 'missing.exe') } | Should -Throw
    }

    It 'rejects a path under the Windows directory' {
        { Resolve-GameExePath -Path (Join-Path $env:WINDIR 'notepad.exe') } | Should -Throw
    }
}

Describe 'Game exe per-program apply/restore' {
    BeforeEach {
        $script:root = 'HKCU:\Software\TweakByjieTest\GameExe'
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:root -Force | Out-Null
        $script:fsoKey = Join-Path $script:root 'Layers'
        $script:gpuKey = Join-Path $script:root 'UserGpuPreferences'
        $script:ifeoRoot = Join-Path $script:root 'IFEO'
        $script:backupFile = Join-Path $TestDrive 'game-exe-backup.json'
        Remove-Item -LiteralPath $script:backupFile -Force -ErrorAction SilentlyContinue
        $script:gameExe = Join-Path $TestDrive 'game.exe'
        Set-Content -LiteralPath $script:gameExe -Value '' -NoNewline
    }

    AfterEach {
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes FSO, GPU preference and CPU priority' {
        Invoke-GameExeApply -GamePath $script:gameExe -FsoKey $script:fsoKey -GpuKey $script:gpuKey -IfeoRoot $script:ifeoRoot -BackupFile $script:backupFile | Should -Be $true

        (Get-Item -LiteralPath $script:fsoKey).GetValue($script:gameExe) | Should -Match 'DISABLEDXMAXIMIZEDWINDOWEDMODE'
        (Get-Item -LiteralPath $script:gpuKey).GetValue($script:gameExe) | Should -Be 'GpuPreference=2;'
        $perf = Get-ItemProperty -LiteralPath (Join-Path $script:ifeoRoot 'game.exe\PerfOptions')
        [uint32]$perf.CpuPriorityClass | Should -Be 3
        (Test-Path -LiteralPath $script:backupFile) | Should -Be $true
    }

    It 'restores originals and removes values/keys it created' {
        Invoke-GameExeApply -GamePath $script:gameExe -FsoKey $script:fsoKey -GpuKey $script:gpuKey -IfeoRoot $script:ifeoRoot -BackupFile $script:backupFile | Should -Be $true
        Invoke-GameExeRestore -BackupFile $script:backupFile | Should -Be $true

        (Test-Path -LiteralPath $script:fsoKey) | Should -Be $false
        (Test-Path -LiteralPath $script:gpuKey) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $script:ifeoRoot 'game.exe\PerfOptions')) | Should -Be $false
    }

    It 'keeps pre-existing values on restore' {
        New-Item -Path $script:fsoKey -Force | Out-Null
        New-ItemProperty -Path $script:fsoKey -Name $script:gameExe -PropertyType String -Value '~ RUNASADMIN' -Force | Out-Null

        Invoke-GameExeApply -GamePath $script:gameExe -FsoKey $script:fsoKey -GpuKey $script:gpuKey -IfeoRoot $script:ifeoRoot -BackupFile $script:backupFile | Should -Be $true
        Invoke-GameExeRestore -BackupFile $script:backupFile | Should -Be $true

        (Get-Item -LiteralPath $script:fsoKey).GetValue($script:gameExe) | Should -Be '~ RUNASADMIN'
    }
}
