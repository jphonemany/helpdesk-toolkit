function Reset-HdPassword {
    <#
    .SYNOPSIS
    The most common help desk ticket: "I forgot my password" / "I'm locked out".

    .DESCRIPTION
    Sets a new random temporary password, unlocks the account if it was locked, and forces a
    password change at next logon. Returns the temporary password so the technician can give
    it to the user after verifying their identity.
    Use -UnlockOnly when the user knows their password but locked themselves out.

    .EXAMPLE
    Reset-HdPassword -Username jdoe

    .EXAMPLE
    Reset-HdPassword -Username jdoe -UnlockOnly
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The password is generated here and must be shown once to the technician to hand to the user.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Username,
        [switch]$UnlockOnly
    )

    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-HdLog -Action 'PasswordReset' -Target $Username -Result Failed -Detail 'Account not found'
        throw "No local account named '$Username'."
    }
    if (-not $user.Enabled) {
        Write-HdLog -Action 'PasswordReset' -Target $Username -Result Skipped -Detail 'Account is disabled'
        throw "'$Username' is disabled. Check whether this user was offboarded before re-enabling."
    }

    $action = 'Reset password and unlock'
    if ($UnlockOnly) { $action = 'Unlock account' }
    if (-not $PSCmdlet.ShouldProcess($Username, $action)) { return }

    $wasLocked = Clear-HdAccountLockout -Username $Username
    $password = ''
    if (-not $UnlockOnly) {
        $password = New-HdPassword
        Set-LocalUser -Name $Username -Password (ConvertTo-SecureString $password -AsPlainText -Force) -ErrorAction Stop
        Set-HdMustChangePassword -Username $Username
    }

    $detail = "Unlocked: $wasLocked; password reset: $(-not $UnlockOnly)"
    Write-HdLog -Action 'PasswordReset' -Target $Username -Result Success -Detail $detail
    [pscustomobject]@{
        Username      = $Username
        WasLocked     = $wasLocked
        PasswordReset = (-not $UnlockOnly)
        TempPassword  = $password
    }
}
