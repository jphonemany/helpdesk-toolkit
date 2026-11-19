function New-HdPassword {
    <#
    .SYNOPSIS
    Generates a random temporary password that meets Windows complexity rules.

    .DESCRIPTION
    Uses the operating system's cryptographic random number generator (not Get-Random, which
    is predictable). Every password has at least one uppercase letter, lowercase letter, digit
    and symbol. Look-alike characters (0/O, 1/l/I) are left out so the user can read it over
    the phone without mistakes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only generates a string; changes nothing on the system.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(12, 64)][int]$Length = 16
    )

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!@#$%*?-+='
    )
    $all = -join $sets

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $chars = New-Object System.Collections.Generic.List[char]
        # One guaranteed character from each set...
        foreach ($set in $sets) { $chars.Add($set[(Get-HdRandomIndex $rng $set.Length)]) }
        # ...then fill the rest from all sets.
        while ($chars.Count -lt $Length) { $chars.Add($all[(Get-HdRandomIndex $rng $all.Length)]) }

        # Shuffle (Fisher-Yates) so the guaranteed characters aren't always at the front.
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = Get-HdRandomIndex $rng ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        return -join $chars
    }
    finally {
        $rng.Dispose()
    }
}

function Get-HdRandomIndex {
    # Unbiased random integer in [0, $Max) using rejection sampling.
    param($Rng, [int]$Max)
    $bytes = New-Object byte[] 4
    $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)
    do {
        $Rng.GetBytes($bytes)
        $value = [BitConverter]::ToUInt32($bytes, 0)
    } while ($value -ge $limit)
    return [int]($value % [uint32]$Max)
}
