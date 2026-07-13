# test-sync-4ai-panes-install.ps1 - Pester-free harness for the provenance guard
# in scripts/sync-4ai-panes-install.ps1 (hole 1, 2026-07-13; ancestor guard added
# 2026-07-14, handoff 202607122200).
#
# Builds a throwaway git repo (primary checkout on master) + a bare "origin"
# remote (so the ancestor guard's `origin/master` resolves) + a linked worktree
# in a temp dir, then drives the REAL sync script as a child process against
# throwaway install dirs. Asserts:
#   (a) linked worktree        -> REFUSED, exit 0, nothing copied, log written
#   (b) primary, non-master    -> REFUSED, exit 0, branch named
#   (c) primary, detached HEAD -> REFUSED, exit 0
#   (d) primary + master, HEAD is an ancestor of origin/master -> PROCEEDS,
#       all 17 files copied, provenance logged
#   (e) SYNC_FORCE=1           -> overrides refusal (FORCED, provenance=forced,
#       and this ALSO skips the ancestor guard entirely)
#   (f) -Force switch          -> overrides refusal (FORCED, provenance=forced)
#   (g) not a git repo         -> REFUSED (fail closed), exit 0
#   (h) provenance sidecar     -> .sync-provenance.json written on a real sync
#   (i) local master AHEAD of origin/master (unpushed commit) -> REFUSED
#       (refused-unmerged), exit 0, PREVIOUSLY DEPLOYED FILES LEFT INTACT
#       (the RED proof the handoff asks for: a gate that can fail)
#   (j) RWN_4AI_ALLOW_UNMERGED=1 on the case in (i) -> PROCEEDS anyway, prints
#       the UNMERGED-ALLOWED warning, logs provenance=unmerged-allowed
#   (k) origin/master unresolvable (no 'origin' remote at all) -> REFUSED
#       (refused-unverifiable-origin), exit 0, fail-closed
#   (l) RWN_4AI_ALLOW_UNMERGED=1 on the case in (k) -> PROCEEDS anyway, prints
#       the UNMERGED-ALLOWED warning naming the unresolvable origin, logs
#       provenance=unmerged-allowed
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
    # files under tools/4ai-panes/ (the allowlist requires all seventeen
    # present), one commit on master. Also build a bare "origin" remote and
    # point the repo at it so the ancestor guard's `origin/master` resolves -
    # without this every primary+master run would hit the fail-closed
    # "origin/master UNRESOLVABLE" path instead of the happy path.
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

    $originDir = Join-Path $work 'origin.git'
    Invoke-Git $work @('init', '--bare', '-b', 'master', $originDir) | Out-Null
    Invoke-Git $repo @('remote', 'add', 'origin', $originDir) | Out-Null
    Invoke-Git $repo @('push', 'origin', 'master') | Out-Null

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

    # (d) primary checkout on master, HEAD is an ancestor of origin/master
    # (it IS origin/master, just pushed above) -> PROCEEDS
    Invoke-Git $repo @('checkout', 'master') | Out-Null
    $tD = New-Target 'install-d'
    $rD = Invoke-Sync $repoSync $tD
    Assert-Equal 0 $rD.Code 'd1: primary+master exits 0'
    Assert-True (-not $rD.Text.Contains('REFUSED')) 'd2: no refusal on primary+master'
    Assert-True (Test-Path (Join-Path $tD 'Selector.ps1') -PathType Leaf) 'd3: tool files copied'
    Assert-Equal 17 (Get-CopiedCount $tD) 'd4: all 17 allowlisted files copied'
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

    # (i) local master AHEAD of origin/master (an unpushed commit) -> REFUSED
    # (refused-unmerged), exit 0, and the RED proof: a PRIOR real deploy's
    # files are left completely untouched (no partial deploy).
    Invoke-Git $repo @('checkout', 'master') | Out-Null
    $tI = New-Target 'install-i'
    # Seed a known-good prior deploy first (HEAD == origin/master here).
    $rI0 = Invoke-Sync $repoSync $tI
    Assert-Equal 0 $rI0.Code 'i0: seed deploy (still an ancestor) exits 0'
    Assert-True (Test-Path (Join-Path $tI 'Selector.ps1') -PathType Leaf) 'i0b: seed deploy actually copied files'
    $seedHash = (Get-FileHash -LiteralPath (Join-Path $tI 'Selector.ps1') -Algorithm SHA256).Hash

    # Now advance local master with an UNPUSHED commit - origin/master does
    # not move, so HEAD is no longer an ancestor of it.
    $unmergedFile = Join-Path $repo 'tools\4ai-panes\Selector.ps1'
    Add-Content -LiteralPath $unmergedFile -Value "`n# unmerged-local-only-change`n"
    Invoke-Git $repo @('add', '-A') | Out-Null
    Invoke-Git $repo @('commit', '-m', 'unpushed local-only change') | Out-Null

    $rI = Invoke-Sync $repoSync $tI
    Assert-Equal 0 $rI.Code 'i1: unpushed-ahead-of-origin exits 0 (refusal is not an error)'
    Assert-Contains $rI.Text 'REFUSED' 'i2: unpushed-ahead-of-origin prints REFUSED'
    Assert-Contains (Get-LogText $tI) 'result=refused-unmerged' 'i3: log records result=refused-unmerged'
    $postHash = (Get-FileHash -LiteralPath (Join-Path $tI 'Selector.ps1') -Algorithm SHA256).Hash
    Assert-Equal $seedHash $postHash 'i4: RED proof - previously deployed file left completely untouched'

    # (j) RWN_4AI_ALLOW_UNMERGED=1 on the exact case in (i) -> PROCEEDS anyway,
    # prints the UNMERGED-ALLOWED warning, logs provenance=unmerged-allowed.
    $tJ = New-Target 'install-j'
    $prevAllow = $env:RWN_4AI_ALLOW_UNMERGED
    $env:RWN_4AI_ALLOW_UNMERGED = '1'
    try {
        $rJ = Invoke-Sync $repoSync $tJ
    } finally {
        if ($null -eq $prevAllow) { Remove-Item Env:\RWN_4AI_ALLOW_UNMERGED -ErrorAction SilentlyContinue } else { $env:RWN_4AI_ALLOW_UNMERGED = $prevAllow }
    }
    Assert-Equal 0 $rJ.Code 'j1: RWN_4AI_ALLOW_UNMERGED=1 run exits 0'
    Assert-Contains $rJ.Text 'UNMERGED-ALLOWED' 'j2: prints the UNMERGED-ALLOWED warning'
    Assert-True (Test-Path (Join-Path $tJ 'Selector.ps1') -PathType Leaf) 'j3: escape hatch deploys the unmerged commit anyway'
    Assert-Contains (Get-LogText $tJ) 'provenance=unmerged-allowed' 'j4: log records provenance=unmerged-allowed'

    # (k) origin/master unresolvable (no 'origin' remote at all) -> REFUSED
    # (refused-unverifiable-origin), exit 0, fail-closed.
    $noOrigin = Join-Path $work 'no-origin'
    & git init -b master $noOrigin 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git init (no-origin) failed' }
    Invoke-Git $noOrigin @('config', 'user.email', 'sync-test@example.com') | Out-Null
    Invoke-Git $noOrigin @('config', 'user.name', 'sync-test') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $noOrigin 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath $syncSrc -Destination (Join-Path $noOrigin 'scripts\sync-4ai-panes-install.ps1')
    Copy-Item -LiteralPath $toolsSrc -Destination (Join-Path $noOrigin 'tools\4ai-panes') -Recurse
    Invoke-Git $noOrigin @('add', '-A') | Out-Null
    Invoke-Git $noOrigin @('commit', '-m', 'init, no origin remote') | Out-Null
    $noOriginSync = Join-Path $noOrigin 'scripts\sync-4ai-panes-install.ps1'

    $tK = New-Target 'install-k'
    $rK = Invoke-Sync $noOriginSync $tK
    Assert-Equal 0 $rK.Code 'k1: no-origin-remote exits 0 (refusal is not an error)'
    Assert-Contains $rK.Text 'REFUSED' 'k2: no-origin-remote prints REFUSED'
    Assert-Contains (Get-LogText $tK) 'result=refused-unverifiable-origin' 'k3: log records result=refused-unverifiable-origin'
    Assert-Equal 0 (Get-CopiedCount $tK) 'k4: no-origin-remote refusal copies nothing'

    # (l) RWN_4AI_ALLOW_UNMERGED=1 on the exact case in (k) -> PROCEEDS anyway,
    # prints the UNMERGED-ALLOWED warning naming the unresolvable origin, logs
    # provenance=unmerged-allowed.
    $tL = New-Target 'install-l'
    $prevAllow2 = $env:RWN_4AI_ALLOW_UNMERGED
    $env:RWN_4AI_ALLOW_UNMERGED = '1'
    try {
        $rL = Invoke-Sync $noOriginSync $tL
    } finally {
        if ($null -eq $prevAllow2) { Remove-Item Env:\RWN_4AI_ALLOW_UNMERGED -ErrorAction SilentlyContinue } else { $env:RWN_4AI_ALLOW_UNMERGED = $prevAllow2 }
    }
    Assert-Equal 0 $rL.Code 'l1: RWN_4AI_ALLOW_UNMERGED=1 (no-origin) run exits 0'
    Assert-Contains $rL.Text 'UNMERGED-ALLOWED' 'l2: prints the UNMERGED-ALLOWED warning'
    Assert-True (Test-Path (Join-Path $tL 'Selector.ps1') -PathType Leaf) 'l3: escape hatch deploys anyway despite unresolvable origin'
    Assert-Contains (Get-LogText $tL) 'provenance=unmerged-allowed' 'l4: log records provenance=unmerged-allowed'
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
