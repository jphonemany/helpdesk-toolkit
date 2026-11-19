function Get-HdHealthReport {
    <#
    .SYNOPSIS
    "My computer is slow": a one-command health check of disk, memory, uptime and services.

    .DESCRIPTION
    Collects the facts a technician checks first on a slow or misbehaving PC:
      - free space on each fixed disk (Warning below 15%, Critical below 5%)
      - free memory (same thresholds)
      - days since last reboot (Warning after 14 days)
      - services set to start automatically that aren't running
    Returns an object, and with -HtmlPath also saves a report you can attach to a ticket.

    .EXAMPLE
    Get-HdHealthReport

    .EXAMPLE
    Get-HdHealthReport -HtmlPath .\health.html
    #>
    [CmdletBinding()]
    param(
        [string]$HtmlPath,
        [int]$UptimeWarningDays = 14
    )

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3')
    $services = @(Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'")

    $diskRows = foreach ($d in $disks) {
        $pct = 0
        if ($d.Size -gt 0) { $pct = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1) }
        [pscustomobject]@{
            Drive       = $d.DeviceID
            SizeGB      = [math]::Round($d.Size / 1GB, 1)
            FreeGB      = [math]::Round($d.FreeSpace / 1GB, 1)
            PercentFree = $pct
            Status      = Get-HdThresholdStatus -PercentFree $pct
        }
    }

    # Win32_OperatingSystem reports memory in kilobytes.
    $memPct = [math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    $memory = [pscustomobject]@{
        TotalGB     = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        FreeGB      = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        PercentFree = $memPct
        Status      = Get-HdThresholdStatus -PercentFree $memPct
    }

    $uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
    $uptimeStatus = 'OK'
    if ($uptimeDays -gt $UptimeWarningDays) { $uptimeStatus = 'Warning' }

    $stopped = foreach ($s in $services) {
        [pscustomobject]@{ Name = $s.Name; DisplayName = $s.DisplayName; State = $s.State }
    }

    $statuses = @($diskRows | ForEach-Object { $_.Status }) + $memory.Status + $uptimeStatus
    $report = [pscustomobject]@{
        ComputerName    = $env:COMPUTERNAME
        Generated       = (Get-Date).ToString('s')
        OperatingSystem = $os.Caption
        UptimeDays      = $uptimeDays
        UptimeStatus    = $uptimeStatus
        Memory          = $memory
        Disks           = @($diskRows)
        StoppedServices = @($stopped)
        Overall         = Get-HdWorstStatus -Status $statuses
    }

    if ($HtmlPath) {
        $head = '<style>body{font-family:Segoe UI,Arial;margin:24px}table{border-collapse:collapse;margin-bottom:16px}' +
                'td,th{border:1px solid #ccc;padding:4px 10px}th{background:#eee}</style>'
        $body = @(
            "<h1>Health report: $($report.ComputerName)</h1>",
            "<p>$($report.Generated) | $($report.OperatingSystem) | Overall: <b>$($report.Overall)</b></p>",
            "<p>Uptime: $uptimeDays days ($uptimeStatus)</p>",
            # ConvertTo-Html returns an array of lines; Out-String joins them into one block of text.
            ($memory | ConvertTo-Html -Fragment -PreContent '<h2>Memory</h2>' | Out-String),
            ($report.Disks | ConvertTo-Html -Fragment -PreContent '<h2>Disks</h2>' | Out-String),
            ($report.StoppedServices | ConvertTo-Html -Fragment -PreContent '<h2>Automatic services not running</h2>' | Out-String)
        ) -join "`n"
        ConvertTo-Html -Head $head -Body $body -Title "Health report $($report.ComputerName)" |
            Set-Content -Path $HtmlPath -Encoding UTF8
    }
    $report
}
