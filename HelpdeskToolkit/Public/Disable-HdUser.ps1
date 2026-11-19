function Disable-HdUser {
    <#
    .SYNOPSIS
    Offboarding: disables an account (it is not deleted) and records why.

    .DESCRIPTION
    Accounts are disabled rather than deleted, so files, mail and audit history stay intact
    and the account can be restored if the departure was a mistake. The reason and date are
    written into the account description and the audit log.

    .EXAMPLE
    Disable-HdUser -Username jdoe -Reason "Last day 2026-11-30, ticket #1042"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)][Alias('Name')][string]$Username,
        [Parameter(Mandatory)][string]$Reason
    )
    process {
        $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if (-not $user) {
            Write-HdLog -Action 'Offboard' -Target $Username -Result Failed -Detail 'Account not found'
            Write-Error "No local account named '$Username'."
            return
        }
        if (-not $user.Enabled) {
            Write-HdLog -Action 'Offboard' -Target $Username -Result Skipped -Detail 'Already disabled'
            Write-Warning "'$Username' is already disabled."
            return
        }
        if (-not $PSCmdlet.ShouldProcess($Username, 'Disable account')) { return }

        $stamp = (Get-Date).ToString('yyyy-MM-dd')
        # Local account descriptions are limited to 48 characters.
        $description = "Disabled $stamp`: $Reason"
        if ($description.Length -gt 48) { $description = $description.Substring(0, 48) }

        Disable-LocalUser -Name $Username -ErrorAction Stop
        Set-LocalUser -Name $Username -Description $description -ErrorAction Stop
        Write-HdLog -Action 'Offboard' -Target $Username -Result Success -Detail $Reason
        [pscustomobject]@{ Username = $Username; Status = 'Disabled'; Reason = $Reason; Date = $stamp }
    }
}
