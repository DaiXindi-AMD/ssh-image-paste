$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bridge.Core.ps1')

$thisProcess = Get-Process -Id $PID
$validState = @{ pid = $PID; processStartUtc = $thisProcess.StartTime.ToUniversalTime().ToString('o') }
if (!(Test-BridgeProcess $validState)) { throw 'FAIL: current PowerShell process not recognized.' }
$staleState = @{ pid = $PID; processStartUtc = $thisProcess.StartTime.ToUniversalTime().AddDays(-1).ToString('o') }
if (Test-BridgeProcess $staleState) { throw 'FAIL: reused PID mistaken for the original helper process.' }
if (Test-BridgeProcess @{ pid = $PID }) { throw 'FAIL: unverifiable legacy state treated as live.' }
if (Test-BridgeProcess @{ pid = 'invalid'; processStartUtc = 'invalid' }) { throw 'FAIL: malformed state treated as live.' }

foreach ($destination in @('gpu-server', 'user@example.com', 'user@192.0.2.10', 'my_server')) {
    Assert-SshDestination $destination
}
foreach ($destination in @('', '-oProxyCommand=bad', 'host name', "host`nnext", 'user@host;id', 'user@host/path', 'user@host:22')) {
    $rejected = $false
    try { Assert-SshDestination $destination } catch { $rejected = $true }
    if (!$rejected) { throw "FAIL: unsafe destination accepted: $destination" }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ssh-image-config-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$configPath = Join-Path $testRoot 'config.json'
try {
    $missingRejected = $false
    try { Read-BridgeConfig $configPath } catch { $missingRejected = $_.Exception.Message -match 'Configure.ps1' }
    if (!$missingRejected) { throw 'FAIL: missing config must explain how to configure.' }
    & (Join-Path $PSScriptRoot 'Configure.ps1') -Destination 'gpu-server' -ConfigPath $configPath
    $config = Read-BridgeConfig $configPath
    if ($config.destination -cne 'gpu-server') { throw 'FAIL: SSH alias did not round-trip.' }
    & (Join-Path $PSScriptRoot 'Configure.ps1') -Destination 'user@example.com' -ConfigPath $configPath
    if ((Read-BridgeConfig $configPath).destination -cne 'user@example.com') { throw 'FAIL: destination update failed.' }
    $before = Get-Content -LiteralPath $configPath -Raw
    try { & (Join-Path $PSScriptRoot 'Configure.ps1') -Destination '-bad' -ConfigPath $configPath } catch { }
    if ((Get-Content -LiteralPath $configPath -Raw) -cne $before) { throw 'FAIL: invalid configuration overwrote existing configuration.' }
    '{"destination":"-bad"}' | Set-Content -LiteralPath $configPath
    $invalidRejected = $false
    try { Read-BridgeConfig $configPath } catch { $invalidRejected = $true }
    if (!$invalidRejected) { throw 'FAIL: invalid destination from config accepted.' }
    '{}' | Set-Content -LiteralPath $configPath
    $emptyRejected = $false
    try { Read-BridgeConfig $configPath } catch { $emptyRejected = $true }
    if (!$emptyRejected) { throw 'FAIL: missing destination from config accepted.' }
} finally {
    Remove-Item -LiteralPath $configPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -ErrorAction SilentlyContinue
}
'PASS: SSH alias validation, configuration round-trip, and actionable configuration errors.'
