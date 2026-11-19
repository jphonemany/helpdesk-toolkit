# These tests never touch real accounts: every Windows account command is mocked,
# so they run safely on any machine (and in CI) without admin rights.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
    $env:HD_LOG_PATH = Join-Path $TestDrive 'audit-log.csv'
}
AfterAll { Remove-Item Env:\HD_LOG_PATH -ErrorAction SilentlyContinue }

Describe 'Import-HdNewHire' {
    BeforeEach {
        Remove-Item $env:HD_LOG_PATH -ErrorAction SilentlyContinue
        Mock -ModuleName HelpdeskToolkit Get-LocalUser { @([pscustomobject]@{ Name = 'jsmith' }) }
        Mock -ModuleName HelpdeskToolkit New-LocalUser { }
        Mock -ModuleName HelpdeskToolkit Add-LocalGroupMember { }
        Mock -ModuleName HelpdeskToolkit Set-HdMustChangePassword { }
        $csv = Join-Path $TestDrive 'hires.csv'
        @(
            'FirstName,LastName,Department'
            'John,Smith,Finance'
            'Jane,Doe,HR'
            'Jamie,Doe,IT'
            ',Nolast,Sales'
        ) | Set-Content -Path $csv
    }

    It 'creates valid rows, avoids existing and in-batch name clashes, skips bad rows' {
        $out = @(Import-HdNewHire -Path $csv)
        $out.Count | Should -Be 4
        $out[0].Username | Should -Be 'jsmith2'   # jsmith already exists
        $out[1].Username | Should -Be 'jdoe'
        $out[2].Username | Should -Be 'jdoe2'     # clashes with Jane created earlier in the same batch
        $out[3].Status | Should -Be 'Skipped'
        @($out | Where-Object Status -eq 'Created').Count | Should -Be 3
        Should -Invoke -ModuleName HelpdeskToolkit New-LocalUser -Times 3 -Exactly
        Should -Invoke -ModuleName HelpdeskToolkit Set-HdMustChangePassword -Times 3 -Exactly
    }

    It 'returns a temp password only for created accounts' {
        $out = @(Import-HdNewHire -Path $csv)
        $out[0].TempPassword.Length | Should -Be 16
        $out[3].TempPassword | Should -BeNullOrEmpty
    }

    It 'changes nothing with -WhatIf' {
        $out = @(Import-HdNewHire -Path $csv -WhatIf)
        Should -Invoke -ModuleName HelpdeskToolkit New-LocalUser -Times 0 -Exactly
        @($out | Where-Object Status -eq 'WhatIf').Count | Should -Be 3
    }

    It 'keeps going when one account fails, and reports it' {
        Mock -ModuleName HelpdeskToolkit New-LocalUser { throw 'Access is denied.' } -ParameterFilter { $Name -eq 'jdoe' }
        $out = @(Import-HdNewHire -Path $csv)
        ($out | Where-Object Username -eq 'jdoe').Status | Should -Be 'Failed'
        ($out | Where-Object Username -eq 'jdoe2').Status | Should -Be 'Created'
    }

    It 'writes an audit line per row and never logs passwords' {
        $out = @(Import-HdNewHire -Path $csv)
        $log = @(Import-Csv $env:HD_LOG_PATH)
        $log.Count | Should -Be 4
        $text = Get-Content $env:HD_LOG_PATH -Raw
        foreach ($p in ($out | Where-Object TempPassword | ForEach-Object TempPassword)) {
            $text.Contains($p) | Should -BeFalse
        }
    }

    It 'rejects a CSV with missing columns' {
        $bad = Join-Path $TestDrive 'bad.csv'
        'First,Last' , 'a,b' | Set-Content $bad
        { Import-HdNewHire -Path $bad } | Should -Throw '*missing column*'
    }
}

Describe 'Disable-HdUser' {
    BeforeEach {
        Mock -ModuleName HelpdeskToolkit Disable-LocalUser { }
        Mock -ModuleName HelpdeskToolkit Set-LocalUser { }
    }

    It 'disables an enabled account and records a short description' {
        Mock -ModuleName HelpdeskToolkit Get-LocalUser { [pscustomobject]@{ Name = 'jdoe'; Enabled = $true } }
        $r = Disable-HdUser -Username jdoe -Reason 'Left the company, ticket 1042 - a long reason that will be cut'
        $r.Status | Should -Be 'Disabled'
        Should -Invoke -ModuleName HelpdeskToolkit Disable-LocalUser -Times 1 -Exactly
        Should -Invoke -ModuleName HelpdeskToolkit Set-LocalUser -Times 1 -Exactly -ParameterFilter { $Description.Length -le 48 }
    }

    It 'does nothing to an account that is already disabled' {
        Mock -ModuleName HelpdeskToolkit Get-LocalUser { [pscustomobject]@{ Name = 'jdoe'; Enabled = $false } }
        Disable-HdUser -Username jdoe -Reason 'x' -WarningAction SilentlyContinue
        Should -Invoke -ModuleName HelpdeskToolkit Disable-LocalUser -Times 0 -Exactly
    }

    It 'errors on an unknown account' {
        Mock -ModuleName HelpdeskToolkit Get-LocalUser { $null }
        { Disable-HdUser -Username ghost -Reason 'x' -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Reset-HdPassword' {
    BeforeEach {
        Mock -ModuleName HelpdeskToolkit Get-LocalUser { [pscustomobject]@{ Name = 'jdoe'; Enabled = $true } }
        Mock -ModuleName HelpdeskToolkit Set-LocalUser { }
        Mock -ModuleName HelpdeskToolkit Set-HdMustChangePassword { }
        Mock -ModuleName HelpdeskToolkit Clear-HdAccountLockout { $true }
    }

    It 'unlocks, sets a new temp password and forces a change at logon' {
        $r = Reset-HdPassword -Username jdoe
        $r.WasLocked | Should -BeTrue
        $r.TempPassword.Length | Should -Be 16
        Should -Invoke -ModuleName HelpdeskToolkit Set-LocalUser -Times 1 -Exactly
        Should -Invoke -ModuleName HelpdeskToolkit Set-HdMustChangePassword -Times 1 -Exactly
    }

    It '-UnlockOnly leaves the password alone' {
        $r = Reset-HdPassword -Username jdoe -UnlockOnly
        $r.PasswordReset | Should -BeFalse
        $r.TempPassword | Should -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Set-LocalUser -Times 0 -Exactly
    }

    It 'refuses to reset a disabled (offboarded) account' {
        Mock -ModuleName HelpdeskToolkit Get-LocalUser { [pscustomobject]@{ Name = 'jdoe'; Enabled = $false } }
        { Reset-HdPassword -Username jdoe } | Should -Throw '*disabled*'
    }
}
