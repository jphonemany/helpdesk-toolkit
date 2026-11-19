function Write-HdLog {
    <#
    .SYNOPSIS
    Appends one line to the audit log (CSV): who did what, to which account, and whether it worked.

    .DESCRIPTION
    Help desks need a record of every account change for security reviews and for answering
    "who disabled my account?". Passwords are never written to the log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][ValidateSet('Success', 'Failed', 'Skipped', 'WhatIf')][string]$Result,
        [string]$Detail = ''
    )

    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('s')
        Operator  = "$env:USERDOMAIN\$env:USERNAME"
        Action    = $Action
        Target    = $Target
        Result    = $Result
        Detail    = $Detail
    }
    $path = Get-HdLogPath
    $dir = Split-Path -Parent $path
    # -WhatIf:$false: a preview run still records what it skipped; the log itself is not a "change".
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null }
    $entry | Export-Csv -Path $path -Append -NoTypeInformation -Encoding UTF8 -WhatIf:$false
}

function Get-HdLogPath {
    if ($env:HD_LOG_PATH) { return $env:HD_LOG_PATH }
    return (Join-Path $env:LOCALAPPDATA 'HelpdeskToolkit\audit-log.csv')
}
