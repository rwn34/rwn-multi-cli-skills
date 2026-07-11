# test-pane-supervisor.ps1 - Pester-free harness for run-pane-supervised.ps1.
#
# Drives the supervisor against a STUB runner (a tiny script that exits a chosen
# code per invocation) so no real CLI is launched. The stub reads a plan file
# ("sleepMs:exitcode" per line) and a counter file, so the supervisor's respawn
# behavior is fully observable via the spawn count + the supervisor's own output.
# Asserts:
#   (A) stub exits 1,1,0            -> supervisor respawns twice, stops on 0 (3 spawns)
#   (B) stub always exits 1, cap 3  -> gives up after exactly 3 spawns, loud message
#   (C) healthy run resets counter  -> a long run mid-loop lets the cap be reached later
#   (D) backoff schedule            -> respawn delays follow 2x exponential up to the cap

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$supervisor = Join-Path $here 'run-pane-supervised.ps1'

# -- tiny assert framework --
$script:pass = 0
$script:fail = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -eq $Actual) {
        $script:pass++
        Write-Host "PASS  $Name" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "FAIL  $Name  (expected=$Expected actual=$Actual)" -ForegroundColor Red
    }
}

# -- temp workspace + stub runner --
$work = Join-Path $env:TEMP ("pane-supervisor-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

# Stub runner: accepts the same args the supervisor passes, pops the next plan
# entry ("sleepMs:code"), records the spawn, and exits that code. Repeats the last
# plan entry once the plan is exhausted (so an "always crash" plan is one line).
$stub = Join-Path $work 'stub-runner.ps1'
@'
param(
    [string]$Cli,
    [string]$ProjectDir,
    [string]$Owner = '',
    [int]$MaxContinues = 5,
    [int]$PollSeconds = 10
)
$state = $env:RWN_SUP_TEST_STATE
$planFile = Join-Path $state 'plan.txt'
$counterFile = Join-Path $state 'counter.txt'
$plan = @(Get-Content -Path $planFile)
$idx = 0
if (Test-Path $counterFile) { $idx = [int](Get-Content -Path $counterFile -Raw) }
$entry = if ($idx -lt $plan.Count) { $plan[$idx] } else { $plan[$plan.Count - 1] }
$idx++
Set-Content -Path $counterFile -Value $idx
$parts = $entry -split ':'
$sleepMs = [int]$parts[0]
$code = [int]$parts[1]
if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
exit $code
'@ | Set-Content -Path $stub -Encoding ascii

# Run the supervisor against the stub with a fresh state dir + plan; return the
# captured output and the final spawn count.
function Invoke-Supervisor {
    param(
        [string[]]$Plan,
        [int]$MaxRetries = 5,
        [double]$BackoffBaseSeconds = 0.02,
        [double]$BackoffMaxSeconds = 0.1,
        [double]$HealthyRunSeconds = 999
    )
    $state = Join-Path $work ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $state -Force | Out-Null
    ($Plan -join "`n") | Set-Content -Path (Join-Path $state 'plan.txt') -Encoding ascii
    $env:RWN_SUP_TEST_STATE = $state
    $out = & $supervisor -Cli claude -ProjectDir $work -RunnerPath $stub `
        -MaxRetries $MaxRetries -BackoffBaseSeconds $BackoffBaseSeconds `
        -BackoffMaxSeconds $BackoffMaxSeconds -HealthyRunSeconds $HealthyRunSeconds `
        -PollSeconds 1 -MaxContinues 1 *>&1 | Out-String
    $counterFile = Join-Path $state 'counter.txt'
    $spawns = if (Test-Path $counterFile) { [int](Get-Content -Path $counterFile -Raw) } else { 0 }
    return [pscustomobject]@{ Output = $out; Spawns = $spawns }
}

# -- (A) exit 1, 1, 0 -> respawn twice, stop on 0 (3 spawns, no give-up) --
$a = Invoke-Supervisor -Plan @('0:1', '0:1', '0:0')
Assert-Equal 3 $a.Spawns 'A: 1,1,0 -> supervisor spawns the runner 3 times'
Assert-Equal $true ($a.Output -match 'not respawning') 'A: clean exit 0 -> "not respawning" message'
Assert-Equal $false ($a.Output -match 'GIVING UP') 'A: clean stop -> no give-up message'

# -- (B) always exit 1, cap 3 -> give up after exactly 3 spawns, loud message --
$b = Invoke-Supervisor -Plan @('0:1') -MaxRetries 3
Assert-Equal 3 $b.Spawns 'B: always-crash, cap 3 -> exactly 3 spawns then give up'
Assert-Equal $true ($b.Output -match 'GIVING UP') 'B: cap reached -> loud GIVING UP message'
Assert-Equal $true ($b.Output -match 'restart-pane') 'B: give-up points at restart-pane.ps1'

# -- (C) healthy run resets the counter --
# cap 3, HealthyRunSeconds 0.2s. Plan: crash, crash, HEALTHY crash (300ms > 200ms
# -> resets count to 1), crash, crash -> cap at spawn 5. Without the reset the cap
# would trip at spawn 3, so a spawn count of 5 proves the reset fired.
$c = Invoke-Supervisor -Plan @('0:1', '0:1', '300:1', '0:1', '0:1') -MaxRetries 3 -HealthyRunSeconds 0.2
Assert-Equal 5 $c.Spawns 'C: a healthy run mid-loop resets the crash counter (5 spawns, not 3)'
Assert-Equal $true ($c.Output -match 'GIVING UP') 'C: cap still enforced after the reset'

# -- (D) backoff schedule: delays double until the cap (0.02,0.04,0.08,0.1,0.1) --
$d = Invoke-Supervisor -Plan @('0:1') -MaxRetries 6 -BackoffBaseSeconds 0.02 -BackoffMaxSeconds 0.1
$delays = @()
foreach ($m in [regex]::Matches($d.Output, 'respawn \d+/\d+ in ([0-9.]+)s')) {
    $delays += [double]$m.Groups[1].Value
}
Assert-Equal '0.02 0.04 0.08 0.1 0.1' ($delays -join ' ') 'D: backoff doubles then caps (0.02,0.04,0.08,0.1,0.1)'

# -- cleanup + summary --
Remove-Item Env:\RWN_SUP_TEST_STATE -ErrorAction SilentlyContinue
Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== pane-supervisor tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
