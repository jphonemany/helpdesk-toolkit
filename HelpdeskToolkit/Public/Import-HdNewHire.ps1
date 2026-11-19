function Import-HdNewHire {
    <#
    .SYNOPSIS
    Onboarding: creates a local account for every new hire in a CSV file.

    .DESCRIPTION
    The CSV needs FirstName, LastName and Department columns. For each valid row this:
      1. builds a unique username (first initial + last name),
      2. creates the account with a random temporary password,
      3. forces a password change at first logon,
      4. adds the account to a group (default: Users),
      5. writes an audit-log line.
    Bad rows are skipped and reported; one bad row never stops the rest of the batch.
    Run with -WhatIf first to preview without changing anything.

    .OUTPUTS
    One object per row: Username, FullName, Department, TempPassword, Status, Message.
    TempPassword is only filled for accounts that were actually created. Hand it to the user
    through a secure channel (in person or by phone), never by email.

    .EXAMPLE
    Import-HdNewHire -Path .\examples\new-hires.csv -WhatIf
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The password is generated here and must be shown once to the technician to hand to the user.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })][string]$Path,
        [string]$Group = 'Users'
    )

    $rows = @(Import-Csv -Path $Path)
    $required = 'FirstName', 'LastName', 'Department'
    $columns = @()
    if ($rows.Count -gt 0) { $columns = $rows[0].PSObject.Properties.Name }
    $missing = @($required | Where-Object { $columns -notcontains $_ })
    if ($rows.Count -eq 0) { throw "'$Path' has no rows." }
    if ($missing.Count -gt 0) { throw "'$Path' is missing column(s): $($missing -join ', ')." }

    # Track existing names plus the ones created in this batch, so two "John Smith"s get jsmith and jsmith2.
    $existing = New-Object System.Collections.Generic.List[string]
    foreach ($u in @(Get-LocalUser)) { $existing.Add($u.Name) }

    $line = 1   # header is line 1
    foreach ($row in $rows) {
        $line++
        $first = "$($row.FirstName)".Trim()
        $last  = "$($row.LastName)".Trim()
        $dept  = "$($row.Department)".Trim()
        $result = [pscustomobject]@{
            Line = $line; Username = ''; FullName = "$first $last".Trim(); Department = $dept
            TempPassword = ''; Status = ''; Message = ''
        }

        if (-not $first -or -not $last -or -not $dept) {
            $result.Status = 'Skipped'
            $result.Message = "Line ${line}: FirstName, LastName and Department are all required."
            Write-HdLog -Action 'Onboard' -Target $result.FullName -Result Skipped -Detail $result.Message
            $result; continue
        }

        try {
            $username = ConvertTo-HdUsername -FirstName $first -LastName $last -Existing $existing
        }
        catch {
            $result.Status = 'Skipped'; $result.Message = $_.Exception.Message
            Write-HdLog -Action 'Onboard' -Target $result.FullName -Result Skipped -Detail $result.Message
            $result; continue
        }
        $result.Username = $username
        $existing.Add($username)

        if (-not $PSCmdlet.ShouldProcess($username, "Create account for $($result.FullName) ($dept)")) {
            $result.Status = 'WhatIf'; $result.Message = 'Preview only; nothing was created.'
            $result; continue
        }

        try {
            $password = New-HdPassword
            $secure = ConvertTo-SecureString $password -AsPlainText -Force
            New-LocalUser -Name $username -FullName $result.FullName -Description "Dept: $dept" `
                -Password $secure -ErrorAction Stop | Out-Null
            Set-HdMustChangePassword -Username $username
            Add-LocalGroupMember -Group $Group -Member $username -ErrorAction Stop
            $result.TempPassword = $password
            $result.Status = 'Created'
            $result.Message = "Added to '$Group'. Must change password at first logon."
            Write-HdLog -Action 'Onboard' -Target $username -Result Success -Detail "$($result.FullName), $dept"
        }
        catch {
            $result.Status = 'Failed'; $result.Message = $_.Exception.Message
            Write-HdLog -Action 'Onboard' -Target $username -Result Failed -Detail $result.Message
        }
        $result
    }
}
