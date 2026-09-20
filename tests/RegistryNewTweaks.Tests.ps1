BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Registry new system tweaks contract" {
    It "contains the 4 new items in registrySystemValues" {
        $keys = @($script:registrySystemValues | ForEach-Object { "$($_.Path)|$($_.Name)" })
        $keys | Should -Contain 'HKLM:\SOFTWARE\Policies\Microsoft\MRT|DontOfferThroughWUAU'
        $keys | Should -Contain 'HKCU:\Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions'
        $keys | Should -Contain 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\EventLog-System\{b675ec37-bdb6-4648-bc92-f3fdc74d3ca2}|Enabled'
        $keys | Should -Contain 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem|NtfsDisableLastAccessUpdate'
    }

    It "uses 0x80000001 for modern NtfsDisableLastAccessUpdate bitfield semantics" {
        # 验证 Registry.ps1 中针对 NtfsDisableLastAccessUpdate 的写入值是 0x80000001
        $scriptPath = Join-Path $PSScriptRoot '../Modules/Registry.ps1'
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
        $scriptText | Should -Match 'Set-RegDword\s+["'']HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem["'']\s+["'']NtfsDisableLastAccessUpdate["'']\s+["'']?0x80000001["'']?'
    }

    It "migrates legacy registry snapshot seamlessly by appending missing definitions" {
        $legacyCoreDefs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\Migrate'; Name = 'CoreVal'; Desc = 'c' }
        )
        $legacySysDefs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\Migrate'; Name = 'SysVal1'; Desc = 's1' }
        )
        $newSysDefs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\Migrate'; Name = 'SysVal1'; Desc = 's1' }
            @{ Path = 'HKCU:\Software\TweakByjieTest\Migrate'; Name = 'SysVal2'; Desc = 's2' }
        )

        $key = 'HKCU:\Software\TweakByjieTest\Migrate'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name 'CoreVal' -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name 'SysVal1' -Value 10 -Type DWord
        Set-ItemProperty -Path $key -Name 'SysVal2' -Value 20 -Type DWord

        # 创建旧版备份对象（只包含 SysVal1，缺少 SysVal2）
        $legacyBackup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Core      = @([pscustomobject]@{ Path = $key; Name = 'CoreVal'; Exists = $true; Kind = 'DWord'; Data = 1 })
            System    = @([pscustomobject]@{ Path = $key; Name = 'SysVal1'; Exists = $true; Kind = 'DWord'; Data = 10 })
        }

        # 用旧版备份对象验证在传入新定义集合时，通过 Migrate-RegistryBackupIfNeeded 自动升级为合法结构
        $migrated = Migrate-RegistryBackupIfNeeded $legacyBackup $legacyCoreDefs $newSysDefs
        $migrated | Should -Not -BeNullOrEmpty
        Test-RegistryBackupSchema $migrated $legacyCoreDefs $newSysDefs | Should -Be $true
        ($migrated.System | Where-Object Name -eq 'SysVal2').Data | Should -Be 20

        Remove-Item -Path 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
    }
}
