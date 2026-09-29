#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$linkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'SSH Image Paste.lnk'
if (Test-Path -LiteralPath $linkPath) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($linkPath)
    if ($link.Arguments -ne ('"' + (Join-Path $PSScriptRoot 'Start.vbs') + '"')) {
        throw 'The startup shortcut belongs to another installation; it was not removed.'
    }
    Remove-Item -LiteralPath $linkPath
}
& (Join-Path $PSScriptRoot 'Stop.ps1')
'Startup entry removed; stop requested. Source files, configuration, logs, and remote images are preserved.'
