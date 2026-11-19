function Get-HdThresholdStatus {
    <#
    .SYNOPSIS
    Turns a "percent free" number into OK / Warning / Critical.

    .DESCRIPTION
    Pure function (no system calls) so the rules are easy to test and easy to change.
    Defaults: below 15% free is a Warning, below 5% is Critical.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][double]$PercentFree,
        [double]$WarningBelow = 15,
        [double]$CriticalBelow = 5
    )
    if ($PercentFree -lt $CriticalBelow) { return 'Critical' }
    if ($PercentFree -lt $WarningBelow) { return 'Warning' }
    return 'OK'
}

function Get-HdWorstStatus {
    # Overall status is the worst of the individual checks.
    param([string[]]$Status)
    if ($Status -contains 'Critical') { return 'Critical' }
    if ($Status -contains 'Warning') { return 'Warning' }
    return 'OK'
}
