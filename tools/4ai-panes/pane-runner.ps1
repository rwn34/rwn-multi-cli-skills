# pane-runner.ps1 - self-driving supervisor loop for one 4AI pane (ADR-0008).
#
# Each pane runs this instead of a bare CLI. It is a visible per-pane state
# machine: IDLE (poll this project's handoff inbox - filesystem only, zero
# tokens) -> CLAIM (per-project claim-lock, crash-recoverable) -> RUN (invoke the
# CLI headless as a blocking child) -> DECIDE (handoff moved to done/? release :
# auto-continue up to MAX). Chaining across CLIs is emergent - each pane watches
# only its own inbox. See docs/architecture/0008-self-driving-fleet-pane-runner.md.
#
# Windows Terminal has no send-keys API, so "continue" is re-invoking a fresh
# headless process with the handoff as context - state lives in files, not
# sessions. The per-CLI headless flags are the single source in Get-HeadlessCmd
# and MUST match .ai/tools/dispatch-handoffs.sh headless_cmd.
#
# Testability: the CLI launch and pid-liveness probe go through overridable
# script-scoped scriptblocks ($script:InvokeCli / $script:TestPidAlive) so the
# test harness can drive the decision logic with a mock CLI. Dot-source with
# -NoRun to load functions without entering the loop.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude', 'kimi', 'kiro', 'opencode')]
    [string]$Cli,

    [string]$ProjectDir = (Get-Location).Path,

    [int]$MaxContinues = 5,

    [int]$PollSeconds = 10,

    # Dot-source for tests: load functions, do not start the supervisor loop.
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'

# -- Single source of headless launch flags (mirrors dispatch-handoffs.sh) --
# This is the ONLY place per-CLI launch flags live. If dispatch-handoffs.sh
# headless_cmd changes, change it here too (and vice versa).
function Get-HeadlessCmd {
    param([string]$CliName, [string]$Prompt)
    switch ($CliName) {
        'claude'   { return "claude -p `"$Prompt`" --permission-mode acceptEdits" }
        'kimi'     { return "kimi -p `"$Prompt`"" }
        'kiro'     { return "kiro-cli chat --no-interactive --trust-all-tools --agent orchestrator `"$Prompt`"" }
        'opencode' { return "opencode run --auto --agent opencode `"$Prompt`"" }
        default    { throw "Unknown CLI: $CliName" }
    }
}

# Bare interactive form (used by the pause / manual-override escape hatch).
# Mirrors Selector.ps1 $cliDefs[...].cmd.
function Get-InteractiveCmd {
    param([string]$CliName)
    switch ($CliName) {
        'claude'   { return "claude --dangerously-skip-permissions" }
        'kimi'     { return "kimi --yolo" }
        'kiro'     { return "kiro-cli chat --trust-all-tools --agent orchestrator" }
        'opencode' { return "opencode --agent opencode" }
        default    { throw "Unknown CLI: $CliName" }
    }
}

# -- Overridable hooks (tests replace these with mocks) --

# Real CLI launch: build the headless command and run it as a blocking child.
# The child's stdout AND stderr are streamed live to the pane console via
# '2>&1 | Out-Host' so EVERY CLI is visibly active - not just the ones that write
# straight to the console handle. Out-Host renders to the host and emits nothing
# onto the pipeline, so the CLI's chatter never leaks into a caller's return
# value; only the exit code below is returned. Returns the child's exit code.
$script:InvokeCli = {
    param([string]$CliName, [string]$Prompt)
    $cmd = Get-HeadlessCmd -CliName $CliName -Prompt $Prompt
    Write-Host "  > $cmd" -ForegroundColor DarkGray
    Invoke-Expression $cmd 2>&1 | Out-Host
    return $LASTEXITCODE
}

# Real pid-liveness probe.
$script:TestPidAlive = {
    param([int]$ProcessId)
    return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

# -- Handoff inbox (IDLE poll - filesystem only) --

# Return the path of the first qualifying handoff in this CLI's open/ inbox, or
# $null. Qualifying = Auto: yes AND Status: OPEN AND Risk: A|B (the exact gate
# dispatch-handoffs.sh uses). Risk C / missing Risk is human-gated -> skipped.
function Get-QualifyingHandoff {
    param([string]$ProjectDir, [string]$CliName)
    $openDir = Join-Path $ProjectDir ".ai/handoffs/to-$CliName/open"
    if (-not (Test-Path $openDir)) { return $null }
    $files = Get-ChildItem -Path $openDir -Filter "*.md" -File -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($f in $files) {
        $head = Get-Content -Path $f.FullName -TotalCount 20 -ErrorAction SilentlyContinue
        if (-not $head) { continue }
        if (-not ($head -match '^\s*Auto:\s*yes')) { continue }
        if (-not ($head -match '^\s*Status:\s*OPEN')) { continue }
        if (-not ($head -match '^\s*Risk:\s*[AB]\s*$')) { continue }
        return $f.FullName
    }
    return $null
}

# Durable done-signal: the handoff moved out of open/ (to done/). No output
# scraping - "still in open/ after the run" means the CLI hit its cap.
function Test-HandoffDone {
    param([string]$HandoffPath)
    return (-not (Test-Path $HandoffPath))
}

# -- Per-project claim-lock (crash-recoverable) --

function Get-ClaimPath {
    param([string]$ProjectDir, [string]$CliName)
    return (Join-Path $ProjectDir ".ai/.claim-$CliName.json")
}

function Get-Claim {
    param([string]$ProjectDir, [string]$CliName)
    $p = Get-ClaimPath -ProjectDir $ProjectDir -CliName $CliName
    if (-not (Test-Path $p)) { return $null }
    try { return (Get-Content -Path $p -Raw | ConvertFrom-Json) } catch { return $null }
}

# Should we SKIP because someone else already holds this project's claim?
# Skip only if a claim exists owned by a DIFFERENT, LIVE pid. A dead-pid claim
# is stale (crash) -> reclaim (return $false). No claim / our own pid -> $false.
function Test-ClaimBlocks {
    param([string]$ProjectDir, [string]$CliName, [int]$MyPid)
    $claim = Get-Claim -ProjectDir $ProjectDir -CliName $CliName
    if ($null -eq $claim) { return $false }
    if (-not $claim.pid) { return $false }
    if ([int]$claim.pid -eq $MyPid) { return $false }
    return [bool](& $script:TestPidAlive ([int]$claim.pid))
}

# Atomic claim write (temp + rename) carrying project + cli + pid + ts.
function Write-Claim {
    param([string]$ProjectDir, [string]$CliName, [int]$MyPid)
    $p = Get-ClaimPath -ProjectDir $ProjectDir -CliName $CliName
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{
        project = (Split-Path -Leaf $ProjectDir)
        cli     = $CliName
        pid     = $MyPid
        ts      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
    $tmp = "$p.tmp.$MyPid"
    ($obj | ConvertTo-Json -Compress) | Set-Content -Path $tmp -Encoding utf8 -NoNewline
    Move-Item -Path $tmp -Destination $p -Force
}

function Remove-Claim {
    param([string]$ProjectDir, [string]$CliName)
    $p = Get-ClaimPath -ProjectDir $ProjectDir -CliName $CliName
    if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue }
}

# -- Prompts --

function Get-InitialPrompt {
    param([string]$RelPath)
    return "Process the open handoff at $RelPath per the protocol in .ai/handoffs/README.md. Execute the steps, prepend an activity-log entry, update the handoff Status, and report."
}

function Get-ContinuePrompt {
    param([string]$RelPath)
    return "Continue processing the open handoff at $RelPath. You previously hit a step or tool cap before completing it; resume where you left off, finish the remaining steps, prepend an activity-log entry, set the handoff Status to DONE, and move it to the matching done/ folder."
}

# -- RUN + DECIDE core (the unit-tested heart) --
#
# Invoke the CLI on a handoff, then auto-continue while it stays OPEN, up to
# MaxContinues. Returns @{ Result = 'DONE'|'MAXED'; Continues = <n>; Invocations = <n> }.
# 'DONE'  -> handoff moved to done/ (release claim, back to IDLE).
# 'MAXED' -> hit the continue cap still OPEN (ALERT, leave for the human).
function Invoke-HandoffRun {
    param(
        [string]$ProjectDir,
        [string]$CliName,
        [string]$HandoffPath,
        [int]$MaxContinues
    )
    $rel = $HandoffPath
    if ($HandoffPath.StartsWith($ProjectDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $HandoffPath.Substring($ProjectDir.Length).TrimStart('\', '/')
    }
    $continues = 0
    $invocations = 0
    while ($true) {
        $prompt = if ($continues -eq 0) { Get-InitialPrompt -RelPath $rel } else { Get-ContinuePrompt -RelPath $rel }
        if ($continues -eq 0) {
            Write-Host "== RUN  [$CliName] $rel ==" -ForegroundColor Cyan
        } else {
            Write-Host "== auto-continuing ($continues/$MaxContinues) [$CliName] $rel ==" -ForegroundColor Yellow
        }
        Write-Host "-- launching $CliName (streaming output below) --" -ForegroundColor DarkCyan
        # Absorb only the returned exit code here; the CLI's own stdout/stderr is
        # already streamed live to the pane inside $script:InvokeCli (Out-Host).
        # This keeps Invoke-HandoffRun's return a clean @{Result;Continues;Invocations}.
        & $script:InvokeCli $CliName $prompt | Out-Null
        $invocations++

        if (Test-HandoffDone -HandoffPath $HandoffPath) {
            Write-Host "== DONE [$CliName] $rel (moved to done/, $continues continue(s)) ==" -ForegroundColor Green
            return @{ Result = 'DONE'; Continues = $continues; Invocations = $invocations }
        }

        if ($continues -ge $MaxContinues) {
            Write-Host "== ALERT [$CliName] $rel still OPEN after $MaxContinues auto-continues - stopping, human needed ==" -ForegroundColor Red
            return @{ Result = 'MAXED'; Continues = $continues; Invocations = $invocations }
        }
        $continues++
    }
}

# -- Supervisor loop (IDLE -> CLAIM -> RUN/DECIDE), interruptible --

function Start-PaneRunner {
    param(
        [string]$Cli,
        [string]$ProjectDir,
        [int]$MaxContinues,
        [int]$PollSeconds
    )
    $myPid = $PID
    $proj = Split-Path -Leaf $ProjectDir
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "| pane-runner  project=$proj  cli=$Cli" -ForegroundColor Cyan
    Write-Host "| IDLE poll every ${PollSeconds}s  |  MAX-continues=$MaxContinues" -ForegroundColor Cyan
    Write-Host "| 'p' = pause -> interactive CLI   Ctrl-C = stop   |" -ForegroundColor Cyan
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan

    try {
        while ($true) {
            # Manual-override escape hatch: 'p' drops to the interactive CLI.
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.KeyChar -eq 'p') {
                    Write-Host "== PAUSED -> dropping to interactive $Cli (exit it to resume the loop) ==" -ForegroundColor Magenta
                    Push-Location $ProjectDir
                    try { Invoke-Expression (Get-InteractiveCmd -CliName $Cli) } finally { Pop-Location }
                    Write-Host "== resumed supervisor loop ==" -ForegroundColor Magenta
                    continue
                }
            }

            $handoff = Get-QualifyingHandoff -ProjectDir $ProjectDir -CliName $Cli
            if ($null -eq $handoff) {
                Start-Sleep -Seconds $PollSeconds
                continue
            }

            if (Test-ClaimBlocks -ProjectDir $ProjectDir -CliName $Cli -MyPid $myPid) {
                # Another live pane already owns this project - skip, re-poll.
                Start-Sleep -Seconds $PollSeconds
                continue
            }

            Write-Claim -ProjectDir $ProjectDir -CliName $Cli -MyPid $myPid
            try {
                Invoke-HandoffRun -ProjectDir $ProjectDir -CliName $Cli -HandoffPath $handoff -MaxContinues $MaxContinues | Out-Null
            } finally {
                Remove-Claim -ProjectDir $ProjectDir -CliName $Cli
            }
        }
    } finally {
        # Ctrl-C / any exit: always release our claim.
        Remove-Claim -ProjectDir $ProjectDir -CliName $Cli
        Write-Host "== pane-runner stopped ($Cli) - claim released ==" -ForegroundColor DarkGray
    }
}

if (-not $NoRun) {
    Start-PaneRunner -Cli $Cli -ProjectDir $ProjectDir -MaxContinues $MaxContinues -PollSeconds $PollSeconds
}
