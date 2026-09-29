#Requires -Version 5.1
param([string]$Destination, [switch]$NoStart)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bridge.Core.ps1')
if ($Destination) { & (Join-Path $PSScriptRoot 'Configure.ps1') -Destination $Destination }
$config = Read-BridgeConfig
$startFile = Join-Path $PSScriptRoot 'Start.vbs'
$linkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'SSH Image Paste.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$expectedArguments = '"' + $startFile + '"'
if ((Test-Path -LiteralPath $linkPath) -and $link.Arguments -ne $expectedArguments) {
    throw 'A different installation owns SSH Image Paste.lnk. Uninstall that copy first.'
}
$link.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$link.Arguments = $expectedArguments
$link.WorkingDirectory = $PSScriptRoot
$link.Description = 'Ctrl+Alt+V: upload a clipboard image over SSH and paste its remote path.'
$link.WindowStyle = 7
$link.Save()
Write-Output "Login startup installed: $linkPath"
if ($NoStart) { return }
# Clear stale state only after checking that its recorded process is not alive.
$stateFile = Join-Path $PSScriptRoot 'state.json'
if (Test-Path -LiteralPath $stateFile) {
    $oldState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if (Test-BridgeProcess $oldState) {
        Write-Output 'A recorded helper process is already running. Restart it to apply configuration changes.'
        return
    }
    Remove-Item -LiteralPath $stateFile
}
Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList $expectedArguments -WindowStyle Hidden
$deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if (Test-BridgeProcess $state) {
                Write-Output "RUNNING: PID=$($state.pid), hotkey=$($state.hotkey), destination=$($state.destination)"
                return
            }
        } catch { } # State may still be being written.
    }
} while ((Get-Date) -lt $deadline)
throw 'Helper did not start. Check bridge.log; another helper may already own Ctrl+Alt+V.'
