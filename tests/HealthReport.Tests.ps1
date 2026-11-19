BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\HelpdeskToolkit\HelpdeskToolkit.psd1') -Force
}

Describe 'Get-HdHealthReport' {
    BeforeEach {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [pscustomobject]@{
                Caption = 'Microsoft Windows 11 Pro'
                TotalVisibleMemorySize = 16GB / 1KB     # reported in KB
                FreePhysicalMemory     = 4GB / 1KB      # 25% free
                LastBootUpTime         = (Get-Date).AddDays(-3)
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [pscustomobject]@{ DeviceID = 'C:'; Size = 500GB; FreeSpace = 20GB }   # 4% free -> Critical
            [pscustomobject]@{ DeviceID = 'D:'; Size = 1000GB; FreeSpace = 600GB }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } {
            [pscustomobject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; State = 'Stopped' }
        }
    }

    It 'flags a nearly full disk and makes the overall status Critical' {
        $r = Get-HdHealthReport
        ($r.Disks | Where-Object Drive -eq 'C:').Status | Should -Be 'Critical'
        ($r.Disks | Where-Object Drive -eq 'D:').Status | Should -Be 'OK'
        $r.Overall | Should -Be 'Critical'
    }

    It 'reports memory and uptime correctly' {
        $r = Get-HdHealthReport
        $r.Memory.PercentFree | Should -Be 25
        $r.Memory.Status | Should -Be 'OK'
        $r.UptimeStatus | Should -Be 'OK'
    }

    It 'warns when the PC has not been rebooted in over two weeks' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [pscustomobject]@{ Caption = 'Windows'; TotalVisibleMemorySize = 100; FreePhysicalMemory = 50; LastBootUpTime = (Get-Date).AddDays(-30) }
        }
        (Get-HdHealthReport).UptimeStatus | Should -Be 'Warning'
    }

    It 'lists automatic services that are not running' {
        (Get-HdHealthReport).StoppedServices[0].Name | Should -Be 'Spooler'
    }

    It 'writes an HTML report when asked' {
        $path = Join-Path $TestDrive 'health.html'
        Get-HdHealthReport -HtmlPath $path | Out-Null
        $html = Get-Content $path -Raw
        $html | Should -Match 'Health report'
        $html | Should -Match 'Print Spooler'
        $html | Should -Not -Match 'System\.Object'
        $html | Should -Match '<td>C:</td>'
    }
}
