BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "Backup machine binding" {

    It "Get-BackupMachineId returns a 64-char hex digest" {
        $id = Get-BackupMachineId
        $id | Should -Match '^[0-9a-f]{64}$'
    }

    It "Test-SecurityMitigationBackupSchema rejects a valid-shape backup without matching binding" {
        $defs = @(@{ Path = 'HKCU:\Software\TweakByjieTest\Bind'; Name = 'V' })
        $backup = [pscustomobject]@{
            Version = 1
            Values = @([pscustomobject]@{ Path = $defs[0].Path; Name = 'V'; Present = $false; Value = $null })
        }
        Test-SecurityMitigationBackupSchema $backup $defs | Should -Be $false
        $backup | Add-Member -NotePropertyName Binding -NotePropertyValue ('f' * 64)
        Test-SecurityMitigationBackupSchema $backup $defs | Should -Be $false
        ($backup.Binding = Get-BackupMachineId) | Out-Null
        Test-SecurityMitigationBackupSchema $backup $defs | Should -Be $true
    }

    It "Test-BcdBackupSchema rejects a valid-shape backup without matching binding" {
        $names = $script:bcdManagedValues
        $values = @($names | ForEach-Object { [pscustomobject]@{ Name = $_; Present = $false; Value = $null } })
        $backup = [pscustomobject]@{ Version = 1; Object = '{current}'; Values = $values }
        Test-BcdBackupSchema $backup $names | Should -Be $false
        $backup | Add-Member -NotePropertyName Binding -NotePropertyValue (Get-BackupMachineId)
        Test-BcdBackupSchema $backup $names | Should -Be $true
    }

    It "Ensure-SecurityMitigationBackup stamps the current machine binding" {
        $key = 'HKCU:\Software\TweakByjieTest\Bind'
        New-Item -Path $key -Force | Out-Null
        $defs = @(@{ Path = $key; Name = 'V' })
        $origFile = $script:securityMitigationBackupFile
        $script:securityMitigationBackupFile = Join-Path $TestDrive 'bind-sm.json'
        try {
            Ensure-SecurityMitigationBackup -Definitions $defs | Should -Be $true
            $backup = Get-Content $script:securityMitigationBackupFile -Raw | ConvertFrom-Json
            [string]$backup.Binding | Should -Be (Get-BackupMachineId)
        } finally {
            Remove-Item 'HKCU:\Software\TweakByjieTest' -Recurse -Force -ErrorAction SilentlyContinue
            if ($origFile) { $script:securityMitigationBackupFile = $origFile }
        }
    }
}
