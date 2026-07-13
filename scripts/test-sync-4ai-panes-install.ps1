# test-sync-4ai-panes-install.ps1 - Pester-free harness for the provenance guard
# in scripts/sync-4ai-panes-install.ps1 (hole 1, 2026-07-13).
#
# Builds a throwaway git repo (primary checkout on master) + a linked worktree
# in a temp dir, then drives the REAL sync script as a child process against
# throwaway install dirs. Asserts:
#   (a) linked worktree        -> REFUSED, exit 0, nothing copied, log written
#   (b) primary, non-master    -> REFUSED, exit 0, branch named
#   (c) primary, detached HEAD -> REFUSED, exit 0
#   (d) primary + master       -> PROCEEDS, all 12 files copied, provenance logged
#   (e) SYNC_FORCE=1           -> overrides refusal (FORCED, provenance=forced)
#   (f) -Force switch          -> overrides refusal (FORCED, provenance=forced)
#   (g) not a git repo         -> REFUSED (fail closed), exit 0
#   (h) provenance sidecar     -> .sync-provenance.json written on a real sync
#
# Convention mirrors tools/4ai-panes/test-pane-runner.ps1 (PASS/FAIL + tally).

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
$syncSrc = Join-Path $here 'sync-4ai-panes-install.ps1'
$toolsSrc = Join-Path $repoRoot 'tools\4ai-panes'

# -- tiny assert framework --
$script:pass = 0
$script:fail = 0
function Assert-True {
    param($Cond, [string]$Name)
    if ($Cond) {
        $script:pass++
        Write-Host "PASS  $Name" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "FAIL  $Name" -ForegroundColor Red
    }
}
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
function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Name)
    if ($Haystack.Contains($Needle)) {
        $script:pass++
        Write-Host "PASS  $Name" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "FAIL  $Name  (needle '$Needle' not found)" -ForegroundColor Red
    }
}

# -- sandbox: primary repo on master + linked worktree + install targets --
$work = Join-Path $env:TEMP ("sync-install-test-" + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $work 'repo'
$wt = Join-Path $work 'wt'

function Invoke-Git {
    param([string]$Repo, [string[]]$GitArgs)
    # EAP=Stop + 2>&1 on a native command turns ANY stderr line (e.g. git's
    # CRLF warnings) into a terminating NativeCommandError on PS 5.1 - so run
    # native calls under Continue and gate on the exit code instead.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Repo @GitArgs 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEAP }
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

function New-Target {
    param([string]$Name)
    $t = Join-Path $work $Name
    New-Item -ItemType Directory -Path $t -Force | Out-Null
    return $t
}

function Invoke-Sync {
    param([string]$ScriptPath, [string]$Target, [string[]]$ExtraArgs = @(), [switch]$ForceEnv)
    $prevForce = $env:SYNC_FORCE
    if ($ForceEnv) { $env:SYNC_FORCE = '1' } else { Remove-Item Env:\SYNC_FORCE -ErrorAction SilentlyContinue }
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Target $Target @ExtraArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEAP
        if ($null -eq $prevForce) { Remove-Item Env:\SYNC_FORCE -ErrorAction SilentlyContinue } else { $env:SYNC_FORCE = $prevForce }
    }
    return @{ Text = ($out -join "`n"); Code = $code }
}

function Get-LogText {
    param([string]$Target)
    $p = Join-Path $Target 'install-sync.log'
    if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Content -LiteralPath $p -Raw) }
    return ''
}

# Count files the sync deployed (everything but its own log + sidecar).
function Get-CopiedCount {
    param([string]$Target)
    return @(Get-ChildItem -LiteralPath $Target -File |
        Where-Object { $_.Name -ne 'install-sync.log' -and $_.Name -ne '.sync-provenance.json' }).Count
}

try {
    # Build the primary repo: the sync script under scripts/, the real tool
    # files under tools/4ai-panes/ (the allowlist requires ALL twelve present),
    # one commit on master.
    & git init -b master $repo 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    Invoke-Git $repo @('config', 'user.email', 'sync-test@example.com') | Out-Null
    Invoke-Git $repo @('config', 'user.name', 'sync-test') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath $syncSrc -Destination (Join-Path $repo 'scripts\sync-4ai-panes-install.ps1')
    Copy-Item -LiteralPath $toolsSrc -Destination (Join-Path $repo 'tools\4ai-panes') -Recurse
    Invoke-Git $repo @('add', '-A') | Out-Null
    Invoke-Git $repo @('commit', '-m', 'init') | Out-Null
    $repoSync = Join-Path $repo 'scripts\sync-4ai-panes-install.ps1'

    # (a) linked worktree -> REFUSED
    Invoke-Git $repo @('worktree', 'add', '-b', 'wt-branch', $wt) | Out-Null
    $wtSync = Join-Path $wt 'scripts\sync-4ai-panes-install.ps1'
    $tA = New-Target 'install-a'
    $rA = Invoke-Sync $wtSync $tA
    Assert-Equal 0 $rA.Code 'a1: worktree sync exits 0 (refusal is not an error)'
    Assert-Contains $rA.Text 'REFUSED' 'a2: worktree sync prints REFUSED'
    Assert-Contains $rA.Text 'primary=no' 'a3: refusal line reports primary=no'
    Assert-Equal 0 (Get-CopiedCount $tA) 'a4: refusal copies nothing'
    $logA = Get-LogText $tA
    Assert-Contains $logA 'result=refused' 'a5: refusal still writes the log line'
    Assert-Contains $logA 'primary=no' 'a6: log carries primary= token'
    Assert-True ($logA -match 'branch=\S+') 'a7: log carries branch= token'

    # (b) primary checkout, non-master branch -> REFUSED
    Invoke-Git $repo @('checkout', '-b', 'feature') | Out-Null
    $tB = New-Target 'install-b'
    $rB = Invoke-Sync $repoSync $tB
    Assert-Equal 0 $rB.Code 'b1: non-master primary exits 0'
    Assert-Contains $rB.Text 'REFUSED' 'b2: non-master primary prints REFUSED'
    Assert-Contains $rB.Text 'branch=feature' 'b3: refusal names the branch'
    Assert-Contains $rB.Text 'primary=yes' 'b4: refusal reports primary=yes'
    Assert-Equal 0 (Get-CopiedCount $tB) 'b5: refusal copies nothing'

    # (c) primary checkout, detached HEAD -> REFUSED
    Invoke-Git $repo @('checkout', '--detach') | Out-Null
    $tC = New-Target 'install-c'
    $rC = Invoke-Sync $repoSync $tC
    Assert-Equal 0 $rC.Code 'c1: detached HEAD exits 0'
    Assert-Contains $rC.Text 'REFUSED' 'c2: detached HEAD refused'
    Assert-Contains $rC.Text 'branch=DETACHED' 'c3: refusal marks the detached HEAD'

    # (d) primary checkout on master -> PROCEEDS
    Invoke-Git $repo @('checkout', 'master') | Out-Null
    $tD = New-Target 'install-d'
    $rD = Invoke-Sync $repoSync $tD
    Assert-Equal 0 $rD.Code 'd1: primary+master exits 0'
    Assert-True (-not $rD.Text.Contains('REFUSED')) 'd2: no refusal on primary+master'
    Assert-True (Test-Path (Join-Path $tD 'Selector.ps1') -PathType Leaf) 'd3: tool files copied'
    Assert-Equal 12 (Get-CopiedCount $tD) 'd4: all 12 allowlisted files copied'
    Assert-Contains (Get-LogText $tD) 'branch=master primary=yes' 'd5: log carries branch=master primary=yes'

    # (h) provenance sidecar written on a real sync
    $provFile = Join-Path $tD '.sync-provenance.json'
    Assert-True (Test-Path $provFile -PathType Leaf) 'h1: .sync-provenance.json written on sync'
    $prov = Get-Content -LiteralPath $provFile -Raw | ConvertFrom-Json
    Assert-Equal 'master' $prov.branch 'h2: sidecar records branch=master'
    Assert-True ($prov.source_repo.Length -gt 0) 'h3: sidecar records source_repo'

    # (e) SYNC_FORCE=1 overrides the worktree refusal
    $tE = New-Target 'install-e'
    $rE = Invoke-Sync $wtSync $tE -ForceEnv
    Assert-Equal 0 $rE.Code 'e1: SYNC_FORCE run exits 0'
    Assert-Contains $rE.Text 'FORCED' 'e2: SYNC_FORCE prints FORCED'
    Assert-True (Test-Path (Join-Path $tE 'Selector.ps1') -PathType Leaf) 'e3: SYNC_FORCE overrides refusal (files copied)'
    Assert-Contains (Get-LogText $tE) 'provenance=forced' 'e4: log records provenance=forced'

    # (f) -Force switch overrides the non-master refusal
    Invoke-Git $repo @('checkout', 'feature') | Out-Null
    $tF = New-Target 'install-f'
    $rF = Invoke-Sync $repoSync $tF -ExtraArgs @('-Force')
    Assert-Equal 0 $rF.Code 'f1: -Force run exits 0'
    Assert-Contains $rF.Text 'FORCED' 'f2: -Force prints FORCED'
    Assert-True (Test-Path (Join-Path $tF 'Selector.ps1') -PathType Leaf) 'f3: -Force overrides refusal (files copied)'
    Assert-Contains (Get-LogText $tF) 'provenance=forced' 'f4: log records provenance=forced'

    # (g) source not a git repo -> REFUSED (fail closed)
    $plain = Join-Path $work 'plain'
    New-Item -ItemType Directory -Path (Join-Path $plain 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath $syncSrc -Destination (Join-Path $plain 'scripts\sync-4ai-panes-install.ps1')
    Copy-Item -LiteralPath $toolsSrc -Destination (Join-Path $plain 'tools\4ai-panes') -Recurse
    $tG = New-Target 'install-g'
    $rG = Invoke-Sync (Join-Path $plain 'scripts\sync-4ai-panes-install.ps1') $tG
    Assert-Equal 0 $rG.Code 'g1: non-repo source exits 0 (fail closed)'
    Assert-Contains $rG.Text 'REFUSED' 'g2: non-repo source refused'
    Assert-Equal 0 (Get-CopiedCount $tG) 'g3: non-repo refusal copies nothing'
} finally {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (Test-Path $repo) {
            & git -C $repo worktree remove --force $wt 2>$null | Out-Null
        }
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    } catch { }
    $ErrorActionPreference = $prevEAP
}

# -- summary --
Write-Host ""
Write-Host "==== sync-install tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
