BeforeAll {
    . "$PSScriptRoot/../tools/Test-CrossRepoCoverage.ps1"
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
}

Describe 'Coverage tool source reference parsing' {
    It 'parses a file-only reference' {
        $refs = Get-ModuleSourceRefs 'see `Modules/Common.ps1` here'
        @($refs).Count | Should -Be 1
        $refs[0].Path | Should -Be 'Modules/Common.ps1'
        $refs[0].Function | Should -Be ''
    }

    It 'parses a slash-separated function reference' {
        $refs = Get-ModuleSourceRefs '`Modules/Common.ps1/Set-RegDword`'
        @($refs).Count | Should -Be 1
        $refs[0].Path | Should -Be 'Modules/Common.ps1'
        $refs[0].Function | Should -Be 'Set-RegDword'
    }

    It 'parses a hash-separated function reference' {
        $refs = Get-ModuleSourceRefs 'Modules/Backup.Nvme.ps1#Test-NativeNvmeConfigured'
        $refs[0].Path | Should -Be 'Modules/Backup.Nvme.ps1'
        $refs[0].Function | Should -Be 'Test-NativeNvmeConfigured'
    }

    It 'parses a legacy line-number reference without inventing a function' {
        $refs = Get-ModuleSourceRefs 'Modules/Backup.Nvme.ps1:75'
        @($refs).Count | Should -Be 1
        $refs[0].Path | Should -Be 'Modules/Backup.Nvme.ps1'
        $refs[0].Function | Should -Be ''
    }

    It 'ignores wildcard module globs' {
        Get-ModuleSourceRefs '`Modules/Backup.*.ps1`' | Should -BeNullOrEmpty
    }

    It 'deduplicates repeated references' {
        $refs = Get-ModuleSourceRefs '`Modules/Common.ps1/Set-RegDword` and again `Modules/Common.ps1/Set-RegDword`'
        @($refs).Count | Should -Be 1
    }
}

Describe 'Coverage tool source reference validation' {
    It 'accepts a real file with the referenced function' {
        $ref = [pscustomobject]@{ Text = ''; Path = 'Modules/Common.ps1'; Function = 'Set-RegDword' }
        Test-ModuleSourceRef $ref $script:repoRoot | Should -BeNullOrEmpty
    }

    It 'accepts a real file without a function requirement' {
        $ref = [pscustomobject]@{ Text = ''; Path = 'Modules/Menu.ps1'; Function = '' }
        Test-ModuleSourceRef $ref $script:repoRoot | Should -BeNullOrEmpty
    }

    It 'rejects a missing function with a descriptive problem' {
        $ref = [pscustomobject]@{ Text = ''; Path = 'Modules/Common.ps1'; Function = 'Set-DoesNotExist' }
        Test-ModuleSourceRef $ref $script:repoRoot | Should -Not -BeNullOrEmpty
    }

    It 'rejects a missing file with a descriptive problem' {
        $ref = [pscustomobject]@{ Text = ''; Path = 'Modules/File.ps1'; Function = '' }
        Test-ModuleSourceRef $ref $script:repoRoot | Should -Not -BeNullOrEmpty
    }
}
