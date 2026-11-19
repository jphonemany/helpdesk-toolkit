function ConvertTo-HdUsername {
    <#
    .SYNOPSIS
    Builds a username (first initial + last name) that doesn't collide with an existing one.

    .DESCRIPTION
    "Jane O'Brien-Smith" becomes "jobriensmith". Accents and punctuation are stripped so the
    name is safe on every system. Windows local account names are limited to 20 characters,
    so long names are cut. If the name is taken, a number is added: jdoe, jdoe2, jdoe3...
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName,
        [string[]]$Existing = @()
    )

    $first = ConvertTo-HdAsciiName $FirstName
    $last  = ConvertTo-HdAsciiName $LastName
    if (-not $first -or -not $last) {
        throw "Can't build a username from '$FirstName $LastName': it needs at least one letter in each name."
    }

    $base = ($first.Substring(0, 1) + $last).ToLowerInvariant()
    $maxLength = 20
    if ($base.Length -gt $maxLength) { $base = $base.Substring(0, $maxLength) }

    $taken = @{}
    foreach ($name in $Existing) { $taken[$name.ToLowerInvariant()] = $true }

    if (-not $taken.ContainsKey($base)) { return $base }

    for ($n = 2; $n -lt 1000; $n++) {
        $suffix = [string]$n
        $stem = $base
        if ($stem.Length + $suffix.Length -gt $maxLength) { $stem = $stem.Substring(0, $maxLength - $suffix.Length) }
        $candidate = $stem + $suffix
        if (-not $taken.ContainsKey($candidate)) { return $candidate }
    }
    throw "No free username left for '$FirstName $LastName'."
}

function ConvertTo-HdAsciiName {
    # Removes accents (e.g. an accented e becomes a plain e) and keeps only a-z / A-Z.
    param([string]$Text)
    if (-not $Text) { return '' }
    $decomposed = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in $decomposed.ToCharArray()) {
        if ($ch -match '[A-Za-z]') { [void]$builder.Append($ch) }
    }
    return $builder.ToString()
}
