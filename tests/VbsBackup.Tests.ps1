BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "VBS backup schema" {
    BeforeAll {
        $defs = @(
            @{ Path = 'HKCU:\Software\TweakByjieTest\Vbs'; Name = 'Enabled'; Desc = 'HVCI' },
            @{ Path = 'HKCU:\Software\TweakByjieTest\Vbs'; Name = 'AbsentValue'; Desc = 'absent' }
        )
        $bcdNames = @('hypervisorlaunchtype','isolatedcontext')
        $featureNames = @('FakeFeature')
        $valid = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            CreatedAt = '2026-08-26T00:00:00.0000000Z'
            Registry = @(
                [pscustomobject]@{ Path = $defs[0].Path; Name = 'Enabled'; Present = $true; Value = [uint32]1 }
                [pscustomobject]@{ Path = $defs[1].Path; Name = 'AbsentValue'; Present = $false; Value = $null }
            )
            Bcd = @(
                [pscustomobject]@{ Name = 'hypervisorlaunchtype'; Present = $true; Value = 'Auto' }
                [pscustomobject]@{ Name = 'isolatedcontext'; Present = $false; Value = $null }
            )
            Features = @([pscustomobject]@{ Name = 'FakeFeature'; Present = $false; State = $null })
        }
    }

    It "rejects null and wrong version" {
        Test-VbsBackupSchema $null $defs $bcdNames $featureNames | Should -Be $false
        $bad = [pscustomobject]@{ Version = 99 }
        Test-VbsBackupSchema $bad $defs $bcdNames $featureNames | Should -Be $false
    }

    It "accepts a valid snapshot" {
        Test-VbsBackupSchema $valid $defs $bcdNames $featureNames | Should -Be $true
    }

    It "rejects foreign registry records" {
        $bad = [pscustomobject]@{
            Version = 1
            Registry = @(
                [pscustomobject]@{ Path = 'HKCU:\Software\Foreign'; Name = 'Enabled'; Present = $true; Value = [uint32]1 }
                [pscustomobject]@{ Path = $defs[1].Path; Name = 'AbsentValue'; Present = $false; Value = $null }
            )
            Bcd = $valid.Bcd
            Features = $valid.Features
        }
        Test-VbsBackupSchema $bad $defs $bcdNames $featureNames | Should -Be $false
    }

    It "rejects command-like BCD values and unknown names" {
        $badBcd = @(
            [pscustomobject]@{ Name = 'hypervisorlaunchtype'; Present = $true; Value = 'Off /set nx AlwaysOff' }
            [pscustomobject]@{ Name = 'isolatedcontext'; Present = $false; Value = $null }
        )
        $bad = [pscustomobject]@{ Version = 1; Registry = $valid.Registry; Bcd = $badBcd; Features = $valid.Features }
        Test-VbsBackupSchema $bad $defs $bcdNames $featureNames | Should -Be $false

        $unknownBcd = @(
            [pscustomobject]@{ Name = 'nx'; Present = $true; Value = 'AlwaysOff' }
            [pscustomobject]@{ Name = 'isolatedcontext'; Present = $false; Value = $null }
        )
        $bad2 = [pscustomobject]@{ Version = 1; Registry = $valid.Registry; Bcd = $unknownBcd; Features = $valid.Features }
        Test-VbsBackupSchema $bad2 $defs $bcdNames $featureNames | Should -Be $false
    }
}

Describe "VBS backup/restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $key = 'HKCU:\Software\TweakByjieTest\Vbs'
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Enabled' -PropertyType DWord -Value 1 -Force | Out-Null

        $defs = @(
            @{ Path = $key; Name = 'Enabled'; Desc = 'HVCI' },
            @{ Path = $key; Name = 'RequirePlatformSecurityFeatures'; Desc = 'policy' }
        )
        $bcdNames = @('hypervisorlaunchtype','vsmlaunchtype','isolatedcontext')
        $featureNames = @('FakeHyperVFeature')

        # Feature 快照改为封闭式 mock：真实 Get-WindowsOptionalFeature 依赖 DISM COM，
        # 在 DISM 组件注册异常的机器上会以"没有注册类"失败并超时约 2 分钟,
        # 使本用例变成环境依赖测试;restore 用例本就 mock 了 Enable/Disable 同款命令。
        # 返回 $null 模拟"功能未安装"（Get-VbsFeatureSnapshot 把返回对象视为 Present=$true）
        Mock Get-WindowsOptionalFeature -ParameterFilter { $FeatureName -eq 'FakeHyperVFeature' } { $null }

        Mock bcdedit.exe {
            $global:LASTEXITCODE = 0
            @('Windows Boot Loader', '---------------------', 'hypervisorlaunchtype    Auto')
        }
        $script:vbsBackupFileReal = $script:vbsBackupFile
        $script:vbsBackupFile = Join-Path $TestDrive 'vbs-backup.json'
    }

    AfterAll {
        Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:vbsBackupFileReal) { $script:vbsBackupFile = $script:vbsBackupFileReal }
    }

    It "Ensure captures registry, BCD and feature states" {
        Ensure-VbsBackup -RegistryDefinitions $defs -BcdNames $bcdNames -FeatureNames $featureNames | Should -Be $true
        $backup = Get-Content $script:vbsBackupFile -Raw | ConvertFrom-Json
        ($backup.Registry | Where-Object Name -eq 'Enabled').Present | Should -Be $true
        [uint32]($backup.Registry | Where-Object Name -eq 'Enabled').Value | Should -Be 1
        ($backup.Registry | Where-Object Name -eq 'RequirePlatformSecurityFeatures').Present | Should -Be $false
        ($backup.Bcd | Where-Object Name -eq 'hypervisorlaunchtype').Present | Should -Be $true
        ($backup.Bcd | Where-Object Name -eq 'hypervisorlaunchtype').Value | Should -Be 'Auto'
        ($backup.Bcd | Where-Object Name -eq 'vsmlaunchtype').Present | Should -Be $false
        ($backup.Features | Where-Object Name -eq 'FakeHyperVFeature').Present | Should -Be $false
    }

    It "Restore brings registry back and restores BCD values from snapshot" {
        Set-ItemProperty -Path $key -Name 'Enabled' -Value 0
        New-ItemProperty -Path $key -Name 'RequirePlatformSecurityFeatures' -PropertyType DWord -Value 3 -Force | Out-Null
        Mock Invoke-BcdEdit { return $true }
        Mock Remove-BcdValue { }
        Mock Enable-WindowsOptionalFeature { }
        Mock Disable-WindowsOptionalFeature { }

        Restore-VbsBackup -RegistryDefinitions $defs -BcdNames $bcdNames -FeatureNames $featureNames | Should -Be $true

        [uint32](Get-ItemProperty -Path $key -Name 'Enabled').Enabled | Should -Be 1
        (Get-Item $key).GetValueNames() -contains 'RequirePlatformSecurityFeatures' | Should -Be $false
        Should -Invoke Invoke-BcdEdit -Times 1 -ParameterFilter { $Arguments -match 'set hypervisorlaunchtype Auto' }
        Should -Invoke Remove-BcdValue -Times 2
        Should -Invoke Enable-WindowsOptionalFeature -Times 0
        Should -Invoke Disable-WindowsOptionalFeature -Times 0
    }
}

Describe "VBS module guards with backup" {

    It "Invoke-VbsModule option 1 aborts all modifications when backup fails" {
        Mock Read-Host { return '1' }
        Mock Ensure-VbsBackup { return $false }
        Mock Set-RegDword { }
        Mock Get-WindowsOptionalFeature { return [pscustomobject]@{ State = 'Disabled' } }
        Mock Invoke-BcdEdit { return $true }
        Mock Verify-BcdValue { return $true }
        Mock Request-Restart { }
        Invoke-VbsModule | Out-Null
        Should -Invoke Set-RegDword -Times 0
        Should -Invoke Invoke-BcdEdit -Times 0
    }

    It "Invoke-VbsModule option 3 restores from snapshot" {
        Mock Read-Host { return '3' }
        Mock Restore-VbsBackup { return $true }
        Mock Request-Restart { }
        Invoke-VbsModule | Out-Null
        Should -Invoke Restore-VbsBackup -Times 1
    }
}
