BeforeAll {
    $env:TWEAK_SKIP_ADMIN_CHECK = '1'
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "PCIe MSI Module Contract" {
    Context "Schema Validation" {
        It "validates a correct MSI backup structure" {
            $validBackup = [pscustomobject]@{
                Version   = 1
                Binding   = (Get-BackupMachineId)
                CreatedAt = (Get-Date).ToString('o')
                Devices   = @(
                    [pscustomobject]@{
                        InstanceId   = 'PCI\VEN_10DE&DEV_2820&SUBSYS_12731D05&REV_A1\4&1e862a78&0&0008'
                        DeviceDesc   = 'NVIDIA GeForce RTX 4070 Laptop GPU'
                        Class        = 'Display'
                        MSISupported = 1
                        MessageLimit = 1
                    }
                )
            }
            Test-MsiBackupSchema $validBackup | Should -Be $true
        }

        It "rejects invalid backup schema or mismatched machine binding" {
            $invalidBackup = [pscustomobject]@{
                Version = 1
                Binding = 'wrong-machine-guid'
                Devices = @()
            }
            Test-MsiBackupSchema $invalidBackup | Should -Be $false
            Test-MsiBackupSchema $null | Should -Be $false
        }
    }

    Context "Device Whitelist & Safety Filtering" {
        It "accepts Display, Net, and Storage controllers" {
            Test-MsiDeviceEligible 'Display' 'NVIDIA GeForce RTX 4070' | Should -Be $true
            Test-MsiDeviceEligible 'Net' 'MediaTek Wi-Fi 6E MT7922' | Should -Be $true
            Test-MsiDeviceEligible 'SCSIAdapter' 'Standard NVM Express Controller' | Should -Be $true
        }

        It "strictly excludes Audio, System, and PCI Bridge devices" {
            Test-MsiDeviceEligible 'MEDIA' 'High Definition Audio Controller' | Should -Be $false
            Test-MsiDeviceEligible 'System' 'Intel PCI Express Root Port' | Should -Be $false
            Test-MsiDeviceEligible 'Bridge' 'PCI standard PCI-to-PCI bridge' | Should -Be $false
        }
    }
}
