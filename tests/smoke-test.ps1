<#
    Runs pc-tuning.ps1 the way a user would, in a separate Windows PowerShell,
    and fails on any error output. Only Check and dry runs: nothing is changed.

    powershell -ExecutionPolicy Bypass -File .\tests\smoke-test.ps1
#>

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'pc-tuning.ps1'
$work   = Join-Path ([IO.Path]::GetTempPath()) "pc-tuning-smoke-$PID"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# Every option on, so that the opinionated settings are checked too
$allOn = @{
    disableMemoryIntegrity = $true; removeNahimic = $true; disableHibernation = $true
    disableTransparency = $true; disableChromeAutostart = $true
    extraApps = @('Microsoft.GamingApp')
    network   = @{ dnsServers = @('9.9.9.9') }
    defender  = @{ excludeSteamLibraries = $true; extraExclusions = @('%USERPROFILE%\Videos') }
    checks    = @{ latestBiosVersion = '1.0' }
}
$allOnFile = Join-Path $work 'all-on.json'
$allOn | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $allOnFile -Encoding UTF8

$typoFile = Join-Path $work 'typo.json'
'{ "disableTelemetri": true }' | Set-Content -LiteralPath $typoFile -Encoding UTF8

$state = Join-Path $work 'state.json'
$runs = @(
    @{ Name = 'Check, defaults, English';  Args = @('-Mode', 'Check', '-Language', 'en');                                   Expect = '=== Summary ===' }
    @{ Name = 'Check, example, French';    Args = @('-Mode', 'Check', '-Language', 'fr', '-Config', "$root\config.example.json"); Expect = '=== Bilan ===' }
    @{ Name = 'Check, every option on';    Args = @('-Mode', 'Check', '-Language', 'en', '-Config', $allOnFile);             Expect = '=== Summary ===' }
    @{ Name = 'Check, unknown key';        Args = @('-Mode', 'Check', '-Language', 'en', '-Config', $typoFile);              Expect = 'Unknown configuration key, ignored: disableTelemetri' }
    @{ Name = 'Apply, dry run';            Args = @('-Mode', 'Apply', '-DryRun', '-Language', 'en', '-Config', $allOnFile, '-StateFile', $state); Expect = 'Dry run: \d+ already in place' }
    @{ Name = 'Undo, dry run';             Args = @('-Mode', 'Undo', '-DryRun', '-Language', 'en', '-Config', $allOnFile, '-StateFile', $state);  Expect = '=== Restore ===|No saved state' }
    @{ Name = 'SecureBoot, dry run';       Args = @('-Mode', 'SecureBoot', '-DryRun', '-Language', 'en');                  Expect = '2023 Secure Boot certificates' }
)

$failed = 0
foreach ($run in $runs) {
    $out = Join-Path $work 'out.txt'
    $err = Join-Path $work 'err.txt'
    $quoted = foreach ($a in $run.Args) { if ($a -match '\s') { "`"$a`"" } else { $a } }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"") + @($quoted) + '-NoPause'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    $stdout = Get-Content -LiteralPath $out -Raw
    $stderr = "$(Get-Content -LiteralPath $err -Raw)".Trim()

    $problems = @()
    if ($p.ExitCode -ne 0)          { $problems += "exit code $($p.ExitCode)" }
    if ($stderr)                    { $problems += 'error output' }
    if ($stdout -notmatch $run.Expect) { $problems += "missing '$($run.Expect)'" }

    Write-Output "----- $($run.Name)"
    Write-Output $stdout
    if ($stderr) { Write-Output $stderr }
    if ($problems) {
        Write-Output "::error::$($run.Name): $($problems -join ', ')"
        $failed++
    } else {
        Write-Output "PASS  $($run.Name)"
    }
}

Write-Output ''
Write-Output ("{0} run(s), {1} failed" -f $runs.Count, $failed)
if ($failed) { exit 1 }
