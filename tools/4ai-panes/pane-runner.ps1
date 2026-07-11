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
#
# Exit-code contract (consumed by run-pane-supervised.ps1): the runner declares
# intent to its parent via the process exit code -
#   0        = intentional / clean stop (Ctrl-C caught, or a 'q' quit key). The
#              supervisor does NOT respawn; the pane falls through to a live prompt.
#   non-zero = crash / escaped exception / parse-bind error / kill. The supervisor
#              respawns subject to exponential backoff + a rolling-window cap.
# The exit fires only from the outer finally in Start-PaneRunner, which runs only
# when -not $NoRun, so -NoRun dot-source (tests) never hits it.

param(
    [Parameter(Mandatory = $true)]
    # keep in sync with fleet-clis.ps1 $FleetClis (ValidateSet needs a literal)
    [ValidateSet('claude', 'kimi', 'kiro', 'opencode')]
    [string]$Cli,

    [string]$ProjectDir = (Get-Location).Path,

    [int]$MaxContinues = 5,

    [int]$PollSeconds = 10,

    # Claim-lock owner identity for this pane. Empty -> derived from the CLI
    # (Get-DefaultOwner); pass 'claude-auto' explicitly for the headless Claude
    # reviewer pane so it is distinct from app-Claude's 'claude-code'.
    [string]$Owner = '',

    # Dot-source for tests: load functions, do not start the supervisor loop.
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'

# SINGLE SOURCE for the fleet CLI list ($FleetClis / $FleetCliProper). The -Cli
# ValidateSet above must stay a literal (PowerShell requirement); this dot-source
# provides the list to any runtime use. Resolve via $PSScriptRoot so it works both
# in the repo tree and in the flat install dir.
. (Join-Path $PSScriptRoot 'fleet-clis.ps1')

# Fleet Telegram notifications (task #26). Dot-sourced for Send-FleetNotification;
# every call site is fail-open (a notify error must never break the pane loop).
. (Join-Path $PSScriptRoot 'notify.ps1')

# UTF-8 console so streamed CLI output (e.g. kimi's bullet glyphs) is not
# mojibake'd. Guarded: never throw in a redirected / no-console context.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Exit-code contract (see header): 0 = intentional stop, non-zero = crash.
$script:ExitIntentional = 0
$script:ExitCrash = 1

# Pure decision helper for the exit-code contract (unit-tested; the loop itself is
# infinite and not unit-testable). Intentional stop -> ExitIntentional, else crash.
function Get-StopExitCode {
    param([bool]$Intent)
    if ($Intent) { return $script:ExitIntentional } else { return $script:ExitCrash }
}

# -- Single source of headless launch flags (mirrors dispatch-handoffs.sh) --
# This is the ONLY place per-CLI launch flags live. If dispatch-handoffs.sh
# headless_cmd changes, change it here too (and vice versa).
#
# SECURITY: returns an argv ARRAY (exe + args), never a command string. The
# untrusted $Prompt (which embeds the handoff rel path, derived from an
# attacker-controllable filename) is ONE array element, so the call operator
# passes it as inert data - it is never re-parsed by a shell/PowerShell.
# Building a string here and running it through Invoke-Expression was a
# command-injection hole (a filename like `x$(cmd).md` executed); do NOT
# reintroduce a string form. The leading comma-free @(...) always yields a
# fresh array so PowerShell never unwraps a single-flag CLI's return.
function Get-HeadlessCmd {
    param([string]$CliName, [string]$Prompt)
    switch ($CliName) {
        'claude'   { return @('claude', '-p', $Prompt, '--permission-mode', 'acceptEdits') }
        'kimi'     { return @('kimi', '-p', $Prompt) }
        'kiro'     { return @('kiro-cli', 'chat', '--no-interactive', '--trust-all-tools', '--agent', 'orchestrator', $Prompt) }
        'opencode' { return @('opencode', 'run', '--auto', '--agent', 'opencode', $Prompt) }
        default    { throw "Unknown CLI: $CliName" }
    }
}

# Bare interactive form (used by the pause / manual-override escape hatch).
# Mirrors Selector.ps1 $cliDefs[...].cmd. Also an argv array (no untrusted
# prompt here, but kept consistent so the call site uses the call operator, not
# Invoke-Expression).
function Get-InteractiveCmd {
    param([string]$CliName)
    switch ($CliName) {
        'claude'   { return @('claude', '--dangerously-skip-permissions') }
        'kimi'     { return @('kimi', '--yolo') }
        'kiro'     { return @('kiro-cli', 'chat', '--trust-all-tools', '--agent', 'orchestrator') }
        'opencode' { return @('opencode', '--agent', 'opencode') }
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
    # argv array: [0] = exe, [1..] = args. The untrusted $Prompt is one element,
    # invoked via the call operator (& $exe @args) so it is NEVER re-parsed as a
    # command string (was Invoke-Expression - a filename-to-RCE hole).
    $argv = @(Get-HeadlessCmd -CliName $CliName -Prompt $Prompt)
    $exe  = $argv[0]
    $rest = @($argv | Select-Object -Skip 1)
    Write-Host "  > $exe $($rest -join ' ')" -ForegroundColor DarkGray
    # A native CLI's stderr is normal progress streaming, not a fatal error. Under
    # $ErrorActionPreference='Stop' the 2>&1-merged stderr record is promoted to a
    # terminating NativeCommandError, which would unwind the whole supervisor loop
    # on the CLI's first stderr line. Force 'Continue' around ONLY the native call
    # (restored in finally). This loses no failure signal: Invoke-HandoffRun decides
    # continue/done by whether the handoff moved to done/ (Test-HandoffDone), not by
    # exit code or stderr.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe @rest 2>&1 | Out-Host
    } finally {
        $ErrorActionPreference = $prevEAP
    }
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
        if (Test-HandoffQuarantined -Recipient $CliName -HandoffPath $f.FullName) { continue }
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

# A same-host claim whose pid is dead is stale immediately; a foreign-host claim
# (pid unverifiable locally) is trusted only within this window, then reclaimed.
$script:ProjectClaimStaleMinutes = 15

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
# No claim / no pid / our own pid -> $false (don't block). Otherwise mirror
# Test-HandoffClaimed: pid-liveness is only trusted when the claim's host matches
# ours. Same host + dead pid -> stale (reclaim). Same host + live pid + fresh ts
# -> block (legit worker). Foreign host -> can't trust the pid; block only within
# the staleness window (falls through to the time-window check). Never throws.
function Test-ClaimBlocks {
    param([string]$ProjectDir, [string]$CliName, [int]$MyPid)
    $claim = Get-Claim -ProjectDir $ProjectDir -CliName $CliName
    if ($null -eq $claim) { return $false }
    if (-not $claim.pid) { return $false }
    if ([int]$claim.pid -eq $MyPid) { return $false }

    $sameHost = (-not $claim.host) -or ($claim.host -eq [System.Net.Dns]::GetHostName())
    if ($sameHost) {
        # Trustworthy pid on this host: dead pid = crash = reclaim.
        if (-not [bool](& $script:TestPidAlive ([int]$claim.pid))) { return $false }
    }
    # Time-window: an old claim is stale regardless of host (covers a foreign-host
    # pid we can't verify, and a hung same-host process that never released).
    if ($claim.ts) {
        $when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$claim.ts, [ref]$when)) {
            $ageMin = ((Get-Date).ToUniversalTime() - $when.ToUniversalTime()).TotalMinutes
            if ($ageMin -gt $script:ProjectClaimStaleMinutes) { return $false }
        }
    }
    # Same-host live pid (fresh or unparseable ts) -> block. Foreign host within
    # the window -> block. Anything judged stale above already returned $false.
    return $true
}

# Atomic claim write (temp + rename) carrying project + cli + pid + host + ts.
# Bytes are emitted BOM-less (UTF8.GetBytes + WriteAllBytes, like Claim-Handoff);
# Set-Content -Encoding utf8 would prepend a BOM under PS 5.1.
function Write-Claim {
    param([string]$ProjectDir, [string]$CliName, [int]$MyPid)
    $p = Get-ClaimPath -ProjectDir $ProjectDir -CliName $CliName
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{
        project = (Split-Path -Leaf $ProjectDir)
        cli     = $CliName
        pid     = $MyPid
        host    = [System.Net.Dns]::GetHostName()
        ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $tmp = "$p.tmp.$MyPid"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    Move-Item -Path $tmp -Destination $p -Force
}

function Remove-Claim {
    param([string]$ProjectDir, [string]$CliName)
    $p = Get-ClaimPath -ProjectDir $ProjectDir -CliName $CliName
    if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue }
}

# -- Per-handoff claim-lock (cross-consumer contract, ADR-0009 section 3) --
#
# Finer-grained than the per-project claim above: a sidecar per handoff so two
# consumers never process the SAME to-<recipient>/open/ item (fixes the observed
# Kiro-vs-Kiro / coder race and lets app-Claude and claude-auto coordinate). The
# per-project claim still gates whole-project pickup; this gates the individual
# handoff. Format + acquire/check/release/stale semantics are documented for
# other consumers in .ai/handoffs/.claims/README.md.

$script:HandoffClaimStaleMinutes = 15

# Map a handoff path to its project's .ai/handoffs/.claims dir by walking up:
# .../.ai/handoffs/to-<recipient>/open/<file> -> .../.ai/handoffs/.claims
function Get-HandoffClaimDir {
    param([string]$HandoffPath)
    $openDir  = Split-Path -Parent $HandoffPath
    $toDir    = Split-Path -Parent $openDir
    $handoffs = Split-Path -Parent $toDir
    return (Join-Path $handoffs ".claims")
}

# Basename = handoff filename without extension (e.g. 202607101530-slug).
function Get-HandoffBasename {
    param([string]$HandoffPath)
    return [System.IO.Path]::GetFileNameWithoutExtension($HandoffPath)
}

function Get-HandoffClaimPath {
    param([string]$Recipient, [string]$HandoffPath)
    $base = Get-HandoffBasename -HandoffPath $HandoffPath
    $dir  = Get-HandoffClaimDir -HandoffPath $HandoffPath
    return (Join-Path $dir "${Recipient}__${base}.claim.json")
}

# Return the claim object if a LIVE/FRESH claim exists, else $null. A claim is
# stale (-> treat as unclaimed, reclaimable) when its pid is dead on this host OR
# its claimed_at is older than HandoffClaimStaleMinutes. pid-liveness is only
# trusted when the claim's host matches ours (a foreign-host pid is meaningless
# locally, so cross-host staleness rests on the time window alone).
function Test-HandoffClaimed {
    param([string]$Recipient, [string]$HandoffPath)
    $p = Get-HandoffClaimPath -Recipient $Recipient -HandoffPath $HandoffPath
    if (-not (Test-Path $p)) { return $null }
    $claim = $null
    try { $claim = Get-Content -Path $p -Raw | ConvertFrom-Json } catch { return $null }
    if ($null -eq $claim) { return $null }

    $sameHost = (-not $claim.host) -or ($claim.host -eq [System.Net.Dns]::GetHostName())
    if ($claim.pid -and $sameHost) {
        if (-not (& $script:TestPidAlive ([int]$claim.pid))) { return $null }
    }
    if ($claim.claimed_at) {
        $when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$claim.claimed_at, [ref]$when)) {
            $ageMin = ((Get-Date).ToUniversalTime() - $when.ToUniversalTime()).TotalMinutes
            if ($ageMin -gt $script:HandoffClaimStaleMinutes) { return $null }
        }
    }
    return $claim
}

# Atomically acquire the per-handoff claim. Returns $true if we won, $false if a
# live/fresh claim by someone else already holds it. The atomic guard is
# [IO.File]::Open with CreateNew, which throws if the sidecar already exists -
# two racing consumers cannot both create it. If the on-disk claim is STALE
# (Test-HandoffClaimed returned $null but a file lingers), we reclaim by
# overwriting under an exclusive (FileShare::None) handle so only one racer wins.
function Claim-Handoff {
    param([string]$Recipient, [string]$HandoffPath, [string]$Owner)
    if ($null -ne (Test-HandoffClaimed -Recipient $Recipient -HandoffPath $HandoffPath)) {
        return $false
    }
    $p = Get-HandoffClaimPath -Recipient $Recipient -HandoffPath $HandoffPath
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $obj = [ordered]@{
        handoff    = Get-HandoffBasename -HandoffPath $HandoffPath
        recipient  = $Recipient
        owner      = $Owner
        pid        = $PID
        host       = [System.Net.Dns]::GetHostName()
        claimed_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $json = $obj | ConvertTo-Json -Compress

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($p, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    } catch {
        # File exists but was judged stale above -> reclaim by exclusive overwrite.
        try {
            $fs = [System.IO.File]::Open($p, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        } catch {
            return $false
        }
    }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $fs.Write($bytes, 0, $bytes.Length)
    } finally {
        $fs.Dispose()
    }
    return $true
}

# Release the per-handoff claim (delete the sidecar). Call when the handoff moves
# to done/, and on graceful pause/stop for claims this owner holds.
function Release-Handoff {
    param([string]$Recipient, [string]$HandoffPath)
    $p = Get-HandoffClaimPath -Recipient $Recipient -HandoffPath $HandoffPath
    if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue }
}

# -- Per-handoff poison-pill quarantine (ADR-0008 self-healing safety valve) --
#
# A handoff that MAXES (still OPEN after the continue cap) or throws every
# iteration would otherwise be re-claimed and re-run on every poll cycle forever,
# ALERT-spamming the pane. This mirrors the per-handoff claim sidecars: a counter
# sidecar under .quarantine (beside .claims) tracks consecutive failed supervisor
# attempts and flips 'quarantined' once the count reaches MaxHandoffAttempts, at
# which point Get-QualifyingHandoff skips it until a human clears the sidecar.

$script:MaxHandoffAttempts = 3   # consecutive failed supervisor attempts before a handoff is quarantined
$script:QuarantineStaleMinutes = 60   # after this long a quarantined handoff ages out for one retry

# Map a handoff path to its project's .ai/handoffs/.quarantine dir by walking up:
# .../.ai/handoffs/to-<recipient>/open/<file> -> .../.ai/handoffs/.quarantine
function Get-HandoffQuarantineDir {
    param([string]$HandoffPath)
    $openDir  = Split-Path -Parent $HandoffPath
    $toDir    = Split-Path -Parent $openDir
    $handoffs = Split-Path -Parent $toDir
    return (Join-Path $handoffs ".quarantine")
}

function Get-HandoffQuarantinePath {
    param([string]$Recipient, [string]$HandoffPath)
    $base = Get-HandoffBasename -HandoffPath $HandoffPath
    $dir  = Get-HandoffQuarantineDir -HandoffPath $HandoffPath
    return (Join-Path $dir "${Recipient}__${base}.quarantine.json")
}

# Read the attempt record sidecar, or $null if missing / unparseable.
function Get-HandoffAttemptRecord {
    param([string]$Recipient, [string]$HandoffPath)
    $p = Get-HandoffQuarantinePath -Recipient $Recipient -HandoffPath $HandoffPath
    if (-not (Test-Path $p)) { return $null }
    try { return (Get-Content -Path $p -Raw | ConvertFrom-Json) } catch { return $null }
}

# $true iff a record exists, is flagged quarantined, AND has not aged out. A
# quarantine older than QuarantineStaleMinutes (by quarantined_at, falling back to
# last_attempt) EXPIRES -> return $false to allow ONE retry; if that retry fails,
# Add-HandoffAttempt re-quarantines with a fresh quarantined_at (bounded to ~one
# retry per window, not spam). Never throws - an unparseable ts stays quarantined.
function Test-HandoffQuarantined {
    param([string]$Recipient, [string]$HandoffPath)
    $rec = Get-HandoffAttemptRecord -Recipient $Recipient -HandoffPath $HandoffPath
    if ($null -eq $rec) { return $false }
    if (-not $rec.quarantined) { return $false }
    $stamp = if ($rec.quarantined_at) { $rec.quarantined_at } else { $rec.last_attempt }
    if ($stamp) {
        $when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$stamp, [ref]$when)) {
            $ageMin = ((Get-Date).ToUniversalTime() - $when.ToUniversalTime()).TotalMinutes
            if ($ageMin -gt $script:QuarantineStaleMinutes) { return $false }
        }
    }
    return $true
}

# Record one failed supervisor attempt: increment the counter, flip quarantined
# once it reaches MaxHandoffAttempts, write the sidecar atomically (temp + rename,
# like Write-Claim). Returns a pscustomobject exposing .attempts and .quarantined.
function Add-HandoffAttempt {
    param([string]$Recipient, [string]$HandoffPath, [string]$ErrorText = '')
    $existing = Get-HandoffAttemptRecord -Recipient $Recipient -HandoffPath $HandoffPath
    $prev = 0
    $firstAttempt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($null -ne $existing) {
        if ($existing.attempts) { $prev = [int]$existing.attempts }
        if ($existing.first_attempt) { $firstAttempt = [string]$existing.first_attempt }
    }
    $attempts = $prev + 1
    $quarantined = ($attempts -ge $script:MaxHandoffAttempts)

    $p = Get-HandoffQuarantinePath -Recipient $Recipient -HandoffPath $HandoffPath
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    # Stamp quarantined_at to now whenever this write leaves the handoff quarantined,
    # so Test-HandoffQuarantined can age it out; $null while below the threshold.
    $quarantinedAt = if ($quarantined) { $now } else { $null }

    $obj = [ordered]@{
        handoff        = Get-HandoffBasename -HandoffPath $HandoffPath
        recipient      = $Recipient
        attempts       = $attempts
        quarantined    = $quarantined
        quarantined_at = $quarantinedAt
        first_attempt  = $firstAttempt
        last_attempt   = $now
        last_error     = $ErrorText
    }
    $json = $obj | ConvertTo-Json -Compress
    $tmp = "$p.tmp.$PID"
    $json | Set-Content -Path $tmp -Encoding utf8 -NoNewline
    Move-Item -Path $tmp -Destination $p -Force

    return [pscustomobject]@{ attempts = $attempts; quarantined = $quarantined }
}

# Clear the attempt counter (delete the sidecar). Call on a successful DONE run,
# or manually by a human to un-quarantine.
function Clear-HandoffAttempts {
    param([string]$Recipient, [string]$HandoffPath)
    $p = Get-HandoffQuarantinePath -Recipient $Recipient -HandoffPath $HandoffPath
    if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue }
}

# Claim owner identity for a pane's CLI. claude-auto (the headless reviewer pane,
# ADR-0009) is a DISTINCT owner from claude-code (the interactive app-Claude), so
# the two Claude instances never double-process a to-claude handoff.
function Get-DefaultOwner {
    param([string]$CliName)
    switch ($CliName) {
        'claude'   { return 'claude-auto' }
        'kimi'     { return 'kimi-cli' }
        'kiro'     { return 'kiro-cli' }
        'opencode' { return 'opencode' }
        default    { throw "Unknown CLI: $CliName" }
    }
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
        [int]$PollSeconds,
        [string]$Owner = ''
    )
    $myPid = $PID
    if ([string]::IsNullOrWhiteSpace($Owner)) { $Owner = Get-DefaultOwner -CliName $Cli }
    # Stamp this pane's CLI in the shell env. Because the pane runs
    # 'powershell -NoExit -File pane-runner.ps1 ...', this persists in the pane's
    # shell AFTER the runner exits (Ctrl-C / bare prompt), so restart-pane.ps1 run
    # in the same pane can infer which CLI to relaunch with no -Cli argument.
    $env:RWN_PANE_CLI = $Cli
    $proj = Split-Path -Leaf $ProjectDir
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "| pane-runner  project=$proj  cli=$Cli" -ForegroundColor Cyan
    Write-Host "| IDLE poll every ${PollSeconds}s  |  MAX-continues=$MaxContinues" -ForegroundColor Cyan
    Write-Host "| 'p' = pause -> CLI   'q' = quit   Ctrl-C = stop  |" -ForegroundColor Cyan
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan

    # Intent flag for the exit-code contract: set true on a deliberate stop (Ctrl-C
    # caught, or the 'q' quit key) so the outer finally exits 0 (do-not-respawn).
    # Left false on a crash / escaped exception -> exit non-zero (supervisor respawns).
    $stopIntent = $false

    # Keyboard hatch guard: [Console]::KeyAvailable throws InvalidOperationException
    # in a headless / redirected / no-console context, and it sits INSIDE the loop -
    # so unguarded it would throw every iteration, tripping the recovery catch into an
    # endless ALERT+sleep spin (the runner could never run headless at all). Probe the
    # console ONCE up front: require an interactive process with non-redirected input,
    # then touch KeyAvailable once to confirm the host backend truly supports it (some
    # hosts pass the flags but still throw). If any check fails, the 'p'/'q' manual
    # override is simply inactive and the loop polls handoffs normally (fail-open).
    $keyboardAvailable = $false
    try {
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $null = [Console]::KeyAvailable
            $keyboardAvailable = $true
        }
    } catch {
        $keyboardAvailable = $false
    }

    try {
        while ($true) {
            # Per-iteration reset so the recovery catch below never releases a claim
            # bound to a stale handoff from a previous iteration.
            $handoff = $null
            try {
                # Manual-override escape hatch: 'p' drops to the interactive CLI;
                # 'q' is a clean intentional stop (exit 0, supervisor does not respawn).
                # Skipped entirely when no keyboard is attached (see guard above) so
                # KeyAvailable never throws in a headless pane.
                if ($keyboardAvailable -and [Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.KeyChar -eq 'p') {
                        Write-Host "== PAUSED -> dropping to interactive $Cli (exit it to resume the loop) ==" -ForegroundColor Magenta
                        Push-Location $ProjectDir
                        # Call operator + argv array (no Invoke-Expression): keeps the
                        # manual-override hatch working without a re-parsed string.
                        $icmd = @(Get-InteractiveCmd -CliName $Cli)
                        try { & $icmd[0] @($icmd | Select-Object -Skip 1) } finally { Pop-Location }
                        Write-Host "== resumed supervisor loop ==" -ForegroundColor Magenta
                        continue
                    }
                    if ($k.KeyChar -eq 'q') {
                        Write-Host "== QUIT -> intentional stop (no respawn) ==" -ForegroundColor Magenta
                        $stopIntent = $true
                        break
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

                # Per-handoff claim (ADR-0009 section 3): if another consumer holds a
                # live claim on THIS handoff, skip just this one and re-poll.
                if (-not (Claim-Handoff -Recipient $Cli -HandoffPath $handoff -Owner $Owner)) {
                    $held = Test-HandoffClaimed -Recipient $Cli -HandoffPath $handoff
                    $by = if ($held -and $held.owner) { $held.owner } else { 'another consumer' }
                    Write-Host "-- skip $(Split-Path -Leaf $handoff) (claimed by $by) --" -ForegroundColor DarkGray
                    Start-Sleep -Seconds $PollSeconds
                    continue
                }

                Write-Claim -ProjectDir $ProjectDir -CliName $Cli -MyPid $myPid
                $hbase = Get-HandoffBasename -HandoffPath $handoff
                # PICKED notify (fail-open: a notify error must not break the loop).
                try { Send-FleetNotification -Kind picked -Project $proj -Handoff $hbase -Cli $Cli -Owner $Owner | Out-Null } catch {}
                try {
                    $runResult = Invoke-HandoffRun -ProjectDir $ProjectDir -CliName $Cli -HandoffPath $handoff -MaxContinues $MaxContinues
                    # Defensive: if the run leaked extra pipeline objects, the decision
                    # record is the last one.
                    $runResult = @($runResult)[-1]
                    if ($runResult -and $runResult.Result -eq 'DONE') {
                        Clear-HandoffAttempts -Recipient $Cli -HandoffPath $handoff
                        # DONE notify (fail-open).
                        try { Send-FleetNotification -Kind done -Project $proj -Handoff $hbase -Cli $Cli -Owner $Owner | Out-Null } catch {}
                    } else {
                        # MAXED (still OPEN after the continue cap) counts as a failed
                        # attempt; quarantine once the threshold is reached.
                        $q = Add-HandoffAttempt -Recipient $Cli -HandoffPath $handoff -ErrorText 'MAXED (still OPEN after continue cap)'
                        # ALERT notify on MAXED or a new quarantine (fail-open).
                        try { Send-FleetNotification -Kind alert -Project $proj -Handoff $hbase -Cli $Cli -Owner $Owner | Out-Null } catch {}
                        if ($q.quarantined) {
                            Write-Host "== QUARANTINE [$Cli] $(Split-Path -Leaf $handoff) after $($q.attempts) failed attempts -- skipping until a human clears .ai/handoffs/.quarantine/ ==" -ForegroundColor Red
                        }
                    }
                } finally {
                    # Done-signal (moved to done/) or crash/pause: release both claims.
                    Release-Handoff -Recipient $Cli -HandoffPath $handoff
                    Remove-Claim -ProjectDir $ProjectDir -CliName $Cli
                }
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                # Ctrl-C / intentional stop: mark intent (exit 0, do-not-respawn) and let
                # it propagate to the outer finally so the runner stops cleanly.
                $stopIntent = $true
                throw
            }
            catch [System.OperationCanceledException] {
                # PS 5.1 may surface a console cancel as OperationCanceled - also a stop.
                $stopIntent = $true
                throw
            }
            catch {
                # Any OTHER error in this iteration must NOT take the pane offline.
                Write-Host "== ALERT [$Cli] pane-runner iteration error: $($_.Exception.Message) -- recovering, still polling ==" -ForegroundColor Red
                # An exception during a run is also a failed attempt -> count it so a
                # handoff that throws every cycle gets quarantined instead of spamming.
                if ($handoff) {
                    try {
                        $q = Add-HandoffAttempt -Recipient $Cli -HandoffPath $handoff -ErrorText $_.Exception.Message
                        if ($q.quarantined) { Write-Host "== QUARANTINE [$Cli] $(Split-Path -Leaf $handoff) after $($q.attempts) failed attempts -- skipping until a human clears .ai/handoffs/.quarantine/ ==" -ForegroundColor Red }
                    } catch {}
                    # Best-effort release so a mid-iteration failure never leaves a claim stuck.
                    try { Release-Handoff -Recipient $Cli -HandoffPath $handoff } catch {}
                }
                try { Remove-Claim -ProjectDir $ProjectDir -CliName $Cli } catch {}
                Start-Sleep -Seconds $PollSeconds
            }
        }
    } finally {
        # Ctrl-C / any exit: always release our claim.
        Remove-Claim -ProjectDir $ProjectDir -CliName $Cli
        Write-Host "== pane-runner stopped ($Cli) - claim released ==" -ForegroundColor DarkGray
        # Exit-code contract: force the process code so the supervisor can tell an
        # intentional stop (0, don't respawn) from a crash (non-zero, respawn). This
        # runs only under -not $NoRun (Start-PaneRunner is not called with -NoRun), so
        # dot-source tests never terminate here. An 'exit' here also suppresses a
        # propagating terminating error, which is intended - intent already recorded.
        exit (Get-StopExitCode -Intent $stopIntent)
    }
}

if (-not $NoRun) {
    Start-PaneRunner -Cli $Cli -ProjectDir $ProjectDir -MaxContinues $MaxContinues -PollSeconds $PollSeconds -Owner $Owner
}
