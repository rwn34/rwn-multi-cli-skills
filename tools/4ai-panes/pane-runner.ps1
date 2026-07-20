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
#
# Worktree-per-CLI (ADR-0004 amendment + ADR-0016 snapshot-copy, 2026-07-11/17):
# a pane-consumed handoff is executed in that CLI's OWN git worktree
# (<parent>/.wt/<project>/<cli>/), never in $ProjectDir (the primary checkout).
# $ProjectDir remains the root for shared .ai/ state (handoff inbox, claims,
# activity log). The dispatcher copies a canonical .ai/ snapshot into the
# worktree before each handoff and syncs changes back afterward; there is NO
# junction into the worktree, eliminating the reverse-write hazard.
# This closes the second half of the shared-HEAD race that
# .ai/tools/dispatch-handoffs.sh already closed for the headless-dispatch path
# (docs/architecture/0004-worktree-multi-project-topology.md, Amendment) — the
# pane-runner is the OTHER, more heavily used dispatch path (the auto panes are
# what actually consume handoffs day to day), and until this fix it still ran
# every CLI in the primary checkout, which is how a live Kimi session in that
# checkout came within one `git checkout -b` of having its uncommitted work
# reverted by a concurrently dispatched pane (see the handoff for this fix).
#
# Worktree creation delegates to scripts/wt-bootstrap.sh (bash) — the SAME
# script .ai/tools/dispatch-handoffs.sh already calls — rather than
# reimplementing worktree/branch-container setup a third time in PowerShell.
# The declared-base branch cut (Ensure-DeclaredBaseBranch below) IS a second,
# native-PowerShell implementation of dispatch-handoffs.sh's
# ensure_declared_base_branch(): that piece is plain git plumbing (fetch,
# rev-parse, branch + symbolic-ref + restore) cheap enough to keep 1:1 in both languages, and
# shelling out to bash for every git call the supervisor loop makes on every
# poll cycle would be slower and adds a bash-availability dependency to the hot
# path. Test (parity guard, see test-pane-runner.ps1) asserts the two
# implementations' BEHAVIOR (branch name, base resolution, dirty-tree refusal)
# stays in lockstep — per the handoff's own guidance: unify what's cheap to
# unify (worktree creation, via wt-bootstrap.sh), guard what's not (the branch
# cut) with a test that fails loudly on divergence rather than silently drifting.
#
# Fail-loud contract: if the worktree cannot be established, the pane MUST NOT
# silently fall back to $ProjectDir. Get-CliWorktreePath returns $null on
# failure; every call site treats $null as "this handoff cannot run right now" —
# it is left OPEN (never claimed), an ALERT is printed, and the poll loop
# continues. This mirrors dispatch-handoffs.sh's ensure_cli_worktree() contract
# verbatim (see that script's header + comments).

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
        # --dangerously-skip-permissions (not --permission-mode acceptEdits):
        # acceptEdits auto-approves ONLY Edit/Write; Bash calls outside
        # .claude/settings.local.json's allow-list (git/mv/rm are NOT on it)
        # were auto-DENIED with no human available headless to approve them —
        # the headless Claude lane was strictly weaker than every other CLI's
        # headless invocation AND weaker than Claude's OWN interactive pane
        # (which already runs --dangerously-skip-permissions, see
        # Get-InteractiveCmd below). This is SAFE because permissions and
        # hooks are different layers: this flag bypasses the permission
        # PROMPT only — the PreToolUse guard hooks (cross-CLI dir, sensitive-
        # file, root-file, destructive-cmd) still fire and remain the
        # mechanical floor (F2 handoff, 2026-07-12; verified empirically, see
        # docs/architecture/0005-commit-governance-backstop.md).
        'claude'   { return @('claude', '-p', $Prompt, '--dangerously-skip-permissions') }
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

# -- Worktree-per-CLI (ADR-0004 amendment; pane-runner parity fix 2026-07-12) --
#
# Pure path arithmetic — MUST match dispatch-handoffs.sh worktree_path_for() and
# scripts/wt-bootstrap.sh's own WT_CONTAINER derivation: a sibling
# .wt/<project>/<cli> next to the primary checkout. No side effects.
function Get-CliWorktreePathFor {
    param([string]$ProjectDir, [string]$CliName)
    $projectDirResolved = (Resolve-Path -Path $ProjectDir).Path.TrimEnd('\', '/')
    $parentDir   = Split-Path -Parent $projectDirResolved
    $projectName = Split-Path -Leaf $projectDirResolved
    return (Join-Path (Join-Path (Join-Path $parentDir '.wt') $projectName) $CliName)
}

# -- wt-bootstrap.sh resolution (regression fix 2026-07-12) --
#
# wt-bootstrap.sh belongs to the PROJECT BEING OPERATED ON, not to the tool's
# install location. The previous single-candidate resolver assumed $PSScriptRoot
# is always <repo>/tools/4ai-panes/, so the repo root is two levels up. That is
# TRUE in the repo tree and FALSE in the DEPLOYED launcher: scripts/sync-4ai-panes-install.ps1
# installs the pane tools into a FLAT dir (~/.rwn-auto/rwn-4AI-panes/), where
# ../../scripts/ resolves to ~/scripts/ — which does not exist. Every pane-runner
# (kimi, kiro, opencode, claude-auto) took that path, so the WHOLE fleet failed
# worktree setup and quarantined every handoff. Sibling dot-sources (fleet-clis.ps1,
# notify.ps1) are fine because they ARE installed flat beside us; only the
# repo-relative path broke.
#
# Candidates, in order — first that exists wins:
#   1. $ProjectDir/scripts/wt-bootstrap.sh   the target project's own copy (also
#      what the shipped .ai/tools/dispatch-handoffs.sh resolves to). Now actually
#      shipped by scripts/install-template.sh.
#   2. $ScriptRoot/../../scripts/wt-bootstrap.sh   the repo-tree / dev checkout
#      case (what worked before this fix).
#   3. $RWN_FRAMEWORK_REPO/scripts/wt-bootstrap.sh   the framework source repo —
#      the load-bearing one for the flat install driving a project that has no
#      copy of its own. Same env var + default as Selector.ps1 $frameworkRepo; do
#      not invent a second convention.
#
# $ScriptRoot is a parameter (not a read of $PSScriptRoot) precisely so a test can
# simulate the flat-install topology. The old resolver was untestable for the
# topology we actually SHIP, which is why a total regression shipped green.
$script:FrameworkRepoDefault = 'C:/Users/rwn34/Code/rwn-multi-cli-skills'

function Get-WtBootstrapCandidates {
    param([string]$ProjectDir, [string]$ScriptRoot)
    $frameworkRepo = if ($env:RWN_FRAMEWORK_REPO) { $env:RWN_FRAMEWORK_REPO } else { $script:FrameworkRepoDefault }
    return @(
        (Join-Path $ProjectDir    'scripts/wt-bootstrap.sh')
        (Join-Path $ScriptRoot    '../../scripts/wt-bootstrap.sh')
        (Join-Path $frameworkRepo 'scripts/wt-bootstrap.sh')
    )
}

# Return the first candidate that exists, or $null if NONE do. $null is the
# fail-loud signal — the caller lists every path tried and refuses to proceed.
function Resolve-WtBootstrapPath {
    param([string]$ProjectDir, [string]$ScriptRoot)
    foreach ($candidate in (Get-WtBootstrapCandidates -ProjectDir $ProjectDir -ScriptRoot $ScriptRoot)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

# --- Git Bash resolution (the 2026-07-12 outage) ----------------------------
# The panes launch from a plain Windows context (vbs -> powershell) whose
# persisted Machine+User PATH puts C:\WINDOWS\system32 FIRST and ships Git only
# as C:\Program Files\Git\cmd — which holds git.exe but NO bash.exe. So a naive
# `Get-Command bash` resolves to the WSL launcher C:\Windows\System32\bash.exe.
#
# WSL bash re-parses its arguments as a shell string, so the backslashes in a
# Windows path are eaten as escapes:
#   C:\Users\rwn34\...\wt-bootstrap.sh  ->  C:Usersrwn34...wt-bootstrap.sh  (exit 127)
# Git Bash runs that SAME backslash path fine, so the fix is NOT path conversion —
# it is pinning Git Bash and REFUSING WSL. Even if WSL bash could find the script,
# running it there would be wrong: `git worktree` and mklink /J junctions are
# Windows-side operations.
#
# The hazard was already documented in test-pane-runner.ps1 (the suite SKIPS on
# WSL bash) but the production resolver never got the same guard — the knowledge
# was in the repo; only the test acted on it.
#
# Overridable ($script:) so tests can drive the probe order without a real install.
$script:GitBashProbePaths = @(
    'C:\Program Files\Git\bin\bash.exe'
    'C:\Program Files\Git\usr\bin\bash.exe'
    'C:\Program Files (x86)\Git\bin\bash.exe'
)

# Reject WSL (System32\bash.exe) and Microsoft Store (WindowsApps) launchers.
# Kept inline-free of helpers so the function stays self-contained and liftable.
function Resolve-GitBash {
    param([string[]]$ProbePaths = $script:GitBashProbePaths)

    $windir = if ($env:WINDIR) { $env:WINDIR } else { 'C:\Windows' }
    $sys32 = [System.IO.Path]::Combine($windir, 'System32')
    $isDisallowed = {
        param([string]$p)
        if ([string]::IsNullOrWhiteSpace($p)) { return $true }
        $n = $p -replace '/', '\'
        if ($n.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        return ($n -match '(?i)WindowsApps')
    }

    # 1. Well-known Git for Windows locations.
    foreach ($p in $ProbePaths) {
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
    # 3. Last resort: whatever is on PATH — but ONLY if it is not WSL/Store.
    $onPath = Get-Command bash -ErrorAction SilentlyContinue
    if ($onPath -and -not (& $isDisallowed $onPath.Source)) { return $onPath.Source }

    return $null
}

# Overridable so tests can stub out the real bash/wt-bootstrap.sh call. Returns
# $true on success (worktree present + usable), $false on failure. NEVER prints
# or returns the primary checkout as a substitute on failure — callers MUST
# treat $false as "this dispatch cannot proceed right now", full stop (mirrors
# dispatch-handoffs.sh ensure_cli_worktree()'s contract exactly).
$script:InvokeWtBootstrap = {
    param([string]$ProjectDir, [string]$CliName)
    $bootstrap = Resolve-WtBootstrapPath -ProjectDir $ProjectDir -ScriptRoot $PSScriptRoot
    if (-not $bootstrap) {
        Write-Host "  ERROR: worktree bootstrap script not found. Tried, in order:" -ForegroundColor Red
        foreach ($candidate in (Get-WtBootstrapCandidates -ProjectDir $ProjectDir -ScriptRoot $PSScriptRoot)) {
            Write-Host "    - $candidate" -ForegroundColor Red
        }
        Write-Host "  Fix: ship scripts/wt-bootstrap.sh into the project, or set RWN_FRAMEWORK_REPO to the framework checkout." -ForegroundColor Red
        return $false
    }
    $bash = Resolve-GitBash
    if (-not $bash) {
        Write-Host "  ERROR: Git Bash not found (WSL bash cannot run wt-bootstrap.sh) - install Git for Windows or set PATH" -ForegroundColor Red
        return $false
    }
    # wt-bootstrap.sh's normal informational logging goes to stdout AND its
    # `warn()` helper to stderr; neither is a fatal error. Under
    # $ErrorActionPreference='Stop' (the supervisor loop's call-site EAP), a
    # 2>&1-merged stderr line from a native command is promoted to a
    # terminating NativeCommandError — same hazard $script:InvokeCli already
    # guards against for the CLI child. Mirror that guard here.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $bash $bootstrap $ProjectDir $CliName 2>&1 | ForEach-Object { Write-Host "  [wt-bootstrap] $_" -ForegroundColor DarkGray }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return ($LASTEXITCODE -eq 0)
}

# Ensure (create-or-reuse) this CLI's dedicated worktree exists and is a usable
# git worktree. Returns the absolute worktree path on success, $null on
# failure — $null is the fail-loud signal every call site must honor: NEVER
# substitute $ProjectDir when this returns $null.
#
# Overridable ($script:GetCliWorktreePath) for the SAME reason $script:InvokeCli
# and $script:TestPidAlive are: the test harness must be able to drive
# Invoke-HandoffRun's worktree-fail-loud logic without touching a real git
# worktree or shelling out to bash. Production code (Invoke-HandoffRun) calls
# through the script-scoped indirection below; only tests replace it.
function Get-CliWorktreePathReal {
    param([string]$ProjectDir, [string]$CliName)
    $wtPath = Get-CliWorktreePathFor -ProjectDir $ProjectDir -CliName $CliName

    $ok = & $script:InvokeWtBootstrap $ProjectDir $CliName
    if (-not $ok) { return $null }

    if (-not (Test-Path $wtPath)) {
        Write-Host "  ERROR: wt-bootstrap.sh reported success but $wtPath does not exist" -ForegroundColor Red
        return $null
    }
    # Belt-and-suspenders: confirm it's actually a usable git worktree, mirroring
    # dispatch-handoffs.sh's own re-verification after calling the same script.
    Push-Location $wtPath
    try {
        git rev-parse --is-inside-work-tree *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: $wtPath exists but is not a usable git worktree" -ForegroundColor Red
            return $null
        }
    } finally {
        Pop-Location
    }
    return $wtPath
}

$script:GetCliWorktreePath = {
    param([string]$ProjectDir, [string]$CliName)
    return (Get-CliWorktreePathReal -ProjectDir $ProjectDir -CliName $CliName)
}

# Discover the repo's default branch. Order of preference, first resolvable
# wins: fresh origin fetch, origin/HEAD, origin/main, local main, HEAD.
# Returns the resolved ref name (e.g. 'origin/main'), or $null when none resolve.
function Resolve-DefaultBase {
    param([string]$ProjectDir)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    # If local main is strictly ahead of origin/main, prefer it so that
    # Observed-in: main@HEAD works after sync-ai-state auto-commits advance
    # local main past the remote (no push required).
    function Local-Main-If-Ahead {
        $localMain = git -C $ProjectDir rev-parse --verify --quiet 'main^{commit}' 2>$null
        $originMain = git -C $ProjectDir rev-parse --verify --quiet 'origin/main^{commit}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $localMain -and $originMain -and ($localMain -ne $originMain)) {
            git -C $ProjectDir merge-base --is-ancestor $originMain $localMain *>$null
            if ($LASTEXITCODE -eq 0) { return 'main' }
        }
        return $null
    }

    try {
        git -C $ProjectDir fetch origin *>$null
        # Fetch failure is not fatal — stale cached refs are still declared bases.

        $sym = git -C $ProjectDir symbolic-ref refs/remotes/origin/HEAD 2>$null
        $rc = $LASTEXITCODE
        if ($rc -eq 0 -and $sym) {
            $sym = $sym -replace '^refs/remotes/', ''
            git -C $ProjectDir rev-parse --verify --quiet "$sym^{commit}" *>$null
            if ($LASTEXITCODE -eq 0) {
                if ($sym -eq 'origin/main') {
                    $ahead = Local-Main-If-Ahead
                    if ($ahead) { return $ahead }
                }
                return $sym
            }
        }

        # No cached origin/HEAD. Best-effort auto-detect over the network, but never
        # fail if the network is unreachable — fall back to the chain.
        git -C $ProjectDir remote set-head origin -a *>$null
        $sym = git -C $ProjectDir symbolic-ref refs/remotes/origin/HEAD 2>$null
        $rc = $LASTEXITCODE
        if ($rc -eq 0 -and $sym) {
            $sym = $sym -replace '^refs/remotes/', ''
            git -C $ProjectDir rev-parse --verify --quiet "$sym^{commit}" *>$null
            if ($LASTEXITCODE -eq 0) {
                if ($sym -eq 'origin/main') {
                    $ahead = Local-Main-If-Ahead
                    if ($ahead) { return $ahead }
                }
                return $sym
            }
        }

        foreach ($candidate in @('origin/main', 'main', 'HEAD')) {
            git -C $ProjectDir rev-parse --verify --quiet "$candidate^{commit}" *>$null
            if ($LASTEXITCODE -eq 0) {
                if ($candidate -eq 'origin/main') {
                    $ahead = Local-Main-If-Ahead
                    if ($ahead) { return $ahead }
                }
                return $candidate
            }
        }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return $null
}

# Read an optional `Base:` line from a handoff's status block (first 20 lines,
# mirrors dispatch-handoffs.sh base_for()); if absent, delegates to
# Resolve-DefaultBase so the pane-runner never hardcodes `origin/master`.
function Get-DeclaredBase-Real {
    param([string]$HandoffPath)
    $head = Get-Content -Path $HandoffPath -TotalCount 20 -ErrorAction SilentlyContinue
    if ($head) {
        foreach ($line in $head) {
            if ($line -match '^\s*Base:\s*(\S.*)$') { return $matches[1].Trim() }
        }
    }

    # No explicit Base: — discover the repo's default branch.
    $projectDir = Split-Path -Path $HandoffPath -Parent
    $projectDir = Split-Path -Path $projectDir -Parent      # .ai/handoffs
    $projectDir = Split-Path -Path $projectDir -Parent      # .ai
    $projectDir = Split-Path -Path $projectDir -Parent      # project root

    $base = Resolve-DefaultBase -ProjectDir $projectDir
    if ($base) { return $base }

    throw "Could not resolve a declared base for $HandoffPath (tried: origin/HEAD auto-detect, origin/main, main, HEAD)"
}

# Overridable hook so tests can stub base resolution without needing a real git repo.
$script:GetDeclaredBase = { param([string]$HandoffPath) return (Get-DeclaredBase-Real -HandoffPath $HandoffPath) }

# Cut/reuse exec/<cli>/<slug> in $WtPath FROM the declared base — never from
# ambient HEAD. Native-PowerShell twin of dispatch-handoffs.sh
# ensure_declared_base_branch() (see the file-header note on why this one stays
# duplicated rather than shelled out to bash). Returns $true on success (worktree
# HEAD now on the per-handoff branch, or left untouched with pre-existing
# uncommitted work reported), $false on hard failure (no declared base
# resolvable). Excludes .ai/** from the dirty-tree check for the same reason
# dispatch-handoffs.sh does: .ai is a snapshot copy of the canonical
# coordination plane into the worktree, populated before each dispatch and
# synced back afterward. Its normal churn must not be treated as uncommitted
# work.
#
# Overridable ($script:EnsureDeclaredBaseBranch) so tests can drive
# Invoke-HandoffRun's declared-base-branch-failure path without a real git
# worktree — same pattern as $script:GetCliWorktreePath above.
#
# NATIVE-STDERR GUARD (regression fix 2026-07-12, second-order): every git call
# below is a NATIVE command, and git writes ordinary progress to STDERR — `git
# fetch` emits "From https://github.com/..." whenever it actually retrieves refs,
# and `git branch <name> origin/<x>` emits "branch '<name>' set up to track...". This script runs
# under $ErrorActionPreference='Stop' (set at the top), which PROMOTES a native
# command's stderr record to a TERMINATING NativeCommandError. `*> $null` does NOT
# suppress that promotion in PS 5.1 — the throw happens before the redirect. So a
# plain, successful `git fetch` that had anything to fetch would throw and take
# out the whole branch cut, surfacing as WORKTREE_FAIL with no useful message.
#
# This is the SAME hazard $script:InvokeCli and $script:InvokeWtBootstrap already
# guard against (see their comments) — this function was simply missing the guard.
# It stayed hidden because the wt-bootstrap path failed FIRST (the flat-install
# regression), so the branch cut was never reached; fixing that unmasked this.
# It is also intermittent by nature: a fetch with nothing new writes no stderr and
# does not throw, so it fails only when the remote has actually moved.
#
# Force EAP='Continue' around the native git calls and restore it in finally. This
# loses no failure signal: every call's outcome is already judged by $LASTEXITCODE,
# never by whether it threw.
function Ensure-DeclaredBaseBranchReal {
    param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base)
    $branch = "exec/$CliName/$Slug"

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $WtPath
    try {
        $dirty = git status --porcelain 2>$null | Where-Object { $_ -notmatch '\s\.ai/' }
        if ($dirty) {
            $current = (git branch --show-current 2>$null)
            Write-Host "  WARN: $WtPath has uncommitted changes on '$current' - reusing as-is, not cutting $branch" -ForegroundColor Yellow
            return $true
        }

        git fetch origin *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARN: git fetch origin failed in $WtPath - using cached '$Base'" -ForegroundColor Yellow
        }

        # Resolve the base ref in the PRIMARY checkout. Worktrees share
        # remote-tracking refs but local branch visibility can vary; a local
        # 'main' may resolve in the project root but not inside the worktree.
        # Use the commit SHA for all worktree operations so the branch is cut
        # from the exact declared base.
        $wtContainer = Split-Path -Parent $WtPath           # .../.wt/<project>
        $projectName = Split-Path -Leaf $wtContainer        # <project>
        $parentDir = Split-Path -Parent $wtContainer        # parent of .wt
        $projectDir = Join-Path $parentDir $projectName     # primary checkout
        $baseSha = git -C $projectDir rev-parse --verify --quiet "$Base^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $baseSha) {
            Write-Host "  ERROR: declared base '$Base' does not resolve in $projectDir (no network + no local cache?)" -ForegroundColor Red
            return $false
        }
        git rev-parse --verify --quiet "$baseSha^{commit}" *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: declared base '$Base' ($baseSha) is not reachable in $WtPath" -ForegroundColor Red
            return $false
        }

        # Attach HEAD to exec/<cli>/<slug> WITHOUT touching the working tree.
        # A plain `git checkout` (or `checkout -b`) would rewrite files in the
        # worktree and can entangle concurrent dispatches. symbolic-ref moves
        # HEAD without rewriting a single file; the restore then converges
        # worktree+index onto the branch tip for everything EXCEPT .ai/. .ai/ is
        # a snapshot copy populated by SnapshotAi and must not be touched by git
        # — the snapshot is the authoritative coordination-plane state for this
        # dispatch. `git restore` with an explicit --source defaults to
        # --no-overlay: files absent on the branch are removed from the worktree
        # too (verified empirically).
        git show-ref --verify --quiet "refs/heads/$branch" *> $null
        if ($LASTEXITCODE -ne 0) {
            git branch $branch $baseSha *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ERROR: could not create branch $branch at $Base ($baseSha) in $WtPath" -ForegroundColor Red
                return $false
            }
        }
        git symbolic-ref HEAD "refs/heads/$branch" *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: could not attach HEAD to $branch in $WtPath" -ForegroundColor Red
            return $false
        }
        git restore --source=$branch --staged --worktree -- . ':!.ai' *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: could not sync $WtPath to $branch (excluding .ai/)" -ForegroundColor Red
            return $false
        }
        # Sync the .ai/ INDEX entries to the branch tip without touching the
        # worktree. The snapshot-copy .ai/ must stay as the live canonical copy,
        # but leaving the index stale would make `git status --porcelain -- .ai`
        # report staged phantoms.
        git restore --source=$branch --staged -- .ai *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: could not sync the .ai/ index entries in $WtPath" -ForegroundColor Red
            return $false
        }
        return $true
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEAP
    }
}

$script:EnsureDeclaredBaseBranch = {
    param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base)
    return (Ensure-DeclaredBaseBranchReal -WtPath $WtPath -CliName $CliName -Slug $Slug -Base $Base)
}

# -- Dispatch-guard child env (F3: nested self-dispatch race) --
#
# The pane-runner IS a dispatcher: it claims a handoff and runs the CLI on it.
# Some CLIs (claude) also run a SessionStart hook that re-dispatches their own
# queue - a SECOND consumer launched from inside the session already processing
# it. Those hooks short-circuit when AI_HANDOFF_DISPATCH is set, so stamp it
# into the process env (inherited by every child we spawn) for ALL CLIs -
# harmless for CLIs whose hooks don't read it, correct for the one that does.
# A per-CLI carve-out is how this bug got in; do not reintroduce one.
function Enable-DispatchGuardEnv {
    # Returns the prior value ($null if unset) so the caller can restore it.
    $prev = $env:AI_HANDOFF_DISPATCH
    $env:AI_HANDOFF_DISPATCH = '1'
    return $prev
}

function Restore-DispatchGuardEnv {
    param([object]$Previous)
    if ($null -eq $Previous) {
        Remove-Item -Path Env:\AI_HANDOFF_DISPATCH -ErrorAction SilentlyContinue
    } else {
        $env:AI_HANDOFF_DISPATCH = [string]$Previous
    }
}

# -- Overridable hooks (tests replace these with mocks) --

# Real CLI launch: build the headless command and run it as a blocking child IN
# $Cwd — the CLI's own worktree (Get-CliWorktreePath), never $ProjectDir. This is
# the worktree-per-CLI fix itself: a concurrently dispatched pane's `git
# checkout` can never revert THIS session's on-disk files, because they are two
# distinct working trees (mirrors dispatch-handoffs.sh's `cd "$wt_path" && ...`,
# which is the same fix on the headless-dispatch path). $Cwd defaults to the
# caller's current location when omitted, which only matters for the test mock
# below — Invoke-HandoffRun always passes an explicit, already-verified $Cwd.
#
# The child's stdout AND stderr are streamed live to the pane console via
# '2>&1 | Out-Host' so EVERY CLI is visibly active - not just the ones that write
# straight to the console handle. Out-Host renders to the host and emits nothing
# onto the pipeline, so the CLI's chatter never leaks into a caller's return
# value; only the exit code below is returned. Returns the child's exit code.
$script:InvokeCli = {
    param([string]$CliName, [string]$Prompt, [string]$Cwd = (Get-Location).Path, [int]$TimeoutSeconds = 0)
    # argv array: [0] = exe, [1..] = args. The untrusted $Prompt is one element,
    # invoked via the call operator (& $exe @args) so it is NEVER re-parsed as a
    # command string (was Invoke-Expression - a filename-to-RCE hole).
    $argv = @(Get-HeadlessCmd -CliName $CliName -Prompt $Prompt)
    $exe  = $argv[0]
    $rest = @($argv | Select-Object -Skip 1)
    Write-Host "  > (cwd=$Cwd) $exe $($rest -join ' ')" -ForegroundColor DarkGray

    # -- Timeout path: some CLIs (opencode run --auto) do not self-exit after one
    # prompt. Without a hard cap the pane runner blocks forever and stops polling.
    if ($TimeoutSeconds -gt 0) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Push-Location $Cwd
        $prevLC_ALL = $env:LC_ALL
        $prevLANG = $env:LANG
        $env:LC_ALL = 'C.UTF-8'
        $env:LANG = 'C.UTF-8'
        $prevDispatch = Enable-DispatchGuardEnv
        $capturePath = $script:CliOutputCapturePath
        $outJob = $null
        $errJob = $null
        $proc = $null
        try {
            # Redirect stdout/stderr to separate temp files (PowerShell's
            # Start-Process rejects the same path for both). Stream each file
            # to the host in a background job so the pane stays visible, then
            # merge stderr into stdout so L2 outcome classification can read
            # the combined tail.
            $outPath = [System.IO.Path]::GetTempFileName()
            $errPath = "$outPath.err"
            if (-not $capturePath) { $capturePath = $outPath }
            $proc = Start-Process -FilePath $exe -ArgumentList $rest -WorkingDirectory $Cwd `
                -NoNewWindow -PassThru -RedirectStandardOutput $outPath -RedirectStandardError $errPath
            $outJob = Start-Job -ScriptBlock {
                param($Path)
                Get-Content -Path $Path -Wait -Tail 1000 | ForEach-Object { Write-Host $_ }
            } -ArgumentList $outPath
            $errJob = Start-Job -ScriptBlock {
                param($Path)
                Get-Content -Path $Path -Wait -Tail 1000 | ForEach-Object { Write-Host $_ }
            } -ArgumentList $errPath
            $timeoutMs = $TimeoutSeconds * 1000
            $exited = $proc.WaitForExit($timeoutMs)
            if (-not $exited) {
                Write-Host "  == TIMEOUT [$CliName] invocation exceeded ${TimeoutSeconds}s; terminating child tree ==" -ForegroundColor Yellow
                Stop-CliProcessTree -RootPid $proc.Id
                return $script:CliTimeoutExitCode
            }
            # Brief pause so the stream jobs can emit the final lines.
            Start-Sleep -Milliseconds 500
            return $proc.ExitCode
        } finally {
            if ($outJob) {
                Stop-Job $outJob -ErrorAction SilentlyContinue
                Remove-Job $outJob -ErrorAction SilentlyContinue
            }
            if ($errJob) {
                Stop-Job $errJob -ErrorAction SilentlyContinue
                Remove-Job $errJob -ErrorAction SilentlyContinue
            }
            Restore-DispatchGuardEnv -Previous $prevDispatch
            Pop-Location
            $ErrorActionPreference = $prevEAP
            $env:LC_ALL = $prevLC_ALL
            $env:LANG = $prevLANG
            # Merge stderr into stdout capture so the tail classifier sees both.
            if ($errPath -and (Test-Path $errPath)) {
                try {
                    Get-Content -Path $errPath -Raw -ErrorAction SilentlyContinue | `
                        Add-Content -Path $outPath -Encoding utf8 -ErrorAction SilentlyContinue
                } catch {}
            }
            if ($capturePath -and $outPath -and $capturePath -ne $outPath -and (Test-Path $outPath)) {
                Move-Item -Path $outPath -Destination $capturePath -Force -ErrorAction SilentlyContinue
            }
            if ($errPath -and (Test-Path $errPath)) {
                Remove-Item -Path $errPath -Force -ErrorAction SilentlyContinue
            }
            # Clean up the temp capture if the pane-runner did not request one.
            if ($capturePath -eq $outPath -and (Test-Path $outPath)) {
                Remove-Item -Path $outPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # -- Non-timeout path: keep the original behavior exactly. --
    # A native CLI's stderr is normal progress streaming, not a fatal error. Under
    # $ErrorActionPreference='Stop' the 2>&1-merged stderr record is promoted to a
    # terminating NativeCommandError, which would unwind the whole supervisor loop
    # on the CLI's first stderr line. Force 'Continue' around ONLY the native call
    # (restored in finally). This loses no failure signal: Invoke-HandoffRun decides
    # continue/done by whether the handoff moved to done/ (Test-HandoffDone), not by
    # exit code or stderr.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Push-Location wraps the WHOLE call (outermost): worktree confinement is a
    # property of where the child runs, independent of the dispatch-guard env,
    # so it must be established before — and torn down after — everything else.
    Push-Location $Cwd
    # S3-1 root cause: force UTF-8 locale for any bash/PowerShell subprocess the
    # CLI spawns, so em-dashes and other non-ASCII chars are not written as cp1252.
    $prevLC_ALL = $env:LC_ALL
    $prevLANG = $env:LANG
    $env:LC_ALL = 'C.UTF-8'
    $env:LANG = 'C.UTF-8'
    try {
        # F3: tell the child (and its SessionStart hooks) that a dispatcher is
        # already driving this queue, so a nested dispatch-own-queue short-circuits
        # instead of re-dispatching the same handoff to a second instance.
        $prevDispatch = Enable-DispatchGuardEnv
        try {
            # Tee CLI output to the capture file when heartbeat L2 is active, so
            # Get-LastCliOutcome can classify auth/quota failures post-invocation.
            # Tee-Object passes through to Out-Host (live console) AND writes the
            # file; the pipeline stays clean (Out-Host emits nothing). Overwrites
            # the file each invocation — only the most recent run's tail matters.
            if ($script:CliOutputCapturePath) {
                & $exe @rest 2>&1 | Tee-Object -FilePath $script:CliOutputCapturePath | Out-Host
            } else {
                & $exe @rest 2>&1 | Out-Host
            }
        } finally {
            # Innermost-acquired, innermost-released: the env guard is undone
            # before EAP/cwd unwind, mirroring the try nesting exactly.
            Restore-DispatchGuardEnv -Previous $prevDispatch
        }
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEAP
        $env:LC_ALL = $prevLC_ALL
        $env:LANG = $prevLANG
    }
    return $LASTEXITCODE
}

# Real pid-liveness probe.
$script:TestPidAlive = {
    param([int]$ProcessId)
    return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

# Snapshot canonical .ai/ into the worktree as ordinary files. Overridable so
# tests can avoid shelling out to bash; production delegates to
# .ai/tools/sync-ai-state.sh snapshot (ADR-0016 snapshot-copy model).
$script:SnapshotAi = {
    param([string]$ProjectDir, [string]$WtPath)
    $bash = Resolve-GitBash
    if (-not $bash) {
        Write-Host "  ERROR: Git Bash not found; cannot snapshot .ai/" -ForegroundColor Red
        return $false
    }
    $sync = Join-Path $ProjectDir '.ai/tools/sync-ai-state.sh'
    if (-not (Test-Path $sync)) {
        Write-Host "  ERROR: sync-ai-state.sh not found at $sync" -ForegroundColor Red
        return $false
    }
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $bash $sync snapshot "$ProjectDir/.ai" "$WtPath/.ai" 2>&1 | ForEach-Object { Write-Host "  [snapshot-ai] $_" -ForegroundColor DarkGray }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return ($LASTEXITCODE -eq 0)
}

# Sync worktree .ai/ changes back to canonical and remove the worktree copy.
# Fail-open: errors are logged but do not abort the runner.
$script:SyncBackAi = {
    param([string]$ProjectDir, [string]$WtPath)
    $bash = Resolve-GitBash
    if (-not $bash) {
        Write-Host "  WARN: Git Bash not found; cannot sync back .ai/" -ForegroundColor Yellow
        return
    }
    $sync = Join-Path $ProjectDir '.ai/tools/sync-ai-state.sh'
    if (-not (Test-Path $sync)) {
        Write-Host "  WARN: sync-ai-state.sh not found at $sync; cannot sync back .ai/" -ForegroundColor Yellow
        return
    }
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $bash $sync sync-back "$WtPath" "$ProjectDir" 2>&1 | ForEach-Object { Write-Host "  [sync-back-ai] $_" -ForegroundColor DarkGray }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

# -- Handoff inbox (IDLE poll - filesystem only) --

# Return the path of the first qualifying handoff in this CLI's open/ or review/
# inbox, or $null. Qualifying = Auto: yes AND Status: OPEN AND Risk: A|B (the
# exact gate dispatch-handoffs.sh uses). Risk C / missing Risk is human-gated ->
# skipped.
#
# open/ and review/ are merged and sorted by filename (timestamp prefix), so the
# oldest qualifying handoff wins regardless of queue. This keeps the review
# pipeline moving without starving new work.
function Get-QualifyingHandoff {
    param([string]$ProjectDir, [string]$CliName)
    $allFiles = @()
    foreach ($sub in @('open', 'review')) {
        $dir = Join-Path $ProjectDir ".ai/handoffs/to-$CliName/$sub"
        if (Test-Path $dir) {
            $allFiles += Get-ChildItem -Path $dir -Filter "*.md" -File -ErrorAction SilentlyContinue
        }
    }
    if ($allFiles.Count -eq 0) { return $null }
    $files = $allFiles | Sort-Object Name
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

# Read a single header field from a handoff file. Returns the value, or $null if
# not present. Handles "Field: value" and "# Field: value" forms.
function Read-HandoffField {
    param([string]$HandoffPath, [string]$FieldName)
    if (-not (Test-Path $HandoffPath)) { return $null }
    $pattern = "^\s*#?\s*${FieldName}:\s*(.+?)\s*$"
    $line = Get-Content -Path $HandoffPath -TotalCount 30 -ErrorAction SilentlyContinue | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if ($line) {
        return ($line -replace $pattern, '$1').Trim()
    }
    return $null
}

# Eight-actor identity normalization. Accepts legacy bare cli names (kimi),
# legacy '-cli' forms, and full eight-actor identities, and returns
# the canonical identity used in Sender:/Recipient:/Owner:.
function Resolve-ActorIdentity {
    param([string]$Actor)
    $a = $Actor.ToLower().Trim()
    switch ($a) {
        { $_ -in @('claude','claude-auto','claude-code') }          { return 'claude-auto' }
        'claude-cockpit'                                            { return 'claude-cockpit' }
        { $_ -in @('kimi','kimai-auto','kimi-auto','kimi-cli') }    { return 'kimai-auto' }
        { $_ -in @('kimi-cockpit','kimai-cockpit') }                { return 'kimai-cockpit' }
        { $_ -in @('kiro','kiro-auto','kiro-cli') }                 { return 'kiro-auto' }
        'kiro-cockpit'                                              { return 'kiro-cockpit' }
        { $_ -in @('opencode','opencode-auto','opencode-cli') }     { return 'opencode-auto' }
        'opencode-cockpit'                                          { return 'opencode-cockpit' }
        default                                                     { return $a }
    }
}

# Map a (possibly legacy) actor string to the queue directory name used by the
# dispatcher and pane-runner (claude, kimi, kiro, opencode).
function Get-QueueNameFromActor {
    param([string]$Actor)
    $a = (Resolve-ActorIdentity -Actor $Actor).ToLower()
    switch -Wildcard ($a) {
        'claude*'   { return 'claude' }
        'kimai*'    { return 'kimi' }
        'kimi*'     { return 'kimi' }
        'kiro*'     { return 'kiro' }
        'opencode*' { return 'opencode' }
        default     { return ($a -replace '-(auto|cockpit|executor|cli)$','') }
    }
}

# Decide Auto flag from a (possibly legacy) actor string. Cockpit identities
# are never auto-dispatched; everything else is.
function Get-AutoFlagFromActor {
    param([string]$Actor)
    $a = (Resolve-ActorIdentity -Actor $Actor).ToLower()
    if ($a -like '*-cockpit') { return 'no' }
    return 'yes'
}

# After a handoff is completed, optionally emit the next stage of the review/
# deploy pipeline. This is generic: the pane-runner emits the next handoff based
# on metadata in the completed file, so individual CLIs do not need custom logic.
function Emit-NextStageHandoff {
    param([string]$ProjectDir, [string]$CliName, [string]$HandoffPath)
    $base = Split-Path -Leaf $HandoffPath
    $donePath = Join-Path $ProjectDir ".ai/handoffs/to-$CliName/done/$base"
    if (-not (Test-Path $donePath)) {
        # The recipient may have renamed or not moved it; nothing to route from.
        return
    }

    $head = Get-Content -Path $donePath -TotalCount 30 -ErrorAction SilentlyContinue
    if (-not ($head -match '^\s*#?\s*Status:\s*DONE')) {
        # Only route on successful completion.
        return
    }

    $ts = (Get-Date -Format 'yyyyMMddHHmm')
    $slug = [System.IO.Path]::GetFileNameWithoutExtension($base)

    # Helper to write a handoff file. $RecipientActor is the full six-actor
    # identity; the queue directory is derived from it.
    function Write-Handoff($RecipientActor, $SubDir, $Title, $BodyLines) {
        $recipientQueue = Get-QueueNameFromActor -Actor $RecipientActor
        $dir = Join-Path $ProjectDir ".ai/handoffs/to-$recipientQueue/$SubDir"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $path = Join-Path $dir "$ts-$slug.md"
        # De-duplicate: if a same-second handoff with this slug already exists,
        # append a suffix. Collisions are vanishingly rare but possible.
        $suffix = ''
        $counter = 1
        while (Test-Path $path) {
            $counter++
            $path = Join-Path $dir "$ts-$slug-$counter.md"
        }
        $sender = Get-DefaultOwner -CliName $CliName
        $autoFlag = Get-AutoFlagFromActor -Actor $RecipientActor
        $content = @(
            "# $Title",
            "Status: OPEN",
            "Sender: $sender",
            "Recipient: $RecipientActor",
            "Owner: $RecipientActor",
            "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
            "Auto: $autoFlag",
            "Risk: B",
            "ReviewOf: $base"
            ""
        ) + $BodyLines
        [System.IO.File]::WriteAllLines($path, $content)
        Write-Host "-- emitted next-stage handoff: $(Split-Path $path -Leaf) -> to-$recipientQueue/$SubDir/ --" -ForegroundColor Cyan
    }

    $validQueues = @('claude','kimi','kiro','opencode')

    $reviewBy = Read-HandoffField -HandoffPath $donePath -FieldName 'ReviewBy'
    if ($reviewBy) {
        $reviewActor = Resolve-ActorIdentity -Actor $reviewBy
        $reviewQueue = Get-QueueNameFromActor -Actor $reviewActor
        if ($validQueues -contains $reviewQueue) {
            Write-Handoff -RecipientActor $reviewActor -SubDir 'review' -Title "Review: $slug" -BodyLines @(
                "## Goal",
                "Review the completed work from $base and verify it meets the spec.",
                "",
                "## Original handoff",
                "- File: .ai/handoffs/to-$CliName/done/$base",
                "",
                "## Verification",
                "- [ ] Read the original handoff and the touched files.",
                "- [ ] Run any verification steps listed in the original handoff.",
                "- [ ] If approved, set Status to DONE and move this file to to-$reviewQueue/done/.",
                "- [ ] If rejected, set Status to BLOCKED, append a ## Blocker section, and move this file back to the original executor's open/ queue.",
                ""
            )
        }
    }

    $finalReview = Read-HandoffField -HandoffPath $donePath -FieldName 'FinalReview'
    if ($finalReview) {
        $finalActor = Resolve-ActorIdentity -Actor $finalReview
        $finalQueue = Get-QueueNameFromActor -Actor $finalActor
        if ($validQueues -contains $finalQueue) {
            Write-Handoff -RecipientActor $finalActor -SubDir 'review' -Title "Final review: $slug" -BodyLines @(
                "## Goal",
                "Final review of the work from $base before release/deploy.",
                "",
                "## Original handoff",
                "- File: .ai/handoffs/to-$CliName/done/$base",
                "",
                "## Verification",
                "- [ ] Confirm peer review passed (if applicable).",
                "- [ ] Confirm the work is safe to release/deploy.",
                "- [ ] If approved, set Status to DONE and move this file to to-$finalQueue/done/.",
                "- [ ] If rejected, set Status to BLOCKED, append a ## Blocker section, and move this file back to the appropriate executor's open/ queue.",
                ""
            )
        }
    }

    $deploy = Read-HandoffField -HandoffPath $donePath -FieldName 'Deploy'
    if ($deploy -and $deploy.Trim().ToLower() -eq 'yes') {
        Write-Handoff -RecipientActor 'opencode-auto' -SubDir 'open' -Title "Deploy: $slug" -BodyLines @(
            "## Goal",
            "Deploy the work from $base to the target environment.",
            "",
            "## Original handoff",
            "- File: .ai/handoffs/to-$CliName/done/$base",
            "",
            "## Steps",
            "1. Verify the deployment target and method from the original handoff.",
            "2. Execute the deploy.",
            "3. Verify the deploy succeeded.",
            "",
            "## When complete",
            "Set Status to DONE and move this file to to-opencode/done/.",
            ""
        )
    }

    $next = Read-HandoffField -HandoffPath $donePath -FieldName 'Next'
    if ($next) {
        foreach ($raw in $next.Split(',')) {
            $nextActor = Resolve-ActorIdentity -Actor $raw.Trim()
            $nextQueue = Get-QueueNameFromActor -Actor $nextActor
            if ($validQueues -contains $nextQueue) {
                Write-Handoff -RecipientActor $nextActor -SubDir 'open' -Title "Next: $slug" -BodyLines @(
                    "## Goal",
                    "Continue the chain from $base.",
                    "",
                    "## Original handoff",
                    "- File: .ai/handoffs/to-$CliName/done/$base",
                    "",
                    "## When complete",
                    "Set Status to DONE and move this file to to-$nextQueue/done/.",
                    ""
                )
            }
        }
    }
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

# -- Pane liveness heartbeat sidecar (the fleet dead-man's switch) --
#
# Written once per poll cycle by the supervisor loop: .ai/.heartbeat-<cli>.json
# carrying cli/pid/host/ts plus the current handoff leaf or 'idle'. Atomic
# temp + rename, byte-for-byte the Write-Claim pattern (BOM-less UTF8). This is
# the ONLY liveness signal that lives outside the pane itself: .ai/tools/
# fleet-health.sh reads it and flags STALL when the file is missing or older
# than the SAME 15-minute staleness window the claim-locks already use
# ($script:ProjectClaimStaleMinutes) — one shared freshness policy, not a
# second one. A pane that stops cycling (dead, or hung inside a single long
# CLI invocation) stops refreshing ts — and that IS the alert.
function Get-HeartbeatPath {
    param([string]$ProjectDir, [string]$CliName)
    return (Join-Path $ProjectDir ".ai/.heartbeat-$CliName.json")
}

function Write-Heartbeat {
    param([string]$ProjectDir, [string]$CliName, [int]$MyPid, [string]$CurrentHandoff = 'idle')
    $p = Get-HeartbeatPath -ProjectDir $ProjectDir -CliName $CliName
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{
        project = (Split-Path -Leaf $ProjectDir)
        cli     = $CliName
        pid     = $MyPid
        host    = [System.Net.Dns]::GetHostName()
        ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        handoff = $CurrentHandoff
    }
    $tmp = "$p.tmp.$MyPid"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    Move-Item -Path $tmp -Destination $p -Force
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
    # Six-actor model: the auto pane is the default owner for every dispatchable
    # CLI. Cockpit ownership is explicit only (claim-handoff.sh / Auto: no).
    switch ($CliName) {
        'claude'   { return 'claude-auto' }
        'kimi'     { return 'kimai-auto' }
        'kiro'     { return 'kiro-auto' }
        'opencode' { return 'opencode-auto' }
        default    { throw "Unknown CLI: $CliName" }
    }
}

# -- Prompts --

function Get-InitialPrompt {
    param([string]$RelPath)
    return "Process the open handoff at $RelPath per the protocol in .ai/handoffs/README.md. Execute the steps, write an activity-log entry, update the handoff Status, and report."
}

function Get-ContinuePrompt {
    param([string]$RelPath)
    return "Continue processing the open handoff at $RelPath. You previously hit a step or tool cap before completing it; resume where you left off, finish the remaining steps, write an activity-log entry, set the handoff Status to DONE, and move it to the matching done/ folder."
}

# -- RUN + DECIDE core (the unit-tested heart) --
#
# Invoke the CLI on a handoff, then auto-continue while it stays OPEN, up to
# MaxContinues. Returns @{ Result = 'DONE'|'MAXED'|'WORKTREE_FAIL'; Continues = <n>; Invocations = <n> }.
# 'DONE'          -> handoff moved to done/ (release claim, back to IDLE).
# 'MAXED'         -> hit the continue cap still OPEN (ALERT, leave for the human).
# 'WORKTREE_FAIL' -> the CLI's worktree/branch could not be established; the CLI
#                    was NEVER invoked (Invocations = 0) and — critically — was
#                    NEVER run in $ProjectDir as a fallback. Fail loudly, not
#                    silently degrade (this is the entire point of this fix; see
#                    the file-header note and the handoff for this change).
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

    # Worktree-per-CLI: resolve (create-or-reuse) this CLI's own worktree BEFORE
    # any CLI invocation. Refuse — do not invoke, do not fall back to
    # $ProjectDir — if it cannot be established.
    Write-Host "-- ensuring $CliName worktree --" -ForegroundColor DarkCyan
    $wtPath = & $script:GetCliWorktreePath $ProjectDir $CliName
    if (-not $wtPath) {
        Write-Host "== FAIL [$CliName] $rel - could not establish worktree; refusing to fall back to the primary checkout ==" -ForegroundColor Red
        return @{ Result = 'WORKTREE_FAIL'; Continues = 0; Invocations = 0 }
    }

    # Snapshot-copy the canonical .ai/ into the worktree (ADR-0016). The executor
    # sees ordinary files, not a junction, eliminating the reverse-write hazard.
    if (-not (& $script:SnapshotAi $ProjectDir $wtPath)) {
        Write-Host "== FAIL [$CliName] $rel - could not snapshot canonical .ai/ into worktree ==" -ForegroundColor Red
        return @{ Result = 'WORKTREE_FAIL'; Continues = 0; Invocations = 0 }
    }
    $snapshotOk = $true

    # Use try/finally so a successfully-started run always syncs the worktree
    # .ai/ copy back (or removes it) before we return. Do NOT sync back when the
    # dispatch failed before the CLI was ever invoked: a failed snapshot/branch-cut
    # leaves the worktree .ai/ in an indeterminate state, and syncing it back can
    # wipe legitimate canonical state written by a concurrent headless dispatch.
    $continues = 0
    $invocations = 0
    try {
        # Declared-base branch cut: never leave the worktree on ambient HEAD.
        $slug = Get-HandoffBasename -HandoffPath $HandoffPath
        $base = & $script:GetDeclaredBase -HandoffPath $HandoffPath
        if (-not $base) {
            Write-Host "== FAIL [$CliName] $rel - could not resolve a declared base ==" -ForegroundColor Red
            return @{ Result = 'WORKTREE_FAIL'; Continues = 0; Invocations = 0 }
        }
        if (-not (& $script:EnsureDeclaredBaseBranch $wtPath $CliName $slug $base)) {
            Write-Host "== FAIL [$CliName] $rel - could not establish declared-base branch (base=$base) ==" -ForegroundColor Red
            return @{ Result = 'WORKTREE_FAIL'; Continues = 0; Invocations = 0 }
        }
        Write-Host "-- worktree: $wtPath  branch: exec/$CliName/$slug (base: $base) --" -ForegroundColor DarkCyan

        while ($true) {
            $prompt = if ($continues -eq 0) { Get-InitialPrompt -RelPath $rel } else { Get-ContinuePrompt -RelPath $rel }
            if ($continues -eq 0) {
                Write-Host "== RUN  [$CliName] $rel ==" -ForegroundColor Cyan
            } else {
                Write-Host "== auto-continuing ($continues/$MaxContinues) [$CliName] $rel ==" -ForegroundColor Yellow
            }
            Write-Host "-- launching $CliName (streaming output below) --" -ForegroundColor DarkCyan
            # Absorb the returned exit code (needed for heartbeat L2 outcome
            # classification). The CLI's stdout/stderr is already streamed live to the
            # pane inside $script:InvokeCli (Out-Host / Tee-Object). $wtPath (NOT
            # $ProjectDir): the CLI runs in ITS OWN worktree — the fix.
            # Keep the fleet heartbeat fresh while the CLI blocks; long handoffs can
            # exceed the supervisor's stale threshold and a stale heartbeat triggers a
            # duplicate-pane relaunch.
            $hbJob = Start-FleetHeartbeatJob -ProjectDir $ProjectDir -CliName $CliName -State 'running'
            $invokeTimeout = Get-CliInvocationTimeoutSeconds -CliName $CliName
            try {
                $cliExit = & $script:InvokeCli $CliName $prompt $wtPath $invokeTimeout
            } finally {
                Stop-FleetHeartbeatJob
            }
            $script:LastCliExitCode = [int](@($cliExit)[-1])
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
    } finally {
        if ($snapshotOk -and $invocations -gt 0) {
            & $script:SyncBackAi $ProjectDir $wtPath
        }
    }
}

# -- Supervisor loop (IDLE -> CLAIM -> RUN/DECIDE), interruptible --

# Idle-heartbeat throttle (F1): a healthy idle pane was previously
# indistinguishable from a dead one - it printed its banner once and went
# silent forever. The heartbeat is TIME-based, not every-Nth-poll: the cadence
# stays stable no matter what PollSeconds is configured to, and emitting on the
# very first idle poll proves liveness immediately at startup. 60s is visible
# enough to glance at, quiet enough not to drown the pane (vs 6x the noise of
# an every-poll line at the default 10s poll).
$script:IdleHeartbeatSeconds = 60

# Emit the idle heartbeat if due: always on the first idle poll, then at most
# once per $script:IdleHeartbeatSeconds. Updates $LastEmitted (a [ref]) when it
# emits. Returns $true if it emitted, $false if throttled - the return value is
# the testable surface (Write-Host itself goes to the host, not the pipeline).
function Write-IdleHeartbeat {
    param([string]$CliName, [ref]$LastEmitted)
    $now = Get-Date
    if ($null -eq $LastEmitted.Value -or ($now - $LastEmitted.Value).TotalSeconds -ge $script:IdleHeartbeatSeconds) {
        Write-Host "-- idle [$CliName] no qualifying handoff ($($now.ToString('HH:mm:ss'))) --" -ForegroundColor DarkGray
        $LastEmitted.Value = $now
        return $true
    }
    return $false
}

function Assert-WorktreeFresh {
    <#
    .SYNOPSIS
        Fail-fast guard: refuse to start a pane whose worktree branch is behind
        the resolved default branch. A stale branch can cause the executor to
        base its work on old state; while ADR-0016 snapshot-copy removed the
        junction reverse-write hazard, freshness still matters.
    #>
    param([string]$ProjectDir)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $ProjectDir
    try {
        $base = Resolve-DefaultBase -ProjectDir $ProjectDir
        if (-not $base) {
            Write-Host "  STALE: could not resolve the default base branch for '$ProjectDir'." -ForegroundColor Red
            Write-Host "  Refusing to start: unresolvable base means we cannot verify the worktree is fresh." -ForegroundColor Red
            return $false
        }
        $behind = git rev-list --count "HEAD..$base" 2>$null
        if ($behind -match '^\d+$') {
            $behindN = [int]$behind
            if ($behindN -gt 0) {
                $branch = git branch --show-current 2>$null
                Write-Host "  STALE: worktree branch '$branch' is $behindN commits behind $base." -ForegroundColor Red
                Write-Host "  Refusing to start: a stale branch bases executor work on old state." -ForegroundColor Red
                Write-Host "  Fix: stop this pane, rebase the branch onto $base, recreate the worktree, then restart." -ForegroundColor Yellow
                return $false
            }
        }
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEAP
    }
    return $true
}

# -- Persistent heartbeat (L1 liveness + L2 capability) for the fleet supervisor --
#
# The fleet supervisor (fleet-supervisor.ps1) runs as an OS-level scheduled task,
# ABOVE run-pane-supervised.ps1. It needs a PERSISTENT liveness signal that
# survives terminal death: a heartbeat FILE with a recent mtime, written by each
# runner on every poll. Console-only heartbeats (Write-IdleHeartbeat) prove a
# live pane is alive but say nothing when the pane is GONE.
#
# Two health levels:
#   L1 (liveness):   heartbeat file exists AND ts is fresh (within stale threshold).
#   L2 (capability): last_invoke_outcome is not a persistent auth/quota failure.
#     A live process that cannot call its LLM (dead API key, exhausted quota) is
#     indistinguishable from healthy by L1 alone. L2 records the outcome of the
#     runner's last real CLI invocation so the supervisor can tell "idle with an
#     empty queue" from "alive but brain-dead".
#
# Location: %LOCALAPPDATA%\rwn-auto\fleet-heartbeat\<project>__<cli>.json
#   - Outside the repo: .ai/ is junctioned across worktrees and shared by every
#     pane; per-poll churn there pollutes the coordination plane and git.
#   - Per-project-per-CLI: the supervisor checks each pane independently.
#   - JSON, atomically written (temp + rename, like Write-Claim).

$script:FleetHeartbeatStaleSeconds = 90   # 3x default 10s poll + generous margin
$script:CliOutputCapturePath = $null       # set by Start-PaneRunner; $null disables tee
$script:LastCliExitCode = 0                # set by Invoke-HandoffRun after each CLI invocation

# Per-CLI invocation timeout (seconds). 0 = no timeout (backward compatible).
# The pane runner blocks synchronously on the CLI; a CLI that enters an
# interactive loop (e.g. opencode run --auto) would stall polling forever.
# A timeout kills the child tree, returns a sentinel exit code, and lets
# the continue mechanism retry.
$script:CliInvocationTimeoutSeconds = 0
$script:CliInvocationTimeoutDefaults = @{
    # opencode run --auto does not self-exit after one prompt; cap it so the
    # pane can poll again. The continue prompt resumes unfinished work.
    'opencode' = 600
    # Claude, Kimi and Kiro headless commands exit reliably after the prompt.
    'claude'   = 0
    'kimi'     = 0
    'kiro'     = 0
}
$script:CliTimeoutExitCode = 124

function Get-CliInvocationTimeoutSeconds {
    param([string]$CliName)
    if ($script:CliInvocationTimeoutSeconds -gt 0) { return $script:CliInvocationTimeoutSeconds }
    $def = $script:CliInvocationTimeoutDefaults[$CliName]
    if ($def -and $def -gt 0) { return $def }
    return 0
}

function Stop-CliProcessTree {
    param([int]$RootPid)
    # Recursively terminate descendant processes first so children are not
    # left orphaned when the parent dies.
    try {
        Get-WmiObject Win32_Process -Filter "ParentProcessId=$RootPid" -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-CliProcessTree -RootPid $_.ProcessId
        }
        Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Get-FleetHeartbeatDir {
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
    return (Join-Path $localAppData 'rwn-auto\fleet-heartbeat')
}

function Get-FleetHeartbeatPath {
    param([string]$ProjectDir, [string]$CliName)
    $proj = Split-Path -Leaf $ProjectDir
    return (Join-Path (Get-FleetHeartbeatDir) "${proj}__${CliName}.json")
}

# Write (or update) the persistent heartbeat file. Fail-open: a heartbeat write
# error must never break the pane loop. Atomic (temp + rename, BOM-less UTF-8).
function Write-FleetHeartbeat {
    param(
        [string]$ProjectDir,
        [string]$CliName,
        [string]$State = 'idle',
        [string]$LastInvokeOutcome = '',
        [string]$LastInvokeTs = '',
        [int]$ConsecutiveFailures = 0
    )
    try {
        $p = Get-FleetHeartbeatPath -ProjectDir $ProjectDir -CliName $CliName
        $dir = Split-Path -Parent $p
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $obj = [ordered]@{
            project              = (Split-Path -Leaf $ProjectDir)
            cli                  = $CliName
            pid                  = $PID
            host                 = [System.Net.Dns]::GetHostName()
            ts                   = $now
            state                = $State
            project_dir          = $ProjectDir
            last_invoke_ts       = $LastInvokeTs
            last_invoke_outcome  = $LastInvokeOutcome
            consecutive_failures = $ConsecutiveFailures
        }
        $tmp = "$p.tmp.$PID"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        Move-Item -Path $tmp -Destination $p -Force
    } catch { }
}

# Read a heartbeat file. Returns the parsed object, or $null if missing/unparseable.
function Read-FleetHeartbeat {
    param([string]$HeartbeatPath)
    if (-not (Test-Path $HeartbeatPath)) { return $null }
    try { return (Get-Content -Path $HeartbeatPath -Raw | ConvertFrom-Json) } catch { return $null }
}

# Background heartbeat job: keeps the fleet heartbeat fresh while a long-running
# CLI invocation is in progress. The pane-runner main thread blocks on the CLI,
# so without this the heartbeat timestamp would age past the supervisor's stale
# threshold and trigger a false-positive relaunch.
$script:FleetHeartbeatJob = $null

function Start-FleetHeartbeatJob {
    param(
        [string]$ProjectDir,
        [string]$CliName,
        [string]$State = 'running',
        [string]$LastInvokeOutcome = '',
        [string]$LastInvokeTs = '',
        [int]$ConsecutiveFailures = 0
    )
    try {
        Stop-FleetHeartbeatJob
        $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
        $hbDir = Join-Path $localAppData 'rwn-auto\fleet-heartbeat'
        $projName = Split-Path -Leaf $ProjectDir
        $hbPath = Join-Path $hbDir "${projName}__${CliName}.json"
        $jobScript = {
            param($HbPath, $ProjectDir, $CliName, $State, $LastInvokeOutcome, $LastInvokeTs, $ConsecutiveFailures)
            try {
                while ($true) {
                    try {
                        $dir = Split-Path -Parent $HbPath
                        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                        $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                        $obj = [ordered]@{
                            project              = (Split-Path -Leaf $ProjectDir)
                            cli                  = $CliName
                            pid                  = $PID
                            host                 = [System.Net.Dns]::GetHostName()
                            ts                   = $now
                            state                = $State
                            project_dir          = $ProjectDir
                            last_invoke_ts       = $LastInvokeTs
                            last_invoke_outcome  = $LastInvokeOutcome
                            consecutive_failures = $ConsecutiveFailures
                        }
                        $tmp = "$HbPath.tmp.$PID"
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
                        [System.IO.File]::WriteAllBytes($tmp, $bytes)
                        Move-Item -Path $tmp -Destination $HbPath -Force
                    } catch { }
                    Start-Sleep -Seconds 30
                }
            } catch { }
        }
        $script:FleetHeartbeatJob = Start-Job -ScriptBlock $jobScript -ArgumentList `
            $hbPath, $ProjectDir, $CliName, $State, $LastInvokeOutcome, $LastInvokeTs, $ConsecutiveFailures
        return $script:FleetHeartbeatJob
    } catch { return $null }
}

function Stop-FleetHeartbeatJob {
    if ($script:FleetHeartbeatJob) {
        try {
            Stop-Job $script:FleetHeartbeatJob -ErrorAction SilentlyContinue
            Remove-Job $script:FleetHeartbeatJob -ErrorAction SilentlyContinue
        } catch { }
        $script:FleetHeartbeatJob = $null
    }
}

# Classify CLI output tail + exit code into an L2 outcome. Auth/quota failures
# must be distinguishable from "idle with an empty queue" — today they look
# identical (both produce a live process that does no work). Returns one of:
#   success | auth_failure | quota_exceeded | error
function Get-CliOutcomeClassification {
    param([int]$ExitCode, [string]$OutputTail = '')
    if ($ExitCode -eq 0) { return 'success' }
    if ($OutputTail -match '(?i)(unauthorized|401\s|authentication\s+(failed|error)|invalid\s+(api\s+)?key|login\s+required|not\s+logged\s+in)') {
        return 'auth_failure'
    }
    if ($OutputTail -match '(?i)(quota\s+(exceeded|exhausted)|rate[\s_-]limit|429\s|too\s+many\s+requests|usage\s+limit)') {
        return 'quota_exceeded'
    }
    return 'error'
}

# Read the tail of the CLI output capture file and classify the outcome.
# Returns 'success' when no capture file exists (tests, or tee disabled).
function Get-LastCliOutcome {
    param([int]$ExitCode = 0)
    if (-not $script:CliOutputCapturePath -or -not (Test-Path $script:CliOutputCapturePath)) {
        return (Get-CliOutcomeClassification -ExitCode $ExitCode)
    }
    try {
        $tail = Get-Content -Path $script:CliOutputCapturePath -Tail 50 -Raw -ErrorAction SilentlyContinue
        return (Get-CliOutcomeClassification -ExitCode $ExitCode -OutputTail $tail)
    } catch {
        return (Get-CliOutcomeClassification -ExitCode $ExitCode)
    }
}

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

    # Fail-fast: stale branch bases executor work on old state.
    # Exit cleanly (0) so the supervisor does not endlessly respawn a stale pane.
    if (-not (Assert-WorktreeFresh -ProjectDir $ProjectDir)) {
        return
    }

    # Intent flag for the exit-code contract: set true on a deliberate stop (Ctrl-C
    # caught, or the 'q' quit key) so the outer finally exits 0 (do-not-respawn).
    # Left false on a crash / escaped exception -> exit non-zero (supervisor respawns).
    $stopIntent = $false

    # Idle-heartbeat state (F1): $null = never emitted -> the first idle poll
    # emits immediately, then Write-IdleHeartbeat throttles by wall-clock.
    $lastHeartbeat = $null

    # Persistent heartbeat state (L1 + L2 for the fleet supervisor).
    # The capture file tees CLI output so Get-LastCliOutcome can classify
    # auth/quota failures. State variables persist across loop iterations.
    $script:CliOutputCapturePath = Join-Path ([System.IO.Path]::GetTempPath()) "fleet-cli-capture-$Cli-$PID.log"
    $hbLastOutcome = ''
    $hbLastInvokeTs = ''
    $hbConsecFailures = 0

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
                # Liveness heartbeat: exactly once per poll cycle, before any
                # skip/continue branch, so the sidecar always reflects the last
                # cycle that RAN. Fail-open: a heartbeat write error must never
                # break the pane loop (same contract as Send-FleetNotification).
                try {
                    Write-Heartbeat -ProjectDir $ProjectDir -CliName $Cli -MyPid $myPid `
                        -CurrentHandoff $(if ($null -eq $handoff) { 'idle' } else { Split-Path -Leaf $handoff })
                } catch {}
                if ($null -eq $handoff) {
                    Write-IdleHeartbeat -CliName $Cli -LastEmitted ([ref]$lastHeartbeat) | Out-Null
                    # Persistent heartbeat: every idle poll proves L1 liveness to the
                    # fleet supervisor. Carries the last known L2 outcome forward so
                    # "idle after a successful run" reads differently from "idle after
                    # repeated auth failures".
                    Write-FleetHeartbeat -ProjectDir $ProjectDir -CliName $Cli -State 'idle' `
                        -LastInvokeOutcome $hbLastOutcome -LastInvokeTs $hbLastInvokeTs `
                        -ConsecutiveFailures $hbConsecFailures
                    Start-Sleep -Seconds $PollSeconds
                    continue
                }

                if (Test-ClaimBlocks -ProjectDir $ProjectDir -CliName $Cli -MyPid $myPid) {
                    # Another live pane already owns this project - skip, re-poll.
                    # Still write a heartbeat: this pane IS alive (it just polled),
                    # it's just not the owner. Without this the supervisor would
                    # see a stale heartbeat and wrongly conclude the pane is dead.
                    Write-FleetHeartbeat -ProjectDir $ProjectDir -CliName $Cli -State 'idle' `
                        -LastInvokeOutcome $hbLastOutcome -LastInvokeTs $hbLastInvokeTs `
                        -ConsecutiveFailures $hbConsecFailures
                    Start-Sleep -Seconds $PollSeconds
                    continue
                }

                # Per-handoff claim (ADR-0009 section 3): if another consumer holds a
                # live claim on THIS handoff, skip just this one and re-poll.
                if (-not (Claim-Handoff -Recipient $Cli -HandoffPath $handoff -Owner $Owner)) {
                    $held = Test-HandoffClaimed -Recipient $Cli -HandoffPath $handoff
                    $by = if ($held -and $held.owner) { $held.owner } else { 'another consumer' }
                    Write-Host "-- skip $(Split-Path -Leaf $handoff) (claimed by $by) --" -ForegroundColor DarkGray
                    Write-FleetHeartbeat -ProjectDir $ProjectDir -CliName $Cli -State 'idle' `
                        -LastInvokeOutcome $hbLastOutcome -LastInvokeTs $hbLastInvokeTs `
                        -ConsecutiveFailures $hbConsecFailures
                    Start-Sleep -Seconds $PollSeconds
                    continue
                }

                # idle->busy transition, made visible (F1): without this line the
                # pane jumps from heartbeat silence straight into streamed CLI
                # output. Placed AFTER the claim is won so it prints only when
                # THIS pane actually starts work, not on claim-contention skips.
                Write-Host "-- picked up $(Split-Path -Leaf $handoff) --" -ForegroundColor Gray

                Write-Claim -ProjectDir $ProjectDir -CliName $Cli -MyPid $myPid
                $hbase = Get-HandoffBasename -HandoffPath $handoff
                # Persistent heartbeat: state=running so the supervisor knows this
                # pane is actively working (not idle, not dead).
                Write-FleetHeartbeat -ProjectDir $ProjectDir -CliName $Cli -State 'running' `
                    -LastInvokeOutcome $hbLastOutcome -LastInvokeTs $hbLastInvokeTs `
                    -ConsecutiveFailures $hbConsecFailures
                # PICKED notify (fail-open: a notify error must not break the loop).
                try { Send-FleetNotification -Kind picked -Project $proj -Handoff $hbase -Cli $Cli -Owner $Owner | Out-Null } catch {}
                try {
                    $runResult = Invoke-HandoffRun -ProjectDir $ProjectDir -CliName $Cli -HandoffPath $handoff -MaxContinues $MaxContinues
                    # Defensive: if the run leaked extra pipeline objects, the decision
                    # record is the last one.
                    $runResult = @($runResult)[-1]
                    # Update L2 capability state from the CLI invocation outcome.
                    # Get-LastCliOutcome reads the tee'd output capture file and
                    # classifies auth/quota/error. $script:LastCliExitCode was set
                    # by Invoke-HandoffRun after the final invocation.
                    $hbLastOutcome = Get-LastCliOutcome -ExitCode $script:LastCliExitCode
                    $hbLastInvokeTs = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    if ($hbLastOutcome -in @('auth_failure', 'quota_exceeded', 'error')) {
                        $hbConsecFailures++
                    } else {
                        $hbConsecFailures = 0
                    }
                    # Write heartbeat with the fresh outcome so the supervisor sees
                    # it immediately (not waiting for the next idle poll).
                    Write-FleetHeartbeat -ProjectDir $ProjectDir -CliName $Cli -State 'idle' `
                        -LastInvokeOutcome $hbLastOutcome -LastInvokeTs $hbLastInvokeTs `
                        -ConsecutiveFailures $hbConsecFailures
                    if ($runResult -and $runResult.Result -eq 'DONE') {
                        Clear-HandoffAttempts -Recipient $Cli -HandoffPath $handoff
                        # DONE notify (fail-open).
                        try { Send-FleetNotification -Kind done -Project $proj -Handoff $hbase -Cli $Cli -Owner $Owner | Out-Null } catch {}
                        # Review / deploy pipeline: emit the next-stage handoff if the
                        # completed handoff requests one (ReviewBy, FinalReview, Deploy).
                        try { Emit-NextStageHandoff -ProjectDir $ProjectDir -CliName $Cli -HandoffPath $handoff } catch {}
                    } else {
                        # MAXED (still OPEN after the continue cap) or WORKTREE_FAIL
                        # (worktree/branch could not be established — the CLI was
                        # never invoked, per Invoke-HandoffRun's fail-loud contract)
                        # both count as a failed attempt; quarantine once the
                        # threshold is reached so a persistently-broken worktree
                        # cannot ALERT-spam the pane forever.
                        $errText = if ($runResult -and $runResult.Result -eq 'WORKTREE_FAIL') {
                            'WORKTREE_FAIL (worktree/branch setup failed — CLI never invoked, no fallback to primary checkout)'
                        } else {
                            'MAXED (still OPEN after continue cap)'
                        }
                        $q = Add-HandoffAttempt -Recipient $Cli -HandoffPath $handoff -ErrorText $errText
                        # ALERT notify on MAXED/WORKTREE_FAIL or a new quarantine (fail-open).
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
        # Clean up the CLI output capture file (temp, per-PID).
        if ($script:CliOutputCapturePath -and (Test-Path $script:CliOutputCapturePath)) {
            Remove-Item -Path $script:CliOutputCapturePath -Force -ErrorAction SilentlyContinue
        }
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
