BeforeAll {
    $env:TWEAK_SKIP_ADMIN_CHECK = '1'
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null

    function New-NetworkTestKey {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
    }

    function Set-NetworkTestValue {
        param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
        New-NetworkTestKey $Path
        Set-TweakRegistryTypedValue -Path $Path -Name $Name -Kind $Type -Value $Value
    }

    function Get-NetworkTestSandboxRoot {
        param([string]$Base)
        return @{
            NicClass        = Join-Path $Base 'Class'
            TcpipInterfaces = Join-Path $Base 'Tcpip'
            WcmLocal        = Join-Path $Base 'Wcm\Local'
            WcmGroupPolicy  = Join-Path $Base 'Wcm\GroupPolicy'
            Services        = Join-Path $Base 'Services'
            Enum            = Join-Path $Base 'Enum'
        }
    }
}

Describe "Network module contract" {
    It "exposes the entry points required by menu 19 and the rollback contract" {
        foreach ($name in @(
            'Invoke-NetworkModule',
            'Ensure-NetworkBackup',
            'Restore-NetworkBackup',
            'Test-NetworkBackupSchema',
            'Get-NetworkWritePlan',
            'Get-NetworkTargetRoots',
            'Get-NetworkPlatformGate'
        )) {
            Get-Command $name -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        $script:networkBackupFile | Should -Match 'network-backup\.json$'
    }

    It "declares every registry root used by the write plan" {
        $roots = Get-NetworkTargetRoots
        $roots.NicClass | Should -Match 'Class\\\{4d36e972-e325-11ce-bfc1-08002be10318\}'
        $roots.TcpipInterfaces | Should -Match 'Services\\Tcpip\\Parameters\\Interfaces'
        $roots.WcmLocal | Should -Match 'WcmSvc\\Local'
        $roots.WcmGroupPolicy | Should -Match 'WcmSvc\\GroupPolicy'
        $roots.Services | Should -Match 'CurrentControlSet\\Services'
        $roots.Enum | Should -Match 'CurrentControlSet\\Enum'
    }
}

Describe "Network wired adapter filtering" {
    It "accepts only 802.3 physical media types" {
        Test-NetworkAdapterWired -MediaType '14' -Description 'Realtek PCIe GbE Family Controller' | Should -BeTrue
        Test-NetworkAdapterWired -MediaType '802.3' -Description 'Intel(R) Ethernet Connection I219-V' | Should -BeTrue
        Test-NetworkAdapterWired -MediaType '9' -Description 'MediaTek Wi-Fi 6E MT7922 160MHz Wireless LAN Card' | Should -BeFalse
        Test-NetworkAdapterWired -MediaType '10' -Description 'Bluetooth Device (Personal Area Network)' | Should -BeFalse
        Test-NetworkAdapterWired -MediaType '0' -Description 'WAN Miniport (IP)' | Should -BeFalse
        Test-NetworkAdapterWired -MediaType '' -Description 'Realtek PCIe GbE Family Controller' | Should -BeFalse
        Test-NetworkAdapterWired -MediaType '14' -Description '' | Should -BeFalse
    }

    It "keeps virtual and Wi-Fi-Direct adapters out of the plan" {
        foreach ($desc in @(
            'Hyper-V Virtual Ethernet Adapter',
            'VMware Virtual Ethernet Adapter for VMnet8',
            'VirtualBox Host-Only Ethernet Adapter',
            'TAP-Windows Adapter V9',
            'WAN Miniport (PPPOE)',
            'Microsoft Wi-Fi Direct Virtual Adapter',
            'Kernel Debug Network Adapter',
            'Sangfor SSL VPN CS Support System VNIC'
        )) {
            Test-NetworkAdapterWired -MediaType '14' -Description $desc | Should -BeFalse -Because "$desc 属于虚拟/无线类，不能写入 TCP 参数或节能开关"
        }
    }
}

Describe "Network platform gate (battery hard gate)" {
    It "blocks the whole section when a battery is present" {
        Mock Test-NetworkBatteryPresent { return $true }
        Mock Get-NetworkChassisType { return 10 }
        $gate = Get-NetworkPlatformGate
        $gate.Allowed | Should -BeFalse
        $gate.Reason | Should -Match '电池'
    }

    It "blocks laptops identified by chassis type even without a battery reading" {
        Mock Test-NetworkBatteryPresent { return $false }
        Mock Get-NetworkChassisType { return 9 }
        $gate = Get-NetworkPlatformGate
        $gate.Allowed | Should -BeFalse
        $gate.Reason | Should -Match '便携'
    }

    It "fails closed when battery state cannot be determined" {
        Mock Test-NetworkBatteryPresent { return $null }
        Mock Get-NetworkChassisType { return $null }
        (Get-NetworkPlatformGate).Allowed | Should -BeFalse
    }

    It "allows a desktop without battery" {
        Mock Test-NetworkBatteryPresent { return $false }
        Mock Get-NetworkChassisType { return 3 }
        $gate = Get-NetworkPlatformGate
        $gate.Allowed | Should -BeTrue
        $gate.Reason | Should -Be ''
    }
}

Describe "Network backup schema" {
    It "rejects null, wrong version and foreign machine bindings" {
        Test-NetworkBackupSchema $null | Should -BeFalse
        Test-NetworkBackupSchema ([pscustomobject]@{ Version = 2; Binding = (Get-BackupMachineId); Entries = @() }) | Should -BeFalse
        Test-NetworkBackupSchema ([pscustomobject]@{ Version = 1; Binding = 'foreign'; Entries = @() }) | Should -BeFalse
        Test-NetworkBackupSchema ([pscustomobject]@{ Version = 1; Binding = (Get-BackupMachineId); Entries = $null }) | Should -BeFalse
        Test-NetworkBackupSchema ([pscustomobject]@{
            Version = 1; Binding = (Get-BackupMachineId)
            Entries = @([pscustomobject]@{ Path = ''; Name = 'TCPNoDelay'; Existed = $false })
        }) | Should -BeFalse
        Test-NetworkBackupSchema ([pscustomobject]@{
            Version = 1; Binding = (Get-BackupMachineId)
            Entries = @([pscustomobject]@{ Path = 'HKLM:\X'; Name = 'TCPNoDelay'; Existed = $true; Kind = 'Weird'; Value = 1 })
        }) | Should -BeFalse
    }

    It "accepts a snapshot with both existing and missing values" {
        $valid = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Entries   = @(
                [pscustomobject]@{ Path = 'HKLM:\A'; Name = 'TcpAckFrequency'; Existed = $true; Kind = 'DWord'; Value = 2 },
                [pscustomobject]@{ Path = 'HKLM:\B'; Name = 'PnPCapabilities'; Existed = $false; Kind = ''; Value = $null }
            )
        }
        Test-NetworkBackupSchema $valid | Should -BeTrue
    }
}

Describe "Network write plan (HKCU sandbox)" {
    BeforeAll {
        $script:PlanBase = 'HKCU:\Software\TweakByjieTest\NetworkPlan'
        if (Test-Path $script:PlanBase) { Remove-Item -Path $script:PlanBase -Recurse -Force -ErrorAction SilentlyContinue }
        $script:PlanRoots = Get-NetworkTestSandboxRoot -Base $script:PlanBase

        $classRoot = Join-Path $script:PlanBase 'Class'
        $script:WiredKey = Join-Path $classRoot '0001'
        $script:WifiKey = Join-Path $classRoot '0010'
        $script:VirtualKey = Join-Path $classRoot '0011'

        Set-NetworkTestValue $script:WiredKey '*PhysicalMediaType' 14 'DWord'
        Set-NetworkTestValue $script:WiredKey 'DriverDesc' 'Test Ethernet Controller' 'String'
        Set-NetworkTestValue $script:WiredKey 'NetCfgInstanceId' '{11111111-1111-1111-1111-111111111111}' 'String'
        Set-NetworkTestValue $script:WiredKey 'PowerSaveEnable' 1 'DWord'
        Set-NetworkTestValue $script:WiredKey 'AdvancedEEE' 0 'DWord'
        Set-NetworkTestValue $script:WiredKey 'EnablePME' '1' 'String'

        Set-NetworkTestValue $script:WifiKey '*PhysicalMediaType' 9 'DWord'
        Set-NetworkTestValue $script:WifiKey 'DriverDesc' 'MediaTek Wi-Fi 6E MT7922' 'String'
        Set-NetworkTestValue $script:WifiKey 'NetCfgInstanceId' '{22222222-2222-2222-2222-222222222222}' 'String'
        Set-NetworkTestValue $script:WifiKey 'PowerSaveEnable' 1 'DWord'

        Set-NetworkTestValue $script:VirtualKey '*PhysicalMediaType' 14 'DWord'
        Set-NetworkTestValue $script:VirtualKey 'DriverDesc' 'Hyper-V Virtual Ethernet Adapter' 'String'
        Set-NetworkTestValue $script:VirtualKey 'NetCfgInstanceId' '{33333333-3333-3333-3333-333333333333}' 'String'

        $script:WiredTcpKey = Join-Path $script:PlanRoots.TcpipInterfaces '{11111111-1111-1111-1111-111111111111}'
        $script:WifiTcpKey = Join-Path $script:PlanRoots.TcpipInterfaces '{22222222-2222-2222-2222-222222222222}'
        New-NetworkTestKey $script:WiredTcpKey
        New-NetworkTestKey $script:WifiTcpKey

        Set-NetworkTestValue (Join-Path $script:PlanBase 'Services\USBHUB3') 'Start' 3 'DWord'
        Set-NetworkTestValue (Join-Path $script:PlanBase 'Services\pci') 'Start' 0 'DWord'
        Set-NetworkTestValue (Join-Path $script:PlanBase 'Services\usbccgp') 'Start' 3 'DWord'

        $script:DeviceKey = Join-Path $script:PlanBase 'Enum\PCI\VEN_TEST&DEV_0001\INST1'
        Set-NetworkTestValue $script:DeviceKey 'EnhancedPowerManagementEnabled' 1 'DWord'
        Set-NetworkTestValue $script:DeviceKey 'AllowIdleIrpInD3' '1' 'String'
        Set-NetworkTestValue $script:DeviceKey 'WdfDirectedPowerTransitionEnable' 1 'DWord'

        $script:EmptyDeviceKey = Join-Path $script:PlanBase 'Enum\PCI\VEN_TEST&DEV_0002\INST2'
        Set-NetworkTestValue $script:EmptyDeviceKey 'ClassGUID' '{4d36e968-e325-11ce-bfc1-08002be10318}' 'String'

        $script:Plan = Get-NetworkWritePlan -Roots $script:PlanRoots
    }

    AfterAll {
        if (Test-Path $script:PlanBase) { Remove-Item -Path $script:PlanBase -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "writes fDisablePowerManagement to both WcmSvc policy keys" {
        $ops = @($script:Plan.Operations | Where-Object { $_.Name -eq 'fDisablePowerManagement' })
        $ops.Count | Should -Be 2
        $ops | ForEach-Object { $_.Value | Should -Be 1; $_.Kind | Should -Be 'DWord' }
    }

    It "applies per-interface TCP tweaks only to the wired adapter" {
        $ack = @($script:Plan.Operations | Where-Object { $_.Name -eq 'TcpAckFrequency' })
        $nodelay = @($script:Plan.Operations | Where-Object { $_.Name -eq 'TCPNoDelay' })
        $ack.Count | Should -Be 1
        $nodelay.Count | Should -Be 1
        $ack[0].Path | Should -Be $script:WiredTcpKey
        $nodelay[0].Path | Should -Be $script:WiredTcpKey
        $ack[0].Value | Should -Be 1
        $nodelay[0].Value | Should -Be 1
        @($script:Plan.Operations | Where-Object { $_.Path -eq $script:WifiTcpKey }).Count | Should -Be 0
    }

    It "zeroes existing NIC class DWORDs and writes PnPCapabilities=24" {
        $power = @($script:Plan.Operations | Where-Object { $_.Path -eq $script:WiredKey -and $_.Name -eq 'PowerSaveEnable' })
        $power.Count | Should -Be 1
        $power[0].Value | Should -Be 0
        $pnp = @($script:Plan.Operations | Where-Object { $_.Path -eq $script:WiredKey -and $_.Name -eq 'PnPCapabilities' })
        $pnp.Count | Should -Be 1
        $pnp[0].Value | Should -Be 24
        @($script:Plan.Operations | Where-Object { $_.Path -eq $script:WifiKey }).Count | Should -Be 0
        @($script:Plan.Operations | Where-Object { $_.Path -eq $script:VirtualKey }).Count | Should -Be 0
    }

    It "records non-DWORD NIC values as skips without writing them" {
        @($script:Plan.Operations | Where-Object { $_.Name -eq 'EnablePME' }).Count | Should -Be 0
        $skip = @($script:Plan.Skips | Where-Object { $_.Name -eq 'EnablePME' })
        $skip.Count | Should -Be 1
        $skip[0].Kind | Should -Be 'String'
        $skip[0].Reason | Should -Match 'DWORD'
    }

    It "handles USB hub and PCI/USB root port power values" {
        $lpm = @($script:Plan.Operations | Where-Object { $_.Name -eq 'DisableLPM' })
        $lpm.Count | Should -Be 1
        $lpm[0].Value | Should -Be 1
        $lpm[0].Path | Should -Be (Join-Path $script:PlanBase 'Services\USBHUB3\Parameters')

        $d3 = @($script:Plan.Operations | Where-Object { $_.Name -eq 'D3ColdSupported' })
        $d3.Count | Should -Be 2
        $d3 | ForEach-Object { $_.Value | Should -Be 0 }
        ($d3.Path -join ';') | Should -Match 'usbccgp'
        ($d3.Path -join ';') | Should -Match 'Services\\pci'
    }

    It "zeroes only existing DWORD device power values and skips REG_SZ ones" {
        $enhanced = @($script:Plan.Operations | Where-Object { $_.Name -eq 'EnhancedPowerManagementEnabled' })
        $enhanced.Count | Should -Be 1
        $enhanced[0].Value | Should -Be 0
        @($script:Plan.Operations | Where-Object { $_.Name -eq 'WdfDirectedPowerTransitionEnable' }).Count | Should -Be 1
        @($script:Plan.Operations | Where-Object { $_.Name -eq 'AllowIdleIrpInD3' }).Count | Should -Be 0
        $skip = @($script:Plan.Skips | Where-Object { $_.Name -eq 'AllowIdleIrpInD3' })
        $skip.Count | Should -Be 1
        $skip[0].Kind | Should -Be 'String'
    }

    It "does not emit duplicate path/name operations" {
        $keys = @($script:Plan.Operations | ForEach-Object { ('{0}|{1}' -f $_.Path, $_.Name).ToLowerInvariant() })
        @($keys | Sort-Object -Unique).Count | Should -Be $keys.Count
    }
}

Describe "Network backup and restore round-trip (HKCU sandbox)" {
    BeforeAll {
        $script:RtBase = 'HKCU:\Software\TweakByjieTest\NetworkRoundTrip'
        if (Test-Path $script:RtBase) { Remove-Item -Path $script:RtBase -Recurse -Force -ErrorAction SilentlyContinue }
        $script:RtRoots = Get-NetworkTestSandboxRoot -Base $script:RtBase
        $script:RtBackup = Join-Path $env:TEMP ("network-backup-test-" + [guid]::NewGuid().ToString('N') + ".json")

        $classRoot = Join-Path $script:RtBase 'Class'
        $script:RtKey = Join-Path $classRoot '0001'
        Set-NetworkTestValue $script:RtKey '*PhysicalMediaType' 14 'DWord'
        Set-NetworkTestValue $script:RtKey 'DriverDesc' 'Round Trip Ethernet' 'String'
        Set-NetworkTestValue $script:RtKey 'NetCfgInstanceId' '{44444444-4444-4444-4444-444444444444}' 'String'
        Set-NetworkTestValue $script:RtKey 'PowerSaveEnable' 1 'DWord'
        $script:RtTcpKey = Join-Path $script:RtRoots.TcpipInterfaces '{44444444-4444-4444-4444-444444444444}'
        New-NetworkTestKey $script:RtTcpKey
        Set-NetworkTestValue (Join-Path $script:RtBase 'Services\USBHUB3') 'Start' 3 'DWord'
        Set-NetworkTestValue (Join-Path $script:RtBase 'Services\pci') 'Start' 0 'DWord'
        Set-NetworkTestValue (Join-Path $script:RtBase 'Services\usbccgp') 'Start' 3 'DWord'
        New-NetworkTestKey $script:RtRoots.Enum
    }

    BeforeEach {
        if (Test-Path -LiteralPath $script:RtBackup) { Remove-Item -LiteralPath $script:RtBackup -Force -ErrorAction SilentlyContinue }
        # reset mutable values so each test starts from the captured baseline
        Set-TweakRegistryTypedValue -Path $script:RtKey -Name 'PowerSaveEnable' -Kind 'DWord' -Value 1
        Remove-TweakRegistryValue -Path $script:RtKey -Name 'PnPCapabilities' | Out-Null
        Remove-TweakRegistryValue -Path $script:RtTcpKey -Name 'TcpAckFrequency' | Out-Null
        Remove-TweakRegistryValue -Path $script:RtTcpKey -Name 'TCPNoDelay' | Out-Null
        Remove-TweakRegistryValue -Path (Join-Path $script:RtBase 'Services\USBHUB3\Parameters') -Name 'DisableLPM' | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:RtBackup) { Remove-Item -LiteralPath $script:RtBackup -Force -ErrorAction SilentlyContinue }
        if (Test-Path $script:RtBase) { Remove-Item -Path $script:RtBase -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "creates a snapshot recording existing values and missing values separately" {
        $plan = Get-NetworkWritePlan -Roots $script:RtRoots
        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue
        Test-Path -LiteralPath $script:RtBackup | Should -BeTrue

        $backup = Get-Content -LiteralPath $script:RtBackup -Raw | ConvertFrom-Json
        $backup.Version | Should -Be 1
        $backup.Binding | Should -Be (Get-BackupMachineId)

        $power = @($backup.Entries | Where-Object { $_.Path -eq $script:RtKey -and $_.Name -eq 'PowerSaveEnable' })
        $power.Count | Should -Be 1
        $power[0].Existed | Should -BeTrue
        $power[0].Kind | Should -Be 'DWord'
        $power[0].Value | Should -Be 1

        $ack = @($backup.Entries | Where-Object { $_.Path -eq $script:RtTcpKey -and $_.Name -eq 'TcpAckFrequency' })
        $ack.Count | Should -Be 1
        $ack[0].Existed | Should -BeFalse
    }

    It "restores existing values and deletes values that did not exist" {
        $plan = Get-NetworkWritePlan -Roots $script:RtRoots
        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue

        # simulate the apply phase on the sandbox
        Set-TweakRegistryTypedValue -Path $script:RtKey -Name 'PowerSaveEnable' -Kind 'DWord' -Value 0
        Set-TweakRegistryTypedValue -Path $script:RtKey -Name 'PnPCapabilities' -Kind 'DWord' -Value 24
        Set-TweakRegistryTypedValue -Path $script:RtTcpKey -Name 'TcpAckFrequency' -Kind 'DWord' -Value 1
        Set-TweakRegistryTypedValue -Path $script:RtTcpKey -Name 'TCPNoDelay' -Kind 'DWord' -Value 1

        Restore-NetworkBackup -BackupFile $script:RtBackup | Should -BeTrue

        (Get-TweakRegistryValue -Path $script:RtKey -Name 'PowerSaveEnable').Value | Should -Be 1
        (Get-TweakRegistryValue -Path $script:RtKey -Name 'PnPCapabilities').Exists | Should -BeFalse
        (Get-TweakRegistryValue -Path $script:RtTcpKey -Name 'TcpAckFrequency').Exists | Should -BeFalse
        (Get-TweakRegistryValue -Path $script:RtTcpKey -Name 'TCPNoDelay').Exists | Should -BeFalse
    }

    It "keeps the first snapshot even when the registry changed afterwards" {
        $plan = Get-NetworkWritePlan -Roots $script:RtRoots
        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue

        Set-TweakRegistryTypedValue -Path $script:RtKey -Name 'PowerSaveEnable' -Kind 'DWord' -Value 5

        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue
        $backup = Get-Content -LiteralPath $script:RtBackup -Raw | ConvertFrom-Json
        $power = @($backup.Entries | Where-Object { $_.Name -eq 'PowerSaveEnable' })
        $power[0].Value | Should -Be 1
    }

    It "appends newly discovered targets without overwriting earlier entries" {
        $plan = Get-NetworkWritePlan -Roots $script:RtRoots
        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue

        Set-TweakRegistryTypedValue -Path $script:RtKey -Name 'EnableGreenEthernet' -Kind 'DWord' -Value 1
        try {
            $plan2 = Get-NetworkWritePlan -Roots $script:RtRoots
            Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan2 | Should -BeTrue
            $backup = Get-Content -LiteralPath $script:RtBackup -Raw | ConvertFrom-Json
            $added = @($backup.Entries | Where-Object { $_.Name -eq 'EnableGreenEthernet' })
            $added.Count | Should -Be 1
            $added[0].Existed | Should -BeTrue
            $added[0].Value | Should -Be 1
            $power = @($backup.Entries | Where-Object { $_.Name -eq 'PowerSaveEnable' })
            $power.Count | Should -Be 1
        } finally {
            Remove-TweakRegistryValue -Path $script:RtKey -Name 'EnableGreenEthernet' | Out-Null
        }
    }

    It "restores the original type for non-DWORD snapshots" {
        $stringKey = Join-Path $script:RtBase 'Class\0009'
        Set-NetworkTestValue $stringKey 'DriverDesc' 'String Value Adapter' 'String'
        Set-NetworkTestValue $stringKey 'EnablePME' 'enabled' 'String'
        $backup = [pscustomobject]@{
            Version   = 1
            Binding   = (Get-BackupMachineId)
            CreatedAt = (Get-Date).ToString('o')
            Entries   = @(
                [pscustomobject]@{ Path = $stringKey; Name = 'EnablePME'; Existed = $true; Kind = 'String'; Value = 'enabled' }
            )
        }
        $json = ConvertTo-Json -InputObject $backup -Depth 6
        [System.IO.File]::WriteAllText($script:RtBackup, $json, [System.Text.UTF8Encoding]::new($false))

        Set-TweakRegistryTypedValue -Path $stringKey -Name 'EnablePME' -Kind 'String' -Value '0'

        Restore-NetworkBackup -BackupFile $script:RtBackup | Should -BeTrue
        $restored = Get-TweakRegistryValue -Path $stringKey -Name 'EnablePME'
        $restored.Value | Should -Be 'enabled'
        $restored.Kind | Should -Be 'String'
    }

    It "fails closed when the snapshot is missing or corrupt" {
        $beforeFail = $script:fail
        Restore-NetworkBackup -BackupFile $script:RtBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail

        [System.IO.File]::WriteAllText($script:RtBackup, '{"Version": 999}', [System.Text.UTF8Encoding]::new($false))
        $beforeFail = $script:fail
        Restore-NetworkBackup -BackupFile $script:RtBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
    }

    It "reports failure when a restore write fails" {
        $plan = Get-NetworkWritePlan -Roots $script:RtRoots
        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeTrue
        Mock Set-TweakRegistryTypedValue { throw '模拟恢复写入失败' }
        $beforeFail = $script:fail
        Restore-NetworkBackup -BackupFile $script:RtBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
    }

    It "aborts backup when the snapshot file is corrupt" {
        [System.IO.File]::WriteAllText($script:RtBackup, 'not-a-json', [System.Text.UTF8Encoding]::new($false))
        $beforeFail = $script:fail
        $plan = Get-NetworkWritePlan -Roots $script:RtRoots
        Ensure-NetworkBackup -BackupFile $script:RtBackup -Plan $plan | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
    }
}

Describe "Network global non-DWORD hard gate (HKCU sandbox)" {
    BeforeAll {
        $script:GateBase = 'HKCU:\Software\TweakByjieTest\NetworkGlobalSkip'
        if (Test-Path $script:GateBase) { Remove-Item -Path $script:GateBase -Recurse -Force -ErrorAction SilentlyContinue }
        $script:GateRoots = Get-NetworkTestSandboxRoot -Base $script:GateBase

        Set-NetworkTestValue (Join-Path $script:GateBase 'Wcm\Local') 'fDisablePowerManagement' 'legacy' 'String'
        Set-NetworkTestValue (Join-Path $script:GateBase 'Wcm\GroupPolicy') 'fDisablePowerManagement' 1 'DWord'

        $classKey = Join-Path $script:GateBase 'Class\0001'
        Set-NetworkTestValue $classKey '*PhysicalMediaType' 14 'DWord'
        Set-NetworkTestValue $classKey 'DriverDesc' 'Gate Test Ethernet' 'String'
        Set-NetworkTestValue $classKey 'NetCfgInstanceId' '{55555555-5555-5555-5555-555555555555}' 'String'
        Set-NetworkTestValue $classKey 'PowerSaveEnable' '1' 'String'

        $tcpKey = Join-Path $script:GateRoots.TcpipInterfaces '{55555555-5555-5555-5555-555555555555}'
        New-NetworkTestKey $tcpKey
        Set-NetworkTestValue $tcpKey 'TcpAckFrequency' '2' 'String'
        Set-NetworkTestValue $tcpKey 'TCPNoDelay' 0 'DWord'

        Set-NetworkTestValue (Join-Path $script:GateBase 'Services\pci') 'Start' 0 'DWord'
        Set-NetworkTestValue (Join-Path $script:GateBase 'Services\pci\Parameters') 'D3ColdSupported' '1' 'String'

        $script:GatePlan = Get-NetworkWritePlan -Roots $script:GateRoots
    }

    AfterAll {
        if (Test-Path $script:GateBase) { Remove-Item -Path $script:GateBase -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "skips a REG_SZ WcmSvc policy value instead of overwriting its type" {
        @($script:GatePlan.Operations | Where-Object { $_.Scope -eq 'WcmSvc' -and $_.Path -like '*\Local' }).Count | Should -Be 0
        $skip = @($script:GatePlan.Skips | Where-Object { $_.Name -eq 'fDisablePowerManagement' -and $_.Path -like '*\Local' })
        $skip.Count | Should -Be 1
        $skip[0].Kind | Should -Be 'String'
        @($script:GatePlan.Operations | Where-Object { $_.Name -eq 'fDisablePowerManagement' }).Count | Should -Be 1
    }

    It "skips a REG_SZ TcpAckFrequency but still plans the DWORD TCPNoDelay" {
        @($script:GatePlan.Operations | Where-Object { $_.Name -eq 'TcpAckFrequency' }).Count | Should -Be 0
        @($script:GatePlan.Skips | Where-Object { $_.Name -eq 'TcpAckFrequency' }).Count | Should -Be 1
        $nodelay = @($script:GatePlan.Operations | Where-Object { $_.Name -eq 'TCPNoDelay' })
        $nodelay.Count | Should -Be 1
        $nodelay[0].Value | Should -Be 1
    }

    It "skips a REG_SZ service value and a missing service without failing" {
        @($script:GatePlan.Operations | Where-Object { $_.Name -eq 'D3ColdSupported' -and $_.Path -like '*\pci\*' }).Count | Should -Be 0
        @($script:GatePlan.Skips | Where-Object { $_.Name -eq 'D3ColdSupported' -and $_.Path -like '*\pci\*' }).Count | Should -Be 1
        @($script:GatePlan.Skips | Where-Object { $_.Name -eq 'DisableLPM' -and $_.Reason -match '服务' }).Count | Should -Be 1
    }

    It "records the non-DWORD skips in the backup as absent from the write set" {
        $backupFile = Join-Path $env:TEMP ("network-gate-" + [guid]::NewGuid().ToString('N') + ".json")
        try {
            Ensure-NetworkBackup -BackupFile $backupFile -Plan $script:GatePlan | Should -BeTrue
            $backup = Get-Content -LiteralPath $backupFile -Raw | ConvertFrom-Json
            @($backup.Entries | Where-Object { $_.Name -eq 'fDisablePowerManagement' -and $_.Path -like '*\Local' }).Count | Should -Be 0
            @($backup.Entries | Where-Object { $_.Name -eq 'TCPNoDelay' }).Count | Should -Be 1
        } finally {
            if (Test-Path -LiteralPath $backupFile) { Remove-Item -LiteralPath $backupFile -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe "Invoke-NetworkModule dispatcher" {
    BeforeAll {
        $script:DispatchBackup = Join-Path $env:TEMP ("network-dispatch-" + [guid]::NewGuid().ToString('N') + ".json")
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:DispatchBackup) { Remove-Item -LiteralPath $script:DispatchBackup -Force -ErrorAction SilentlyContinue }
    }

    BeforeEach {
        Mock Request-Restart { }
    }

    It "skips the whole section on battery without creating a snapshot" {
        Mock Test-NetworkBatteryPresent { return $true }
        Mock Get-NetworkChassisType { return 10 }
        Mock Get-NetworkWritePlan { throw '配置计划不应在电池门禁前构建' }
        Mock Ensure-NetworkBackup { throw '电池门禁下不应创建快照' }
        $beforeSkip = $script:skip
        Invoke-NetworkModule -Action '1' -BackupFile $script:DispatchBackup | Should -BeTrue
        $script:skip | Should -BeGreaterThan $beforeSkip
        Test-Path -LiteralPath $script:DispatchBackup | Should -BeFalse
    }

    It "applies every planned operation and counts success" {
        Mock Get-NetworkPlatformGate { return [pscustomobject]@{ Allowed = $true; Reason = '' } }
        Mock Get-NetworkWritePlan {
            return [pscustomobject]@{
                Operations = @(
                    [pscustomobject]@{ Scope = 'Tcpip'; Path = 'HKCU:\TweakTest\If1'; Name = 'TcpAckFrequency'; Kind = 'DWord'; Value = 1 }
                )
                Skips      = @()
            }
        }
        Mock Ensure-NetworkBackup { return $true }
        Mock Set-TweakRegistryTypedValue { }
        $beforeOk = $script:ok
        Invoke-NetworkModule -Action '1' -BackupFile $script:DispatchBackup | Should -BeTrue
        $script:ok | Should -BeGreaterThan $beforeOk
        Should -Invoke Ensure-NetworkBackup -Times 1
        Should -Invoke Set-TweakRegistryTypedValue -Times 1
    }

    It "counts non-DWORD skips without failing the run" {
        Mock Get-NetworkPlatformGate { return [pscustomobject]@{ Allowed = $true; Reason = '' } }
        Mock Get-NetworkWritePlan {
            return [pscustomobject]@{
                Operations = @(
                    [pscustomobject]@{ Scope = 'Tcpip'; Path = 'HKCU:\TweakTest\If1'; Name = 'TCPNoDelay'; Kind = 'DWord'; Value = 1 }
                )
                Skips      = @(
                    [pscustomobject]@{ Scope = 'NicClass'; Path = 'HKCU:\TweakTest\Nic'; Name = 'EnablePME'; Kind = 'String'; Reason = '非 REG_DWORD' }
                )
            }
        }
        Mock Ensure-NetworkBackup { return $true }
        Mock Set-TweakRegistryTypedValue { }
        $beforeSkip = $script:skip
        Invoke-NetworkModule -Action '1' -BackupFile $script:DispatchBackup | Should -BeTrue
        $script:skip | Should -BeGreaterThan $beforeSkip
    }

    It "aborts without writing when the snapshot cannot be created" {
        Mock Get-NetworkPlatformGate { return [pscustomobject]@{ Allowed = $true; Reason = '' } }
        Mock Get-NetworkWritePlan { return [pscustomobject]@{ Operations = @(); Skips = @() } }
        Mock Ensure-NetworkBackup { return $false }
        Mock Set-TweakRegistryTypedValue { }
        Invoke-NetworkModule -Action '1' -BackupFile $script:DispatchBackup | Should -BeFalse
        Should -Invoke Set-TweakRegistryTypedValue -Times 0
    }

    It "rolls back on a write failure" {
        Mock Get-NetworkPlatformGate { return [pscustomobject]@{ Allowed = $true; Reason = '' } }
        Mock Get-NetworkWritePlan {
            return [pscustomobject]@{
                Operations = @(
                    [pscustomobject]@{ Scope = 'Tcpip'; Path = 'HKCU:\TweakTest\If1'; Name = 'TcpAckFrequency'; Kind = 'DWord'; Value = 1 }
                )
                Skips      = @()
            }
        }
        Mock Ensure-NetworkBackup { return $true }
        Mock Set-TweakRegistryTypedValue { throw '模拟写入失败' }
        Mock Restore-NetworkBackup { return $true }
        $beforeFail = $script:fail
        Invoke-NetworkModule -Action '1' -BackupFile $script:DispatchBackup | Should -BeFalse
        $script:fail | Should -BeGreaterThan $beforeFail
        Should -Invoke Restore-NetworkBackup -Times 1
    }

    It "status is read-only and returns true" {
        Mock Get-NetworkPlatformGate { return [pscustomobject]@{ Allowed = $true; Reason = '' } }
        Mock Get-NetworkWiredAdapters { return @() }
        Invoke-NetworkModule -Action '0' | Should -BeTrue
    }

    It "restore action delegates to Restore-NetworkBackup" {
        Mock Restore-NetworkBackup { return $true }
        Invoke-NetworkModule -Action '2' -BackupFile $script:DispatchBackup | Should -BeTrue
        Should -Invoke Restore-NetworkBackup -Times 1
    }

    It "rejects invalid and missing actions in non-interactive mode" {
        $beforeFail = $script:fail
        Invoke-NetworkModule -Action 'bogus' | Should -BeFalse
        $script:TweakNonInteractive = $true
        try {
            Invoke-NetworkModule -Action '' | Should -BeFalse
        } finally {
            $script:TweakNonInteractive = $false
        }
        $script:fail | Should -BeGreaterThan ($beforeFail - 1)
    }
}
