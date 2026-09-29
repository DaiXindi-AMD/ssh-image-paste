$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bridge.Core.ps1')
$config = Read-BridgeConfig
$sample = Join-Path ([IO.Path]::GetTempPath()) ('ssh-image-test-' + [guid]::NewGuid().ToString('N') + '.png')
$remotePath = $null
try {
    # Generated test fixture only; this test never reads the user's clipboard.
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap(8, 8)
    try {
        $bitmap.SetPixel(0, 0, [System.Drawing.Color]::Blue)
        $bitmap.Save($sample, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    $remotePath = Send-ImageFile -FilePath $sample -Destination $config.destination
    $localHash = (Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteDir = $remotePath.Substring(0, $remotePath.LastIndexOf('/'))
    $remoteCheck = "sha256sum '$remotePath'; stat -c '%a' '$remotePath' '$remoteDir'"
    $output = & "$env:SystemRoot\System32\OpenSSH\ssh.exe" -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 $config.destination $remoteCheck
    if ($LASTEXITCODE -ne 0) { throw 'Remote hash and permission check failed.' }
    $joined = $output -join "`n"
    if ($joined -notmatch [regex]::Escape($localHash)) { throw 'Uploaded PNG hash mismatch.' }
    if ($joined -notmatch '(?m)^600\r?\n700\r?$') { throw "Unexpected remote permissions: $joined" }
    'PASS: generated PNG uploaded intact (SHA-256 matched); file mode 600, directory mode 700.'
} finally {
    if ($remotePath) {
        $remoteDir = $remotePath.Substring(0, $remotePath.LastIndexOf('/'))
        # Exact test paths validated by Read-ImageUploadPath; never recursive deletion.
        & "$env:SystemRoot\System32\OpenSSH\ssh.exe" -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 $config.destination "rm -- '$remotePath' && rmdir -- '$remoteDir'"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Test cleanup failed: $remoteDir" }
    }
    Remove-Item -LiteralPath $sample -ErrorAction SilentlyContinue
}
