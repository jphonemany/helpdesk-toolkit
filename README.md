# helpdesk-toolkit

![CI](https://github.com/jphonemany/helpdesk-toolkit/actions/workflows/ci.yml/badge.svg)

PowerShell scripts for the tickets a help desk sees every day: onboarding new hires, offboarding,
password resets and lockouts, "my computer is slow" health checks, and software inventory.

Each command is written up below as a knowledge-base (KB) article: when to use it, the steps,
and what to check if it goes wrong.

- Works with **Windows PowerShell 5.1** (built into Windows 10/11), no extra installs needed
- Every command that changes an account supports **`-WhatIf`** (preview without changing anything)
- Every account change is written to an **audit log** (passwords are never logged)
- **36 Pester tests** plus PSScriptAnalyzer linting run in GitHub Actions on every push. The tests
  mock every Windows account command, so they never touch real accounts

> **Scope:** version 0.1 manages **local** Windows accounts. Active Directory support is planned
> once the companion home lab (Windows Server domain controller) is built.

## Quick start

```powershell
git clone https://github.com/jphonemany/helpdesk-toolkit.git
cd helpdesk-toolkit
Import-Module .\HelpdeskToolkit\HelpdeskToolkit.psd1
Get-Command -Module HelpdeskToolkit       # list the commands
Get-Help Import-HdNewHire -Full          # full help for any command
```

Commands that create or change accounts need an **elevated** (Run as administrator) PowerShell window.
The health report and software inventory don't.

---

## KB-001: Onboard new hires from a CSV

**Ticket:** "Three people start Monday. Please set up their accounts."

1. Get a CSV from HR with `FirstName,LastName,Department` (see `examples/new-hires.csv`).
2. Preview first. Nothing changes:
   ```powershell
   Import-HdNewHire -Path .\new-hires.csv -WhatIf
   ```
3. Run it for real and keep the output somewhere safe until you've handed out the passwords:
   ```powershell
   Import-HdNewHire -Path .\new-hires.csv | Format-Table Username, FullName, Status, TempPassword
   ```

**What it does for each row:** builds a username (first initial + last name, e.g. `mgarcia`), adds a
number if it's taken (`knguyen`, `knguyen2`), creates the account with a random 16-character
temporary password, forces a password change at first logon, adds it to the `Users` group
(change with `-Group`), and logs it.

**If something goes wrong:**
| Status | Meaning | Fix |
|---|---|---|
| `Skipped` | A row was missing a first name, last name or department | Fix the row in the CSV and re-run just that person |
| `Failed` "Access is denied" | PowerShell isn't elevated | Re-open PowerShell with "Run as administrator" |
| `Failed` "password does not meet requirements" | A stricter local password policy | Check `net accounts` for the minimum length |

**Security:** give the temporary password to the user in person or by phone after checking their
identity, never by email or chat.

## KB-002: Offboard a departing employee

**Ticket:** "Jane's last day is Friday. Please remove her access."

```powershell
Disable-HdUser -Username jdoe -Reason "Last day 2026-11-30, ticket 1042"
```

The account is **disabled, not deleted**, so files and history stay intact and it can be restored if
the request was a mistake. The date and reason go into the account description (Windows limits it
to 48 characters) and the audit log. Pipe several users at once:
`'jdoe','asmith' | Disable-HdUser -Reason "Contract ended"`.

## KB-003: Password reset and account lockout

**Ticket:** "I forgot my password" or "It says my account is locked."

1. **Verify the caller's identity first** (employee ID, manager callback, whatever your policy says).
2. Locked out but knows the password:
   ```powershell
   Reset-HdPassword -Username jdoe -UnlockOnly
   ```
3. Forgot the password:
   ```powershell
   Reset-HdPassword -Username jdoe
   ```
   This unlocks the account if needed, sets a new temporary password (shown once in `TempPassword`),
   and forces a change at next logon.

It refuses to reset a **disabled** account on purpose: a disabled account usually means the person
was offboarded, and re-enabling it should be a deliberate decision, not a side effect.

## KB-004: "My computer is slow"

```powershell
Get-HdHealthReport -HtmlPath .\health.html
```

Checks what a technician looks at first, and rates each one OK / Warning / Critical:

| Check | Warning | Critical |
|---|---|---|
| Free disk space (each fixed drive) | under 15% | under 5% |
| Free memory | under 15% | under 5% |
| Days since last reboot | over 14 days | n/a |
| Automatic services that aren't running | listed for review | n/a |

The HTML file can be attached to the ticket. Typical fixes: clear space with Disk Cleanup or Storage
Sense, restart a PC that hasn't rebooted in weeks, close memory-heavy apps, and look into any
important service that should be running but isn't.

## KB-005: Software inventory

**Ticket:** "Which PCs still have the old VPN client?" or "How many Adobe licenses are in use?"

```powershell
Get-HdSoftwareInventory -Name '*VPN*'
Get-HdSoftwareInventory -CsvPath .\inventory.csv     # everything, for a spreadsheet
```

Reads the same registry keys as Settings > Apps (64-bit, 32-bit and per-user installs). It skips
Windows updates and hidden system components and removes duplicates. It deliberately avoids
`Win32_Product`, which is slow and can trigger a repair of every MSI-installed program.

## Audit log

Every onboarding, offboarding and reset is appended to
`%LOCALAPPDATA%\HelpdeskToolkit\audit-log.csv` (override with the `HD_LOG_PATH` environment variable):

```
Timestamp,Operator,Action,Target,Result,Detail
2026-11-18T21:47:17,DESKTOP\tech,Onboard,mgarcia,Success,"Maria Garcia, Finance"
```

## Running the tests

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path .\tests -Output Detailed
```

## Bugs the testing caught

- **HTML report showed `System.Object[]` instead of tables.** `ConvertTo-Html -Fragment` returns an
  array of lines, and joining it into a larger string printed the array's type name. Fixed by piping
  each fragment through `Out-String`. A test now checks the report contains real table rows.
- **Inventory crashed on a real PC.** One installed program had an impossible install date in the
  registry, and `ParseExact` threw an error that stopped the whole inventory. Installers write that
  value themselves, so it can't be trusted. Switched to `TryParseExact`, which treats bad dates as
  unknown. A test now covers `00000000`, `20240231` and free-text dates.

## Project layout

```
HelpdeskToolkit/
  HelpdeskToolkit.psd1   module manifest (version, exported commands)
  HelpdeskToolkit.psm1   loads every function file
  Public/                the commands you run
  Private/               helpers: usernames, passwords, thresholds, audit log
tests/                   Pester tests (all Windows account commands are mocked)
examples/new-hires.csv   sample onboarding file
```
