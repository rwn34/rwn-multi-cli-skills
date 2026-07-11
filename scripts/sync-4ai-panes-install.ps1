<#
================================================================================
 sync-4ai-panes-install.ps1  -  allowlist-driven install sync
================================================================================
 Keeps the executable install (default ~/.rwn-auto/rwn-4AI-panes) in lockstep
 with the canonical source tree tools/4ai-panes/ by copying ONLY the eleven tool
 files named in the allowlist below. It never touches the embedded framework
 (.ai/ .claude/ .git/ ...) or runtime state (.4pane-history, *.log, ...) that
 also live in the install dir. See docs/specs/4ai-panes-install-sync.md.

 Contract:
   exit 0  - synced, already in sync (no-op), or target absent (graceful skip).
   exit 1  - a copy was attempted but post-copy hash verification failed, OR an
             allowlisted file is missing from the source tree. Loud stderr warn.

 Copy is BYTE-EXACT ([IO.File]::Copy) - no Get-Content/Set-Content round-trip -
 so committed EOL is preserved and icon.ico (binary) stays intact. Each drifted
 file is written to a temp path in the target dir, hash-verified against source,
 then atomically moved into place; a failed verify leaves the target untouched.

 Called directly by a human (with -DryRun to preview) or by the bash git hooks
 scripts/git-hooks/post-merge and post-checkout when tools/4ai-panes/** changes.
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Target,
    [switch]$DryRun,
    [switch]$Quiet,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

# --- Authoritative tool-file allowlist -------------------------------------
# The ONLY place the "which files are tool files" knowledge lives. Adding a
# twelfth tool file is a one-line edit here.
$Allowlist = @(
    'Launch4Panes.ps1',
    'Launch4Panes.vbs',
    'Selector.ps1',
    'fleet-clis.ps1',
    'pane-runner.ps1',
    'run-pane-supervised.ps1',
    'restart-pane.ps1',
    'test-pane-runner.ps1',
    'test-selector-e2e.ps1',
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

# --- Graceful skip when target absent --------------------------------------
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Line "no install at $Target, skipping"
    exit 0
}

# --- Source commit (best-effort) -------------------------------------------
$commit = 'n/a'
try {
    $c = & git -C $SourceDir rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $c) { $commit = $c.Trim() }
} catch { $commit = 'n/a' }

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
$stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$logLine = "[$stamp] commit=$commit result=$result | " + ($actions -join ' ')
try {
    $logPath = Join-Path $Target 'install-sync.log'
    Add-Content -LiteralPath $logPath -Value $logLine -Encoding ascii
} catch {
    Write-Warning "could not write install-sync.log: $($_.Exception.Message)"
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
