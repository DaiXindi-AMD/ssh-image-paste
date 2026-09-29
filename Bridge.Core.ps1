function Assert-SshDestination {
    param([AllowEmptyString()][string]$Destination)
    # Keep SSH options in ~/.ssh/config; never accept option-like or shell input here.
    if ($Destination -cnotmatch '\A(?:[A-Za-z0-9_][A-Za-z0-9_.-]*@)?[A-Za-z0-9_][A-Za-z0-9_.-]*\z') {
        throw 'Use an SSH config alias or user@hostname. Put ports, keys, IPv6 addresses and jump hosts in your SSH config.'
    }
}

function Read-BridgeConfig {
    param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))
    if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw 'Configuration missing. Run .\Configure.ps1 -Destination your-ssh-alias first.'
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($config.destination -isnot [string]) { throw 'config.json must contain a string destination. Run Configure.ps1.' }
    Assert-SshDestination $config.destination
    return $config
}

function Test-BridgeProcess {
    param($State)
    try {
        if (!$State.processStartUtc -or !$State.pid) { return $false }
        $recordedStart = [DateTimeOffset]::Parse($State.processStartUtc).UtcDateTime
        $candidate = Get-Process -Id $State.pid -ErrorAction Stop
        return ($candidate.ProcessName -eq 'powershell' -and $candidate.StartTime.ToUniversalTime().Ticks -eq $recordedStart.Ticks)
    } catch { return $false }
}

function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string]$Value)
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Read-ImageUploadPath {
    param([AllowEmptyString()][string]$Output)
    $paths = [regex]::Matches($Output, '(?m)^CODEX_IMAGE_PATH=(/tmp/codex-clipboard\.[A-Za-z0-9]{10}/image\.png)\r?$')
    $markers = [regex]::Matches($Output, '(?m)^CODEX_IMAGE_PATH=')
    if ($paths.Count -ne 1 -or $markers.Count -ne 1) {
        throw 'The SSH upload did not return one valid image path.'
    }
    return $paths[0].Groups[1].Value
}

function Send-ImageFile {
    param([string]$FilePath, [string]$Destination)
    Assert-SshDestination $Destination
    if (!(Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Image file does not exist: $FilePath" }
    $sshExe = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
    # A private directory per image avoids collisions and public /tmp permissions.
    $remoteCommand = 'umask 077; d=$(mktemp -d /tmp/codex-clipboard.XXXXXXXXXX) || exit 1; cat > "$d/image.png" || exit 1; printf ''\nCODEX_IMAGE_PATH=%s/image.png\n'' "$d"'
    $parts = @('-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=2', $Destination, $remoteCommand)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $sshExe
    $info.Arguments = ($parts | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $stream = [System.IO.File]::OpenRead($FilePath)
        try { $stream.CopyTo($process.StandardInput.BaseStream) } finally { $stream.Dispose(); $process.StandardInput.Close() }
        if (!$process.WaitForExit(45000)) { $process.Kill(); throw 'SSH upload timed out.' }
        $outText = $stdout.GetAwaiter().GetResult()
        $errText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            if ($errText.Length -gt 1200) { $errText = $errText.Substring($errText.Length - 1200) }
            throw "SSH upload failed (exit $($process.ExitCode)): $errText"
        }
        Read-ImageUploadPath $outText
    } finally {
        try { if (!$process.HasExited) { $process.Kill() } } catch { }
        $process.Dispose()
    }
}
