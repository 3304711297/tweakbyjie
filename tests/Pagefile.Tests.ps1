# Pagefile.Tests.ps1 - 虚拟内存 (Pagefile) 只读诊断与配置建议模块测试
# 遵守绝对只读原则：任何情况下不得自动化修改页面文件设置

BeforeAll {
    $env:TWEAK_SKIP_ADMIN_CHECK = '1'
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
    . "$PSScriptRoot/../Modules/Pagefile.ps1"
}

Describe "Pagefile Module Contract & Existence" {
    It "exports required diagnostic and recommendation functions" {
        Get-Command 'Get-PagefileStatus' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command 'Get-PagefileRecommendations' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command 'Invoke-PagefileModule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-PagefileStatus Diagnostic Probing" {
    It "correctly parses physical memory, managed state, and pagefiles with injected mocks" {
        $mockCs = [pscustomobject]@{
            TotalPhysicalMemory      = 17179869184 # 16 GB
            AutomaticManagedPagefile = $true
        }
        $mockSettings = @(
            [pscustomobject]@{
                Name        = 'C:\pagefile.sys'
                InitialSize = 0
                MaximumSize = 0
            }
        )
        $mockUsage = @(
            [pscustomobject]@{
                Name              = 'C:\pagefile.sys'
                AllocatedBaseSize = 2048
                CurrentUsage      = 128
                PeakUsage         = 512
            }
        )
        $mockVolumes = @(
            [pscustomobject]@{
                DeviceID   = 'C:'
                FreeSpace  = 53687091200  # 50 GB
                Size       = 107374182400 # 100 GB
                FileSystem = 'NTFS'
                DriveType  = 3
            },
            [pscustomobject]@{
                DeviceID   = 'D:'
                FreeSpace  = 214748364800 # 200 GB
                Size       = 536870912000 # 500 GB
                FileSystem = 'NTFS'
                DriveType  = 3
            }
        )
        $mockRegPaging = @('c:\pagefile.sys 0 0')

        $status = Get-PagefileStatus -ComputerSystem $mockCs `
                                     -PageFileSettings $mockSettings `
                                     -PageFileUsage $mockUsage `
                                     -Volumes $mockVolumes `
                                     -RegistryPagingFiles $mockRegPaging

        $status | Should -Not -BeNullOrEmpty
        $status.TotalPhysicalMemoryBytes | Should -Be 17179869184
        $status.TotalPhysicalMemoryGB | Should -Be 16
        $status.AutomaticManagedPagefile | Should -Be $true
        $status.PageFiles.Count | Should -Be 1
        $status.PageFiles[0].Drive | Should -Be 'C:'
        $status.PageFiles[0].InitialSizeMB | Should -Be 0
        $status.PageFiles[0].MaximumSizeMB | Should -Be 0
        $status.PageFiles[0].AllocatedBaseSizeMB | Should -Be 2048
        $status.Volumes.Count | Should -Be 2
        $status.Volumes[0].DriveLetter | Should -Be 'C:'
        $status.Volumes[0].IsSystemDrive | Should -Be $true
        $status.Volumes[1].DriveLetter | Should -Be 'D:'
        $status.Volumes[1].IsSystemDrive | Should -Be $false
    }

    It "correctly handles multi-disk custom pagefile settings" {
        $mockCs = [pscustomobject]@{
            TotalPhysicalMemory      = 34359738368 # 32 GB
            AutomaticManagedPagefile = $false
        }
        $mockSettings = @(
            [pscustomobject]@{
                Name        = 'D:\pagefile.sys'
                InitialSize = 32768
                MaximumSize = 32768
            }
        )
        $mockUsage = @(
            [pscustomobject]@{
                Name              = 'D:\pagefile.sys'
                AllocatedBaseSize = 32768
                CurrentUsage      = 100
                PeakUsage         = 200
            }
        )
        $mockVolumes = @(
            [pscustomobject]@{
                DeviceID   = 'C:'
                FreeSpace  = 107374182400
                Size       = 214748364800
                FileSystem = 'NTFS'
                DriveType  = 3
            },
            [pscustomobject]@{
                DeviceID   = 'D:'
                FreeSpace  = 536870912000
                Size       = 1073741824000
                FileSystem = 'NTFS'
                DriveType  = 3
            }
        )
        $mockRegPaging = @('d:\pagefile.sys 32768 32768')

        $status = Get-PagefileStatus -ComputerSystem $mockCs `
                                     -PageFileSettings $mockSettings `
                                     -PageFileUsage $mockUsage `
                                     -Volumes $mockVolumes `
                                     -RegistryPagingFiles $mockRegPaging

        $status.AutomaticManagedPagefile | Should -Be $false
        $status.TotalPhysicalMemoryGB | Should -Be 32
        $status.PageFiles.Count | Should -Be 1
        $status.PageFiles[0].Drive | Should -Be 'D:'
        $status.PageFiles[0].InitialSizeMB | Should -Be 32768
        $status.PageFiles[0].MaximumSizeMB | Should -Be 32768
        $status.PageFiles[0].IsSystemDrive | Should -Be $false
    }

    It "parses registry entries when WMI pagefile objects are empty" {
        $mockCs = [pscustomobject]@{
            TotalPhysicalMemory      = 17179869184
            AutomaticManagedPagefile = $false
        }
        $mockRegPaging = @('c:\pagefile.sys 4096 8192', 'e:\pagefile.sys 16384 16384')

        $status = Get-PagefileStatus -ComputerSystem $mockCs `
                                     -PageFileSettings @() `
                                     -PageFileUsage @() `
                                     -Volumes @() `
                                     -RegistryPagingFiles $mockRegPaging

        $status.PageFiles.Count | Should -Be 2
        $status.PageFiles[0].Path | Should -Be 'c:\pagefile.sys'
        $status.PageFiles[0].InitialSizeMB | Should -Be 4096
        $status.PageFiles[0].MaximumSizeMB | Should -Be 8192
        $status.PageFiles[1].Path | Should -Be 'e:\pagefile.sys'
        $status.PageFiles[1].InitialSizeMB | Should -Be 16384
        $status.PageFiles[1].MaximumSizeMB | Should -Be 16384
    }

    It "probes live system without errors when no mock parameters are provided" {
        $liveStatus = Get-PagefileStatus
        $liveStatus | Should -Not -BeNullOrEmpty
        $liveStatus.TotalPhysicalMemoryGB | Should -BeGreaterThan 0
        $liveStatus.Volumes | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-PagefileRecommendations Calculation Rules" {
    Context "RAM <= 16GB tier: 1.5x initial, 2.0x~3.0x max" {
        It "calculates correct recommendation for 8GB RAM" {
            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 8
            $rec.Tier | Should -Be '<=16GB'
            $rec.RecommendedInitialMB | Should -Be 12288 # 8 * 1024 * 1.5
            $rec.RecommendedMaximumMB | Should -Be 24576 # 8 * 1024 * 3.0
            $rec.AntiFragmentationInitialMB | Should -Be 12288
            $rec.AntiFragmentationMaximumMB | Should -Be 12288
            $rec.RecommendedInitialMB | Should -Be $rec.AntiFragmentationInitialMB
        }

        It "calculates correct recommendation for 16GB RAM" {
            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 16
            $rec.Tier | Should -Be '<=16GB'
            $rec.RecommendedInitialMB | Should -Be 24576 # 16 * 1024 * 1.5
            $rec.RecommendedMaximumMB | Should -Be 49152 # 16 * 1024 * 3.0
            $rec.AntiFragmentationInitialMB | Should -Be 24576
            $rec.AntiFragmentationMaximumMB | Should -Be 24576
        }
    }

    Context "RAM 24GB~32GB tier: 1.0x~1.5x initial, 1.5x~2.0x max (or fixed 32GB~48GB)" {
        It "calculates correct recommendation for 24GB RAM" {
            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 24
            $rec.Tier | Should -Be '24GB~32GB'
            $rec.RecommendedInitialMB | Should -BeGreaterOrEqual 24576
            $rec.RecommendedInitialMB | Should -BeLessOrEqual 36864
            $rec.RecommendedMaximumMB | Should -BeGreaterOrEqual 36864
            $rec.RecommendedMaximumMB | Should -BeLessOrEqual 49152
            $rec.AntiFragmentationInitialMB | Should -Be $rec.AntiFragmentationMaximumMB
            $rec.AntiFragmentationInitialMB | Should -BeGreaterOrEqual 24576
            $rec.AntiFragmentationInitialMB | Should -BeLessOrEqual 49152
        }

        It "calculates correct recommendation for 32GB RAM" {
            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 32
            $rec.Tier | Should -Be '24GB~32GB'
            $rec.RecommendedInitialMB | Should -BeGreaterOrEqual 32768
            $rec.RecommendedInitialMB | Should -BeLessOrEqual 49152
            $rec.RecommendedMaximumMB | Should -BeGreaterOrEqual 49152
            $rec.RecommendedMaximumMB | Should -BeLessOrEqual 65536
            $rec.AntiFragmentationInitialMB | Should -Be $rec.AntiFragmentationMaximumMB
            $rec.AntiFragmentationInitialMB | Should -BeGreaterOrEqual 32768
            $rec.AntiFragmentationInitialMB | Should -BeLessOrEqual 49152
        }
    }

    Context "RAM >= 64GB tier: fixed 16GB~24GB initial, 32GB~48GB max" {
        It "calculates correct recommendation for 64GB RAM" {
            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 64
            $rec.Tier | Should -Be '>=64GB'
            $rec.RecommendedInitialMB | Should -BeGreaterOrEqual 16384 # 16 GB
            $rec.RecommendedInitialMB | Should -BeLessOrEqual 24576    # 24 GB
            $rec.RecommendedMaximumMB | Should -BeGreaterOrEqual 32768 # 32 GB
            $rec.RecommendedMaximumMB | Should -BeLessOrEqual 49152    # 48 GB
            $rec.AntiFragmentationInitialMB | Should -Be $rec.AntiFragmentationMaximumMB
            $rec.AntiFragmentationInitialMB | Should -BeGreaterOrEqual 16384
            $rec.AntiFragmentationInitialMB | Should -BeLessOrEqual 24576
        }

        It "calculates correct recommendation for 128GB RAM" {
            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 128
            $rec.Tier | Should -Be '>=64GB'
            $rec.RecommendedInitialMB | Should -BeGreaterOrEqual 16384
            $rec.RecommendedInitialMB | Should -BeLessOrEqual 24576
            $rec.RecommendedMaximumMB | Should -BeGreaterOrEqual 32768
            $rec.RecommendedMaximumMB | Should -BeLessOrEqual 49152
            $rec.AntiFragmentationInitialMB | Should -Be $rec.AntiFragmentationMaximumMB
        }
    }

    Context "Drive Partition & Anti-Fragmentation Planning" {
        It "recommends placing pagefile on secondary SSD (D:) and disabling C: paging when D: is available" {
            $mockVolumes = @(
                [pscustomobject]@{
                    DeviceID   = 'C:'
                    FreeSpace  = 64424509440  # 60 GB
                    Size       = 128849018880 # 120 GB
                    FileSystem = 'NTFS'
                    DriveType  = 3
                },
                [pscustomobject]@{
                    DeviceID   = 'D:'
                    FreeSpace  = 214748364800 # 200 GB
                    Size       = 536870912000 # 500 GB
                    FileSystem = 'NTFS'
                    DriveType  = 3
                }
            )

            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 32 -Volumes $mockVolumes
            $rec.RecommendedDrive | Should -Be 'D:'
            $rec.DisableSystemDrivePagefile | Should -Be $true
            $rec.DriveAdvice | Should -Match 'D:'
            $rec.AntiFragmentationAdvice | Should -Match '相同'
        }

        It "falls back to system drive C: when secondary drive D: has insufficient free space" {
            $mockVolumesLowSpaceD = @(
                [pscustomobject]@{
                    DeviceID   = 'C:'
                    FreeSpace  = 107374182400 # 100 GB
                    Size       = 536870912000 # 500 GB
                    FileSystem = 'NTFS'
                    DriveType  = 3
                },
                [pscustomobject]@{
                    DeviceID   = 'D:'
                    FreeSpace  = 2147483648   # 2 GB (不足以承载页面文件)
                    Size       = 536870912000 # 500 GB
                    FileSystem = 'NTFS'
                    DriveType  = 3
                }
            )

            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 32 -Volumes $mockVolumesLowSpaceD
            $rec.RecommendedDrive | Should -Be 'C:'
            $rec.DisableSystemDrivePagefile | Should -Be $false
        }

        It "recommends keeping pagefile on C: with anti-fragmentation settings when only C: exists" {
            $mockVolumesOnlyC = @(
                [pscustomobject]@{
                    DeviceID   = 'C:'
                    FreeSpace  = 107374182400 # 100 GB
                    Size       = 536870912000 # 500 GB
                    FileSystem = 'NTFS'
                    DriveType  = 3
                }
            )

            $rec = Get-PagefileRecommendations -TotalPhysicalMemoryGB 16 -Volumes $mockVolumesOnlyC
            $rec.RecommendedDrive | Should -Be 'C:'
            $rec.DisableSystemDrivePagefile | Should -Be $false
            $rec.DriveAdvice | Should -Match 'C:'
        }
    }
}

Describe "Invoke-PagefileModule Read-Only Safety and Dispatcher" {
    It "strictly executes read-only inspection and NEVER modifies registry or system state" {
        $adapterWrites = [System.Collections.Generic.List[string]]::new()
        Set-TweakAdapters -SetRegistryDword {
            param($Path, $Name, $Value)
            $adapterWrites.Add("SetRegistryDword:$($Path):$($Name)=$Value")
            return $true
        } -SetRegistryString {
            param($Path, $Name, $Value)
            $adapterWrites.Add("SetRegistryString:$($Path):$($Name)=$Value")
        } -SetRegistryBinary {
            param($Path, $Name, $Hex)
            $adapterWrites.Add("SetRegistryBinary:$($Path):$($Name)=$Hex")
        } -RemoveRegistryValue {
            param($Path, $Name)
            $adapterWrites.Add("RemoveRegistryValue:$($Path):$($Name)")
        } -InvokeBcd {
            param($BcdArgs)
            $adapterWrites.Add("InvokeBcd:$BcdArgs")
            return $true
        }

        $initFail = $script:fail
        $initOk = $script:ok

        $result = Invoke-PagefileModule -Action '0'

        $adapterWrites.Count | Should -Be 0
        $script:fail | Should -Be $initFail
        $script:ok | Should -Be $initOk
        $result | Should -Not -BeNullOrEmpty

        Initialize-TweakAdapters
    }

    It "provides sysdm.cpl GUI guidance and manual PowerShell reference command" {
        $status = Get-PagefileStatus
        $rec = Get-PagefileRecommendations -CurrentStatus $status

        $rec.GuiGuide | Should -Not -BeNullOrEmpty
        $rec.GuiGuide.RunCommand | Should -Be 'sysdm.cpl'
        $rec.GuiGuide.Steps | Should -Match '高级'
        $rec.GuiGuide.Steps | Should -Match '虚拟内存'

        $rec.ManualPowerShellCommand | Should -Not -BeNullOrEmpty
        $rec.ManualPowerShellCommand | Should -Match 'Win32_PageFileSetting'
    }
}
