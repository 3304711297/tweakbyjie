BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe 'PCIe link diagnostics' {
    It 'reports a full x16 link as OK' {
        $r = Get-PcieLinkStatus -NvidiaSmiOutput '4, 16, 4, 16'
        $r.Status | Should -Be 'OK'
        $r.MaxWidth | Should -Be 16
        $r.Summary | Should -Match 'x16'
    }

    It 'flags an x4 link as Attention' {
        $r = Get-PcieLinkStatus -NvidiaSmiOutput '4, 4, 4, 4'
        $r.Status | Should -Be 'Attention'
        $r.Summary | Should -Match 'x4'
    }

    It 'treats x8 as informational, not a fault' {
        $r = Get-PcieLinkStatus -NvidiaSmiOutput '4, 8, 4, 8'
        $r.Status | Should -Be 'Info'
        $r.Summary | Should -Match 'x8'
    }

    It 'explains idle down-clocking without flagging it' {
        $r = Get-PcieLinkStatus -NvidiaSmiOutput '4, 16, 1, 16'
        $r.Status | Should -Be 'OK'
        $r.Summary | Should -Match '空闲'
    }

    It 'returns N/A when nvidia-smi is unavailable' {
        $r = Get-PcieLinkStatus -NvidiaSmiOutput ''
        $r.Status | Should -Be 'N/A'
    }
}

Describe 'VC++ v14 runtime diagnostics' {
    It 'flags a missing x86 runtime' {
        $r = Get-VcRedistStatus -RuntimeKeys @{
            x64 = @{ Installed = 1; Version = '14.44.35211' }
            x86 = $null
        }
        $r.Status | Should -Be 'Attention'
        $r.Summary | Should -Match 'x86'
    }

    It 'passes when both architectures are installed' {
        $r = Get-VcRedistStatus -RuntimeKeys @{
            x64 = @{ Installed = 1; Version = '14.44.35211' }
            x86 = @{ Installed = 1; Version = '14.44.35211' }
        }
        $r.Status | Should -Be 'OK'
    }

    It 'only informs on x64/x86 version skew' {
        $r = Get-VcRedistStatus -RuntimeKeys @{
            x64 = @{ Installed = 1; Version = '14.44.35211' }
            x86 = @{ Installed = 1; Version = '14.38.33135' }
        }
        $r.Status | Should -Be 'Info'
        $r.Summary | Should -Match '不同步'
    }
}

Describe 'Memory frequency diagnostics' {
    It 'flags memory running below its rated speed' {
        $r = Get-MemoryFrequencyStatus -Modules @(
            [pscustomobject]@{ Speed = 6000; ConfiguredClockSpeed = 4800; Manufacturer = 'Test'; PartNumber = 'X' }
        )
        $r.Status | Should -Be 'Attention'
        $r.Summary | Should -Match '4800'
    }

    It 'passes when configured speed reaches the rated speed' {
        $r = Get-MemoryFrequencyStatus -Modules @(
            [pscustomobject]@{ Speed = 6000; ConfiguredClockSpeed = 6000; Manufacturer = 'Test'; PartNumber = 'X' }
        )
        $r.Status | Should -Be 'OK'
    }

    It 'returns N/A when the platform does not expose configured speed' {
        $r = Get-MemoryFrequencyStatus -Modules @(
            [pscustomobject]@{ Speed = 4800; ConfiguredClockSpeed = 0; Manufacturer = 'Test'; PartNumber = 'X' }
        )
        $r.Status | Should -Be 'N/A'
    }
}

Describe 'NVIDIA App auto-optimize diagnostics' {
    It 'flags an enabled auto-optimize switch' {
        $r = Get-NvidiaAppAutoOptStatus -ConfigXml '<config><EnableAutomaticApplyOPS>true</EnableAutomaticApplyOPS></config>'
        $r.Status | Should -Be 'Attention'
    }

    It 'passes when auto-optimize is off' {
        $r = Get-NvidiaAppAutoOptStatus -ConfigXml '<config><EnableAutomaticApplyOPS>false</EnableAutomaticApplyOPS></config>'
        $r.Status | Should -Be 'OK'
    }

    It 'returns N/A when NVIDIA App is not installed' {
        $r = Get-NvidiaAppAutoOptStatus -ConfigXml ''
        $r.Status | Should -Be 'N/A'
    }
}

Describe 'System health report aggregation' {
    It 'counts attention items across all checks' {
        $report = Get-SystemHealthReport -PcieOutput '4, 4, 4, 4' -RuntimeKeys @{
            x64 = @{ Installed = 1; Version = '14.44.35211' }
            x86 = $null
        } -MemoryModules @(
            [pscustomobject]@{ Speed = 6000; ConfiguredClockSpeed = 4800 }
        ) -NvidiaConfigXml '<config><EnableAutomaticApplyOPS>true</EnableAutomaticApplyOPS></config>'
        $report.AttentionCount | Should -Be 4
        @($report.Results).Count | Should -Be 4
    }
}
