BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

Describe 'ConvertTo-HdUsername' {
    It 'uses first initial + last name, lowercase' {
        InModuleScope HelpdeskToolkit { ConvertTo-HdUsername -FirstName 'Jane' -LastName 'Doe' } | Should -Be 'jdoe'
    }
    It 'strips accents, apostrophes, hyphens and spaces' {
        InModuleScope HelpdeskToolkit { ConvertTo-HdUsername -FirstName 'José' -LastName "O'Brien-Smith" } | Should -Be 'jobriensmith'
    }
    It 'adds a number when the name is taken (case-insensitive)' {
        InModuleScope HelpdeskToolkit { ConvertTo-HdUsername -FirstName 'John' -LastName 'Smith' -Existing 'JSmith', 'jsmith2' } | Should -Be 'jsmith3'
    }
    It 'keeps names within the 20-character Windows limit, including the number' {
        $name = InModuleScope HelpdeskToolkit {
            ConvertTo-HdUsername -FirstName 'Alexandra' -LastName 'Wolfeschlegelsteinhausen' -Existing 'awolfeschlegelsteinh'
        }
        $name | Should -Be 'awolfeschlegelstein2'
        $name.Length | Should -BeLessOrEqual 20
    }
    It 'throws when a name has no letters' {
        { InModuleScope HelpdeskToolkit { ConvertTo-HdUsername -FirstName '123' -LastName 'Doe' } } | Should -Throw
    }
}

Describe 'New-HdPassword' {
    It 'has the requested length' {
        (InModuleScope HelpdeskToolkit { New-HdPassword -Length 20 }).Length | Should -Be 20
    }
    It 'always contains upper, lower, digit and symbol (checked 200 times)' {
        $passwords = InModuleScope HelpdeskToolkit { 1..200 | ForEach-Object { New-HdPassword } }
        foreach ($p in $passwords) {
            $p | Should -MatchExactly '[A-Z]'
            $p | Should -MatchExactly '[a-z]'
            $p | Should -Match '[0-9]'
            $p | Should -Match '[!@#$%*?\-+=]'
        }
    }
    It 'never uses look-alike characters 0, O, 1, l or I' {
        $joined = -join (InModuleScope HelpdeskToolkit { 1..200 | ForEach-Object { New-HdPassword } })
        $joined | Should -Not -MatchExactly '[0O1lI]'
    }
    It 'does not repeat itself' {
        $passwords = InModuleScope HelpdeskToolkit { 1..100 | ForEach-Object { New-HdPassword } }
        @($passwords | Select-Object -Unique).Count | Should -Be 100
    }
    It 'refuses lengths under 12' {
        { InModuleScope HelpdeskToolkit { New-HdPassword -Length 8 } } | Should -Throw
    }
}

Describe 'Get-HdThresholdStatus' {
    It 'returns <Expected> for <Pct>% free' -ForEach @(
        @{ Pct = 50;   Expected = 'OK' }
        @{ Pct = 15;   Expected = 'OK' }
        @{ Pct = 14.9; Expected = 'Warning' }
        @{ Pct = 5;    Expected = 'Warning' }
        @{ Pct = 4.9;  Expected = 'Critical' }
        @{ Pct = 0;    Expected = 'Critical' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters @{ Pct = $Pct } { param($Pct) Get-HdThresholdStatus -PercentFree $Pct } | Should -Be $Expected
    }
    It 'overall status is the worst one' {
        InModuleScope HelpdeskToolkit { Get-HdWorstStatus -Status 'OK', 'Warning', 'OK' } | Should -Be 'Warning'
        InModuleScope HelpdeskToolkit { Get-HdWorstStatus -Status 'Warning', 'Critical' } | Should -Be 'Critical'
        InModuleScope HelpdeskToolkit { Get-HdWorstStatus -Status 'OK' } | Should -Be 'OK'
    }
}

Describe 'ConvertTo-HdSoftwareItem' {
    It 'skips blanks, updates and system components, removes duplicates and parses dates' {
        $raw = @(
            [pscustomobject]@{ DisplayName = 'Google Chrome'; DisplayVersion = '131.0'; Publisher = 'Google LLC'; InstallDate = '20261101' }
            [pscustomobject]@{ DisplayName = 'Google Chrome'; DisplayVersion = '131.0'; Publisher = 'Google LLC'; InstallDate = '20261101' }
            [pscustomobject]@{ DisplayName = '7-Zip'; DisplayVersion = '24.08'; Publisher = 'Igor Pavlov'; InstallDate = $null }
            [pscustomobject]@{ DisplayName = 'Security Update for Office'; ReleaseType = 'Security Update' }
            [pscustomobject]@{ DisplayName = 'Hidden runtime'; SystemComponent = 1 }
            [pscustomobject]@{ DisplayName = 'KB500001'; ParentKeyName = 'Office' }
            [pscustomobject]@{ DisplayName = $null }
        )
        $items = @(ConvertTo-HdSoftwareItem -Entry $raw)
        $items.Count | Should -Be 2
        $items[0].Name | Should -Be '7-Zip'                       # sorted by name
        $items[0].InstallDate | Should -BeNullOrEmpty
        $items[1].Name | Should -Be 'Google Chrome'
        $items[1].InstallDate | Should -Be ([datetime]'2026-11-01')
    }
    It 'treats impossible install dates as unknown instead of crashing (found on a real PC)' {
        $raw = @(
            [pscustomobject]@{ DisplayName = 'Bad date app'; InstallDate = '00000000' }
            [pscustomobject]@{ DisplayName = 'Feb 31 app'; InstallDate = '20240231' }
            [pscustomobject]@{ DisplayName = 'Text date app'; InstallDate = 'Nov 1 2026' }
        )
        $items = @(ConvertTo-HdSoftwareItem -Entry $raw)
        $items.Count | Should -Be 3
        $items | ForEach-Object { $_.InstallDate | Should -BeNullOrEmpty }
    }
}
