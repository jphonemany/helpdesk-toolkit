function Get-HdSoftwareInventory {
    <#
    .SYNOPSIS
    Lists installed software (name, version, publisher, install date), optionally to CSV.

    .DESCRIPTION
    Reads the same registry "Uninstall" keys that Settings > Apps uses, for 64-bit apps,
    32-bit apps and per-user apps. This is faster and safer than Win32_Product, which can
    trigger a repair of every MSI package on the machine.
    Useful for audits ("who still has the old VPN client?") and license counts.

    .EXAMPLE
    Get-HdSoftwareInventory -Name '*Chrome*'

    .EXAMPLE
    Get-HdSoftwareInventory -CsvPath .\inventory.csv
    #>
    [CmdletBinding()]
    param(
        [string]$Name = '*',
        [string]$CsvPath
    )

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = foreach ($key in $keys) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    }
    $items = ConvertTo-HdSoftwareItem -Entry $entries | Where-Object { $_.Name -like $Name }

    if ($CsvPath) { $items | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 }
    $items
}

function ConvertTo-HdSoftwareItem {
    <#
    .SYNOPSIS
    Cleans raw registry entries into one row per app (exported so it can be tested on its own).

    .DESCRIPTION
    Skips entries with no display name, Windows updates and system components (they clutter
    the list and aren't "apps"), removes duplicates that appear under more than one key, and
    turns the registry's yyyyMMdd install date into a real date.
    #>
    [CmdletBinding()]
    param([object[]]$Entry)

    $seen = @{}
    $rows = foreach ($e in $Entry) {
        if (-not $e -or -not $e.DisplayName) { continue }
        if ($e.SystemComponent -eq 1) { continue }
        if ($e.ParentKeyName -or $e.ReleaseType -in @('Update', 'Hotfix', 'Security Update')) { continue }

        $key = "$($e.DisplayName)|$($e.DisplayVersion)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        # Installers write this value themselves, and some write junk like "00000000" or "20240231".
        # TryParseExact returns $false for those instead of crashing the whole inventory.
        $installed = $null
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact("$($e.InstallDate)", 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $installed = $parsed
        }
        [pscustomobject]@{
            Name        = "$($e.DisplayName)".Trim()
            Version     = $e.DisplayVersion
            Publisher   = $e.Publisher
            InstallDate = $installed
        }
    }
    $rows | Sort-Object Name
}
