#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bridge.Core.ps1')
Assert-SshDestination $Destination
@{ destination = $Destination } | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
Write-Output "Configured SSH destination: $Destination"
Write-Output 'If the helper is running, stop it with .\Stop.ps1, then double-click Start.vbs.'
