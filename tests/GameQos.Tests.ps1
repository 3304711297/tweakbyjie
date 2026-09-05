BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "GameQoS backup schema validation" {
    It "rejects null and malformed snapshots" {
        Test-GameQosBackupSchema $null | Should -Be $false
        Test-GameQosBackupSchema @{ Version = "2.0"; Policies = @{} } | Should -Be $false
        Test-GameQosBackupSchema @{ Version = "1.0" } | Should -Be $false
    }

    It "accepts valid snapshot" {
        $valid = [pscustomobject]@{
            Version   = "1.0"
            CreatedAt = (Get-Date).ToString("o")
            Policies  = @{
                "CS2" = @{ "Application Name" = "cs2.exe"; "DSCP Value" = "46" }
            }
        }
        Test-GameQosBackupSchema $valid | Should -Be $true
    }
}

Describe "GameQoS round-trip backup and restore (HKCU Sandbox)" {
    BeforeAll {
        $script:SandboxRoot = "HKCU:\Software\TweakByjieTest\QoS"
        if (Test-Path $script:SandboxRoot) {
            Remove-Item -Path $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:SandboxRoot -Force | Out-Null

        $script:TestBackup = "$env:TEMP\pester-gameqos-test.json"
        if (Test-Path $script:TestBackup) {
            Remove-Item -Path $script:TestBackup -Force -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        if (Test-Path $script:SandboxRoot) {
            Remove-Item -Path $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:TestBackup) {
            Remove-Item -Path $script:TestBackup -Force -ErrorAction SilentlyContinue
        }
    }

    It "creates backup, applies policies, and restores cleanly" {
        $preKey = Join-Path $script:SandboxRoot "PreExistingPolicy"
        New-Item -Path $preKey -Force | Out-Null
        Set-ItemProperty -Path $preKey -Name "Application Name" -Value "custom.exe" -Type String -Force | Out-Null
        Set-ItemProperty -Path $preKey -Name "DSCP Value" -Value "32" -Type String -Force | Out-Null

        $backupOk = Ensure-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot
        $backupOk | Should -Be $true
        Test-Path $script:TestBackup | Should -Be $true

        Set-SingleGameQosPolicy -PolicyName "CS2" -ExeName "cs2.exe" -RegistryBasePath $script:SandboxRoot
        Set-SingleGameQosPolicy -PolicyName "Valorant" -ExeName "VALORANT-Win64-Shipping.exe" -RegistryBasePath $script:SandboxRoot

        (Test-Path (Join-Path $script:SandboxRoot "CS2")) | Should -Be $true
        $cs2Props = Get-ItemProperty -Path (Join-Path $script:SandboxRoot "CS2")
        $cs2Props."DSCP Value" | Should -Be "46"
        $cs2Props."Application Name" | Should -Be "cs2.exe"
        $cs2Props."Throttle Rate" | Should -Be "-1"

        $managedNames = @("CS2", "Valorant", "ApexLegends")
        $restoreOk = Restore-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot -ManagedPolicyNames $managedNames
        $restoreOk | Should -Be $true

        (Test-Path (Join-Path $script:SandboxRoot "CS2")) | Should -Be $false
        (Test-Path (Join-Path $script:SandboxRoot "Valorant")) | Should -Be $false
        (Test-Path $preKey) | Should -Be $true
        $preRestored = Get-ItemProperty -Path $preKey
        $preRestored."DSCP Value" | Should -Be "32"
    }
}

Describe "GameQoS fail-closed semantics" {
    BeforeAll {
        . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null

        $script:SandboxRoot = "HKCU:\Software\TweakByjieTest\QoSFailClosed"
        if (Test-Path $script:SandboxRoot) {
            Remove-Item -Path $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:SandboxRoot -Force | Out-Null

        $script:TestBackup = "$env:TEMP\pester-gameqos-failclosed.json"
        if (Test-Path $script:TestBackup) {
            Remove-Item -Path $script:TestBackup -Force -ErrorAction SilentlyContinue
        }
    }

    AfterAll {
        if (Test-Path $script:SandboxRoot) {
            Remove-Item -Path $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:TestBackup) {
            Remove-Item -Path $script:TestBackup -Force -ErrorAction SilentlyContinue
        }
    }

    It "restore reports failure when writing a policy value fails" {
        $preKey = Join-Path $script:SandboxRoot "PreExistingPolicy"
        New-Item -Path $preKey -Force | Out-Null
        Set-ItemProperty -Path $preKey -Name "DSCP Value" -Value "32" -Type String -Force | Out-Null
        Ensure-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot | Should -Be $true

        # 制造一个待清理的托管键，清理本身应正常完成
        Set-SingleGameQosPolicy -PolicyName "CS2" -ExeName "cs2.exe" -RegistryBasePath $script:SandboxRoot

        Mock Set-ItemProperty { throw "模拟写入失败" }
        $restoreOk = Restore-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot -ManagedPolicyNames @("CS2")
        $restoreOk | Should -Be $false
    }

    It "restore reports failure when cleanup of an existing managed key fails" {
        $preKey = Join-Path $script:SandboxRoot "PreExistingPolicy2"
        New-Item -Path $preKey -Force | Out-Null
        Set-ItemProperty -Path $preKey -Name "DSCP Value" -Value "32" -Type String -Force | Out-Null
        Ensure-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot | Should -Be $true

        Set-SingleGameQosPolicy -PolicyName "CS2" -ExeName "cs2.exe" -RegistryBasePath $script:SandboxRoot

        Mock Remove-Item { throw "模拟删除失败" }
        $restoreOk = Restore-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot -ManagedPolicyNames @("CS2")
        $restoreOk | Should -Be $false
    }

    It "cleanup-only restore without backup file reports failure when removal fails" {
        Set-SingleGameQosPolicy -PolicyName "Valorant" -ExeName "VALORANT-Win64-Shipping.exe" -RegistryBasePath $script:SandboxRoot

        Mock Remove-Item { throw "模拟删除失败" }
        $restoreOk = Restore-GameQosBackup -BackupFile "$env:TEMP\pester-gameqos-not-exist.json" -RegistryBasePath $script:SandboxRoot -ManagedPolicyNames @("Valorant")
        $restoreOk | Should -Be $false
    }

    It "restore reports failure when creating a policy key fails" {
        $preKey = Join-Path $script:SandboxRoot "PreExistingPolicy3"
        New-Item -Path $preKey -Force | Out-Null
        Set-ItemProperty -Path $preKey -Name "DSCP Value" -Value "32" -Type String -Force | Out-Null
        Ensure-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot | Should -Be $true

        # 移除现有键，使恢复过程必须重新创建目标键
        Remove-Item -Path $preKey -Recurse -Force

        # 清理后目标键不存在，需要重新创建；模拟创建失败必须让恢复判定为失败
        Mock New-Item { throw "模拟创建失败" }
        $restoreOk = Restore-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot -ManagedPolicyNames @()
        $restoreOk | Should -Be $false
    }

    It "backup aborts with failure when policy enumeration fails" {
        if (Test-Path $script:TestBackup) {
            Remove-Item -Path $script:TestBackup -Force -ErrorAction SilentlyContinue
        }
        Mock Get-ChildItem { throw "模拟枚举失败" }
        $backupOk = Ensure-GameQosBackup -BackupFile $script:TestBackup -RegistryBasePath $script:SandboxRoot
        $backupOk | Should -Be $false
        Test-Path $script:TestBackup | Should -Be $false
    }
}
