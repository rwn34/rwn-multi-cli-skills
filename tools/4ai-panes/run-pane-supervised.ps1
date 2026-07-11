# run-pane-supervised.ps1 - auto-resurrection supervisor for one 4AI pane.
#
# Runs pane-runner.ps1 as an ISOLATED CHILD process and reads its exit code to
# decide whether to respawn (ADR-0008 self-heal, gap-analysis B6: "runner crashed
# -> handoff sits with no actor and no alert"). Child-process isolation is
# deliberate: a parse/bind error in the runner crashes only the child (non-zero
# exit) instead of taking this supervisor down too, and a kill is legible as a
# non-zero child exit.
#
# Exit-code contract (defined in pane-runner.ps1 header):
#   child exit 0        -> intentional stop (Ctrl-C / 'q'). Do NOT respawn; fall
#                          through to a live prompt (Selector launches us -NoExit).
#   child exit non-zero -> crash. Respawn with exponential backoff, bounded by a
#                          rolling-window crash cap; on cap, stop LOUDLY pointing at
#                          restart-pane.ps1. A healthy run resets the crash counter.
#
# The supervisor NEVER calls 'exit' on its terminal paths - it breaks/returns so the
# pane's -NoExit keeps a live prompt (an explicit 'exit' would override -NoExit).
# The child is launched WITHOUT -NoExit so its exit code returns here.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude', 'kimi', 'kiro', 'opencode')]
    [string]$Cli,

    [string]$ProjectDir = (Get-Location).Path,

    [string]$Owner = '',

    [int]$MaxContinues = 5,

    [int]$PollSeconds = 10,

    # Crashes allowed within the rolling window before giving up.
    [int]$MaxRetries = 5,

    # Rolling window length for the crash cap.
    [double]$RetryWindowMinutes = 10,

    # First backoff (seconds); doubles each consecutive crash up to the cap.
    [double]$BackoffBaseSeconds = 2,

    # Backoff ceiling (seconds).
    [double]$BackoffMaxSeconds = 60,

    # A single run lasting >= this (seconds) is "healthy" -> resets the crash counter.
    [double]$HealthyRunSeconds = 120,

    # Runner script to supervise. Overridable so tests can inject a stub without
    # launching a real CLI; defaults to pane-runner.ps1 beside this script.
    [string]$RunnerPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RunnerPath)) {
    $RunnerPath = Join-Path $PSScriptRoot 'pane-runner.ps1'
}
if (-not (Test-Path $RunnerPath)) {
    Write-Host "supervisor: runner not found at $RunnerPath - cannot start." -ForegroundColor Red
    return
}

# Stamp this pane's CLI so restart-pane.ps1 still infers it from this pane's shell.
$env:RWN_PANE_CLI = $Cli

$proj = Split-Path -Leaf $ProjectDir
Write-Host "== supervisor up: cli=$Cli project=$proj (respawn on crash, cap $MaxRetries/${RetryWindowMinutes}min) ==" -ForegroundColor Cyan

# Child argument list. -Owner is omitted when empty: 'powershell -File' drops an
# empty-string argument, which would raise "Missing an argument for parameter
# 'Owner'" and crash-loop the child every spawn. Omitting it lets the runner derive
# the default owner (Get-DefaultOwner), matching a direct pane-runner launch.
$childArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RunnerPath,
    '-Cli', $Cli, '-ProjectDir', $ProjectDir,
    '-MaxContinues', $MaxContinues, '-PollSeconds', $PollSeconds
)
if (-not [string]::IsNullOrWhiteSpace($Owner)) { $childArgs += @('-Owner', $Owner) }

# Rolling window of recent crash timestamps.
$crashes = [System.Collections.Generic.List[datetime]]::new()

try {
    while ($true) {
        $start = Get-Date
        & powershell @childArgs
        $code = $LASTEXITCODE
        $ranSeconds = ((Get-Date) - $start).TotalSeconds

        if ($code -eq 0) {
            Write-Host "== supervisor: runner exited cleanly (code 0) - not respawning ==" -ForegroundColor DarkGray
            break
        }

        # --- crash path ---
        # Prune crashes outside the rolling window.
        $cutoff = (Get-Date).AddMinutes(-$RetryWindowMinutes)
        for ($i = $crashes.Count - 1; $i -ge 0; $i--) {
            if ($crashes[$i] -lt $cutoff) { $crashes.RemoveAt($i) }
        }
        # A healthy run (long uptime) means this crash is a fresh blip, not part of a
        # hot crash-loop -> reset the accumulated count.
        if ($ranSeconds -ge $HealthyRunSeconds) { $crashes.Clear() }
        $crashes.Add((Get-Date))

        if ($crashes.Count -ge $MaxRetries) {
            Write-Host "== supervisor: runner crashed $($crashes.Count) times in ${RetryWindowMinutes}min - GIVING UP ==" -ForegroundColor Red
            Write-Host "   the runner is not staying up. To try again, run: restart-pane.ps1 -Cli $Cli" -ForegroundColor Red
            break
        }

        $delay = [math]::Min($BackoffMaxSeconds, $BackoffBaseSeconds * [math]::Pow(2, $crashes.Count - 1))
        Write-Host "== supervisor: runner crashed (code $code, ran $([math]::Round($ranSeconds,1))s) - respawn $($crashes.Count)/$MaxRetries in ${delay}s ==" -ForegroundColor Yellow
        Start-Sleep -Milliseconds ([int]($delay * 1000))
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl-C during a backoff sleep = intentional stop.
    Write-Host "== supervisor: interrupted - stopping ==" -ForegroundColor DarkGray
}
# Fall off the end -> the pane's -NoExit drops to a live prompt. No 'exit' here.
