#Requires -Version 5.1
param([switch]$Check, [switch]$CheckHotkey, [string]$UploadFile)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bridge.Core.ps1')
if ($UploadFile) { $config = Read-BridgeConfig; Send-ImageFile -FilePath $UploadFile -Destination $config.destination; exit }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'Bridge.Native.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
if ($Check) {
    'PASS: native helper compiled; clipboard not accessed and hotkey not registered.'
    exit
}
if ($CheckHotkey) {
    $probe = New-Object CodexClipboard.HotkeyWindow
    $probe.Dispose()
    'PASS: native helper compiled and Ctrl+Alt+V is available.'
    exit
}
$config = Read-BridgeConfig

$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = New-Object System.Threading.Mutex($false, ('Local\SshImagePaste-' + $userSid))
if (!$mutex.WaitOne(0, $false)) { $mutex.Dispose(); exit }
$log = Join-Path $PSScriptRoot 'bridge.log'
$stopFile = Join-Path $PSScriptRoot 'stop.signal'
$stateFile = Join-Path $PSScriptRoot 'state.json'
$script:busy = $false
$tray = $null
$hotkey = $null
$timer = $null

function Write-BridgeLog([string]$Message) {
    Add-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message)
}
function Show-BridgeNotice([string]$Message, [switch]$Failure) {
    $icon = [System.Windows.Forms.ToolTipIcon]::Info
    if ($Failure) { $icon = [System.Windows.Forms.ToolTipIcon]::Error }
    $tray.ShowBalloonTip(5000, 'Codex SSH image paste', $Message, $icon)
}
function Invoke-ClipboardUpload {
    if ($script:busy) { return }
    $window = [CodexClipboard.TerminalInput]::GetForegroundWindow()
    $terminalPid = [CodexClipboard.TerminalInput]::ProcessId($window)
    try { $foreground = Get-Process -Id $terminalPid -ErrorAction Stop } catch { return }
    if ($foreground.ProcessName -ne 'WindowsTerminal') { return }
    $terminalTitle = [CodexClipboard.TerminalInput]::Title($window)
    $script:busy = $true
    $localFile = $null
    try {
        $clipboardSequence = [CodexClipboard.TerminalInput]::GetClipboardSequenceNumber()
        if (![System.Windows.Forms.Clipboard]::ContainsImage()) { throw 'No image in clipboard. Copy a screenshot first.' }
        $bitmap = [System.Windows.Forms.Clipboard]::GetImage()
        $localFile = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-clipboard-' + [guid]::NewGuid().ToString('N') + '.png')
        try { $bitmap.Save($localFile, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
        if ([CodexClipboard.TerminalInput]::GetClipboardSequenceNumber() -ne $clipboardSequence) {
            throw 'Clipboard changed while reading the image. New content preserved; copy the intended image and retry.'
        }
        $tray.Text = 'Uploading image to SSH server...'
        Show-BridgeNotice 'Uploading screenshot. Keep this terminal tab selected.'
        $remotePath = Send-ImageFile -FilePath $localFile -Destination $config.destination
        Write-BridgeLog "UPLOADED $remotePath"
        if ([CodexClipboard.TerminalInput]::GetClipboardSequenceNumber() -ne $clipboardSequence) {
            throw "Image uploaded, but you copied something else during upload. Clipboard preserved. Image path: $remotePath"
        }
        [System.Windows.Forms.Clipboard]::SetText($remotePath + ' ')
        $deadline = (Get-Date).AddSeconds(2)
        while ([CodexClipboard.TerminalInput]::ModifiersDown() -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 25 }
        if ([CodexClipboard.TerminalInput]::Title($window) -ceq $terminalTitle -and [CodexClipboard.TerminalInput]::Paste($window)) {
            Write-BridgeLog "PASTED window=$window"
            Show-BridgeNotice 'Image path pasted. Add your question and press Enter.'
        } else {
            Write-BridgeLog 'COPIED (focus changed or keys held); no paste sent.'
            Show-BridgeNotice 'Uploaded. Return to Codex and use Ctrl+Shift+V to paste the path.'
        }
    } catch {
        Write-BridgeLog ('ERROR ' + $_.Exception.Message)
        Show-BridgeNotice $_.Exception.Message -Failure
    } finally {
        if ($localFile -and (Test-Path -LiteralPath $localFile)) { Remove-Item -LiteralPath $localFile -Force }
        $tray.Text = 'Codex SSH image paste: Ctrl+Alt+V'
        $script:busy = $false
    }
}

try {
    Remove-Item -LiteralPath $stopFile -ErrorAction SilentlyContinue
    $context = New-Object System.Windows.Forms.ApplicationContext
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = [System.Drawing.SystemIcons]::Information
    $tray.Text = 'Codex SSH image paste: Ctrl+Alt+V'
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $exitItem = $menu.Items.Add('Exit image paste helper')
    $exitItem.add_Click({ $context.ExitThread() })
    $tray.ContextMenuStrip = $menu
    $tray.Visible = $true
    $hotkey = New-Object CodexClipboard.HotkeyWindow
    $hotkey.add_Invoked({ Invoke-ClipboardUpload })
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $timer.add_Tick({ if (Test-Path -LiteralPath $stopFile) { $context.ExitThread() } })
    $timer.Start()
    @{ pid = $PID; processStartUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'); destination = $config.destination; started = (Get-Date).ToString('o'); hotkey = 'Ctrl+Alt+V' } | ConvertTo-Json | Set-Content -LiteralPath $stateFile
    Write-BridgeLog ('STARTED Ctrl+Alt+V destination=' + $config.destination)
    [System.Windows.Forms.Application]::Run($context)
} catch {
    Write-BridgeLog ('FATAL ' + $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex image paste helper') | Out-Null
} finally {
    if ($timer) { $timer.Dispose() }
    if ($hotkey) { $hotkey.Dispose() }
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    Remove-Item -LiteralPath $stateFile -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stopFile -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    Write-BridgeLog 'STOPPED'
}
