# Loads every function file. Public functions are exported (listed in the .psd1);
# Private helpers stay inside the module.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $here $folder) -Filter '*.ps1') {
        . $file.FullName
    }
}
