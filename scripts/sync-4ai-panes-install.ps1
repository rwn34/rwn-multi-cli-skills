<#
================================================================================
 sync-4ai-panes-install.ps1  -  allowlist-driven install sync
================================================================================
 Keeps the executable install (default ~/.rwn-auto/rwn-4AI-panes) in lockstep
 with the canonical source tree tools/4ai-panes/ by copying ONLY the twelve tool
 files named in the allowlist below. It never touches the embedded framework
 (.ai/ .claude/ .git/ ...) or runtime state (.4pane-history, *.log, ...) that
 also live in the install dir. See docs/specs/4ai-panes-install-sync.md.

 Contract:
   exit 0  - synced, already in sync (no-op), target absent (graceful skip),
             or REFUSED by the provenance guard (refusal is CORRECT behavior in
             a worktree / off-main checkout, not an error - see below).
   exit 1  - a .ps1 source file failed the syntax gate, OR a copy was attempted
             but post-copy hash verification failed, OR an allowlisted file is
             missing from the source tree. Loud stderr warn.

 PROVENANCE GUARD (why a worktree must not deploy):
   The git hooks fire this sync from whatever worktree ran the merge/checkout/
   commit, on whatever branch. Without a guard, unmerged branch code silently
   reaches the owner's live install (the 2026-07-13 incident: a worktree hook
   fired at ~05:45 deployed branch code over the live launcher). So before any
   file work the sync requires (a) the source to be the PRIMARY checkout
   (git-dir == git-common-dir; in a linked worktree git-dir is
   <common>/worktrees/<name>) and (b) HEAD on branch 'main' (detached HEAD
   refuses) - only merged main code may deploy. Unverifiable provenance (git
   unavailable / source not a repo) fails CLOSED. Refusal prints a one-liner,
   still writes its install-sync.log line, and exits 0 - exit 1 stays reserved
   for genuine failures because the hooks paint non-zero as "sync REPORTED
   ERRORS". Override: -Force or SYNC_FORCE=1 (prints FORCED, logs
   provenance=forced). Every run's log line carries branch=<b> primary=<yes|no>.

 Copy is BYTE-EXACT ([IO.File]::Copy) - no Get-Content/Set-Content round-trip -
 so committed EOL is preserved and icon.ico (binary) stays intact. Each drifted
 file is written to a temp path in the target dir, hash-verified against source,
 then atomically moved into place; a failed verify leaves the target untouched.

 SYNTAX GATE (why hash-verify is not enough):
   The hash check proves FIDELITY - "the bytes that landed in the install are the
   bytes that were in the source". It says nothing about VALIDITY - a Selector.ps1
   with an unbalanced brace hashes perfectly and deploys straight into the owner's
   live launcher, where it fails at runtime. So before any .ps1 is moved into the
   target we PARSE it ([Parser]::ParseFile) and refuse to deploy that file if it
   has syntax errors: the previously-deployed known-good copy stays untouched, the
   failure is printed loudly (file + first error + line), and the script exits 1 so
   the calling git hook surfaces it. Non-.ps1 files are unaffected (hash-verify
   only). The gate runs BEFORE the atomic move, so the target is never half-updated.

 Called directly by a human (with -DryRun to preview) or by the bash git hooks
 scripts/git-hooks/post-merge and post-checkout when tools/4ai-panes/** changes.
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Target,
    [switch]$DryRun,
    [switch]$Quiet,
    [switch]$Verify,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Authoritative tool-file allowlist -------------------------------------
# The ONLY place the "which files are tool files" knowledge lives. Adding a
# thirteenth tool file is a one-line edit here.
$Allowlist = @(
    'Launch4Panes.ps1',
    'Launch4Panes.vbs',
    'Selector.ps1',
    'fleet-clis.ps1',
    'notify.ps1',
    'pane-runner.ps1',
    'run-pane-supervised.ps1',
    'restart-pane.ps1',
    'fleet-supervisor.ps1',
    'install-fleet-supervisor.ps1',
    'uninstall-fleet-supervisor.ps1',
    'test-pane-runner.ps1',
    'test-selector-e2e.ps1',
    'test-fleet-supervisor.ps1',
    'test-pane-supervisor.ps1',
    'README.md',
    'icon.ico'
)

# --- Resolve source and target ---------------------------------------------
# Script lives in <repo>/scripts/, so source = <repo>/tools/4ai-panes.
$SourceDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\4ai-panes'
$SourceDir = [IO.Path]::GetFullPath($SourceDir)

if (-not $Target -or $Target -eq '') {
    if ($env:RWN_AUTO_INSTALL_DIR) {
        $Target = $env:RWN_AUTO_INSTALL_DIR
    } else {
        $Target = Join-Path $HOME '.rwn-auto\rwn-4AI-panes'
    }
}
$Target = [IO.Path]::GetFullPath($Target)

function Write-Line {
    param([string]$Text)
    if (-not $Quiet) { Write-Host $Text }
}

function Get-Hash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# Parse a .ps1 with the PowerShell language parser. Returns $null when the file
# is syntactically valid, or a "message (line N)" string describing the FIRST
# syntax error. This is the validity half of the gate; Get-Hash is the fidelity
# half. A file that fails here must never reach the target.
function Test-Ps1Syntax {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $first = $errors[0]
        return "$($first.Message) (line $($first.Extent.StartLineNumber))"
    }
    return $null
}

# Append one line per run to the sync log (best-effort; never fatal). The
# provenance tokens ride on EVERY line so the next post-mortem is trivial.
# Reads the script-scope $commit/$branch/$primaryStr/$forced set by the guard.
function Write-SyncLog {
    param([string]$Result, [string[]]$Actions)
    $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $prov = if ($forced) { ' provenance=forced' } else { '' }
    $logLine = "[$stamp] commit=$commit branch=$branch primary=$primaryStr result=$Result$prov"
    if ($Actions.Count -gt 0) { $logLine += ' | ' + ($Actions -join ' ') }
    try {
        $logPath = Join-Path $Target 'install-sync.log'
        Add-Content -LiteralPath $logPath -Value $logLine -Encoding ascii
    } catch {
        Write-Warning "could not write install-sync.log: $($_.Exception.Message)"
    }
}

# --- Provenance guard: only primary-checkout main code may deploy ---------
# One choke point covering the hooks AND manual/agent invocation. Refusal is
# CORRECT behavior, not an error: print one clear line, write the log line,
# exit 0 (exit 1 is reserved for genuine failures - the hooks treat non-zero as
# "sync REPORTED ERRORS" and would spam that banner on every legitimate branch
# checkout in every worktree).
$commit = 'n/a'
$branch = 'n/a'
$toplevel = 'n/a'
$isPrimary = $false
$primaryStr = 'no'
$forced = [bool]$Force -or ($env:SYNC_FORCE -eq '1')

$gitOk = $false
# EAP=Stop + a native command writing stderr (e.g. symbolic-ref's "not a
# symbolic ref" on a detached HEAD) throws even through 2>$null on PS 5.1 -
# probe under Continue and gate each step on $LASTEXITCODE instead.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $gitDirOut = & git -C $SourceDir rev-parse --path-format=absolute --git-dir 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitDirOut) {
        $commonOut = & git -C $SourceDir rev-parse --path-format=absolute --git-common-dir 2>$null
        if ($LASTEXITCODE -eq 0 -and $commonOut) {
            $gitOk = $true
            # Primary checkout: git-dir IS the common dir. Linked worktree:
            # git-dir is <common>/worktrees/<name>. The canonical test - no
            # path pattern-matching. (PowerShell -eq on strings is
            # case-insensitive, right for Windows paths; GetFullPath
            # normalizes separators.)
            $isPrimary = ([IO.Path]::GetFullPath($gitDirOut.Trim()) -eq [IO.Path]::GetFullPath($commonOut.Trim()))
            $primaryStr = if ($isPrimary) { 'yes' } else { 'no' }

            $topOut = & git -C $SourceDir rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and $topOut) { $toplevel = $topOut.Trim() }

            $c = & git -C $SourceDir rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $c) { $commit = $c.Trim() }

            # symbolic-ref fails on a detached HEAD - branch stays 'DETACHED'
            # and the branch test below refuses it.
            $b = & git -C $SourceDir symbolic-ref --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $b) { $branch = $b.Trim() } else { $branch = 'DETACHED' }
        }
    }
} catch { $gitOk = $false }
finally { $ErrorActionPreference = $prevEAP }

if ($forced) {
    Write-Line "sync-4ai-panes-install: FORCED - provenance guard overridden (-Force/SYNC_FORCE=1): toplevel=$toplevel branch=$branch primary=$primaryStr"
} elseif (-not $gitOk -or -not $isPrimary -or $branch -ne 'main') {
    Write-Line "sync-4ai-panes-install: REFUSED - not primary/main (toplevel=$toplevel branch=$branch primary=$primaryStr). Only merged main code may reach the live install. Override: -Force or SYNC_FORCE=1."
    Write-SyncLog -Result 'refused' -Actions @()
    exit 0
}

# --- Graceful skip when target absent --------------------------------------
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Line "no install at $Target, skipping"
    exit 0
}

# --- Sync each allowlisted file --------------------------------------------
$exitCode = 0
$actions = @()   # per-file tokens for the log line

Write-Line "sync-4ai-panes-install: source=$SourceDir"
Write-Line "                        target=$Target  (commit=$commit)$(if($DryRun){'  [DRY-RUN]'})"

foreach ($name in $Allowlist) {
    $src = Join-Path $SourceDir $name
    $dst = Join-Path $Target $name

    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Warning "MISSING SOURCE: allowlisted file '$name' is absent from $SourceDir - allowlist and tree have diverged; a maintainer must reconcile."
        $actions += "${name}:missing-source"
        $exitCode = 1
        continue
    }

    $srcHash = Get-Hash $src
    $dstHash = if (Test-Path -LiteralPath $dst -PathType Leaf) { Get-Hash $dst } else { $null }

    if ($dstHash -eq $srcHash) {
        Write-Line "  unchanged  $name"
        $actions += "${name}:unchanged"
        continue
    }

    $reason = if ($null -eq $dstHash) { 'missing' } else { 'drifted' }

    # --- Syntax gate: never deploy a .ps1 that does not parse -----------------
    # Runs BEFORE the temp copy / atomic move, so a broken source leaves whatever
    # is already installed (the last known-good file) completely untouched.
    if ([IO.Path]::GetExtension($name) -eq '.ps1') {
        $syntaxError = Test-Ps1Syntax $src
        if ($syntaxError) {
            Write-Warning "SYNTAX ERROR - REFUSING TO DEPLOY: $name`n    source=$src`n    first error: $syntaxError`n    Target file left UNTOUCHED (previously deployed version kept). Fix the source and re-run."
            $actions += "${name}:syntax-error"
            $exitCode = 1
            continue
        }
    }

    if ($DryRun) {
        Write-Line "  WOULD COPY $name  ($reason)"
        $actions += "${name}:would-copy($reason)"
        continue
    }

    # Copy to temp in target dir -> hash-verify temp==source -> atomic move.
    $tmp = Join-Path $Target ("$name.sync-tmp-$PID-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        [IO.File]::Copy($src, $tmp, $true)
        $tmpHash = Get-Hash $tmp
        if ($tmpHash -ne $srcHash) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            Write-Warning "VERIFY FAILED: $name - temp copy hash != source. Target left UNTOUCHED.`n    source=$srcHash`n    temp  =$tmpHash"
            $actions += "${name}:verify-fail"
            $exitCode = 1
            continue
        }
        Move-Item -LiteralPath $tmp -Destination $dst -Force
        # Confirm the file landed byte-identical.
        $finalHash = Get-Hash $dst
        if ($finalHash -ne $srcHash) {
            Write-Warning "POST-MOVE MISMATCH: $name - target hash != source after move.`n    source=$srcHash`n    target=$finalHash"
            $actions += "${name}:post-move-fail"
            $exitCode = 1
            continue
        }
        Write-Line "  copied     $name  ($reason, verify=ok)"
        $actions += "${name}:copied($reason,verify=ok)"
    } catch {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        Write-Warning "COPY ERROR: $name - $($_.Exception.Message). Target left untouched."
        $actions += "${name}:copy-error"
        $exitCode = 1
    }
}

# --- Append one line per run to the sync log -------------------------------
$result = if ($exitCode -eq 0) { if ($DryRun) { 'dry-run' } else { 'in-sync' } } else { 'ERRORS' }
Write-SyncLog -Result $result -Actions $actions

# --- Provenance sidecar for launch-time drift detection ---------------------
# Written on every successful real run so run-pane-supervised.ps1 can warn at
# launch when the live install drifts from the recorded repo's tools/4ai-panes/.
if ($exitCode -eq 0 -and -not $DryRun) {
    try {
        $provJson = [ordered]@{
            source_repo = $toplevel
            commit      = $commit
            branch      = $branch
            synced_at   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText((Join-Path $Target '.sync-provenance.json'), $provJson)
    } catch {
        Write-Warning "could not write .sync-provenance.json: $($_.Exception.Message)"
    }
}

# --- Optional post-sync verification (opt-in, never called by the hooks) ----
if ($Verify) {
    Write-Line ""
    Write-Line "sync-4ai-panes-install: -Verify - running tool tests from target"
    foreach ($testName in @('test-pane-runner.ps1', 'test-selector-e2e.ps1')) {
        $testPath = Join-Path $Target $testName
        if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
            Write-Warning "  -Verify: $testName not found in target - skipping"
            continue
        }
        Push-Location $Target
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $testPath 2>&1 | ForEach-Object { Write-Line "    | $_" }
            if ($LASTEXITCODE -eq 0) {
                Write-Line "  PASS  $testName"
            } else {
                Write-Warning "  FAIL  $testName (exit $LASTEXITCODE) - reported, does not change sync exit"
            }
        } catch {
            Write-Warning "  ERROR running $testName - $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    }
}

if ($exitCode -ne 0) {
    Write-Warning "sync-4ai-panes-install: completed WITH ERRORS (see warnings above). Install path: $Target"
} else {
    Write-Line "sync-4ai-panes-install: $result"
}

exit $exitCode
