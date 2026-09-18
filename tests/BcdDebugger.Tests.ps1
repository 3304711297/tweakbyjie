BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "BCD Debugger type validation" {
    It "accepts all allowed debugger transport types" {
        @('Local','Serial','1394','USB','Net') | ForEach-Object {
            Test-BcdDebuggerTypeAllowed $_ | Should -Be $true
        }
    }

    It "rejects unsupported or arbitrary debugger types" {
        @('PCIe', 'Ethernet', 'Wireless', '', 'CommandInjection;whoami') | ForEach-Object {
            Test-BcdDebuggerTypeAllowed $_ | Should -Be $false
        }
    }
}

Describe "BCD value whitelist validation" {
    It "accepts valid values for known BCD settings" {
        Test-BcdValueAllowed 'testsigning' 'Yes' | Should -Be $true
        Test-BcdValueAllowed 'testsigning' 'No' | Should -Be $true
        Test-BcdValueAllowed 'debug' 'Yes' | Should -Be $true
        Test-BcdValueAllowed 'nx' 'OptIn' | Should -Be $true
        Test-BcdValueAllowed 'tscsyncpolicy' 'Enhanced' | Should -Be $true
    }

    It "rejects invalid values and malicious injections" {
        Test-BcdValueAllowed 'testsigning' 'Maybe' | Should -Be $false
        Test-BcdValueAllowed 'nx' 'DropTable' | Should -Be $false
        Test-BcdValueAllowed 'testsigning' 'Yes;rmdir /s /q c:\' | Should -Be $false
        Test-BcdValueAllowed 'unknown_key' 'Yes' | Should -Be $false
    }
}

Describe "BCD Debugger snapshot generation" {
    Context "When debugger is not present" {
        It "returns present=false with machine binding" {
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return ""
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Present | Should -Be $false
            $snap.Type | Should -BeNullOrEmpty
            $snap.Arguments | Should -BeNullOrEmpty
            $snap.Binding | Should -Be (Get-BackupMachineId)
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }
    }

    Context "When debugger is Net (KDNET)" {
        It "captures hostip, port, encryption key, nodhcp, and busparams" {
            $mockOutput = @"
debugtype               Net
hostip                  192.168.1.50
port                    50005
key                     1.2.3.4
dhcp                    No
busparams               1.2.0
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Present | Should -Be $true
            $snap.Type | Should -Be 'Net'
            $snap.Arguments | Should -Be 'net hostip:192.168.1.50 port:50005 key:1.2.3.4 nodhcp busparams:1.2.0'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }

        It "captures standard Net settings without optional flags" {
            $mockOutput = @"
debugtype               Net
hostip                  10.0.0.1
port                    50000
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Arguments | Should -Be 'net hostip:10.0.0.1 port:50000'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }

        It "captures hostipv6 when hostip is absent" {
            $mockOutput = @"
debugtype               Net
hostipv6                fe80::1
port                    50000
key                     abcd.1234.efgh.5678
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Arguments | Should -Be 'net hostipv6:fe80::1 port:50000 key:abcd.1234.efgh.5678'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }

        It "captures global debugstart AUTOENABLE and noumex options" {
            $mockOutput = @"
debugtype               Net
hostip                  192.168.1.10
port                    50000
debugstart              AUTOENABLE
noumex                  Yes
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Arguments | Should -Be 'net hostip:192.168.1.10 port:50000 /start:AUTOENABLE /noumex'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }

        It "captures debugstart DISABLE" {
            $mockOutput = @"
debugtype               Net
hostip                  192.168.1.10
port                    50000
debugstart              DISABLE
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Arguments | Should -Be 'net hostip:192.168.1.10 port:50000 /start:DISABLE'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }

        It "captures start ACTIVE (legacy/alias compatibility)" {
            $mockOutput = @"
debugtype               Net
hostip                  192.168.1.10
port                    50000
start                   active
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Arguments | Should -Be 'net hostip:192.168.1.10 port:50000 /start:ACTIVE'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }

        It "throws when neither hostip nor hostipv6 is present" {
            $mockOutput = @"
debugtype               Net
port                    50000
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            { Get-BcdDebuggerSnapshot } | Should -Throw '*缺少 hostip 或 hostipv6*'
        }
    }

    Context "When debugger is Serial" {
        It "captures port and baudrate" {
            $mockOutput = @"
debugtype               Serial
port                    2
baudrate                115200
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Present | Should -Be $true
            $snap.Type | Should -Be 'Serial'
            $snap.Arguments | Should -Be 'serial port:2 baudrate:115200'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }
    }

    Context "When debugger is USB" {
        It "captures targetname" {
            $mockOutput = @"
debugtype               USB
targetname              mytesttarget
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Present | Should -Be $true
            $snap.Type | Should -Be 'USB'
            $snap.Arguments | Should -Be 'usb targetname:mytesttarget'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }
    }

    Context "When debugger is 1394" {
        It "captures channel" {
            $mockOutput = @"
debugtype               1394
channel                 32
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Present | Should -Be $true
            $snap.Type | Should -Be '1394'
            $snap.Arguments | Should -Be '1394 channel:32'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }
    }

    Context "When debugger is Local" {
        It "captures local argument" {
            $mockOutput = @"
debugtype               Local
"@
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return $mockOutput
            }
            $snap = Get-BcdDebuggerSnapshot
            $snap.Present | Should -Be $true
            $snap.Type | Should -Be 'Local'
            $snap.Arguments | Should -Be 'local'
            Test-BcdDebuggerBackupSchema $snap | Should -Be $true
        }
    }

    Context "When bcdedit encounters error or injection" {
        It "throws when bcdedit execution fails" {
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 1
                return "Error reading bcd"
            }
            { Get-BcdDebuggerSnapshot } | Should -Throw
        }

        It "throws when debugger type is unsupported" {
            Mock bcdedit.exe {
                $global:LASTEXITCODE = 0
                return "debugtype EvilTransport"
            }
            { Get-BcdDebuggerSnapshot } | Should -Throw
        }
    }
}

Describe "BCD Debugger backup schema validation" {
    It "rejects null, bad version, or mismatched machine binding" {
        Test-BcdDebuggerBackupSchema $null | Should -Be $false
        Test-BcdDebuggerBackupSchema ([pscustomobject]@{ Version = 2 }) | Should -Be $false
        $badBinding = [pscustomobject]@{
            Version = 1
            Binding = 'wrong-machine'
            Present = $false
            Type = $null
            Arguments = $null
        }
        Test-BcdDebuggerBackupSchema $badBinding | Should -Be $false
    }

    It "rejects present=true with invalid arguments or injection characters" {
        $badArgs = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            Present = $true
            Type = 'Local'
            Arguments = 'local & calc.exe'
        }
        Test-BcdDebuggerBackupSchema $badArgs | Should -Be $false
    }
}

Describe "BCD Debugger Ensure and Restore round-trip" {
    BeforeEach {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) ("Pester_BcdDbg_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $backupFile = Join-Path $testDir 'testmode-debugger-backup.json'
        $script:fail = 0
        $script:ok = 0
    }
    AfterEach {
        if (Test-Path -LiteralPath $testDir) {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "creates backup file and does not overwrite existing valid backup" {
        Mock bcdedit.exe {
            $global:LASTEXITCODE = 0
            return "debugtype Local"
        }
        Ensure-BcdDebuggerBackup -BackupFile $backupFile | Should -Be $true
        Test-Path -LiteralPath $backupFile | Should -Be $true

        # Verify first-snapshot protection
        Ensure-BcdDebuggerBackup -BackupFile $backupFile | Should -Be $true
    }

    It "refuses to overwrite corrupted snapshot" {
        Set-Content -LiteralPath $backupFile -Value '{"Version": 99}' -Encoding UTF8
        Ensure-BcdDebuggerBackup -BackupFile $backupFile | Should -Be $false
        $script:fail | Should -Be 1
    }

    It "restores debugger settings when Present=true" {
        $snap = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            Present = $true
            Type = 'Net'
            Arguments = 'net hostip:192.168.1.1 port:50000 key:1.2.3.4'
        }
        $json = ConvertTo-Json -InputObject $snap
        Set-Content -LiteralPath $backupFile -Value $json -Encoding UTF8

        Mock Invoke-BcdEdit { return $true }
        Restore-BcdDebuggerBackup -BackupFile $backupFile | Should -Be $true
        Should -Invoke Invoke-BcdEdit -ParameterFilter {
            $Arguments -eq '/dbgsettings net hostip:192.168.1.1 port:50000 key:1.2.3.4'
        } -Times 1
    }

    It "cleans up debugger settings when Present=false" {
        $snap = [pscustomobject]@{
            Version = 1
            Binding = (Get-BackupMachineId)
            Present = $false
            Type = $null
            Arguments = $null
        }
        $json = ConvertTo-Json -InputObject $snap
        Set-Content -LiteralPath $backupFile -Value $json -Encoding UTF8

        Mock Invoke-BcdEdit { return $true }
        Restore-BcdDebuggerBackup -BackupFile $backupFile | Should -Be $true
        Should -Invoke Invoke-BcdEdit -ParameterFilter {
            $Arguments -eq '/deletevalue {dbgsettings} debugtype'
        } -Times 1
    }

    It "fails closed when backup file does not exist" {
        $nonExistent = Join-Path $testDir 'no-such-backup.json'
        Restore-BcdDebuggerBackup -BackupFile $nonExistent | Should -Be $false
        $script:fail | Should -Be 1
    }
}
