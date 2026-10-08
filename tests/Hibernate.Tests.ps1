BeforeAll {
    $env:TWEAK_SKIP_ADMIN_CHECK = '1'
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
    if (Test-Path "$PSScriptRoot/../Modules/Hibernate.ps1") {
        . "$PSScriptRoot/../Modules/Hibernate.ps1"
    }
}

Describe "Hibernate Module Contract" {
    Context "Schema Validation" {
        It "validates a correct Hibernate backup structure" {
            $validBackup = [pscustomobject]@{
                Version   = 1
                Binding   = (Get-BackupMachineId)
                CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
                State     = [pscustomobject]@{
                    HibernateEnabled  = 1
                    HiberbootEnabled  = 1
                    HiberfilExists    = $true
                    HiberfilSizeBytes = [int64]6442450944
                }
            }
            Test-HibernateBackupSchema $validBackup | Should -Be $true
        }

        It "rejects null or non-v1 version" {
            Test-HibernateBackupSchema $null | Should -Be $false
            $invalidVer = [pscustomobject]@{
                Version = 2
                Binding = (Get-BackupMachineId)
                State   = [pscustomobject]@{
                    HibernateEnabled = 1
                    HiberbootEnabled = 1
                }
            }
            Test-HibernateBackupSchema $invalidVer | Should -Be $false
        }

        It "rejects mismatched machine binding" {
            $badBinding = [pscustomobject]@{
                Version = 1
                Binding = 'wrong-machine-guid-binding'
                State   = [pscustomobject]@{
                    HibernateEnabled = 1
                    HiberbootEnabled = 1
                }
            }
            Test-HibernateBackupSchema $badBinding | Should -Be $false
        }

        It "rejects missing State or invalid property values" {
            $noState = [pscustomobject]@{
                Version = 1
                Binding = (Get-BackupMachineId)
            }
            Test-HibernateBackupSchema $noState | Should -Be $false

            $missingHiberboot = [pscustomobject]@{
                Version = 1
                Binding = (Get-BackupMachineId)
                State   = [pscustomobject]@{
                    HibernateEnabled = 1
                }
            }
            Test-HibernateBackupSchema $missingHiberboot | Should -Be $false

            $invalidVal = [pscustomobject]@{
                Version = 1
                Binding = (Get-BackupMachineId)
                State   = [pscustomobject]@{
                    HibernateEnabled = 5
                    HiberbootEnabled = 1
                }
            }
            Test-HibernateBackupSchema $invalidVal | Should -Be $false
        }
    }

    Context "Get-HibernateStatus Inspection" {
        BeforeAll {
            $sandboxKeyPower = 'HKCU:\Software\TweakByjieTest\Power'
            $sandboxKeySession = 'HKCU:\Software\TweakByjieTest\SessionPower'

            New-Item -Path $sandboxKeyPower -Force | Out-Null
            New-Item -Path $sandboxKeySession -Force | Out-Null
        }

        AfterAll {
            Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "correctly extracts enabled status and file metrics when present" {
            $dummyHiberfile = Join-Path $TestDrive 'hiberfil.sys'
            Set-ItemProperty -Path $sandboxKeyPower -Name 'HibernateEnabled' -Value 1 -Type DWord
            Set-ItemProperty -Path $sandboxKeySession -Name 'HiberbootEnabled' -Value 1 -Type DWord
            [System.IO.File]::WriteAllBytes($dummyHiberfile, (New-Object byte[] (2 * 1024 * 1024))) # 2MB

            $status = Get-HibernateStatus -HiberfilePath $dummyHiberfile -PowerKey $sandboxKeyPower -SessionPowerKey $sandboxKeySession
            $status.HibernateEnabled | Should -Be 1
            $status.HiberbootEnabled | Should -Be 1
            $status.HiberfilExists | Should -Be $true
            $status.HiberfilSizeBytes | Should -Be (2 * 1024 * 1024)
            $status.HiberfilSizeMB | Should -Be 2.0
        }

        It "correctly reports disabled status and non-existent file" {
            Set-ItemProperty -Path $sandboxKeyPower -Name 'HibernateEnabled' -Value 0 -Type DWord
            Set-ItemProperty -Path $sandboxKeySession -Name 'HiberbootEnabled' -Value 0 -Type DWord
            $nonExistent = Join-Path $TestDrive 'nonexistent-hiberfil.sys'

            $status = Get-HibernateStatus -HiberfilePath $nonExistent -PowerKey $sandboxKeyPower -SessionPowerKey $sandboxKeySession
            $status.HibernateEnabled | Should -Be 0
            $status.HiberbootEnabled | Should -Be 0
            $status.HiberfilExists | Should -Be $false
            $status.HiberfilSizeBytes | Should -Be 0
        }

        It "handles missing registry keys cleanly without throwing" {
            $emptyPower = 'HKCU:\Software\TweakByjieTest\EmptyPower'
            $emptySession = 'HKCU:\Software\TweakByjieTest\EmptySession'
            New-Item -Path $emptyPower -Force | Out-Null
            New-Item -Path $emptySession -Force | Out-Null

            $status = Get-HibernateStatus -HiberfilePath (Join-Path $TestDrive 'no.sys') -PowerKey $emptyPower -SessionPowerKey $emptySession
            $status.HibernateEnabled | Should -Be 0
            $status.HiberbootEnabled | Should -Be 0
            $status.HiberfilExists | Should -Be $false
        }
    }

    Context "Backup & Restore Flow (Sandbox)" {
        BeforeAll {
            $script:OriginalHibernateBackup = $script:hibernateBackupFile
            $script:TestHibernateBackup = Join-Path $TestDrive 'hibernate-backup-test.json'
            $script:hibernateBackupFile = $script:TestHibernateBackup
        }

        AfterAll {
            $script:hibernateBackupFile = $script:OriginalHibernateBackup
        }

        It "Ensure-HibernateBackup generates valid snapshot and is idempotent" {
            Mock Get-HibernateStatus {
                return [pscustomobject]@{
                    HibernateEnabled      = 1
                    HiberbootEnabled      = 1
                    HiberfilExists        = $true
                    HiberfilSizeBytes     = [int64]4294967296
                    HiberfilSizeMB        = 4096.0
                    HiberfilSizeGB        = 4.0
                    HiberfilSizeFormatted = '4.00 GB'
                    HiberfilePath         = 'C:\hiberfil.sys'
                }
            }

            Ensure-HibernateBackup -BackupFile $script:TestHibernateBackup | Should -Be $true
            Test-Path -LiteralPath $script:TestHibernateBackup | Should -Be $true

            $backup = Get-Content -LiteralPath $script:TestHibernateBackup -Raw | ConvertFrom-Json
            Test-HibernateBackupSchema $backup | Should -Be $true
            $backup.State.HibernateEnabled | Should -Be 1
            $backup.State.HiberbootEnabled | Should -Be 1

            # Idempotency: re-running should reuse existing valid backup and return true
            Ensure-HibernateBackup -BackupFile $script:TestHibernateBackup | Should -Be $true
        }

        It "Ensure-HibernateBackup rejects corrupted existing snapshot without overwriting" {
            Set-Content -LiteralPath $script:TestHibernateBackup -Value '{"Version": 999}' -Encoding UTF8
            Ensure-HibernateBackup -BackupFile $script:TestHibernateBackup | Should -Be $false
        }

        It "Restore-HibernateBackup restores HibernateEnabled=1 and HiberbootEnabled=1" {
            $snap = [pscustomobject]@{
                Version   = 1
                Binding   = (Get-BackupMachineId)
                CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
                State     = [pscustomobject]@{
                    HibernateEnabled  = 1
                    HiberbootEnabled  = 1
                    HiberfilExists    = $true
                    HiberfilSizeBytes = [int64]4294967296
                }
            }
            ConvertTo-Json -InputObject $snap -Depth 5 | Set-Content -LiteralPath $script:TestHibernateBackup -Encoding UTF8

            $pcfgArgs = [System.Collections.Generic.List[string]]::new()
            Mock powercfg.exe {
                $pcfgArgs.Add(($args -join ' '))
                $global:LASTEXITCODE = 0
            }
            Mock Set-RegDword { }

            Restore-HibernateBackup -BackupFile $script:TestHibernateBackup | Should -Be $true
            $pcfgArgs | Should -Contain '-h on'
        }

        It "Restore-HibernateBackup restores HibernateEnabled=0 and cleans hiberfil.sys" {
            $snap = [pscustomobject]@{
                Version   = 1
                Binding   = (Get-BackupMachineId)
                CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
                State     = [pscustomobject]@{
                    HibernateEnabled  = 0
                    HiberbootEnabled  = 0
                    HiberfilExists    = $false
                    HiberfilSizeBytes = [int64]0
                }
            }
            ConvertTo-Json -InputObject $snap -Depth 5 | Set-Content -LiteralPath $script:TestHibernateBackup -Encoding UTF8

            $pcfgArgs = [System.Collections.Generic.List[string]]::new()
            Mock powercfg.exe {
                $pcfgArgs.Add(($args -join ' '))
                $global:LASTEXITCODE = 0
            }
            Mock Set-RegDword { }

            Restore-HibernateBackup -BackupFile $script:TestHibernateBackup | Should -Be $true
            $pcfgArgs | Should -Contain '-h off'
        }

        It "Restore-HibernateBackup fails cleanly when backup file does not exist" {
            $nonExistent = Join-Path $TestDrive 'no-such-backup.json'
            $beforeFail = $script:fail
            Restore-HibernateBackup -BackupFile $nonExistent | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }
    }

    Context "Invoke-HibernateModule Dispatcher" {
        BeforeAll {
            $script:OriginalHibernateBackup = $script:hibernateBackupFile
            $script:TestHibernateBackup = Join-Path $TestDrive 'hibernate-dispatch-test.json'
            $script:hibernateBackupFile = $script:TestHibernateBackup
        }

        AfterAll {
            $script:hibernateBackupFile = $script:OriginalHibernateBackup
        }

        It "Action 0 executes in read-only mode and returns true" {
            Mock Get-HibernateStatus {
                return [pscustomobject]@{
                    HibernateEnabled      = 1
                    HiberbootEnabled      = 1
                    HiberfilExists        = $false
                    HiberfilSizeBytes     = [int64]0
                    HiberfilSizeMB        = 0.0
                    HiberfilSizeGB        = 0.0
                    HiberfilSizeFormatted = '0 MB'
                    HiberfilePath         = 'C:\hiberfil.sys'
                }
            }

            Invoke-HibernateModule -Action '0' | Should -Be $true
        }

        It "Action 1 backs up, runs powercfg -h off, sets HiberbootEnabled=0, and requests restart" {
            Mock Ensure-HibernateBackup { return $true }
            $pcfgArgs = [System.Collections.Generic.List[string]]::new()
            Mock powercfg.exe {
                $pcfgArgs.Add(($args -join ' '))
                $global:LASTEXITCODE = 0
            }
            Mock Set-RegDword { }
            Mock Request-Restart { }

            Invoke-HibernateModule -Action '1' | Should -Be $true
            $pcfgArgs | Should -Contain '-h off'
        }

        It "Action 1 aborts modification when backup fails" {
            Mock Ensure-HibernateBackup { return $false }
            Mock powercfg.exe { throw 'powercfg should not be called' }

            Invoke-HibernateModule -Action '1' | Should -Be $false
        }

        It "Action 1 fails cleanly when powercfg -h off exits non-zero" {
            Mock Ensure-HibernateBackup { return $true }
            Mock powercfg.exe {
                $global:LASTEXITCODE = 1
                return 'Access denied'
            }

            $beforeFail = $script:fail
            Invoke-HibernateModule -Action '1' | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }

        It "Action 2 restores from backup and requests restart" {
            Mock Restore-HibernateBackup { return $true }
            Mock Request-Restart { }

            Invoke-HibernateModule -Action '2' | Should -Be $true
        }

        It "Action with invalid input fails cleanly" {
            $beforeFail = $script:fail
            Invoke-HibernateModule -Action '999' | Should -Be $false
            $script:fail | Should -BeGreaterThan $beforeFail
        }

        It "Action empty in non-interactive mode fails cleanly" {
            $script:TweakNonInteractive = $true
            try {
                $beforeFail = $script:fail
                Invoke-HibernateModule -Action '' | Should -Be $false
                $script:fail | Should -BeGreaterThan $beforeFail
            } finally {
                $script:TweakNonInteractive = $false
            }
        }
    }

    Context "Pipeline Hygiene" {
        It "Ensure-HibernateBackup does not leak arbitrary objects into pipeline" {
            Mock Get-HibernateStatus {
                return [pscustomobject]@{
                    HibernateEnabled      = 1
                    HiberbootEnabled      = 1
                    HiberfilExists        = $false
                    HiberfilSizeBytes     = [int64]0
                    HiberfilSizeMB        = 0.0
                    HiberfilSizeGB        = 0.0
                    HiberfilSizeFormatted = '0 MB'
                    HiberfilePath         = 'C:\hiberfil.sys'
                }
            }
            $testFile = Join-Path $TestDrive 'pipeline-ensure.json'
            $out = @(Ensure-HibernateBackup -BackupFile $testFile)
            $out.Count | Should -Be 1
            $out[0] | Should -Be $true
        }

        It "Restore-HibernateBackup outputs exactly one boolean" {
            $testFile = Join-Path $TestDrive 'pipeline-restore.json'
            $snap = [pscustomobject]@{
                Version   = 1
                Binding   = (Get-BackupMachineId)
                CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
                State     = [pscustomobject]@{
                    HibernateEnabled  = 1
                    HiberbootEnabled  = 1
                    HiberfilExists    = $false
                    HiberfilSizeBytes = [int64]0
                }
            }
            ConvertTo-Json -InputObject $snap -Depth 5 | Set-Content -LiteralPath $testFile -Encoding UTF8
            Mock powercfg.exe { $global:LASTEXITCODE = 0 }
            Mock Set-RegDword { }

            $out = @(Restore-HibernateBackup -BackupFile $testFile)
            $out.Count | Should -Be 1
            $out[0] | Should -Be $true
        }

        It "Invoke-HibernateModule does not leak extraneous pipeline output" {
            Mock Ensure-HibernateBackup { return $true }
            Mock powercfg.exe { $global:LASTEXITCODE = 0 }
            Mock Set-RegDword { }
            Mock Request-Restart { }

            $out = @(Invoke-HibernateModule -Action '1')
            $out.Count | Should -Be 1
            $out[0] | Should -Be $true
        }
    }
}
