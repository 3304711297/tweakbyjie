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

    It "prunes empty parent key on restore when key originally did not exist" {
        $parentKey = 'HKCU:\Software\TweakByjieTest\AbsentParent'
        if (Test-Path $parentKey) { Remove-Item -Path $parentKey -Recurse -Force | Out-Null }
        (Test-Path $parentKey) | Should -Be $false

        $customCoreDefs = @()
        $customSysDefs = @(
            @{ Path = $parentKey; Name = 'TestVal'; Desc = 'test' }
        )

        # 建立快照时父键不存在
        $backupObj = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Core      = @()
            System    = @(
                [pscustomobject]@{ Path = $parentKey; Name = 'TestVal'; Exists = $false; Kind = $null; Data = $null; KeyExists = $false }
            )
        }

        # 模拟 Apply：创建了父键并写入了值
        New-Item -Path $parentKey -Force | Out-Null
        Set-ItemProperty -Path $parentKey -Name 'TestVal' -Value 1 -Type DWord -Force | Out-Null
        (Test-Path $parentKey) | Should -Be $true

        # 执行 Restore，父键应因属于新增且恢复后为空而被干净移除
        Restore-RegistryBackupRecords @($backupObj.System) '系统行为优化' | Out-Null
        (Test-Path $parentKey) | Should -Be $false
    }

    It "preserves parent key on restore when key originally existed" {
        $parentKey = 'HKCU:\Software\TweakByjieTest\ExistedParent'
        if (-not (Test-Path $parentKey)) { New-Item -Path $parentKey -Force | Out-Null }
        (Test-Path $parentKey) | Should -Be $true

        $backupObj = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Core      = @()
            System    = @(
                [pscustomobject]@{ Path = $parentKey; Name = 'TestVal'; Exists = $false; Kind = $null; Data = $null; KeyExists = $true }
            )
        }

        # 模拟 Apply 写入值
        Set-ItemProperty -Path $parentKey -Name 'TestVal' -Value 1 -Type DWord -Force | Out-Null

        # 执行 Restore：删除值，但保留原本就存在的父键
        Restore-RegistryBackupRecords @($backupObj.System) '系统行为优化' | Out-Null
        (Test-Path $parentKey) | Should -Be $true
        ((Get-Item $parentKey).GetValueNames() -contains 'TestVal') | Should -Be $false

        Remove-Item -Path 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
    }
}
