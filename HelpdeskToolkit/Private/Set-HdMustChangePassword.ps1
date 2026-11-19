function Set-HdMustChangePassword {
    <#
    .SYNOPSIS
    Forces "user must change password at next logon" on a local account.

    .DESCRIPTION
    New-LocalUser has no switch for this, so it goes through the older WinNT (ADSI) provider.
    Kept in its own function so tests can mock it without touching real accounts.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Internal helper; the public caller already asks ShouldProcess (-WhatIf).')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Username)
    $account = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
    $account.PasswordExpired = 1
    $account.SetInfo()
}

function Clear-HdAccountLockout {
    <#
    .SYNOPSIS
    Unlocks a local account that was locked after too many wrong passwords.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Username)
    $account = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
    if ($account.IsAccountLocked) {
        $account.IsAccountLocked = $false
        $account.SetInfo()
        return $true
    }
    return $false
}
