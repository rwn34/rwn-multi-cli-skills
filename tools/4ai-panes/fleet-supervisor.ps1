# fleet-supervisor.ps1 - OS-level fleet supervisor (Windows Task Scheduler).
#
# Runs periodically via Task Scheduler ("run only when user is logged on" +
# interactive, so it CAN open wt panes). Checks each fleet pane's heartbeat
# for L1 (liveness) and L2 (capability). On failure:
#   DEAD + open handoffs  -> alert + relaunch
#   DEAD + empty queue    -> alert only (deduped, once per incident)
#   ALIVE + NOT CAPABLE   -> alert only (no relaunch - a dead API key is not
#                            fixed by restarting the process)
#   HEALTHY               -> no action
#
# Safety properties (from the handoff's adversarial gaps):
#   1. False-positive relaunch is the WORST outcome (two fleets, two consumers
#      racing the same handoff queue). Liveness = heartbeat FILE mtime, not
#      window titles. A live fleet is NEVER relaunched.
#   2. Heartbeat files live outside the repo (%LOCALAPPDATA%) - no .ai/ churn.
#   3. Exponential backoff + max-attempts circuit breaker on relaunch failure.
#      A supervisor that can loop unattended is a liability, not a fix.
#   4. Task Scheduler + GUI: "run only when user is logged on" + interactive.
#      Verified empirically - see the handoff report.
#   5. Alert dedupe: alert on state TRANSITION, not on every poll.
#   6. Registration is scripted + reversible (install/uninstall scripts).
#
# Dot-source with -NoRun to load functions for testing without running the loop.

param(
    # Override paths for testing. Empty = use defaults.
    [string]$HeartbeatDir = '',
    [string]$StateDir = '',
    [string]$ToolsDir = $PSScriptRoot,
    [string]$WtExe = '',
    [int]$StaleSeconds = 0,
    [int]$MaxRelaunchAttempts = 5,
    [double]$BackoffBaseMinutes = 1,
    [double]$BackoffMaxMinutes = 16,
    [int]$CapabilityThreshold = 3,
    [switch]$DryRun,
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'

# Persistent log for scheduled-task debugging. The console output is lost when the
# supervisor runs hidden via wscript.exe, so tee everything to %LOCALAPPDATA%.
$script:SupervisorLogDir = if ($StateDir) { $StateDir } else {
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
    Join-Path $localAppData 'rwn-auto\fleet-supervisor'
}
if (-not (Test-Path $script:SupervisorLogDir)) {
    New-Item -ItemType Directory -Path $script:SupervisorLogDir -Force | Out-Null
}
$script:SupervisorLogFile = Join-Path $script:SupervisorLogDir 'supervisor.log'
try {
    Start-Transcript -Path $script:SupervisorLogFile -Append -Force -ErrorAction Stop | Out-Null
    $script:SupervisorTranscriptActive = $true
} catch {
    # Transcription may fail in no-console contexts; continue silently.
    $script:SupervisorTranscriptActive = $false
}

# Dot-source notify.ps1 for Send-FleetNotification (fail-open Telegram alerts).
$notifyPath = Join-Path $ToolsDir 'notify.ps1'
if (Test-Path $notifyPath) { . $notifyPath }

# Dot-source fleet-clis.ps1 for the canonical CLI list.
$clisPath = Join-Path $ToolsDir 'fleet-clis.ps1'
if (Test-Path $clisPath) { . $clisPath }

# -- Path resolution ---------------------------------------------------------

function Get-SupervisorHeartbeatDir {
    if ($HeartbeatDir) { return $HeartbeatDir }
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
    return (Join-Path $localAppData 'rwn-auto\fleet-heartbeat')
}

function Get-SupervisorStateDir {
    if ($StateDir) { return $StateDir }
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
    return (Join-Path $localAppData 'rwn-auto\fleet-supervisor')
}

function Get-SupervisorStatePath {
    return (Join-Path (Get-SupervisorStateDir) 'state.json')
}

function Get-SupervisorWtExe {
    if ($WtExe) { return $WtExe }
    return "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
}

function Get-SupervisorStaleSeconds {
    if ($StaleSeconds -gt 0) { return $StaleSeconds }
    return 90   # 3x default 10s poll + generous margin
}

# -- Heartbeat reading -------------------------------------------------------

# Read all heartbeat files from the heartbeat directory. Returns an array of
# parsed heartbeat objects (with an added .StaleSeconds property for age).
function Get-AllHeartbeats {
    $dir = Get-SupervisorHeartbeatDir
    if (-not (Test-Path $dir)) { return @() }
    $files = Get-ChildItem -Path $dir -Filter '*.json' -File -ErrorAction SilentlyContinue
    $heartbeats = @()
    $now = (Get-Date).ToUniversalTime()
    foreach ($f in $files) {
        try {
            $hb = Get-Content -Path $f.FullName -Raw | ConvertFrom-Json
            if (-not $hb.ts) { continue }
            $ts = [datetime]::MinValue
            if ([datetime]::TryParse([string]$hb.ts, [ref]$ts)) {
                $hb | Add-Member -NotePropertyName 'AgeSeconds' -NotePropertyValue ($now - $ts.ToUniversalTime()).TotalSeconds -Force
            } else {
                $hb | Add-Member -NotePropertyName 'AgeSeconds' -NotePropertyValue 999999 -Force
            }
            $hb | Add-Member -NotePropertyName 'FilePath' -NotePropertyValue $f.FullName -Force
            $heartbeats += $hb
        } catch { }
    }
    return $heartbeats
}

# -- Health classification ---------------------------------------------------

# Classify a single pane's health from its heartbeat.
# Returns: 'healthy' | 'dead' | 'incapable'
#   healthy   = L1 fresh AND (no capability concern OR below threshold)
#   dead      = L1 stale (heartbeat too old or missing)
#   incapable = L1 fresh BUT L2 shows persistent auth/quota failure
function Get-PaneHealth {
    param(
        [object]$Heartbeat,   # parsed heartbeat object with .AgeSeconds, or $null
        [int]$StaleThreshold,
        [int]$CapThreshold
    )
    if ($null -eq $Heartbeat) { return 'dead' }
    if ($Heartbeat.AgeSeconds -gt $StaleThreshold) { return 'dead' }

    # L2 check: alive but can it do work?
    $outcome = [string]$Heartbeat.last_invoke_outcome
    $failures = 0
    if ($Heartbeat.consecutive_failures) { $failures = [int]$Heartbeat.consecutive_failures }

    if (($outcome -eq 'auth_failure' -or $outcome -eq 'quota_exceeded') -and $failures -ge $CapThreshold) {
        return 'incapable'
    }
    return 'healthy'
}

# Group heartbeats by project and classify the project's overall health.
# Returns an array of project health objects:
#   @{ Project; ProjectDir; State; DeadClis; IncapableClis; HealthyClis; HasOpenHandoffs }
# State: 'healthy' | 'down' | 'incapable' | 'partial'
function Get-ProjectHealth {
    param([int]$StaleThreshold, [int]$CapThreshold)
    $heartbeats = Get-AllHeartbeats

    # Canonical fleet list: if fleet-clis.ps1 is loaded, every CLI in the fleet
    # must be accounted for. A missing heartbeat file means that CLI has never
    # started (or its heartbeat was lost) -> dead. If the fleet list is not
    # available, fall back to whatever heartbeats exist.
    $canonicalClis = if ($script:FleetClis) { $script:FleetClis } else { @($heartbeats | ForEach-Object { $_.cli } | Sort-Object -Unique) }

    $projects = @{}
    foreach ($hb in $heartbeats) {
        $proj = [string]$hb.project
        if (-not $proj) { continue }
        if (-not $projects.ContainsKey($proj)) {
            $projects[$proj] = @{
                ProjectDir    = [string]$hb.project_dir
                DeadClis      = @()
                IncapableClis = @()
                HealthyClis   = @()
                IncapableReasons = @{}
                SeenClis      = @{}
            }
        }
        $health = Get-PaneHealth -Heartbeat $hb -StaleThreshold $StaleThreshold -CapThreshold $CapThreshold
        $cli = [string]$hb.cli
        $projects[$proj].SeenClis[$cli] = $true
        switch ($health) {
            'dead'      { $projects[$proj].DeadClis += $cli }
            'incapable' {
                $projects[$proj].IncapableClis += $cli
                $projects[$proj].IncapableReasons[$cli] = [string]$hb.last_invoke_outcome
            }
            'healthy'   { $projects[$proj].HealthyClis += $cli }
        }
    }

    # Mark any canonical fleet CLI that has no heartbeat as dead for every
    # discovered project. Without this, a freshly-reset heartbeat dir with only
    # one pane's heartbeat looks "healthy" and the missing panes never relaunch.
    foreach ($projName in $projects.Keys) {
        $p = $projects[$projName]
        foreach ($cli in $canonicalClis) {
            if (-not $p.SeenClis.ContainsKey($cli)) {
                $p.DeadClis += $cli
            }
        }
    }

    # Empty heartbeat dir (first install or after a wipe): if the install
    # provenance points at a repo with open handoffs, synthesize a down project
    # so the supervisor can still relaunch. Without open handoffs there is no
    # work to do, so we stay silent and avoid non-deterministic alerts tied to
    # the live repo state.
    if ($projects.Count -eq 0 -and $canonicalClis.Count -gt 0) {
        $provPath = if ($env:RWN_FLEET_SUPERVISOR_PROVENANCE) { $env:RWN_FLEET_SUPERVISOR_PROVENANCE } else { Join-Path $PSScriptRoot '.sync-provenance.json' }
        if (Test-Path $provPath) {
            try {
                $prov = Get-Content $provPath -Raw | ConvertFrom-Json
                $sourceRepo = [string]$prov.source_repo
                if ($sourceRepo -and (Test-Path $sourceRepo) -and (Test-ProjectHasOpenHandoffs -ProjectDir $sourceRepo)) {
                    $projName = Split-Path -Leaf $sourceRepo
                    $projects[$projName] = @{
                        ProjectDir       = $sourceRepo
                        DeadClis         = @($canonicalClis)
                        IncapableClis    = @()
                        HealthyClis      = @()
                        IncapableReasons = @{}
                        SeenClis         = @{}
                    }
                }
            } catch {
                Write-Host "  WARNING: could not read .sync-provenance.json: $_" -ForegroundColor Yellow
            }
        }
    }

    if ($projects.Count -eq 0) { return @() }

    $results = @()
    foreach ($projName in $projects.Keys) {
        $p = $projects[$projName]
        $totalClis = $p.DeadClis.Count + $p.IncapableClis.Count + $p.HealthyClis.Count
        $hasOpenHandoffs = Test-ProjectHasOpenHandoffs -ProjectDir $p.ProjectDir

        $state = 'healthy'
        if ($p.IncapableClis.Count -gt 0 -and $p.DeadClis.Count -eq 0) {
            $state = 'incapable'
        } elseif ($p.DeadClis.Count -eq $totalClis) {
            $state = 'down'
        } elseif ($p.DeadClis.Count -gt 0) {
            $state = 'partial'
        }

        $results += [pscustomobject]@{
            Project          = $projName
            ProjectDir       = $p.ProjectDir
            State            = $state
            DeadClis         = $p.DeadClis
            IncapableClis    = $p.IncapableClis
            IncapableReasons = $p.IncapableReasons
            HealthyClis      = $p.HealthyClis
            HasOpenHandoffs  = $hasOpenHandoffs
        }
    }
    return $results
}

# Check if a project has any open handoffs (any recipient).
function Test-ProjectHasOpenHandoffs {
    param([string]$ProjectDir)
    if (-not $ProjectDir) { return $false }
    $handoffsDir = Join-Path $ProjectDir '.ai\handoffs'
    if (-not (Test-Path $handoffsDir)) { return $false }
    $toDirs = Get-ChildItem -Path $handoffsDir -Directory -Filter 'to-*' -ErrorAction SilentlyContinue
    foreach ($toDir in $toDirs) {
        $openDir = Join-Path $toDir.FullName 'open'
        if (Test-Path $openDir) {
            $count = @(Get-ChildItem -Path $openDir -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
            if ($count -gt 0) { return $true }
        }
    }
    return $false
}

# -- State management (dedupe + backoff) -------------------------------------

# Load the supervisor state file. Returns a hashtable keyed by project name.
function Get-SupervisorState {
    $path = Get-SupervisorStatePath
    if (-not (Test-Path $path)) { return @{} }
    try {
        $json = Get-Content -Path $path -Raw | ConvertFrom-Json
        $state = @{}
        if ($json.projects) {
            foreach ($prop in $json.projects.PSObject.Properties) {
                $state[$prop.Name] = $prop.Value
            }
        }
        return $state
    } catch { return @{} }
}

# Save the supervisor state atomically (temp + rename).
function Save-SupervisorState {
    param([hashtable]$State)
    try {
        $path = Get-SupervisorStatePath
        $dir = Split-Path -Parent $path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $projects = [ordered]@{}
        foreach ($k in ($State.Keys | Sort-Object)) { $projects[$k] = $State[$k] }
        $obj = [ordered]@{ projects = $projects }
        $tmp = "$path.tmp.$PID"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        Move-Item -Path $tmp -Destination $path -Force
    } catch { }
}

# Determine whether an alert should fire (state transition dedupe).
# Returns $true if this is a NEW condition (state changed since last check).
function Test-ShouldAlert {
    param([hashtable]$State, [string]$Project, [string]$NewState)
    if (-not $State.ContainsKey($Project)) { return $true }
    $prev = $State[$Project]
    $prevState = [string]$prev.state
    return ($prevState -ne $NewState)
}

# Determine whether a relaunch should be attempted (backoff + circuit breaker).
# Returns @{ Allowed = bool; Reason = string }
function Test-ShouldRelaunch {
    param([hashtable]$State, [string]$Project, [int]$MaxAttempts, [double]$BaseMin, [double]$MaxMin)
    if (-not $State.ContainsKey($Project)) {
        return @{ Allowed = $true; Reason = 'first attempt' }
    }
    $prev = $State[$Project]
    $attempts = 0
    if ($prev.relaunch_attempts) { $attempts = [int]$prev.relaunch_attempts }
    if ($attempts -ge $MaxAttempts) {
        return @{ Allowed = $false; Reason = "circuit breaker: $attempts attempts >= max $MaxAttempts" }
    }
    # Exponential backoff: don't retry until enough time has passed.
    if ($prev.last_relaunch_ts) {
        $lastRelaunch = [datetime]::MinValue
        if ([datetime]::TryParse([string]$prev.last_relaunch_ts, [ref]$lastRelaunch)) {
            $delayMin = [math]::Min($MaxMin, $BaseMin * [math]::Pow(2, $attempts))
            $elapsed = ((Get-Date).ToUniversalTime() - $lastRelaunch.ToUniversalTime()).TotalMinutes
            if ($elapsed -lt $delayMin) {
                return @{ Allowed = $false; Reason = "backoff: ${elapsed}min elapsed < ${delayMin}min required (attempt $attempts)" }
            }
        }
    }
    return @{ Allowed = $true; Reason = "attempt $($attempts + 1)/$MaxAttempts" }
}

# -- Relaunch ----------------------------------------------------------------

# Detect available CLIs on this host (same detection as Selector.ps1),
# restricted to the canonical fleet list and excluding any that are already
# supervised for this project (prevents duplicate panes on partial-fleet relaunch).
function Get-AvailableClis {
    $clis = @(
        @{ name = 'claude';   detect = 'claude' },
        @{ name = 'kiro';     detect = 'kiro-cli' },
        @{ name = 'kimi';     detect = 'kimi' },
        @{ name = 'opencode'; detect = 'opencode' }
    )
    # If the canonical fleet list is loaded (production), only relaunch CLIs
    # that belong to the supervised fleet.
    if ($script:FleetClis) {
        $clis = $clis | Where-Object { $script:FleetClis -contains $_.name }
    }
    $available = @()
    foreach ($c in $clis) {
        if (Get-Command $c.detect -ErrorAction SilentlyContinue) { $available += $c.name }
    }
    return $available
}

# Returns $true if this CLI has a heartbeat file for the project and the
# heartbeat is fresh (within the supervisor stale threshold). This is the same
# L1 signal the main health check uses; relying on it avoids CIM/Win32_Process
# queries that may fail or return empty in the scheduled-task context.
function Test-HeartbeatFresh {
    param([string]$Cli, [string]$ProjectDir)
    $hbDir = Get-SupervisorHeartbeatDir
    $projName = Split-Path -Leaf $ProjectDir
    $hbPath = Join-Path $hbDir "$projName`__$Cli.json"
    if (-not (Test-Path -LiteralPath $hbPath)) { return $false }
    try {
        $hb = Get-Content -LiteralPath $hbPath -Raw | ConvertFrom-Json
        if (-not $hb.ts) { return $false }
        $ts = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$hb.ts, [ref]$ts)) { return $false }
        $age = ((Get-Date).ToUniversalTime() - $ts.ToUniversalTime()).TotalSeconds
        return ($age -le (Get-SupervisorStaleSeconds))
    } catch { return $false }
}

# Kill any existing supervisor process for a given CLI/project. Called before
# relaunching so a stale/dead pane cannot coexist with the new one. This is the
# second line of defence after Test-HeartbeatFresh: a heartbeat may be stale
# because the pane process is hung but still alive, and without this guard the
# supervisor would accumulate duplicate panes on every relaunch attempt.
function Stop-ExistingSupervisor {
    param([string]$Cli, [string]$ProjectDir)
    try {
        $procs = Get-CimInstance Win32_Process | Where-Object {
            $_.CommandLine -like '*run-pane-supervised.ps1*' -and
            $_.CommandLine -match "-Cli\s+\b$Cli\b" -and
            $_.CommandLine -match [regex]::Escape($ProjectDir)
        }
        foreach ($p in $procs) {
            Write-Host "  stopping existing $Cli supervisor PID $($p.ProcessId)" -ForegroundColor DarkGray
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

# Relaunch the fleet for a project. Uses the same pane-runner scripts and wt
# invocation pattern as Selector.ps1's Build-FleetTabStages, simplified to a
# 4-pane grid (one pane per CLI). The supervisor's job is to get the fleet
# RUNNING, not to replicate the exact interactive layout.
#
# Returns $true on success, $false on failure.
function Invoke-FleetRelaunch {
    param([string]$ProjectDir)
    $wt = Get-SupervisorWtExe
    if (-not (Test-Path $wt)) {
        Write-Host "  ERROR: wt.exe not found at $wt - cannot relaunch" -ForegroundColor Red
        return $false
    }
    $supervisor = Join-Path $ToolsDir 'run-pane-supervised.ps1'
    if (-not (Test-Path $supervisor)) {
        Write-Host "  ERROR: run-pane-supervised.ps1 not found at $supervisor" -ForegroundColor Red
        return $false
    }

    $available = Get-AvailableClis |
        Where-Object { -not (Test-HeartbeatFresh -Cli $_ -ProjectDir $ProjectDir) }

    $running = Get-AvailableClis |
        Where-Object { Test-HeartbeatFresh -Cli $_ -ProjectDir $ProjectDir }

    if ($running.Count -gt 0) {
        Write-Host "  SKIP (heartbeat fresh): $($running -join ', ')" -ForegroundColor DarkGray
    }

    if ($available.Count -eq 0) {
        Write-Host "  All fleet panes already running for $ProjectDir - nothing to relaunch" -ForegroundColor Green
        return $true
    }

    $dq = '"'
    $leaf = Split-Path -Leaf $ProjectDir
    $n = $available.Count

    # Build wt stages: new-tab for first CLI, split-pane for the rest.
    # Same invocation pattern as Selector.ps1 (paced, one stage per wt call).
    $stages = @()
    $firstCmd = "powershell -NoExit -NoProfile -File $dq$supervisor$dq -Cli $($available[0]) -ProjectDir $dq$ProjectDir$dq"
    $stages += "new-tab --title $dq$leaf$dq -d $dq$ProjectDir$dq $firstCmd"

    for ($i = 1; $i -lt $n; $i++) {
        $frac = [math]::Round(($n - $i) / ($n - $i + 1), 4)
        $cmd = "powershell -NoExit -NoProfile -File $dq$supervisor$dq -Cli $($available[$i]) -ProjectDir $dq$ProjectDir$dq"
        $stages += "split-pane -V -s $frac -d $dq$ProjectDir$dq $cmd"
    }

    Write-Host "  Relaunching fleet for $leaf ($n panes: $($available -join ', '))" -ForegroundColor Cyan

    # Before launching anything, tear down any existing supervisor processes for
    # the CLIs we are about to relaunch. A stale heartbeat means the old pane is
    # dead or stuck; leaving it running creates duplicates.
    foreach ($cli in $available) {
        Stop-ExistingSupervisor -Cli $cli -ProjectDir $ProjectDir
    }

    $ok = $false

    # Primary path: Windows Terminal grid in the existing rwn4ai window.
    if (Test-Path $wt) {
        $wtOk = $true
        foreach ($stage in $stages) {
            $wtCmd = "-w rwn4ai $stage"
            Write-Host "    `"$wt`" $wtCmd" -ForegroundColor DarkGray
            if (-not $DryRun) {
                try {
                    & cmd.exe /c "`"$wt`" $wtCmd"
                    # Give the new pane a moment to appear so the next split targets it.
                    Start-Sleep -Milliseconds 500
                } catch {
                    Write-Host "    FAILED: $_" -ForegroundColor Red
                    $wtOk = $false
                    break
                }
            }
        }
        # Verify that the launched CLIs actually produced fresh heartbeats.
        # wt.exe may return success without opening a window (e.g. the target
        # window is gone), so we must check the L1 signal, not the exit code.
        if ($wtOk -and -not $DryRun) {
            Start-Sleep -Seconds 3
            $missing = $available | Where-Object { -not (Test-HeartbeatFresh -Cli $_ -ProjectDir $ProjectDir) }
            if ($missing) {
                Write-Host "  WT launch did not produce heartbeats for: $($missing -join ', ') - will fallback" -ForegroundColor Yellow
                $wtOk = $false
            }
        }
        $ok = $wtOk
    }

    # Fallback: standalone PowerShell console windows. Used when wt.exe is missing,
    # the rwn4ai window is gone, or the split-pane sequence fails. The scheduled
    # task runs interactive, so these windows are visible and stay up.
    if (-not $ok -and -not $DryRun) {
        Write-Host "  Falling back to standalone PowerShell windows" -ForegroundColor Yellow
        foreach ($cli in $available) {
            try {
                Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$supervisor`" -Cli $cli -ProjectDir `"$ProjectDir`"" -WorkingDirectory $ProjectDir
                Write-Host "    started $cli in standalone window" -ForegroundColor Green
                Start-Sleep -Milliseconds 250
            } catch {
                Write-Host "    FAILED to start $cli`: $_" -ForegroundColor Red
                continue
            }
        }
        # Verify at least one fresh heartbeat appeared.
        Start-Sleep -Seconds 3
        $ok = ($available | Where-Object { Test-HeartbeatFresh -Cli $_ -ProjectDir $ProjectDir }).Count -gt 0
    }

    return $ok
}

# -- Alert -------------------------------------------------------------------

# Send a fleet alert via Telegram (fail-open). Also prints to console.
function Send-SupervisorAlert {
    param([string]$Project, [string]$Message)
    Write-Host "  ALERT [$Project]: $Message" -ForegroundColor Red
    if (-not $DryRun) {
        try {
            Send-FleetNotification -Kind alert -Project $Project -Handoff $Message -Cli 'supervisor' -Owner 'fleet-supervisor' | Out-Null
        } catch { }
    }
}

# -- Main check cycle --------------------------------------------------------

# Overridable hooks (tests replace these with mocks — same pattern as
# pane-runner.ps1's $script:InvokeCli / $script:TestPidAlive). Production code
# calls through these indirections; only tests replace them.
$script:SupervisorRelaunch = {
    param([string]$ProjectDir)
    return (Invoke-FleetRelaunch -ProjectDir $ProjectDir)
}
$script:SupervisorSendAlert = {
    param([string]$Project, [string]$Message)
    Send-SupervisorAlert -Project $Project -Message $Message
}

# Run one supervisor check cycle. Returns an array of action objects for
# testability. Each action: @{ Project; Action; Detail }
# Action: 'none' | 'alert' | 'relaunch' | 'alert+relaunch' | 'give-up'
function Invoke-SupervisorCheck {
    $staleThreshold = Get-SupervisorStaleSeconds
    $state = Get-SupervisorState
    $projects = Get-ProjectHealth -StaleThreshold $staleThreshold -CapThreshold $CapabilityThreshold
    $actions = @()

    foreach ($proj in $projects) {
        $projName = $proj.Project
        $action = 'none'
        $detail = ''

        switch ($proj.State) {
            'healthy' {
                # All panes alive and capable. If previously in a bad state, log recovery.
                if ($state.ContainsKey($projName) -and [string]$state[$projName].state -ne 'healthy') {
                    Write-Host "  RECOVERED [$projName]: fleet is healthy again" -ForegroundColor Green
                    $action = 'recovered'
                }
                # Reset incident tracking on recovery.
                if ($state.ContainsKey($projName)) {
                    $state[$projName] = [pscustomobject]@{
                        state              = 'healthy'
                        last_alert_ts      = $null
                        relaunch_attempts  = 0
                        last_relaunch_ts   = $null
                        incident_start_ts  = $null
                    }
                }
            }
            'incapable' {
                # ALIVE but NOT CAPABLE -> alert only, NEVER relaunch.
                $shouldAlert = Test-ShouldAlert -State $state -Project $projName -NewState 'incapable'
                if ($shouldAlert) {
                    $reasons = @()
                    foreach ($cli in $proj.IncapableClis) {
                        $reason = if ($proj.IncapableReasons[$cli]) { $proj.IncapableReasons[$cli] } else { 'unknown' }
                        $reasons += "$cli ($reason)"
                    }
                    $detail = "CLI(s) alive but NOT CAPABLE: $($reasons -join ', '). Not relaunching - fix credentials/quota."
                    & $script:SupervisorSendAlert $projName $detail
                    $action = 'alert'
                } else {
                    $detail = 'incapable (already alerted, deduped)'
                    $action = 'none'
                }
                $state[$projName] = [pscustomobject]@{
                    state              = 'incapable'
                    last_alert_ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    relaunch_attempts  = 0
                    last_relaunch_ts   = $null
                    incident_start_ts  = if ($state.ContainsKey($projName) -and $state[$projName].incident_start_ts) { $state[$projName].incident_start_ts } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                }
            }
            { $_ -in @('down', 'partial') } {
                $shouldAlert = Test-ShouldAlert -State $state -Project $projName -NewState $proj.State
                $relaunchCheck = Test-ShouldRelaunch -State $state -Project $projName `
                    -MaxAttempts $MaxRelaunchAttempts -BaseMin $BackoffBaseMinutes -MaxMin $BackoffMaxMinutes

                if ($shouldAlert) {
                    $deadList = $proj.DeadClis -join ', '
                    $handoffNote = if ($proj.HasOpenHandoffs) { ' (open handoffs pending)' } else { ' (no open handoffs)' }
                    $detail = "Fleet DOWN: $deadList$handoffNote"
                    & $script:SupervisorSendAlert $projName $detail
                    $action = 'alert'
                }

                # Only relaunch if there are open handoffs (or always for down? per handoff:
                # "DOWN with an empty queue -> alert is optional"). We relaunch only when
                # handoffs exist — an idle fleet that's down doesn't need immediate restore.
                if ($proj.HasOpenHandoffs -and $relaunchCheck.Allowed) {
                    Write-Host "  Attempting relaunch for $projName ($($relaunchCheck.Reason))" -ForegroundColor Yellow
                    $relaunchOk = & $script:SupervisorRelaunch $proj.ProjectDir
                    $attempts = 0
                    if ($state.ContainsKey($projName) -and $state[$projName].relaunch_attempts) {
                        $attempts = [int]$state[$projName].relaunch_attempts
                    }
                    $state[$projName] = [pscustomobject]@{
                        state              = $proj.State
                        last_alert_ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                        relaunch_attempts  = ($attempts + 1)
                        last_relaunch_ts   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                        incident_start_ts  = if ($state.ContainsKey($projName) -and $state[$projName].incident_start_ts) { $state[$projName].incident_start_ts } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                    }
                    if ($relaunchOk) {
                        $action = if ($action -eq 'alert') { 'alert+relaunch' } else { 'relaunch' }
                        $detail = "relaunch attempted ($($relaunchCheck.Reason))"
                    } else {
                        $detail = "relaunch FAILED ($($relaunchCheck.Reason))"
                    }
                } elseif (-not $relaunchCheck.Allowed) {
                    # Circuit breaker or backoff: don't relaunch.
                    if ($relaunchCheck.Reason -match 'circuit breaker') {
                        $cbAlert = Test-ShouldAlert -State $state -Project $projName -NewState 'give-up'
                        if ($cbAlert) {
                            & $script:SupervisorSendAlert $projName "GAVE UP relaunching after $MaxRelaunchAttempts attempts. Manual intervention needed."
                            $state[$projName].state = 'give-up'
                            $action = 'give-up'
                        }
                    }
                    $detail = "no relaunch: $($relaunchCheck.Reason)"
                    if ($action -eq 'none') { $action = 'none' }
                } else {
                    $detail = 'down but no open handoffs - alert only'
                }

                # Ensure state is recorded even if no relaunch was attempted.
                if (-not $state.ContainsKey($projName) -or [string]$state[$projName].state -eq 'healthy') {
                    $state[$projName] = [pscustomobject]@{
                        state              = $proj.State
                        last_alert_ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                        relaunch_attempts  = 0
                        last_relaunch_ts   = $null
                        incident_start_ts  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    }
                }
            }
        }

        $actions += [pscustomobject]@{ Project = $projName; Action = $action; Detail = $detail }
    }

    Save-SupervisorState -State $state
    return $actions
}

# -- Entry point -------------------------------------------------------------

if (-not $NoRun) {
    Write-Host "== fleet-supervisor check $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" -ForegroundColor Cyan
    $actions = Invoke-SupervisorCheck
    foreach ($a in $actions) {
        if ($a.Action -ne 'none') {
            Write-Host "  $($a.Project): $($a.Action) - $($a.Detail)" -ForegroundColor White
        }
    }
    if ($actions.Count -eq 0) {
        Write-Host "  no heartbeats found (fleet not running or heartbeat dir empty)" -ForegroundColor DarkGray
    } elseif (@($actions | Where-Object { $_.Action -ne 'none' }).Count -eq 0) {
        Write-Host "  all projects healthy" -ForegroundColor Green
    }

    if ($script:SupervisorTranscriptActive) {
        Stop-Transcript | Out-Null
    }
}
