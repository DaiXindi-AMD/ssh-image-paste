$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot 'Bridge.Core.ps1'
if (!(Test-Path -LiteralPath $core)) { throw 'FAIL: image upload response validation is not implemented.' }
. $core

$expected = '/tmp/codex-clipboard.Abc1234567/image.png'
$actual = Read-ImageUploadPath "SSH banner`nCODEX_IMAGE_PATH=$expected`n"
if ($actual -cne $expected) { throw 'FAIL: valid upload path was not recovered from SSH output.' }
foreach ($bad in @('', 'Permission denied', 'CODEX_IMAGE_PATH=/etc/passwd', "CODEX_IMAGE_PATH=$expected;evil", "CODEX_IMAGE_PATH=$expected`nCODEX_IMAGE_PATH=$expected")) {
    $rejected = $false
    try { Read-ImageUploadPath $bad | Out-Null } catch { $rejected = $true }
    if (!$rejected) { throw "FAIL: invalid or ambiguous upload response accepted: $bad" }
}

# Native argument quoting must preserve spaces, quotes, and trailing backslashes.
$cases = @('plain', 'two words', 'a"b', 'C:\trailing\', 'a\"b', '')
$child = Join-Path $PSScriptRoot ('Echo-Args-' + [guid]::NewGuid().ToString('N') + '.exe')
try {
    Add-Type -OutputAssembly $child -OutputType ConsoleApplication -TypeDefinition 'public class ArgEcho { public static void Main(string[] args) { foreach (string arg in args) System.Console.WriteLine(System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(arg))); } }'
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $child
    $info.Arguments = ($cases | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $proc = [System.Diagnostics.Process]::Start($info)
    $raw = $proc.StandardOutput.ReadToEnd()
    $encoded = @($raw -split '\r?\n')
    $roundtrip = @($encoded[0..($encoded.Count - 2)] | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0 -or $roundtrip.Count -ne $cases.Count) { throw 'FAIL: argument count changed.' }
    for ($i = 0; $i -lt $cases.Count; $i++) {
        if ($cases[$i] -cne $roundtrip[$i]) { throw "FAIL: argument $i changed in native process transport." }
    }
    $proc.Dispose()
} finally {
    Remove-Item -LiteralPath $child -ErrorAction SilentlyContinue
}
'PASS: remote path validation (including invalid and ambiguous responses) and native argument transport.'
