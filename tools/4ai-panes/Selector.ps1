# Selector.ps1 - Interactive project selector for rwn-4AI-panes
# Phase 1: Box-drawing menu with arrow-key navigation
# Phase 2: Splits into 4 panes: Claude | Kiro | Kimi | OpenCode

$ErrorActionPreference = "SilentlyContinue"

# Refresh process PATH from user environment in case the parent process (e.g. Windows Terminal) has a stale PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$procPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
if ($userPath -and $procPath) {
    $missing = @($userPath -split ';' | Where-Object { $_ -and ($procPath -notlike "*$_*") })
    if ($missing.Count -gt 0) {
        [Environment]::SetEnvironmentVariable('Path', "$procPath;$userPath", 'Process')
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectsDir = "C:\Users\rwn34\Code"
$historyFile = Join-Path $scriptDir ".4pane-history"
$layoutFile = Join-Path $scriptDir ".4pane-layout"
$wtExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
$frameworkRepo = if ($env:RWN_FRAMEWORK_REPO) { $env:RWN_FRAMEWORK_REPO } else { "C:/Users/rwn34/Code/rwn-multi-cli-skills" }

# SINGLE SOURCE for the fleet CLI list. Resolve via $PSScriptRoot so it works both
# in the repo tree and in the flat install dir (fleet-clis.ps1 sits beside this file).
. (Join-Path $PSScriptRoot 'fleet-clis.ps1')   # provides $FleetClis + $FleetCliProper
# Derive both case maps from the shared source instead of hardcoding them:
#   $cliKey   : lower -> Proper (identical to $FleetCliProper) - used by Get-ProjectBadges
#   $cliLower : Proper -> lower (the inverse) - used by the pane-launch commands
$cliKey = @{}
$cliLower = @{}
foreach ($c in $FleetClis) { $cliKey[$c] = $FleetCliProper[$c]; $cliLower[$FleetCliProper[$c]] = $c }

# ── Per-tab pane layout (ADR-0009 operator-over-fleet) ── OWNER-TWEAKABLE ──
# RWN_PANE_LAYOUT selects the WT tab layout built per project:
#   '6pane' (default/unset) = TOP row (~50% tall) holding 2 side-by-side NON-polling
#                             interactive cockpits (top-left app-Claude/claude-code,
#                             top-right bare Kimi) OVER a BOTTOM row of 4 self-driving
#                             pane-runner workers (incl. auto-Claude). 2-over-4 fleet.
#   '5pane'                 = fallback: TOP full-width ~50% strip running bare
#                             interactive Claude only + BOTTOM 4 self-driving workers.
#   '4grid'                 = legacy 4-pane grid (instant fallback if the new WT
#                             split misbehaves on this machine).
$paneLayoutMode = if ($env:RWN_PANE_LAYOUT) { $env:RWN_PANE_LAYOUT } else { '6pane' }
# Top ROW height as a fraction of the tab (0.50 = 50%, now holding 2 operators).
# Bottom region (the 4-column fleet) = 1 - this.
$topStripFraction = 0.50

# ── Launch pacing (owner defect 2026-07-11: batch launches landed scrambled) ──
# Firing one `wt` call that chains dozens of new-tab/split-pane subcommands makes
# Windows Terminal race itself: splits land against whichever pane happens to be
# focused when WT gets to them, so the layout comes out shuffled. We therefore
# PACE the launch — one wt invocation per stage, with a settle delay between:
#   RWN_4AI_PANE_DELAY_MS : ms between pane stages inside one project's tab (250)
#   RWN_4AI_TAB_DELAY_MS  : ms between project tabs in a batch launch (4000)
#   Raised to 4000ms (owner request 2026-07-14) so Windows Terminal has time to
#   settle each tab layout before the next project tab arrives during multi-mark
#   batch launches; single-project launches are unaffected because they never pay
#   the tab delay.
# Either knob set to 0 restores the legacy ATOMIC single-invocation behavior for
# that dimension (escape hatch if staging ever misbehaves on a machine):
#   pane delay 0 -> a project's whole tab ships as one chained wt call
#   tab delay 0  -> the WHOLE batch ships as one chained wt call (which necessarily
#                   makes the panes atomic too — one invocation cannot be staged)
# Garbage / negative / non-numeric values fall back to the default, never crash.
function Get-DelayMs {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][int]$Default)
    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
    $parsed = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$parsed)) { return $Default }
    if ($parsed -lt 0) { return $Default }
    return $parsed
}
$paneDelayMs = Get-DelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250
$tabDelayMs  = Get-DelayMs -Name 'RWN_4AI_TAB_DELAY_MS'  -Default 4000

# Windows caps a command line at ~8191 chars. Only the ATOMIC escape-hatch paths
# can approach that now (staged emission ships one short subcommand per call), but
# a single over-long invocation would silently truncate, so it is warned about.
$maxSafeCmdLen = 7000

# ── CLI Definitions ──
# Each CLI: name, detection command, launch command
$cliDefs = [ordered]@{}
$cliDefs["Claude"] = @{ detect = "claude"; cmd = "claude --dangerously-skip-permissions" }
$cliDefs["Kiro"]   = @{ detect = "kiro-cli"; cmd = "kiro-cli chat --trust-all-tools --agent orchestrator" }  # v2 interactive form (enforces mechanically in interactive mode per rollup 2026-07-09); --agent pins the hook-bearing orchestrator, bare `chat` runs the hookless built-in default (T-K2). TODO(owner): confirm the v3-TUI launch string that ALSO carries --agent. Evidence 2026-07-09 (kiro-cli-chat 2.12.0): canonical `kiro-cli --v3` (per v3 docs) REJECTS --agent ("error: unexpected argument '--agent'; Usage: kiro-cli.exe --v3"); `--v3 chat` WITHOUT --tui is the classic non-TUI mode the docs say does NOT support v3 (silent v2 fallback); `kiro-cli --v3 chat --tui --agent orchestrator` parses but engine-engagement unverifiable without a TTY. Left on working v2 until owner confirms the v3-TUI string in a live session.
$cliDefs["Kimi"]   = @{ detect = "kimi"; cmd = "kimi --yolo" }
$cliDefs["OpenCode"] = @{ detect = "opencode"; cmd = "opencode --agent opencode" }  # --agent pins the contract-carrying agent (TUI accepts --agent, verified 2026-07-09); no --yolo equivalent — permissions + framework-guard plugin govern (ADR-0002 amendment 2026-07-09)

$cliAvailable = @{}
foreach ($name in $cliDefs.Keys) {
    $cliAvailable[$name] = [bool](Get-Command $cliDefs[$name].detect -ErrorAction SilentlyContinue)
}

$anyAvailable = $false
foreach ($name in $cliAvailable.Keys) {
    if ($cliAvailable[$name]) { $anyAvailable = $true; break }
}
if (-not $anyAvailable) {
    Write-Host "No code CLIs found (claude, kiro-cli, kimi, opencode)." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Stop-Process -Id $PID
}

# ── Layout Management ──
function Get-Layout {
    if (Test-Path $layoutFile) {
        try {
            $raw = Get-Content $layoutFile -Raw | ConvertFrom-Json
            if ($raw -is [array] -and $raw.Count -gt 0) {
                $valid = $true
                foreach ($item in $raw) {
                    if (-not $cliDefs.Contains($item)) { $valid = $false; break }
                }
                if ($valid) { return @($raw) }
            }
        } catch {}
    }
    return @("Claude", "Kiro", "Kimi", "OpenCode")
}

function Save-Layout($layout) {
    ConvertTo-Json -InputObject $layout | Set-Content $layoutFile
}

# ── Project Functions ──
function Get-Projects {
    if (Test-Path $projectsDir) {
        Get-ChildItem -Path $projectsDir -Directory |
            Where-Object { $_.Name -notmatch '^\.' } |
            Select-Object -ExpandProperty Name | Sort-Object
    } else {
        @()
    }
}

function Get-History {
    if (Test-Path $historyFile) {
        try {
            $raw = Get-Content $historyFile -Raw | ConvertFrom-Json
            if ($raw -is [array]) { return $raw }
            if ($raw) { return @($raw) }
            return @()
        } catch { return @() }
    }
    return @()
}

function Save-History($project) {
    $history = @(Get-History)
    $entry = [PSCustomObject]@{
        project = $project
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $history = $history | Where-Object { $_.project -ne $project }
    $history = @($entry) + $history
    $history = $history | Select-Object -First 5
    ConvertTo-Json -InputObject $history | Set-Content $historyFile
}

function Format-TimeAgo($timestamp) {
    try {
        $dt = [datetime]::Parse($timestamp)
        $diff = [datetime]::Now - $dt
        if ($diff.TotalMinutes -lt 1) { return "now" }
        if ($diff.TotalMinutes -lt 60) { return "$([math]::Floor($diff.TotalMinutes))m" }
        if ($diff.TotalHours -lt 24) { return "$([math]::Floor($diff.TotalHours))h" }
        if ($diff.TotalDays -lt 2) { return "1d" }
        return "$([math]::Floor($diff.TotalDays))d"
    } catch { return "" }
}

# -Project resolves under $projectsDir (default list); -Path takes an arbitrary
# directory (browse mode, which walks nested folders outside the flat project list).
function Get-ProjectInfo {
    param([string]$Project, [string]$Path)
    $dir = if ($Path) { $Path } else { Join-Path $projectsDir $Project }
    $branch = $null
    try { $branch = & git -C $dir branch --show-current 2>$null } catch {}

    $modified = (Get-Item $dir -ErrorAction SilentlyContinue).LastWriteTime
    if ($modified) {
        $ago = [datetime]::Now - $modified
        $timeStr = if ($ago.TotalMinutes -lt 60) { "$([math]::Floor($ago.TotalMinutes))m" }
                   elseif ($ago.TotalHours -lt 24) { "$([math]::Floor($ago.TotalHours))h" }
                   else { "$([math]::Floor($ago.TotalDays))d" }
    } else { $timeStr = "" }

    $parts = @()
    if ($branch) { $parts += $branch }
    if ($timeStr) { $parts += $timeStr }
    return $parts -join " "
}

# Canonical form of a directory path for identity comparison: absolute, no trailing
# separator. NEVER throws and never touches the filesystem (the path need not exist);
# an unusable value degrades to the trimmed input, which simply won't match anything.
function Get-CanonicalDir {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }
    try {
        return ([System.IO.Path]::GetFullPath($PathValue)).TrimEnd('\', '/')
    } catch {
        return $PathValue.Trim().TrimEnd('\', '/')
    }
}

# True when $dir IS the framework source repo ($frameworkRepo). Case-insensitive,
# trailing-slash and separator tolerant, non-existent paths safe.
function Test-IsFrameworkSource {
    param([string]$Dir)
    $a = Get-CanonicalDir $Dir
    $b = Get-CanonicalDir $frameworkRepo
    if (-not $a -or -not $b) { return $false }
    return ($a -eq $b)      # PowerShell string -eq is case-insensitive
}

# Per-project status badges shown in the menu row:
#   framework-version: [v SRC] = this dir IS the framework source repo ($frameworkRepo).
#                      It never carries .ai/.framework-version — that marker is written
#                      BY the installer INTO target projects — so the version badges do
#                      not apply to it. Its own version is
#                      tools/multi-cli-install/package.json .version. Badging it [! OLD]
#                      (pre-fix behavior) claimed the framework was stale against itself.
#                      [v OK] = .ai/.framework-version present (current install)
#                      [! OLD] = .ai/ exists but no version marker (pre-marker install)
#                      [- none] = no .ai/ (framework not installed)
#   handoff queue:     [H:<n>] = n open cross-CLI handoffs (.ai/handoffs/to-*/open/*.md),
#                      hidden when n = 0. B6: when one or more recipients have open
#                      handoffs but their CLI is NOT available on this host (nobody
#                      will poll/execute them), the badge appends a stranded marker:
#                      [H:3 stranded:kimi,opencode]. This surfaces work that would
#                      otherwise sit silently with no consumer.
#                      B7 (pane liveness): a recipient WITH open handoffs whose
#                      heartbeat sidecar (.ai/.heartbeat-<cli>.json) is missing or
#                      older than the 15-minute pane staleness window (mirrors
#                      pane-runner.ps1 ProjectClaimStaleMinutes / fleet-health.sh)
#                      has a queue nobody is watching -> [H:2 stall:opencode],
#                      the badge twin of fleet-health.sh's STALL verdict.
# Cheap on purpose: two Test-Path calls + one shallow glob per project, plus —
# only when [H:n] is already non-zero — one Test-Path + one Get-Item per
# recipient WITH handoffs (mtime tracks the heartbeat ts: the file is
# atomically rewritten each poll cycle, so no JSON parse, no pid probe). Any
# error in a broken project dir yields an empty/partial badge, never a crash.
# -Project resolves under $projectsDir (default list); -Path takes an arbitrary
# directory (browse mode). Both paths produce identical badges.
function Get-ProjectBadges {
    param([string]$Project, [string]$Path)
    $badges = @()
    try {
        $dir = if ($Path) { $Path } else { Join-Path $projectsDir $Project }
        $aiDir = Join-Path $dir ".ai"
        # The framework SOURCE repo is not an install target: badge it as the source.
        # The [H:n] handoff badge below still applies to it, unchanged.
        if (Test-IsFrameworkSource $dir) { $badges += "[v SRC]" }
        elseif (Test-Path (Join-Path $aiDir ".framework-version")) { $badges += "[v OK]" }
        elseif (Test-Path $aiDir) { $badges += "[! OLD]" }
        else { $badges += "[- none]" }

        # B6: count open handoffs PER recipient and flag "consumer-less" ones -- a
        # recipient with >=1 open handoff whose CLI is NOT available on this host
        # (not in $cliAvailable), so no pane-runner/dispatcher will ever poll it.
        # Map the to-<name> dir to the proper-case $cliAvailable key via the
        # shared $cliKey (derived from fleet-clis.ps1 $FleetCliProper at load).
        $handoffCount = 0
        $stranded = @()
        $stalled = @()
        $handoffRoot = Join-Path $aiDir "handoffs"
        if (Test-Path $handoffRoot) {
            Get-ChildItem -Path $handoffRoot -Directory -Filter "to-*" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $openDir = Join-Path $_.FullName "open"
                    $n = @(Get-ChildItem -Path $openDir -Filter "*.md" -File -ErrorAction SilentlyContinue).Count
                    if ($n -gt 0) {
                        $handoffCount += $n
                        $suffix = ($_.Name -replace '^to-', '').ToLower()
                        $key = $cliKey[$suffix]
                        if ($key -and $cliAvailable -and -not $cliAvailable[$key]) { $stranded += $suffix }
                        # B7: pane-liveness twin of fleet-health.sh STALL — open handoffs
                        # but no fresh heartbeat = a queue nobody is watching. mtime
                        # tracks the heartbeat ts (atomic rewrite each poll cycle).
                        $hbPath = Join-Path $aiDir ".heartbeat-$suffix.json"
                        $hbFresh = (Test-Path $hbPath) -and `
                            ((Get-Item $hbPath -ErrorAction SilentlyContinue).LastWriteTimeUtc -ge (Get-Date).ToUniversalTime().AddMinutes(-15))
                        if (-not $hbFresh) { $stalled += $suffix }
                    }
                }
        }
        if ($handoffCount -gt 0) {
            $hBadge = "[H:$handoffCount"
            if ($stranded.Count -gt 0) { $hBadge += " stranded:$(($stranded | Sort-Object -Unique) -join ',')" }
            if ($stalled.Count -gt 0)  { $hBadge += " stall:$(($stalled | Sort-Object -Unique) -join ',')" }
            $hBadge += "]"
            $badges += $hBadge
        }
    } catch {}
    return $badges -join " "
}

# One-line badge legend, shown in BOTH the default list and browse mode so the
# glyphs are never cryptic. Kept at <= 70 chars to fit the narrowest box (the box
# truncates, so an overflowing legend loses its tail). Adding [v SRC] cost the
# "stranded:no CLI" tail -- the stranded badge spells its own recipients out
# ([H:3 stranded:kimi]), so it is the most self-describing thing here. B7's
# "stall:<cli>" follows the same self-describing pattern and likewise stays out
# of the legend budget.
$badgeLegend = " [v OK]=ok [v SRC]=fw src [! OLD]=stale [- none]=none [H:n]=handoffs"

# History label for a target dir: the folder name, or its path relative to
# $projectsDir when it lives under it, so nested browse picks stay distinguishable.
function Get-HistoryName($dir) {
    $name = Split-Path $dir -Leaf
    if ($dir.StartsWith($projectsDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $dir.Substring($projectsDir.Length).TrimStart('\', '/')
        if ($rel) { $name = $rel }
    }
    return $name
}

# Browse-mode row metadata = the SAME badges + git/mtime column the default list
# shows, for an arbitrary directory. Cached per path: the browser redraws on every
# keypress and Get-ProjectInfo shells out to git, so recomputing every row on every
# redraw would stall navigation. Only VISIBLE rows are ever computed, so a folder
# with hundreds of children stays cheap. Never throws (a broken dir yields blanks).
$script:browseMeta = @{}
function Get-BrowseMeta($path) {
    if ($script:browseMeta.ContainsKey($path)) { return $script:browseMeta[$path] }
    $meta = @{ badges = ''; info = '' }
    try {
        $meta.badges = Get-ProjectBadges -Path $path
        $meta.info = Get-ProjectInfo -Path $path
    } catch {}
    $script:browseMeta[$path] = $meta
    return $meta
}

# Resolve GIT Bash specifically — never WSL bash, never the Store alias.
#
# The old body trusted `Get-Command bash` FIRST. From the launcher's plain
# Windows context (vbs -> powershell), the persisted PATH has C:\WINDOWS\system32
# ahead of Git, and Git ships only ...\Git\cmd (git.exe, no bash.exe) — so that
# resolved to the WSL launcher C:\Windows\System32\bash.exe. WSL bash re-parses
# its args as a shell string and eats the backslashes of a Windows path
# (C:\Users\... -> C:Users...), so every bash call died with exit 127. Git Bash
# runs the same backslash path fine: pin Git Bash, reject WSL — do NOT convert paths.
#
# Same defect and same fix as Resolve-GitBash in pane-runner.ps1; kept
# self-contained because test-selector-e2e.ps1 lifts this function by AST name.
function Find-Bash {
    $windir = if ($env:WINDIR) { $env:WINDIR } else { 'C:\Windows' }
    $sys32 = [System.IO.Path]::Combine($windir, 'System32')
    $isDisallowed = {
        param([string]$p)
        if ([string]::IsNullOrWhiteSpace($p)) { return $true }
        $n = $p -replace '/', '\'
        if ($n.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        return ($n -match '(?i)WindowsApps')
    }

    # 1. Well-known Git for Windows locations, BEFORE anything on PATH.
    foreach ($p in @(
        "C:\Program Files\Git\bin\bash.exe"
        "C:\Program Files\Git\usr\bin\bash.exe"
        "C:\Program Files (x86)\Git\bin\bash.exe"
    )) {
        if ((& $isDisallowed $p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    # 2. Derive from git.exe: ...\Git\cmd\git.exe -> ...\Git\{bin,usr\bin}\bash.exe
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitHome = Split-Path -Parent (Split-Path -Parent $git.Source)
        foreach ($rel in @('bin\bash.exe', 'usr\bin\bash.exe')) {
            $c = Join-Path $gitHome $rel
            if ((& $isDisallowed $c)) { continue }
            if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
        }
    }
    # 3. Last resort: PATH — but ONLY if it is not WSL/Store.
    $onPath = Get-Command bash -ErrorAction SilentlyContinue
    if ($onPath -and -not (& $isDisallowed $onPath.Source)) { return $onPath.Source }

    return $null
}

# Warn-only framework drift check. Compares the project's recorded framework
# version (.ai/.framework-version) against the template SSOT
# (tools/multi-cli-install/package.json). Emits a yellow WARNING with the adopt
# command only when the project trails the template. NEVER throws, NEVER mutates:
# any read/parse failure stays silent so a broken marker cannot break launch.
function Test-FrameworkDrift {
    param($ProjVersionFile, $TemplatePkgJson, $AdoptCmd)
    try {
        $projVer = ([version](Get-Content $ProjVersionFile -Raw |
            ConvertFrom-Json).framework_version)
        $tmplVer = ([version](Get-Content $TemplatePkgJson -Raw |
            ConvertFrom-Json).version)
    } catch { return }                      # unparseable / missing => silent
    if ($null -eq $projVer -or $null -eq $tmplVer) { return }
    if ($projVer -lt $tmplVer) {
        Write-Host "Framework drift: project is v$projVer, template is v$tmplVer." `
            -ForegroundColor Yellow
        Write-Host "  To adopt updates: $AdoptCmd" -ForegroundColor Yellow
        Write-Host "  (lands on an isolated 'ai-template-install' branch to review before merging)" `
            -ForegroundColor Yellow
    }
    # projVer >= tmplVer, or equal, or any error => no output.
}

function Install-Framework($targetDir) {
    if ([string]::IsNullOrWhiteSpace($targetDir)) { return }

    $logFile = Join-Path $scriptDir "install-framework.log"
    function Write-InstallLog($msg) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] $msg" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
    Write-InstallLog "=== Install-Framework start ==="
    Write-InstallLog "targetDir: $targetDir"

    $fwMarker = Join-Path $targetDir ".ai\.framework-version"
    Write-InstallLog "framework marker exists: $(Test-Path $fwMarker)"
    if (Test-Path $fwMarker) {
        # Warn-only drift check: resolve the template source the same way the
        # install path does, compare recorded version vs template SSOT, print an
        # advisory adopt command if the project trails. Never auto-updates.
        $src = if ((Test-Path $frameworkRepo) -and (Test-Path (Join-Path $frameworkRepo '.ai'))) {
            $frameworkRepo
        } elseif (Test-Path (Join-Path $scriptDir '.ai')) { $scriptDir } else { $null }

        if ($src) {
            $adopt = "bash $src/scripts/install-template.sh $targetDir"
            Test-FrameworkDrift `
                -ProjVersionFile $fwMarker `
                -TemplatePkgJson (Join-Path $src 'tools/multi-cli-install/package.json') `
                -AdoptCmd $adopt
        }
        Write-InstallLog "Framework marker exists; ran drift check (warn-only), skipping install"
        return
    }

    # Determine the framework template source. Prefer the configured repo,
    # but fall back to the launcher directory if the repo is missing or empty,
    # so the script can still self-inject even when the external repo path
    # is unavailable.
    $fwSource = $null
    if ((Test-Path $frameworkRepo) -and (Test-Path (Join-Path $frameworkRepo '.ai'))) {
        $fwSource = $frameworkRepo
    } elseif (Test-Path (Join-Path $scriptDir '.ai')) {
        $fwSource = $scriptDir
        Write-InstallLog "frameworkRepo unavailable or incomplete; using scriptDir as template source"
    }
    Write-InstallLog "fwSource: $fwSource"

    if (-not $fwSource) {
        Write-Host "Framework template source not found; skipping framework install" -ForegroundColor Yellow
        Write-InstallLog "Skipped: no framework template source"
        return
    }

    $bashExe = Find-Bash
    Write-InstallLog "bashExe: $bashExe"
    if (-not $bashExe) {
        Write-Host "Git Bash not found; will try direct template copy fallback" -ForegroundColor Yellow
        Write-InstallLog "Git Bash not found; proceeding to fallback copy"
    }

    $hadCommits = $false
    $gitExists = Test-Path (Join-Path $targetDir ".git")
    Write-InstallLog ".git exists: $gitExists"
    if ($gitExists) {
        & git -C $targetDir rev-parse HEAD 2>$null | Out-Null
        $hadCommits = ($LASTEXITCODE -eq 0)
        Write-InstallLog "rev-parse HEAD exit: $LASTEXITCODE, hadCommits: $hadCommits"
    } else {
        Write-InstallLog "Running git init"
        & git -C $targetDir init | Out-Null
        Write-InstallLog "git init exit: $LASTEXITCODE"
    }
    if (-not $hadCommits) {
        # Newly-initialized repos often lack user identity; set a local one so
        # the initial commit and the installer's commit both succeed.
        & git -C $targetDir config user.email "ai-framework@local" 2>$null | Out-Null
        & git -C $targetDir config user.name "AI Framework Installer" 2>$null | Out-Null
        & git -C $targetDir add -A 2>$null | Out-Null
        Write-InstallLog "git add exit: $LASTEXITCODE"
        & git -C $targetDir commit --allow-empty -m "init" 2>$null | Out-Null
        Write-InstallLog "git commit exit: $LASTEXITCODE"
    } else {
        $dirty = & git -C $targetDir status --porcelain 2>$null
        Write-InstallLog "git status porcelein length: $($dirty.Length)"
        if ($dirty) {
            Write-Host "Project has uncommitted changes; skipping framework install to avoid sweeping them into the install commit. Commit/stash and re-open to adopt." -ForegroundColor Yellow
            Write-InstallLog "Skipped: dirty working tree"
            return
        }
    }

    $bashTarget = $targetDir -replace '\\', '/'
    $installer = "$fwSource/scripts/install-template.sh"
    $name = Split-Path $targetDir -Leaf
    Write-InstallLog "installer: $installer"
    Write-InstallLog "bashTarget: $bashTarget"
    if ($bashExe) {
        try {
            $output = & $bashExe $installer $bashTarget 2>&1
            Write-InstallLog "installer exit code: $LASTEXITCODE"
            Write-InstallLog "installer output length: $($output.Length)"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Framework installed into $name" -ForegroundColor Green
                Write-InstallLog "Success"
            } else {
                Write-Host "Framework install failed (continuing to launch):" -ForegroundColor Yellow
                Write-Host ($output | Out-String) -ForegroundColor Yellow
                Write-InstallLog "FAILED"
                Write-InstallLog ($output | Out-String)
            }
        } catch {
            Write-Host "Framework install errored (continuing to launch): $_" -ForegroundColor Yellow
            Write-InstallLog "ERROR: $_"
        }
    }
    $templateItems = @(
        '.ai',
        '.claude',
        '.kimi',
        '.kiro',
        '.archive',
        'CLAUDE.md',
        'AGENTS.md',
        '.opencode',
        'opencode.json',
        '.mcp.json.example',
        'docs/architecture/0001-root-file-exceptions.md',
        'docs/architecture/0002-cli-role-topology.md',
        'docs/architecture/0003-code-graph-rationalization.md',
        '.github/workflows/framework-check.yml',
        '.github/workflows/gates.yml',
        '.codegraph/config.json'
    )
    $missingItems = @($templateItems | Where-Object { -not (Test-Path (Join-Path $targetDir $_)) })
    Write-InstallLog "post-install missing items: $($missingItems -join ', ')"

    # Fallback: if the installer didn't create all required items (failed early,
    # missing git, verification failed before copy, etc.), copy the core template
    # files ourselves so the selected folder is never left incomplete.
    if ($missingItems.Count -gt 0) {
        Write-Host "Framework install incomplete; injecting missing template files directly..." -ForegroundColor Yellow
        Write-InstallLog "Fallback: copying core framework template files"
        foreach ($item in $templateItems) {
            $src = Join-Path $fwSource $item
            $dst = Join-Path $targetDir $item
            if (-not (Test-Path $src)) {
                Write-InstallLog "Fallback skip (source missing): $item"
                continue
            }
            try {
                if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
                if (Test-Path $src -PathType Container) {
                    Copy-Item -Path $src -Destination $dst -Recurse -Force
                } else {
                    $parent = Split-Path -Parent $dst
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -Path $src -Destination $dst -Force
                }
                Write-InstallLog "Fallback copied: $item"
            } catch {
                Write-InstallLog "Fallback failed to copy ${item}: $_"
            }
        }

        # Reset the activity log to the clean template header so it doesn't
        # contain the template repo's history.
        $activityLog = Join-Path $targetDir '.ai\activity\log.md'
        if (Test-Path $activityLog) {
            $cleanHeader = @(
                '# Activity Log',
                '',
                'Newest entries at the top. Each CLI prepends an entry after completing substantive work.',
                '',
                '**Timestamp rule:** the `HH:MM` in each entry heading is local wall-clock time at the',
                'moment of prepending (i.e. when the work finished, not when it started). CLIs on',
                'different local clocks may produce timestamps that don''t sort monotonically;',
                '**prepend order is the authoritative sequencing**, timestamps are annotations.',
                '',
                '**Archive:** older entries live in `.ai/activity/archive/YYYY-MM.md` (one file per',
                'calendar month). See `.ai/activity/archive/README.md` for the rollover protocol.',
                '',
                '---',
                ''
            ) -join "`r`n"
            $cleanHeader | Set-Content -Path $activityLog -Encoding utf8 -NoNewline
            Write-InstallLog "Fallback reset activity log"
        }

        # Stamp a minimal framework version marker. Resolve the version from the
        # framework repo's installer package.json at runtime; fall back to the
        # last-known literal only if it is unreadable.
        try {
            $fwVersion = '0.0.5'
            try {
                $pkgPath = Join-Path $frameworkRepo 'tools/multi-cli-install/package.json'
                $pkgVersion = (Get-Content $pkgPath -Raw -ErrorAction Stop | ConvertFrom-Json).version
                if ($pkgVersion) { $fwVersion = $pkgVersion }
            } catch {
                Write-InstallLog "Fallback could not read installer package.json; using literal $fwVersion"
            }
            $markerDir = Join-Path $targetDir '.ai'
            if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
            $markerPath = Join-Path $markerDir '.framework-version'
            $markerJson = @{
                framework_version = $fwVersion
                installer_name = 'Selector.ps1 fallback'
                installer_version = $fwVersion
                installed_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                upgrade_history = @()
            } | ConvertTo-Json -Depth 3
            $markerJson | Set-Content -Path $markerPath -Encoding utf8
            Write-InstallLog "Fallback wrote .ai/.framework-version"
        } catch {
            Write-InstallLog "Fallback failed to write marker: $_"
        }

        Write-Host "Framework files injected into $name" -ForegroundColor Green
    }

    Write-InstallLog "=== Install-Framework end ==="
}

# ── Framework install/update shortcut (owner request 2026-07-14) ──
# Opens a NEW WT tab that runs the bash installer against the target directory.
# No CLI is launched — this is pure framework onboarding/adoption. Works for both
# fresh installs and updates (install-template.sh detects the .ai/.framework-version
# marker and enters UPDATE_MODE).
function Install-Framework-In-NewTab($targetDir) {
    if ([string]::IsNullOrWhiteSpace($targetDir)) {
        Write-Host "No directory selected; cannot install framework." -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        Write-Host "Directory does not exist: $targetDir" -ForegroundColor Red
        return
    }

    # Resolve template source the same way Install-Framework does.
    $fwSource = $null
    if ((Test-Path $frameworkRepo) -and (Test-Path (Join-Path $frameworkRepo '.ai'))) {
        $fwSource = $frameworkRepo
    } elseif (Test-Path (Join-Path $scriptDir '.ai')) {
        $fwSource = $scriptDir
    }
    if (-not $fwSource) {
        Write-Host "Framework template source not found; cannot install." -ForegroundColor Red
        return
    }

    $bashExe = Find-Bash
    if (-not $bashExe) {
        Write-Host "Git Bash not found; cannot run framework installer." -ForegroundColor Red
        return
    }

    $installer = "$fwSource/scripts/install-template.sh"
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        Write-Host "Installer not found: $installer" -ForegroundColor Red
        return
    }

    $bashTarget = $targetDir -replace '\\', '/'
    $leaf = Split-Path $targetDir -Leaf
    $tabTitle = "Install $leaf"

    # Windows Terminal uses ';' as a subcommand separator, so we cannot embed the
    # PowerShell command directly (its statement separators would split the WT
    # invocation). Write a temp .ps1 script and have the new tab run that instead.
    $tmpScript = Join-Path $env:TEMP ("rwn-framework-install-{0}-{1}.ps1" -f $leaf, [Guid]::NewGuid().ToString('N').Substring(0,8))
    $scriptBody = @(
        "& `"$bashExe`" `"$installer`" `"$bashTarget`"",
        "Write-Host ''",
        "Write-Host 'Install finished. Run the merge command above to adopt the framework.' -ForegroundColor Green",
        "Write-Host 'Press Enter to close this tab.' -ForegroundColor DarkGray",
        "[void][Console]::ReadLine()"
    ) -join "`r`n"
    try {
        [IO.File]::WriteAllText($tmpScript, $scriptBody)
    } catch {
        Write-Host "Failed to write install script: $_" -ForegroundColor Red
        return
    }

    $wtCmd = "-w rwn4ai new-tab --title `"$tabTitle`" -d `"$targetDir`" powershell -NoExit -NoProfile -File `"$tmpScript`""

    Write-Host "Opening install tab for $leaf..." -ForegroundColor Cyan
    try {
        & cmd.exe /c "`"$wtExe`" $wtCmd"
    } catch {
        Write-Host "Failed to open install tab: $_" -ForegroundColor Red
    }
}

# -- Fleet-tab STAGE builder (shared by single-select and multi-select batch) --
# Returns ONE project's fleet tab as an ORDERED [string[]] of Windows-Terminal
# subcommand STAGES: stage 0 is always `new-tab ...`, the rest are `split-pane ...`
# / `move-focus ...`. No -w prefix and no ' ; ' glue -- the caller decides whether to
# fire each stage as its own `wt -w rwn4ai <stage>` call (paced, the default) or to
# join them with ' ; ' into one atomic call (the delay=0 escape hatch). Both forms
# produce the SAME layout: every stage after new-tab acts on the active pane of the
# active tab in the rwn4ai window, which is exactly the pane the chained form acts on.
#
# Structured array rather than string-splitting the old chained string on ' ; ':
# the stages embed quoted CLI payloads and paths, and a payload that ever contained
# a literal ' ; ' would silently corrupt a split. Building the boundaries where they
# are KNOWN removes the ambiguity entirely.
#
# Layout is chosen the same way the single-launch path chooses it:
#   6pane (default) = top-LEFT app-Claude + top-RIGHT Kimi over N pane-runner workers
#   5pane           = full-width app-Claude over N pane-runner workers
#   otherwise (4grid/bare/nodir-scripts-missing) = plain interactive REPLs per CLI
# Reads script-scope state ($activeCLIs, $cliDefs, $cliLower, $cliAvailable,
# $paneLayoutMode, $topStripFraction, $scriptDir) resolved at call time, so callers
# must set $activeCLIs before invoking.
function Build-FleetTabStages {
    param([Parameter(Mandatory = $true)][string]$TargetDir)

    $dq = '"'
    $leaf = Split-Path -Leaf $TargetDir             # project name -> WT tab --title
    $bottomCLIs = $activeCLIs                       # available CLIs, layout order
    $n = $bottomCLIs.Count
    $stages = New-Object System.Collections.Generic.List[string]

    $paneRunner = Join-Path $scriptDir 'pane-runner.ps1'
    $paneSupervisor = Join-Path $scriptDir 'run-pane-supervised.ps1'
    $bareMode = ($env:RWN_PANE_BARE -and $env:RWN_PANE_BARE -ne '0' -and $env:RWN_PANE_BARE -ne 'false')
    $composite = $cliAvailable['Claude'] -and (Test-Path $paneRunner) `
                 -and (Test-Path $paneSupervisor) -and (-not $bareMode) `
                 -and ($paneLayoutMode -eq '6pane' -or $paneLayoutMode -eq '5pane')

    if (-not $composite) {
        # Fallback tab: each available CLI as a plain interactive REPL (mirrors the
        # legacy 4-grid/bare intent, but as its own new-tab so a batch still works).
        $stages.Add("new-tab --title $dq$leaf$dq -d $dq$TargetDir$dq powershell -NoExit -NoProfile -Command $dq$($cliDefs[$bottomCLIs[0]].cmd)$dq")
        for ($i = 1; $i -lt $n; $i++) {
            $frac = [math]::Round(($n - $i) / ($n - $i + 1), 4)
            $stages.Add("split-pane -V -s $frac -d $dq$TargetDir$dq powershell -NoExit -NoProfile -Command $dq$($cliDefs[$bottomCLIs[$i]].cmd)$dq")
        }
        return $stages.ToArray()
    }

    # Composite 6pane/5pane fleet tab (identical to the single-launch build).
    # TOP pane: bare interactive Claude (app-Claude). No pane-runner, no -Owner.
    $topCmd = "powershell -NoExit -NoProfile -Command $dq$($cliDefs['Claude'].cmd)$dq"
    $stages.Add("new-tab --title $dq$leaf$dq -d $dq$TargetDir$dq $topCmd")

    # BOTTOM pane 1: split-pane -H, new (bottom) pane takes (1 - topStripFraction).
    # Launch the SUPERVISOR (keeps -NoExit) so a crashed runner auto-respawns.
    $bottomFraction = [math]::Round(1 - $topStripFraction, 4)
    $runner0 = "powershell -NoExit -NoProfile -File $dq$paneSupervisor$dq -Cli $($cliLower[$bottomCLIs[0]]) -ProjectDir $dq$TargetDir$dq"
    $stages.Add("split-pane -H -s $bottomFraction -d $dq$TargetDir$dq $runner0")

    # BOTTOM panes 2..N: vertical splits sized for N equal columns.
    for ($i = 1; $i -lt $n; $i++) {
        $frac = [math]::Round(($n - $i) / ($n - $i + 1), 4)
        $runner = "powershell -NoExit -NoProfile -File $dq$paneSupervisor$dq -Cli $($cliLower[$bottomCLIs[$i]]) -ProjectDir $dq$TargetDir$dq"
        $stages.Add("split-pane -V -s $frac -d $dq$TargetDir$dq $runner")
    }

    # 6pane adds the top-RIGHT Kimi cockpit; 5pane keeps a single full-width top.
    # move-focus is its own stage: it is its own wt subcommand in the chained form too.
    if ($paneLayoutMode -ne '5pane' -and $cliAvailable['Kimi']) {
        $topRightCmd = "powershell -NoExit -NoProfile -Command $dq$($cliDefs['Kimi'].cmd)$dq"
        $stages.Add("move-focus up")
        $stages.Add("split-pane -V -s 0.5 -d $dq$TargetDir$dq $topRightCmd")
    }
    return $stages.ToArray()
}

# -- Launch PLAN: the ordered wt invocations for a set of project tabs --
# PURE (no side effects, no WT): takes one string[] of stages per project and the two
# pacing knobs, returns the ordered list of invocations to fire, each carrying the
# delay to observe AFTER it:
#     [pscustomobject]@{ Wt = '-w rwn4ai <subcommands>'; DelayAfterMs = <int> }
# Default (both delays > 0): one invocation per STAGE, pane delay between stages of a
# tab, tab delay between projects -> exactly one `new-tab` per project, paced.
# PaneDelayMs = 0: each project's tab collapses to one atomic chained invocation.
# TabDelayMs  = 0: the WHOLE batch collapses to one atomic chained invocation (full
#                  legacy behavior; a single invocation cannot be pane-staged).
# Being pure is what makes the pacing testable without launching Windows Terminal.
function Get-FleetLaunchPlan {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$TabStages,  # array of string[]
        [int]$PaneDelayMs = 250,
        [int]$TabDelayMs = 1200
    )
    $plan = New-Object System.Collections.Generic.List[object]
    if ($TabStages.Count -eq 0) { return @() }

    if ($TabDelayMs -le 0) {
        $joined = (@($TabStages | ForEach-Object { @($_) -join ' ; ' }) -join ' ; ')
        $plan.Add([pscustomobject]@{ Wt = "-w rwn4ai $joined"; DelayAfterMs = 0 })
        return $plan.ToArray()
    }

    for ($t = 0; $t -lt $TabStages.Count; $t++) {
        $stages = @($TabStages[$t])
        $isLastTab = ($t -eq $TabStages.Count - 1)
        if ($PaneDelayMs -le 0) {
            $after = if ($isLastTab) { 0 } else { $TabDelayMs }
            $plan.Add([pscustomobject]@{ Wt = "-w rwn4ai " + ($stages -join ' ; '); DelayAfterMs = $after })
            continue
        }
        for ($s = 0; $s -lt $stages.Count; $s++) {
            $isLastStage = ($s -eq $stages.Count - 1)
            $after = if (-not $isLastStage) { $PaneDelayMs }
                     elseif (-not $isLastTab) { $TabDelayMs }
                     else { 0 }
            $plan.Add([pscustomobject]@{ Wt = "-w rwn4ai $($stages[$s])"; DelayAfterMs = $after })
        }
    }
    return $plan.ToArray()
}

# Fire a plan at Windows Terminal. Every invocation targets the SAME rwn4ai window,
# so paced stages land in the tab/pane the atomic chain would have used. Returns
# $true when every invocation was issued without throwing.
function Invoke-FleetLaunchPlan {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Plan)
    $ok = $true
    foreach ($step in $Plan) {
        $wtCmd = $step.Wt
        if ($wtCmd.Length -gt $maxSafeCmdLen) {
            Write-Host "Warning: wt command is $($wtCmd.Length) chars (safe limit $maxSafeCmdLen); Windows may truncate it. Unset RWN_4AI_TAB_DELAY_MS/RWN_4AI_PANE_DELAY_MS=0 to use the paced (short) invocations." -ForegroundColor Yellow
        }
        Write-Host "  `"$wtExe`" $wtCmd" -ForegroundColor DarkGray
        try {
            & cmd.exe /c "`"$wtExe`" $wtCmd"
        } catch {
            $ok = $false
            Write-Host "Failed to launch: $_" -ForegroundColor Red
        }
        if ($step.DelayAfterMs -gt 0) { Start-Sleep -Milliseconds $step.DelayAfterMs }
    }
    return $ok
}

# ── Build Menu Items ──
$allProjects = Get-Projects
$history = Get-History

$ordered = [System.Collections.ArrayList]::new()
$seen = @{}
foreach ($h in $history) {
    if (($allProjects -contains $h.project) -and -not $seen.ContainsKey($h.project)) {
        [void]$ordered.Add($h.project)
        $seen[$h.project] = $true
    }
}
foreach ($p in $allProjects) {
    if (-not $seen.ContainsKey($p)) {
        [void]$ordered.Add($p)
        $seen[$p] = $true
    }
}

$menuItems = [System.Collections.ArrayList]::new()
foreach ($p in $ordered) {
    $info = Get-ProjectInfo -project $p
    $histEntry = $history | Where-Object { $_.project -eq $p } | Select-Object -First 1
    $ago = if ($histEntry) { Format-TimeAgo -timestamp $histEntry.timestamp } else { "" }
    $badges = Get-ProjectBadges -project $p
    [void]$menuItems.Add(@{ name = $p; info = $info; lastUsed = $ago; badges = $badges; type = 'project' })
}
[void]$menuItems.Add(@{ name = '[>] Browse folder...'; info = ''; lastUsed = ''; type = 'browse' })
[void]$menuItems.Add(@{ name = '[+] New project...'; info = ''; lastUsed = ''; type = 'new' })
[void]$menuItems.Add(@{ name = '[*] Open without directory'; info = ''; lastUsed = ''; type = 'nodir' })

# ── Interactive Menu ──
$script:selected = 0
$script:pageOffset = 0
$script:pageSize = [Math]::Max(3, [Console]::WindowHeight - 13)
# Multi-select (task #25): project name -> $true for each SPACE-marked project.
# ENTER with >=1 marked launches every marked project in its own WT tab (batch);
# ENTER with none marked keeps today's single-highlighted-project launch.
$script:marked = @{}
# Browse-mode multi-select: absolute paths SPACE-marked inside Show-FolderBrowser.
# Same contract as $script:marked, but ordered (launch order = mark order) and keyed
# by path because browse entries are nested dirs, not flat $projectsDir names.
$script:browseMarked = [System.Collections.ArrayList]::new()

function Draw-Menu {
    $conW = [Console]::WindowWidth
    $boxW = [Math]::Max(40, [Math]::Min(72, $conW - 2))
    $innerW = $boxW - 2

    if ($script:selected -lt $script:pageOffset) { $script:pageOffset = $script:selected }
    if ($script:selected -ge $script:pageOffset + $script:pageSize) {
        $script:pageOffset = $script:selected - $script:pageSize + 1
    }

    $visibleCount = [Math]::Min($script:pageSize, $menuItems.Count - $script:pageOffset)

    Clear-Host

    Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan
    $title = " rwn-4AI-panes"
    Write-Host ("|" + $title.PadRight($innerW) + "|") -ForegroundColor Cyan
    Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

    # CLI status
    $layout = Get-Layout
    $statusParts = @()
    foreach ($name in $layout) {
        $avail = if ($cliAvailable[$name]) { "Y" } else { "N" }
        $statusParts += "$name[$avail]"
    }
    $allOK = $true
    foreach ($name in $layout) {
        if (-not $cliAvailable[$name]) { $allOK = $false; break }
    }
    $statusColor = if ($allOK) { "Green" } else { "Yellow" }
    $status = " " + ($statusParts -join " ")
    Write-Host ("|" + $status.PadRight($innerW) + "|") -ForegroundColor $statusColor

    # Separator
    Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray

    # Items
    for ($i = 0; $i -lt $visibleCount; $i++) {
        $idx = $script:pageOffset + $i
        $item = $menuItems[$idx]
        $isSel = ($idx -eq $script:selected)

        if ($item.type -eq 'project') {
            $marker = if ($isSel) { " >" } else { "  " }
            $check = if ($script:marked.ContainsKey($item.name)) { "[x]" } else { "[ ]" }
            $num = "$($idx + 1)".PadLeft(2)
            $namePart = "$marker $check $num $($item.name)"
            if ($item.badges) { $namePart += " $($item.badges)" }

            $infoParts = @()
            if ($item.info) { $infoParts += $item.info }
            if ($item.lastUsed) { $infoParts += "$($item.lastUsed) ago" }
            $infoStr = $infoParts -join " | "

            $spaceForInfo = $innerW - $namePart.Length - 1
            if ($spaceForInfo -gt 8 -and $infoStr.Length -gt 0) {
                if ($infoStr.Length -gt $spaceForInfo) {
                    $infoStr = $infoStr.Substring(0, $spaceForInfo - 2) + ".."
                }
                $line = $namePart + " " + $infoStr.PadLeft($spaceForInfo - 1)
            } else {
                $line = $namePart
            }

            if ($line.Length -gt $innerW) { $line = $line.Substring(0, $innerW) }
            $color = if ($isSel) { "Yellow" } else { "White" }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        } else {
            $marker = if ($isSel) { " >" } else { "  " }
            $line = "$marker $($item.name)"
            $color = if ($isSel) { "Yellow" } else { "DarkCyan" }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        }
    }

    # Footer
    Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray
    $footer = if ($script:marked.Count -gt 0) {
        " Space:mark($($script:marked.Count))  Enter:launch marked  b:browse  o:order  q:quit"
    } else {
        " Up/Dn  Space:mark  Enter  b:browse  i:install  n:new  w:nodir  o:order  q:quit"
    }
    if ($footer.Length -gt $innerW) { $footer = $footer.Substring(0, $innerW) }
    Write-Host ("|" + $footer.PadRight($innerW) + "|") -ForegroundColor DarkGray
    $legend = $badgeLegend
    if ($legend.Length -gt $innerW) { $legend = $legend.Substring(0, $innerW) }
    Write-Host ("|" + $legend.PadRight($innerW) + "|") -ForegroundColor DarkGray
    Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

    if ($menuItems.Count -gt $script:pageSize) {
        $totalPages = [Math]::Ceiling($menuItems.Count / $script:pageSize)
        $currentPage = [Math]::Floor($script:pageOffset / $script:pageSize) + 1
        Write-Host " Page $currentPage/$totalPages ($($menuItems.Count) items)" -ForegroundColor DarkGray
    }
}

function Show-LayoutPicker {
    $layout = Get-Layout
    $available = @($layout | Where-Object { $cliAvailable[$_] })
    if ($available.Count -lt 2) {
        Write-Host "Need at least 2 CLIs to rearrange." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    $pickSel = 0
    $done = $false
    while (-not $done) {
        Clear-Host
        $conW = [Console]::WindowWidth
        $boxW = [Math]::Max(40, [Math]::Min(72, $conW - 2))
        $innerW = $boxW - 2

        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Magenta
        Write-Host ("|" + " Pane Order (Up/Down to reorder, Enter to confirm)".PadRight($innerW) + "|") -ForegroundColor Magenta
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Magenta

        for ($i = 0; $i -lt $available.Count; $i++) {
            $marker = if ($i -eq $pickSel) { ">" } else { " " }
            $paneNum = $i + 1
            $avail = if ($cliAvailable[$available[$i]]) { "" } else { " (not installed)" }
            $line = " $marker $paneNum. $($available[$i])$avail"
            $color = if ($i -eq $pickSel) { "Yellow" } else { "White" }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        }

        Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray
        $helpLine = " Up/Down:select  s/S:swap up/down  Enter:save  Esc:cancel"
        if ($helpLine.Length -gt $innerW) { $helpLine = $helpLine.Substring(0, $innerW) }
        Write-Host ("|" + $helpLine.PadRight($innerW) + "|") -ForegroundColor DarkGray
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Magenta

        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $pickSel = [Math]::Max(0, $pickSel - 1) }
            'DownArrow' { $pickSel = [Math]::Min($available.Count - 1, $pickSel + 1) }
            'Enter'     { $done = $true }
            'Escape'    { return }
            default {
                $ch = $key.KeyChar
                if ($ch -eq 's') {
                    if ($pickSel -lt $available.Count - 1) {
                        $tmp = $available[$pickSel]
                        $available[$pickSel] = $available[$pickSel + 1]
                        $available[$pickSel + 1] = $tmp
                        $pickSel++
                    }
                }
                elseif ($ch -eq 'S') {
                    if ($pickSel -gt 0) {
                        $tmp = $available[$pickSel]
                        $available[$pickSel] = $available[$pickSel - 1]
                        $available[$pickSel - 1] = $tmp
                        $pickSel--
                    }
                }
            }
        }
    }

    Save-Layout -layout $available
}

# ── Folder Browser ──
function Show-FolderBrowser {
    param([string]$Root = $projectsDir)

    $current = Resolve-Path $Root -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path
    if (-not $current -or -not (Test-Path $current -PathType Container)) {
        $current = $PSScriptRoot
    }

    function Get-BrowserItems($path) {
        $list = [System.Collections.ArrayList]::new()
        [void]$list.Add([PSCustomObject]@{ name = './'; path = $path; type = 'current' })

        $canGoUpLocal = ($path -ne $projectsDir) -and
            ($path.StartsWith($projectsDir, [System.StringComparison]::OrdinalIgnoreCase))
        if ($canGoUpLocal) {
            $parent = Split-Path -Parent $path
            [void]$list.Add([PSCustomObject]@{ name = '../'; path = $parent; type = 'parent' })
        }

        try {
            Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name |
                ForEach-Object {
                    [void]$list.Add([PSCustomObject]@{
                        name = $_.Name + '/'
                        path = $_.FullName
                        type = 'dir'
                    })
                }
        } catch {}

        return $list
    }

    function Get-FirstSubfolderIndex($list) {
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i].type -eq 'dir') { return $i }
        }
        return -1
    }

    $initialItems = Get-BrowserItems -path $current
    $initialFirstSub = Get-FirstSubfolderIndex -list $initialItems
    $sel = if ($initialFirstSub -ge 0) { $initialFirstSub } else { 0 }
    $pageOffset = 0
    $pageSize = [Math]::Max(3, [Console]::WindowHeight - 13)
    $done = $false
    $cancel = $false

    while (-not $done) {
        $items = Get-BrowserItems -path $current
        $canGoUp = ($current -ne $projectsDir) -and
            ($current.StartsWith($projectsDir, [System.StringComparison]::OrdinalIgnoreCase))

        if ($sel -lt 0) { $sel = 0 }
        if ($sel -ge $items.Count) { $sel = [Math]::Max(0, $items.Count - 1) }
        if ($sel -lt $pageOffset) { $pageOffset = $sel }
        if ($sel -ge $pageOffset + $pageSize) { $pageOffset = $sel - $pageSize + 1 }

        $visibleCount = [Math]::Min($pageSize, $items.Count - $pageOffset)

        $conW = [Console]::WindowWidth
        $boxW = [Math]::Max(40, [Math]::Min(72, $conW - 2))
        $innerW = $boxW - 2

        Clear-Host
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan
        Write-Host ("|" + " Browse Folder".PadRight($innerW) + "|") -ForegroundColor Cyan
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

        $pathLine = " " + $current
        if ($pathLine.Length -gt $innerW) { $pathLine = $pathLine.Substring(0, $innerW - 3) + "..." }
        Write-Host ("|" + $pathLine.PadRight($innerW) + "|") -ForegroundColor DarkGray
        Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray

        for ($i = 0; $i -lt $visibleCount; $i++) {
            $idx = $pageOffset + $i
            $item = $items[$idx]
            $isSel = ($idx -eq $sel)
            $marker = if ($isSel) { ">" } else { " " }
            if ($item.type -eq 'parent') {
                # '../' is navigation, not a launchable target: no checkbox, no badges.
                $line = " $marker $($item.name)"
            } else {
                # Same row shape as the default project list: mark, name, badges, then
                # the right-aligned git/mtime column.
                $check = if ($script:browseMarked -contains $item.path) { "[x]" } else { "[ ]" }
                $meta = Get-BrowseMeta $item.path
                $namePart = " $marker $check $($item.name)"
                if ($meta.badges) { $namePart += " $($meta.badges)" }
                $infoStr = [string]$meta.info
                $spaceForInfo = $innerW - $namePart.Length - 1
                if ($spaceForInfo -gt 8 -and $infoStr.Length -gt 0) {
                    if ($infoStr.Length -gt $spaceForInfo) {
                        $infoStr = $infoStr.Substring(0, $spaceForInfo - 2) + ".."
                    }
                    $line = $namePart + " " + $infoStr.PadLeft($spaceForInfo - 1)
                } else {
                    $line = $namePart
                }
            }
            if ($line.Length -gt $innerW) { $line = $line.Substring(0, $innerW) }
            $color = if ($isSel) { "Yellow" } else { "White" }
            if ($item.type -eq 'parent') { $color = if ($isSel) { "Yellow" } else { "DarkGray" } }
            elseif ($item.type -eq 'current') { $color = if ($isSel) { "Yellow" } else { "Green" } }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        }

        for ($i = $visibleCount; $i -lt $pageSize; $i++) {
            Write-Host ("|" + (" " * $innerW) + "|") -ForegroundColor DarkGray
        }

        Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray
        $help = if ($script:browseMarked.Count -gt 0) {
            " Space:mark($($script:browseMarked.Count))  Enter:launch marked  Left:up  Esc:cancel"
        } else {
            " Up/Dn  Space:mark  Enter/Right:open  Left:up  i:install  c:select  Esc:cancel"
        }
        if ($help.Length -gt $innerW) { $help = $help.Substring(0, $innerW) }
        Write-Host ("|" + $help.PadRight($innerW) + "|") -ForegroundColor DarkGray
        $legend = $badgeLegend
        if ($legend.Length -gt $innerW) { $legend = $legend.Substring(0, $innerW) }
        Write-Host ("|" + $legend.PadRight($innerW) + "|") -ForegroundColor DarkGray
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'    { $sel = [Math]::Max(0, $sel - 1) }
            'DownArrow'  { $sel = [Math]::Min([Math]::Max(0, $items.Count - 1), $sel + 1) }
            'Spacebar'   {
                # Toggle the highlighted entry's mark. '../' is navigation-only and
                # never markable; './' (the current dir) and real subfolders are.
                if ($items.Count -gt 0 -and $items[$sel].type -ne 'parent') {
                    $p = $items[$sel].path
                    if ($script:browseMarked -contains $p) { $script:browseMarked.Remove($p) }
                    else { [void]$script:browseMarked.Add($p) }
                }
            }
            'Enter'      {
                # >=1 marked -> hand the marks to the batch-launch path (one WT tab per
                # marked dir). Nothing marked -> today's open/navigate behavior, unchanged.
                if ($script:browseMarked.Count -ge 1) { return $null }
                if ($items.Count -gt 0) {
                    if ($items[$sel].type -eq 'current') {
                        return $items[$sel].path
                    }
                    $current = $items[$sel].path
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'RightArrow' {
                if ($items.Count -gt 0) {
                    if ($items[$sel].type -eq 'current') {
                        return $items[$sel].path
                    }
                    $current = $items[$sel].path
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'LeftArrow'  {
                if ($canGoUp) {
                    $current = Split-Path -Parent $current
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'Backspace'  {
                if ($canGoUp) {
                    $current = Split-Path -Parent $current
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'Escape'     { $script:browseMarked.Clear(); $done = $true; $cancel = $true }
            default {
                $ch = $key.KeyChar
                if ($ch -eq 'c') {
                    if ($items.Count -gt 0) {
                        return $items[$sel].path
                    }
                    return $current
                }
                elseif ($ch -eq 'i') {
                    if ($items.Count -gt 0) {
                        $installDir = if ($items[$sel].type -eq 'parent') { $current } else { $items[$sel].path }
                        Install-Framework-In-NewTab -targetDir $installDir
                    }
                }
                elseif ($ch -eq 'q') {
                    $script:browseMarked.Clear(); $done = $true; $cancel = $true
                }
            }
        }
    }

    if ($cancel) { return $null }
    return $current
}

$script:targetDirFromBrowse = $null

function Invoke-Browse {
    $path = Show-FolderBrowser -Root $projectsDir
    # Marked entries win: the batch-launch block below consumes $script:browseMarked
    # and never reads $script:selected, so the highlighted row is irrelevant here.
    if ($script:browseMarked.Count -ge 1) { return $true }
    if ($path) {
        $script:targetDirFromBrowse = $path
        for ($i = 0; $i -lt $menuItems.Count; $i++) {
            if ($menuItems[$i].type -eq 'browse') {
                $script:selected = $i
                break
            }
        }
        return $true
    }
    return $false
}

# ── Key Loop ──
$done = $false
while (-not $done) {
    Draw-Menu
    $key = [System.Console]::ReadKey($true)

    switch ($key.Key) {
        'UpArrow'   { $script:selected = [Math]::Max(0, $script:selected - 1) }
        'DownArrow' { $script:selected = [Math]::Min($menuItems.Count - 1, $script:selected + 1) }
        'Spacebar'  {
            # Toggle the highlighted PROJECT's mark. Non-project rows (browse/new/
            # nodir) are not markable. Remove-on-untoggle keeps .Count = marked total.
            $cur = $menuItems[$script:selected]
            if ($cur.type -eq 'project') {
                if ($script:marked.ContainsKey($cur.name)) { $script:marked.Remove($cur.name) }
                else { $script:marked[$cur.name] = $true }
            }
        }
        'Enter'     {
            if ($script:marked.Count -ge 1) {
                # >=1 marked -> batch launch handled after the loop (ignores highlight).
                $done = $true
            }
            elseif ($menuItems[$script:selected].type -eq 'browse') {
                if (Invoke-Browse) { $done = $true }
            } else {
                $done = $true
            }
        }
        'Escape'    { Stop-Process -Id $PID }
        'PageUp'    { $script:selected = [Math]::Max(0, $script:selected - $script:pageSize) }
        'PageDown'  { $script:selected = [Math]::Min($menuItems.Count - 1, $script:selected + $script:pageSize) }
        'Home'      { $script:selected = 0 }
        'End'       { $script:selected = $menuItems.Count - 1 }
        default {
            $ch = $key.KeyChar
            if ($ch -eq 'b') {
                if (Invoke-Browse) { $done = $true }
            }
            elseif ($ch -eq 'i') {
                $cur = $menuItems[$script:selected]
                if ($cur.type -eq 'project') {
                    Install-Framework-In-NewTab -targetDir (Join-Path $projectsDir $cur.name)
                }
                elseif ($cur.type -eq 'browse') {
                    if (Invoke-Browse) {
                        if ($script:targetDirFromBrowse) {
                            Install-Framework-In-NewTab -targetDir $script:targetDirFromBrowse
                        }
                    }
                }
            }
            elseif ($ch -eq 'n') {
                for ($i = 0; $i -lt $menuItems.Count; $i++) {
                    if ($menuItems[$i].type -eq 'new') { $script:selected = $i; break }
                }
                $done = $true
            }
            elseif ($ch -eq 'w') {
                for ($i = 0; $i -lt $menuItems.Count; $i++) {
                    if ($menuItems[$i].type -eq 'nodir') { $script:selected = $i; break }
                }
                $done = $true
            }
            elseif ($ch -eq 'o') { Show-LayoutPicker }
            elseif ($ch -eq 'q') { Stop-Process -Id $PID }
            elseif ($ch -match '[0-9]') {
                $num = [int]$ch.ToString()
                if ($num -ge 1 -and $num -le $menuItems.Count) {
                    $script:selected = $num - 1
                    $done = $true
                }
            }
        }
    }
}

# -- Multi-select batch launch (task #25) --
# If any projects are SPACE-marked, launch every marked project in its own WT tab
# inside the one rwn4ai window -- one PACED wt invocation per tab (see
# Get-FleetLaunchPlan), each tab running that project's full fleet via the shared
# Build-FleetTabStages. When nothing is marked this whole block is skipped and the
# single-select path below runs unchanged.
$script:markedList = @()
foreach ($mi in $menuItems) {
    if ($mi.type -eq 'project' -and $script:marked.ContainsKey($mi.name)) {
        $script:markedList += $mi.name
    }
}

# Browse-mode marks join the same batch: main-list marks are names under $projectsDir,
# browse marks are already absolute paths (possibly nested). Normalize both to dirs.
$batchDirs = @()
foreach ($p in $script:markedList) { $batchDirs += (Join-Path $projectsDir $p) }
foreach ($p in $script:browseMarked) {
    if ($batchDirs -notcontains $p) { $batchDirs += $p }
}

if ($batchDirs.Count -ge 1) {
    $layout = Get-Layout
    $activeCLIs = @($layout | Where-Object { $cliAvailable[$_] })
    if ($activeCLIs.Count -eq 0) {
        Write-Host "No CLIs available." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        Stop-Process -Id $PID
    }

    # Per-project prep: record history + install/adopt framework (same as single).
    $targetDirs = @()
    foreach ($d in $batchDirs) {
        Save-History -project (Get-HistoryName $d)
        Install-Framework -targetDir $d
        $targetDirs += $d
    }

    # Kiro global-agent injection (profile-level, project-independent -> do once).
    if ($cliAvailable["Kiro"]) {
        $globalKiroAgents = Join-Path $env:USERPROFILE ".kiro\agents"
        $backupAgents = Join-Path $scriptDir ".kiro\agents"
        if (Test-Path $backupAgents) {
            try {
                Get-ChildItem -Path $backupAgents -Filter "*.json" | ForEach-Object {
                    $dest = Join-Path $globalKiroAgents $_.Name
                    if (-not (Test-Path $dest)) { Copy-Item -Path $_.FullName -Destination $dest -Force }
                }
            } catch {
                Write-Host "Warning: failed to inject Kiro agents: $_" -ForegroundColor Yellow
            }
        }
    }

    if ($targetDirs.Count -gt 4) {
        Write-Host "Note: $($targetDirs.Count) projects marked; opening many fleet tabs at once is resource-heavy." -ForegroundColor Yellow
    }

    # One new-tab fleet group per marked project, as stage arrays.
    # PACING (owner defect 2026-07-11): the old code packed ALL projects' groups into
    # as few wt invocations as it could (split only by a char budget), so marking ~7
    # projects dumped dozens of splits on WT at once and the layout came out scrambled.
    # Now every project is its OWN wt invocation (one tab), fired sequentially with
    # $tabDelayMs between them, and each project's panes are staged with $paneDelayMs
    # between them. Delay = 0 restores the legacy atomic form for that dimension.
    $tabStages = @()
    foreach ($d in $targetDirs) { $tabStages += , (Build-FleetTabStages -TargetDir $d) }
    # @( ) forces an array: PowerShell unrolls a single-element result on return, and
    # the atomic escape hatch produces exactly one invocation.
    $plan = @(Get-FleetLaunchPlan -TabStages $tabStages -PaneDelayMs $paneDelayMs -TabDelayMs $tabDelayMs)

    Clear-Host
    $batchNames = @($targetDirs | ForEach-Object { Get-HistoryName $_ })
    Write-Host "Batch launch ($($targetDirs.Count) projects): $($batchNames -join ', ')" -ForegroundColor Cyan
    Write-Host "Pacing: pane ${paneDelayMs}ms, tab ${tabDelayMs}ms ($($plan.Count) wt invocations)." -ForegroundColor DarkGray
    $launchOk = Invoke-FleetLaunchPlan -Plan $plan
    if ($launchOk) {
        Write-Host "Launched $($targetDirs.Count) project tabs in window rwn4ai." -ForegroundColor Green
    }
    return
}

# ── Process Selection ──
$chosen = $menuItems[$script:selected]
$targetDir = $null

switch ($chosen.type) {
    'project' {
        $targetDir = Join-Path $projectsDir $chosen.name
        Save-History -project $chosen.name
    }
    'new' {
        Clear-Host
        Write-Host "+----------------------+" -ForegroundColor Cyan
        Write-Host "| Create New Project   |" -ForegroundColor Cyan
        Write-Host "+----------------------+" -ForegroundColor Cyan
        $name = Read-Host "Project name"
        if ([string]::IsNullOrWhiteSpace($name)) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            Stop-Process -Id $PID
        }
        $targetDir = Join-Path $projectsDir $name
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
            Write-Host "Created: $targetDir" -ForegroundColor Green
        }
        Save-History -project $name
        Start-Sleep -Milliseconds 500
    }
    'browse' {
        $targetDir = $script:targetDirFromBrowse
        if ($targetDir) {
            Save-History -project (Get-HistoryName $targetDir)
        }
    }
    'nodir' {
        $targetDir = $null
    }
}

# ── Install Framework ──
Install-Framework -targetDir $targetDir

# ── Split Panes ──
# The selector pane becomes the first CLI in the layout.
# We split off panes for the remaining CLIs.
# Layout math: starting from 100%, each split takes the right portion.
# Split 1: pane2 takes 75% of current -> pane1=25%, pane2=75%
# Split 2: pane3 takes 66.67% of pane2 -> pane2=25%, pane3=50%
# Split 3: pane4 takes 50% of pane3 -> pane3=25%, pane4=25%
# Result: 25% each for 4 panes.

Clear-Host
$layout = Get-Layout
$activeCLIs = @($layout | Where-Object { $cliAvailable[$_] })
$launching = $activeCLIs -join ', '
Write-Host "Launching $launching..." -ForegroundColor Cyan

if ($activeCLIs.Count -eq 0) {
    Write-Host "No CLIs available." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Stop-Process -Id $PID
}

# Kiro agent injection
if ($cliAvailable["Kiro"] -and $targetDir) {
    $globalKiroAgents = Join-Path $env:USERPROFILE ".kiro\agents"
    $backupAgents = Join-Path $scriptDir ".kiro\agents"
    if (Test-Path $backupAgents) {
        try {
            $didCopy = $false
            Get-ChildItem -Path $backupAgents -Filter "*.json" | ForEach-Object {
                $dest = Join-Path $globalKiroAgents $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item -Path $_.FullName -Destination $dest -Force
                    $didCopy = $true
                }
            }
            if ($didCopy) {
                Write-Host "Injected Kiro agents into global profile" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "Warning: failed to inject Kiro agents: $_" -ForegroundColor Yellow
        }
    }
}

# ── Pane launch: self-driving runner vs bare CLI (ADR-0008) ──
# Each pane normally launches pane-runner.ps1 (the self-driving supervisor loop
# that auto-continues + auto-executes handoffs for its CLI). Fall back to the
# bare interactive CLI when the owner wants a plain REPL: set env RWN_PANE_BARE=1,
# or when there is no project dir (nodir mode) — the runner needs a project's
# .ai/ to watch, so no-dir always uses the bare CLI.
# $cliLower (Proper -> lower) is derived from fleet-clis.ps1 near the top of this script.
$paneRunner = Join-Path $scriptDir 'pane-runner.ps1'
# Auto-resurrection supervisor: launched instead of pane-runner.ps1 so a crashed
# runner is respawned as an isolated child (exit-code contract, exp backoff, cap).
$paneSupervisor = Join-Path $scriptDir 'run-pane-supervised.ps1'
$bareMode = ($env:RWN_PANE_BARE -and $env:RWN_PANE_BARE -ne '0' -and $env:RWN_PANE_BARE -ne 'false')

# ── Layout gating ──
# 6pane/5pane both need a project dir (the runner watches its .ai/), an available
# Claude, the runner script, the supervisor script, and non-bare mode. Anything else
# (4grid, bare, nodir, unknown RWN_PANE_LAYOUT value, missing Claude/runner/supervisor)
# falls through to the legacy 4-grid path below — the instant, always-safe fallback,
# which itself supervises when the supervisor script is present.
$layoutSupported = $targetDir -and $cliAvailable['Claude'] `
                   -and (Test-Path $paneRunner) -and (Test-Path $paneSupervisor) -and (-not $bareMode)
$use6pane = ($paneLayoutMode -eq '6pane') -and $layoutSupported
$use5pane = ($paneLayoutMode -eq '5pane') -and $layoutSupported

# ── 6-pane dual-operator-over-fleet layout (ADR-0009 / owner-directed 2026-07-10) ──
# Build ONE composite WT tab as a 2-over-4 grid:
#   TOP row  (topStripFraction = 50% tall) = 2 side-by-side NON-polling interactive
#            cockpits: top-LEFT = app-Claude (identity claude-code), top-RIGHT = bare
#            Kimi. Neither runs the pane-runner (no auto-continue, no claim, no poll).
#            ROLE INTENT: top-LEFT Claude is the owner's app-paired / remote-control
#            session (session-sharing with the Claude app) -- NOT a fleet executor.
#            top-RIGHT Kimi is the owner's general operator for asides / ad-hoc
#            questions -- NOT an executor lane.
#   BOTTOM row (50% tall) = up to N equal columns, each running the self-driving
#            pane-runner worker (the Claude column self-IDs as claude-auto). Same
#            fleet behavior as the 5pane bottom.
#
# WT split sequence (each split acts on the FOCUSED pane; -s sizes the NEW pane):
#   1. new-tab               -> P0 : top pane, full width (top-LEFT interactive Claude).
#   2. split-pane -H -s 0.5  -> B0 : bottom pane, full width, 50% tall (runner CLI[0]);
#                                    focus moves to B0.
#   3. split-pane -V (xN-1)  -> cut the bottom into N equal columns (pane-runners); the
#                                    k-th split gives the new pane (N-k)/(N-k+1) of the
#                                    focused region, leaving 1/N per column overall.
#   4. move-focus up         -> return focus to the still-single full-width top pane P0.
#   5. split-pane -V -s 0.5  -> split P0 into top-LEFT (Claude, kept) + top-RIGHT (Kimi).
# The top-RIGHT Kimi split is only emitted when Kimi is available; otherwise the top
# row stays one full-width interactive Claude (graceful degrade, never a broken split).
if ($use6pane) {
    # Single-project fleet tab via the shared builder (same output as the batch path),
    # emitted stage-by-stage so a lone project also lands cleanly (RWN_4AI_PANE_DELAY_MS
    # = 0 collapses it back to the legacy single atomic wt call).
    $stages = Build-FleetTabStages -TargetDir $targetDir
    $plan = @(Get-FleetLaunchPlan -TabStages @(, $stages) -PaneDelayMs $paneDelayMs -TabDelayMs $tabDelayMs)

    $topDesc = if ($cliAvailable['Kimi']) { 'app-Claude | Kimi' } else { 'app-Claude' }
    Write-Host "6-pane layout (top=$topDesc, bottom=$($activeCLIs -join ', ')), pane pacing ${paneDelayMs}ms:" -ForegroundColor Cyan
    if (Invoke-FleetLaunchPlan -Plan $plan) {
        Write-Host "Launched $(Split-Path -Leaf $targetDir) in a new tab." -ForegroundColor Green
    } else {
        Write-Host "Failed to launch 6-pane layout." -ForegroundColor Red
    }
    return
}

# ── 5-pane operator-over-fleet layout (retained fallback: RWN_PANE_LAYOUT=5pane) ──
# Build ONE composite WT tab: new-tab = TOP pane (bare interactive Claude =
# app-Claude, identity claude-code, NOT the pane-runner); split-pane -H sizes the
# new bottom region to (1 - topStripFraction) so the top strip is topStripFraction;
# then N-1 vertical splits cut the bottom into equal columns, each running the
# self-driving pane-runner (the Claude column self-IDs as claude-auto).
if ($use5pane) {
    # Single-project fleet tab via the shared builder (same output as the batch path),
    # staged the same way as the 6pane path.
    $stages = Build-FleetTabStages -TargetDir $targetDir
    $plan = @(Get-FleetLaunchPlan -TabStages @(, $stages) -PaneDelayMs $paneDelayMs -TabDelayMs $tabDelayMs)

    Write-Host "5-pane layout (top=app-Claude, bottom=$($activeCLIs -join ', ')), pane pacing ${paneDelayMs}ms:" -ForegroundColor Cyan
    if (Invoke-FleetLaunchPlan -Plan $plan) {
        Write-Host "Launched $(Split-Path -Leaf $targetDir) in a new tab." -ForegroundColor Green
    } else {
        Write-Host "Failed to launch 5-pane layout." -ForegroundColor Red
    }
    return
}

# ── Legacy 4-grid path (RWN_PANE_LAYOUT=4grid / bare / nodir fallback) ──
function Get-PaneLaunch {
    param([string]$CliName, [string]$TargetDir)
    if ($bareMode -or (-not $TargetDir) -or (-not (Test-Path $paneRunner))) {
        return "powershell -NoExit -NoProfile -Command `"$($cliDefs[$CliName].cmd)`""
    }
    # Prefer the supervisor (auto-respawn) when present; degrade to the bare runner.
    $launcher = if (Test-Path $paneSupervisor) { $paneSupervisor } else { $paneRunner }
    return "powershell -NoExit -NoProfile -File `"$launcher`" -Cli $($cliLower[$CliName]) -ProjectDir `"$TargetDir`""
}

# Split sequence: first CLI stays in this pane, remaining CLIs split off to the right
$splitFractions = @(0.75, 0.6667, 0.5)

for ($i = 1; $i -lt $activeCLIs.Count; $i++) {
    $cliName = $activeCLIs[$i]
    $fraction = $splitFractions[$i - 1]

    $dirArg = if ($targetDir) { "-d `"$targetDir`"" } else { "" }
    $splitCmd = "$dirArg $(Get-PaneLaunch -CliName $cliName -TargetDir $targetDir)"
    $wtCmd = "-w rwn4ai split-pane -V -s $fraction $splitCmd"
    try {
        & cmd.exe /c "`"$wtExe`" $wtCmd"
        Start-Sleep -Milliseconds 400
    } catch {
        Write-Host "Failed to launch $cliName pane." -ForegroundColor Red
    }
}

# This pane -> first CLI in the layout.
# Self-driving path: run the supervisor (auto-respawn) directly in this pane so it
# too supervises its CLI, degrading to the bare runner if the supervisor is absent.
# Bare path (RWN_PANE_BARE / nodir): plain interactive REPL.
$firstCli = $activeCLIs[0]

Clear-Host
if ($targetDir) {
    Set-Location $targetDir
}
if ($bareMode -or (-not $targetDir) -or (-not (Test-Path $paneRunner))) {
    Invoke-Expression $cliDefs[$firstCli].cmd
} else {
    $launcher = if (Test-Path $paneSupervisor) { $paneSupervisor } else { $paneRunner }
    & $launcher -Cli $cliLower[$firstCli] -ProjectDir $targetDir
}
