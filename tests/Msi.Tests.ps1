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
            Test-MsiDeviceEligible 'Volume' 'Storage Volume' | Should -Be $false
            Test-MsiDeviceEligible 'DiskDrive' 'NVMe Disk' | Should -Be $false
            Test-MsiDeviceEligible 'Display' 'Intel High Definition Audio Root Port' | Should -Be $false
            Test-MsiDeviceEligible 'Net' 'PCI Express Host Bridge' | Should -Be $false
            Test-MsiDeviceEligible 'SCSIAdapter' 'Intel Serial IO I2C Host Controller' | Should -Be $false
            Test-MsiDeviceEligible '' 'NVIDIA RTX' | Should -Be $false
            Test-MsiDeviceEligible $null 'NVIDIA RTX' | Should -Be $false
        }
    }

    Context "Backup and Restore Flow (Temp Sandbox)" {
        BeforeAll {
            $script:OriginalBackupFile = $script:msiBackupFile
            $script:TestBackupFile = Join-Path $env:TEMP ("msi-test-backup-" + [guid]::NewGuid().ToString() + ".json")
            $script:msiBackupFile = $script:TestBackupFile
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:TestBackupFile) {
                Remove-Item -LiteralPath $script:TestBackupFile -Force -ErrorAction SilentlyContinue
            }
            $script:msiBackupFile = $script:OriginalBackupFile
        }

        It "Restore-MsiBackup fails cleanly when backup file does not exist" {
            $beforeFail = $script:fail
            Restore-MsiBackup | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }

        It "Ensure-MsiBackup creates a valid backup snapshot and is idempotent" {
            Mock Get-MsiManagedDevices {
                return @(
                    [pscustomobject]@{
                        InstanceId   = 'PCI\TEST_GPU\001'
                        DeviceDesc   = 'Mocked GPU'
                        Class        = 'Display'
                        MSISupported = [uint32]1
                        MessageLimit = [uint32]1
                        RegPath      = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\TEST_GPU\001\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
                    }
                )
            }

            Ensure-MsiBackup | Should -Be $true
            Test-Path -LiteralPath $script:TestBackupFile | Should -Be $true

            # Idempotency check: should reuse existing valid backup
            Ensure-MsiBackup | Should -Be $true
        }

        It "Restore-MsiBackup rejects corrupted or mismatched snapshot" {
            Set-Content -LiteralPath $script:TestBackupFile -Value '{"Version": 999}' -Encoding UTF8
            $beforeFail = $script:fail
            Restore-MsiBackup | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }
    }

    Context "Invoke-MsiModule Dispatcher" {
        BeforeAll {
            $script:OriginalBackupFile = $script:msiBackupFile
            $script:TestBackupFile = Join-Path $env:TEMP ("msi-test-module-" + [guid]::NewGuid().ToString() + ".json")
            $script:msiBackupFile = $script:TestBackupFile
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:TestBackupFile) {
                Remove-Item -LiteralPath $script:TestBackupFile -Force -ErrorAction SilentlyContinue
            }
            $script:msiBackupFile = $script:OriginalBackupFile
        }

        It "Action 0 executes in read-only mode and returns true" {
            Invoke-MsiModule -Action '0' | Should -Be $true
        }

        It "Action with invalid input fails cleanly" {
            $beforeFail = $script:fail
            Invoke-MsiModule -Action 'invalid-action' | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }

        It "Action empty in non-interactive mode fails cleanly" {
            $script:TweakNonInteractive = $true
            try {
                $beforeFail = $script:fail
                Invoke-MsiModule -Action '' | Should -Be $false
                $script:fail | Should -BeGreaterThan $beforeFail
            } finally {
                $script:TweakNonInteractive = $false
            }
        }

        It "Action 1 applies MSI settings with backup and restart request" {
            Mock Ensure-MsiBackup { return $true }
            Mock Get-MsiManagedDevices {
                return @(
                    [pscustomobject]@{
                        InstanceId   = 'PCI\TEST_GPU\001'
                        DeviceDesc   = 'Mocked GPU'
                        Class        = 'Display'
                        MSISupported = $null
                        MessageLimit = $null
                        RegPath      = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\TEST_GPU\001\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
                    }
                )
            }
            Mock Set-RegDword { }
            Mock Verify-RegDword { return $true }
            Mock Request-Restart { }

            Invoke-MsiModule -Action '1' | Should -Be $true
        }

        It "Action 1 triggers rollback when verification fails" {
            Mock Ensure-MsiBackup { return $true }
            Mock Get-MsiManagedDevices {
                return @(
                    [pscustomobject]@{
                        InstanceId   = 'PCI\TEST_GPU\001'
                        DeviceDesc   = 'Mocked GPU'
                        Class        = 'Display'
                        MSISupported = $null
                        MessageLimit = $null
                        RegPath      = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\TEST_GPU\001\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
                    }
                )
            }
            Mock Set-RegDword { }
            Mock Verify-RegDword { return $false }
            Mock Restore-MsiBackup { return $true }

            $beforeFail = $script:fail
            Invoke-MsiModule -Action '1' | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }

        It "Action 2 restores MSI configuration" {
            Mock Restore-MsiBackup { return $true }
            Mock Request-Restart { }

            Invoke-MsiModule -Action '2' | Should -Be $true
        }
    }
}
