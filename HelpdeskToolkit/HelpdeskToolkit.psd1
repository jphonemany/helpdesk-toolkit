@{
    RootModule        = 'HelpdeskToolkit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '5b0f6f7e-3a3d-4b7e-9d1c-6a2f1e8c4d21'
    Author            = 'Jacke Phonemany'
    Description       = 'PowerShell scripts for everyday help desk work: onboarding, offboarding, password resets, health checks and software inventory.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Import-HdNewHire',
        'Disable-HdUser',
        'Reset-HdPassword',
        'Get-HdHealthReport',
        'Get-HdSoftwareInventory',
        'ConvertTo-HdSoftwareItem'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
