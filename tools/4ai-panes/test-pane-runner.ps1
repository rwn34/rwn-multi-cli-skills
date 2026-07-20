# test-pane-runner.ps1 - Pester-free harness for pane-runner.ps1 decision logic.
#
# Dot-sources pane-runner.ps1 with -NoRun (functions only, no loop), then drives
# the RUN/DECIDE core and the claim-lock with a MOCK CLI (an overridable
# scriptblock). No real CLI is ever launched. Asserts:
#   (a) handoff -> done on first run            (DONE, 0 continues)
#   (b) still-open then done on 2nd run         (auto-continue works: DONE, 1 continue)
#   (c) never-done                              (MAX cap halts at 5: MAXED, 5 continues)
#   (d) claim held by a live pid                (Test-ClaimBlocks = true  -> skip)
#   (e) claim by a dead pid                     (Test-ClaimBlocks = false -> reclaim)
#   (f) IDLE poll gate                          (Risk A returned, Risk C skipped)
#   (g) first per-handoff Claim-Handoff wins    (true + sidecar written)
#   (h) 2nd claim, different owner, while live  (false - not double-processed)
#   (i) stale per-handoff claim (old ts)        (reclaimable -> Claim-Handoff true)
#   (j) Release-Handoff removes the sidecar     (Test-Path false)
#   (k) first Add-HandoffAttempt                (attempts=1, not quarantined)
#   (l) attempts reach MaxHandoffAttempts       (quarantined=true)
#   (m) fresh handoff / no sidecar              (Test-HandoffQuarantined false)
#   (n) Get-QualifyingHandoff skips quarantined (returns next candidate)
#   (o) Clear-HandoffAttempts removes sidecar   (Test-HandoffQuarantined false)
#   (p) REAL InvokeCli vs stderr+nonzero child  (no throw under EAP=Stop; exit=3; EAP restored)
#   (q) Test-ClaimBlocks foreign host past win  (false -> reclaim)
#   (r) Test-ClaimBlocks same-host live+fresh   (true  -> block)
#   (s) Test-HandoffQuarantined expired record  (false -> allow one retry)
#   (t) Test-HandoffQuarantined fresh record    (true  -> still quarantined)
#   (u) Get-StopExitCode intentional stop        (Intent=$true  -> 0)
#   (v) Get-StopExitCode crash                    (Intent=$false -> non-zero)
#   (w) Get-HeadlessCmd claude carries --dangerously-skip-permissions (F2)
#   (x) parity guard: pane-runner vs dispatch-handoffs.sh Claude argv (F2)
#   (an-at) FLAT-INSTALL TOPOLOGY (the shape we actually DEPLOY, previously
#           untested — see the block at the bottom of this file):
#     (an) prove-the-bug: old single-candidate path fails under a flat $ScriptRoot
#     (ao) prove-the-fix: flat install resolves via $ProjectDir/scripts
#     (ap) flat install + bare project resolves via $RWN_FRAMEWORK_REPO
#     (aq) repo-tree checkout still resolves via ../../scripts (no regression)
#     (ar) candidate order: project copy beats framework repo
#     (as) fail-loud: nothing found -> $null, all 3 candidates reportable
#     (at) anti-rot: InvokeWtBootstrap goes through the multi-candidate resolver
#   (y) Invoke-HandoffRun resolves the worktree BEFORE invoking the CLI, and the
#       CLI is invoked with cwd == that worktree (NOT $ProjectDir)
#   (z) worktree failure -> WORKTREE_FAIL, CLI NEVER invoked, no fallback to
#       $ProjectDir (the acceptance assertion for this whole fix)
#   (aa) declared-base-branch failure -> WORKTREE_FAIL, CLI NEVER invoked
#   (ab) Get-DeclaredBase reads a handoff's Base: field; discovers the repo's
#        default branch offline-first when absent (origin/HEAD, origin/main,
#        main, HEAD); never hardcodes origin/master.
#   (ac) parity guard: Ensure-DeclaredBaseBranchReal vs
#        dispatch-handoffs.sh's ensure_declared_base_branch() behave the same on
#        a real sandbox repo (branch cut from declared base, not ambient HEAD;
#        dirty non-.ai tree -> refuse to touch, matching bash's WARN-and-reuse)
#   (ad) REGRESSION (the incident this handoff fixes): two concurrent
#        Invoke-HandoffRun calls for two different CLIs, each in its own real
#        worktree, never perturb each other's HEAD or working files, and the
#        PRIMARY checkout's HEAD is unchanged throughout
#   (ae) idle heartbeat on first idle poll         (emits; line has CLI name + time)
#   (af) heartbeat is throttled                    (10 rapid polls -> exactly 1 emit)
#   (ag) heartbeat re-emits after the interval     (true)
#   (ah) heartbeat is idle-only                    (one call site, null-handoff branch)
#   (ai) picked-up line on idle->busy              (present, printed after claim won)
#   (aj) Enable/Restore-DispatchGuardEnv          (sets 1, returns+restores prior)
#   (ak) real InvokeCli child env                 (child sees AI_HANDOFF_DISPATCH=1)
#   (al) GUARD: AI_HANDOFF_DISPATCH=1 in source   (fails loudly if ever dropped)
#   (am) real InvokeCli honors BOTH the worktree cwd AND AI_HANDOFF_DISPATCH=1
#        in the SAME child invocation (the interleave this rebase must prove)
#   (av) ADR-0016 SNAPSHOT-COPY regression: real sandbox worktree, real
#        SnapshotAi/SyncBackAi hooks — .ai/ is an ordinary directory copy, not
#        a junction, and a report written into worktree .ai/ syncs back to
#        canonical.
#   (ba-be) PANE LIVENESS HEARTBEAT SIDECAR (fleet-health.sh dead-man's switch):
#     (ba) Write-Heartbeat writes .ai/.heartbeat-<cli>.json w/ contract fields
#     (bb) atomic temp+rename leaves no .tmp debris
#     (bc) busy state records the current handoff leaf
#     (bd) rewrite over an existing sidecar is a clean replace, still valid JSON
#     (be) anti-rot: Start-PaneRunner calls Write-Heartbeat, fail-open wrapped
#   (bf) ANTI-ROT: Assert-WorktreeFresh guards Start-PaneRunner before polling
#   (bg-bj) REGRESSION (handoff 202607140930 - malformed -Cli spawns malformed
#        supervisors): [ValidateSet] on $Cli rejects an empty string and a
#        truncated value ('k') at PARAMETER BIND TIME, in a real child process,
#        for BOTH pane-runner.ps1 (bg/bh) and run-pane-supervised.ps1 (bi/bj) -
#        before any loop/banner/heartbeat logic runs.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $here 'pane-runner.ps1'

# Load functions without starting the supervisor loop.
. $runner -Cli claude -ProjectDir $here -NoRun

# Capture the REAL $script:InvokeCli BEFORE the mock below overwrites it, so test
# (p) can exercise the actual native-invocation path (the stderr-crash regression).
$script:RealInvokeCli = $script:InvokeCli

# -- tiny assert framework --
$script:pass = 0
$script:fail = 0
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

# -- temp workspace --
$work = Join-Path $env:TEMP ("pane-runner-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$openDir = Join-Path $work ".ai/handoffs/to-claude/open"
New-Item -ItemType Directory -Path $openDir -Force | Out-Null

function New-TestHandoff {
    param([string]$Slug, [string]$Risk = 'A')
    $p = Join-Path $openDir "$Slug.md"
    @(
        "# Test handoff $Slug",
        "Status: OPEN",
        "Sender: claude-code",
        "Recipient: claude-code",
        "Created: 2026-07-09 00:00",
        "Auto: yes",
        "Risk: $Risk",
        "",
        "## Goal",
        "test"
    ) -join "`n" | Set-Content -Path $p -Encoding utf8
    return $p
}

# -- mock CLI: deletes the handoff on the Nth call to simulate completion --
$script:mockCalls = 0
$script:mockDeleteOnCall = 0      # 0 = never delete
$script:mockHandoffPath = $null
$script:InvokeCli = {
    param([string]$CliName, [string]$Prompt, [string]$Cwd = (Get-Location).Path)
    $script:mockCalls++
    $script:lastInvokeCwd = $Cwd
    if ($script:mockDeleteOnCall -gt 0 -and $script:mockCalls -eq $script:mockDeleteOnCall) {
        Remove-Item -Path $script:mockHandoffPath -Force
    }
    return 0
}

# -- mock worktree resolution (tests a-x): a fake, always-succeeding worktree so
#    the existing RUN/DECIDE tests never touch real git or shell out to bash.
#    Capture the args Invoke-HandoffRun passes through so (y) can assert on them.
$script:mockWtPath = Join-Path $env:TEMP ("pane-runner-test-wt-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:mockWtPath -Force | Out-Null
$script:mockWtFails = $false
$script:mockBranchFails = $false
$script:GetCliWorktreePath = {
    param([string]$ProjectDir, [string]$CliName)
    $script:lastWtCliName = $CliName
    if ($script:mockWtFails) { return $null }
    return $script:mockWtPath
}
$script:EnsureDeclaredBaseBranch = {
    param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base, [string]$ProjectDir)
    $script:lastBranchArgs = @{ WtPath = $WtPath; CliName = $CliName; Slug = $Slug; Base = $Base; ProjectDir = $ProjectDir }
    if ($script:mockBranchFails) { return $false }
    return $true
}

# Mock .ai/ snapshot/sync-back for tests (a)-(z): the mock worktree is not a real
# git repo, so shelling out to sync-ai-state.sh would fail. Capture call args.
$script:snapshotCalls = @()
$script:syncBackCalls = @()
$script:SnapshotAi = {
    param([string]$ProjectDir, [string]$WtPath)
    $script:snapshotCalls += @{ ProjectDir = $ProjectDir; WtPath = $WtPath }
    return $true
}
$script:SyncBackAi = {
    param([string]$ProjectDir, [string]$WtPath)
    $script:syncBackCalls += @{ ProjectDir = $ProjectDir; WtPath = $WtPath }
}

# Mock base resolution for tests (a)-(z): avoids requiring every temp workspace to be
# a full git repo. The dedicated (ab) test exercises the real discovery logic.
$script:GetDeclaredBase = { param([string]$HandoffPath) return 'origin/master' }

# -- (a) done on first run --
$script:mockCalls = 0; $script:mockDeleteOnCall = 1
$h = New-TestHandoff -Slug 'a-first'
$script:mockHandoffPath = $h
$r = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $h -MaxContinues 5
Assert-Equal 'DONE' $r.Result 'a: done on first run -> Result=DONE'
Assert-Equal 0 $r.Continues 'a: done on first run -> 0 continues'
Assert-Equal 1 $r.Invocations 'a: done on first run -> 1 invocation'
Assert-Equal $work $script:snapshotCalls[-1].ProjectDir 'a: SnapshotAi called with ProjectDir'
Assert-Equal $script:mockWtPath $script:snapshotCalls[-1].WtPath 'a: SnapshotAi called with WtPath'
Assert-Equal $work $script:syncBackCalls[-1].ProjectDir 'a: SyncBackAi called with ProjectDir'
Assert-Equal $script:mockWtPath $script:syncBackCalls[-1].WtPath 'a: SyncBackAi called with WtPath'

# -- (b) still-open then done on 2nd run (auto-continue) --
$script:mockCalls = 0; $script:mockDeleteOnCall = 2
$h = New-TestHandoff -Slug 'b-second'
$script:mockHandoffPath = $h
$r = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $h -MaxContinues 5
Assert-Equal 'DONE' $r.Result 'b: done on 2nd run -> Result=DONE'
Assert-Equal 1 $r.Continues 'b: done on 2nd run -> 1 continue (auto-continue fired)'
Assert-Equal 2 $r.Invocations 'b: done on 2nd run -> 2 invocations'

# -- (c) never-done -> MAX cap halts at 5 --
$script:mockCalls = 0; $script:mockDeleteOnCall = 0
$h = New-TestHandoff -Slug 'c-never'
$script:mockHandoffPath = $h
$r = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $h -MaxContinues 5
Assert-Equal 'MAXED' $r.Result 'c: never-done -> Result=MAXED'
Assert-Equal 5 $r.Continues 'c: never-done -> halts at 5 continues'
Assert-Equal 6 $r.Invocations 'c: never-done -> 6 invocations (1 initial + 5 continues)'

# -- (d) claim held by a LIVE pid -> skip --
$script:TestPidAlive = { param([int]$ProcessId) return $true }
Write-Claim -ProjectDir $work -CliName 'claude' -MyPid 999999
$blocks = Test-ClaimBlocks -ProjectDir $work -CliName 'claude' -MyPid $PID
Assert-Equal $true $blocks 'd: live foreign pid -> Test-ClaimBlocks = true (skip)'

# -- (e) claim by a DEAD pid -> reclaim --
$script:TestPidAlive = { param([int]$ProcessId) return $false }
# claim file from (d) still on disk with pid 999999; now probe says dead
$blocks = Test-ClaimBlocks -ProjectDir $work -CliName 'claude' -MyPid $PID
Assert-Equal $false $blocks 'e: dead foreign pid -> Test-ClaimBlocks = false (reclaim)'
Remove-Claim -ProjectDir $work -CliName 'claude'

# -- (f) IDLE poll gate: Risk A returned, Risk C skipped --
Get-ChildItem -Path $openDir -Filter '*.md' | Remove-Item -Force
$cPath = New-TestHandoff -Slug '202607090001-riskc' -Risk 'C'
$aPath = New-TestHandoff -Slug '202607090002-riska' -Risk 'A'
$picked = Get-QualifyingHandoff -ProjectDir $work -CliName 'claude'
Assert-Equal $aPath $picked 'f: IDLE poll returns the Risk A handoff, skips Risk C'

# -- per-handoff claim-lock (ADR-0009 section 3) --
Get-ChildItem -Path $openDir -Filter '*.md' | Remove-Item -Force

# (g) first Claim-Handoff wins + sidecar exists
$script:TestPidAlive = { param([int]$ProcessId) return $true }
$hc = New-TestHandoff -Slug 'g-claim'
$won = Claim-Handoff -Recipient 'claude' -HandoffPath $hc -Owner 'claude'
Assert-Equal $true $won 'g: first Claim-Handoff wins -> true'
$sidecar = Get-HandoffClaimPath -Recipient 'claude' -HandoffPath $hc
Assert-Equal $true (Test-Path $sidecar) 'g: sidecar written on win'

# (h) second Claim-Handoff by a DIFFERENT owner loses while the first is live
$won2 = Claim-Handoff -Recipient 'claude' -HandoffPath $hc -Owner 'claude-cockpit'
Assert-Equal $false $won2 'h: 2nd claim (different owner, live) loses -> false'

# (i) a STALE claim (old claimed_at) is reclaimable
$stale = [ordered]@{
    handoff    = Get-HandoffBasename -HandoffPath $hc
    recipient  = 'claude'
    owner      = 'kiro'
    pid        = $PID
    host       = [System.Net.Dns]::GetHostName()
    claimed_at = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$stale | ConvertTo-Json -Compress | Set-Content -Path $sidecar -Encoding utf8 -NoNewline
$reclaimed = Claim-Handoff -Recipient 'claude' -HandoffPath $hc -Owner 'claude'
Assert-Equal $true $reclaimed 'i: stale (old claimed_at) claim is reclaimable -> true'

# (j) Release-Handoff removes the sidecar
Release-Handoff -Recipient 'claude' -HandoffPath $hc
Assert-Equal $false (Test-Path $sidecar) 'j: Release-Handoff removes the sidecar'

# -- Get-DefaultOwner returns eight-actor auto identities --
Assert-Equal 'claude'   (Get-DefaultOwner -CliName 'claude')   'k: claude owner is claude'
Assert-Equal 'kimi'     (Get-DefaultOwner -CliName 'kimi')     'k: kimi owner is kimi'
Assert-Equal 'kiro'     (Get-DefaultOwner -CliName 'kiro')     'k: kiro owner is kiro'
Assert-Equal 'opencode' (Get-DefaultOwner -CliName 'opencode') 'k: opencode owner is opencode'

# -- poison-pill quarantine (ADR-0008 self-healing safety valve) --
$kimiOpen = Join-Path $work ".ai/handoffs/to-kimi/open"
New-Item -ItemType Directory -Path $kimiOpen -Force | Out-Null

function New-KimiHandoff {
    param([string]$Slug, [string]$Risk = 'B')
    $p = Join-Path $kimiOpen "$Slug.md"
    @(
        "# Test handoff $Slug",
        "Status: OPEN",
        "Sender: claude-code",
        "Recipient: kimi-cli",
        "Created: 2026-07-09 00:00",
        "Auto: yes",
        "Risk: $Risk",
        "",
        "## Goal",
        "test"
    ) -join "`n" | Set-Content -Path $p -Encoding utf8
    return $p
}

# (k) first Add-HandoffAttempt -> sidecar exists, attempts=1, not quarantined
$hk = New-KimiHandoff -Slug 'k-attempt'
$qPath = Get-HandoffQuarantinePath -Recipient 'kimi' -HandoffPath $hk
$q1 = Add-HandoffAttempt -Recipient 'kimi' -HandoffPath $hk -ErrorText 'first fail'
Assert-Equal $true (Test-Path $qPath) 'k: Add-HandoffAttempt writes the sidecar'
Assert-Equal 1 $q1.attempts 'k: first attempt -> attempts=1'
Assert-Equal $false $q1.quarantined 'k: first attempt -> not quarantined'
Assert-Equal $false (Test-HandoffQuarantined -Recipient 'kimi' -HandoffPath $hk) 'k: below threshold -> Test-HandoffQuarantined false'

# (l) reaching MaxHandoffAttempts flips quarantined true (lower the threshold to 2)
$origMax = $script:MaxHandoffAttempts
$script:MaxHandoffAttempts = 2
$q2 = Add-HandoffAttempt -Recipient 'kimi' -HandoffPath $hk -ErrorText 'second fail'
Assert-Equal 2 $q2.attempts 'l: second attempt -> attempts=2'
Assert-Equal $true $q2.quarantined 'l: attempts >= threshold -> quarantined true'
Assert-Equal $true (Test-HandoffQuarantined -Recipient 'kimi' -HandoffPath $hk) 'l: quarantined -> Test-HandoffQuarantined true'

# (m) a fresh (unattempted) handoff is not quarantined; no sidecar -> false
$hfresh = New-KimiHandoff -Slug 'm-fresh'
Assert-Equal $false (Test-HandoffQuarantined -Recipient 'kimi' -HandoffPath $hfresh) 'm: no sidecar -> Test-HandoffQuarantined false'

# (n) Get-QualifyingHandoff SKIPS the quarantined handoff, returns the next candidate
#     k-attempt sorts before m-fresh, so without quarantine it would be picked first.
$picked = Get-QualifyingHandoff -ProjectDir $work -CliName 'kimi'
Assert-Equal $hfresh $picked 'n: Get-QualifyingHandoff skips the quarantined handoff'

# (o) Clear-HandoffAttempts removes the sidecar -> Test-HandoffQuarantined false again
Clear-HandoffAttempts -Recipient 'kimi' -HandoffPath $hk
Assert-Equal $false (Test-Path $qPath) 'o: Clear-HandoffAttempts removes the sidecar'
Assert-Equal $false (Test-HandoffQuarantined -Recipient 'kimi' -HandoffPath $hk) 'o: after clear -> Test-HandoffQuarantined false'

# restore the real threshold
$script:MaxHandoffAttempts = $origMax

# -- (bn-bs) Emit-NextStageHandoff: eight-actor identities + Next: fan-out --
# Use an isolated workspace so earlier tests' leftover queue files do not skew counts.
$emitWork = Join-Path $env:TEMP ("pane-runner-emit-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $emitWork -Force | Out-Null

function New-DoneHandoff {
    param([string]$CliName, [string]$Slug, [string]$ExtraLines = '')
    $dir = Join-Path $emitWork ".ai/handoffs/to-$CliName/done"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $p = Join-Path $dir "$Slug.md"
    $lines = @(
        "# Done handoff $Slug",
        "Status: DONE",
        "Sender: claude-cockpit",
        "Recipient: $CliName-auto",
        "Created: 2026-07-18 00:00",
        "Auto: yes",
        "Risk: B"
    )
    if ($ExtraLines) { $lines += ($ExtraLines -split "`n") }
    $lines += @("", "## Goal", "test")
    $lines -join "`n" | Set-Content -Path $p -Encoding utf8
    return $p
}

function Get-EmitCount {
    param([string]$Queue, [string]$SubDir)
    $d = Join-Path $emitWork ".ai/handoffs/to-$Queue/$SubDir"
    if (-not (Test-Path $d)) { return 0 }
    return (Get-ChildItem -Path $d -Filter '*.md' -File).Count
}

function Get-EmitFile {
    param([string]$Queue, [string]$SubDir, [string]$SlugPattern)
    $d = Join-Path $emitWork ".ai/handoffs/to-$Queue/$SubDir"
    if (-not (Test-Path $d)) { return $null }
    return (Get-ChildItem -Path $d -Filter '*.md' -File | Where-Object { $_.Name -like "*$SlugPattern*" } | Select-Object -First 1)
}

# (bn) ReviewBy: bare cli maps to <cli>, sender is the emitting pane's eight-actor identity
$bnDone = New-DoneHandoff -CliName 'kimi' -Slug 'bn-review' -ExtraLines 'ReviewBy: kiro'
Emit-NextStageHandoff -ProjectDir $emitWork -CliName 'kimi' -HandoffPath $bnDone
Assert-Equal 1 (Get-EmitCount -Queue 'kiro' -SubDir 'review') 'bn: ReviewBy bare kiro emits one review handoff'
$bnFile = Get-EmitFile -Queue 'kiro' -SubDir 'review' -SlugPattern 'bn-review'
Assert-Equal $true ($null -ne $bnFile) 'bn: review file exists'
$bnContent = Get-Content -Path $bnFile.FullName -Raw
Assert-Equal $true ($bnContent -match '(?m)^Sender:\s*kimi\s*$') 'bn: review sender is kimi'
Assert-Equal $true ($bnContent -match '(?m)^Recipient:\s*kiro\s*$') 'bn: review recipient is kiro'
Assert-Equal $true ($bnContent -match '(?m)^Auto:\s*yes\s*$') 'bn: review handoff is Auto: yes'
Assert-Equal $true ($bnContent -match 'ReviewOf:\s*bn-review\.md') 'bn: review handoff carries ReviewOf'

# (bo) Next: fans out to multiple actors with correct identities and Auto flags
$boDone = New-DoneHandoff -CliName 'claude' -Slug 'bo-next' -ExtraLines "Next: kimi, kiro`nFinalReview: claude"
Emit-NextStageHandoff -ProjectDir $emitWork -CliName 'claude' -HandoffPath $boDone
Assert-Equal 1 (Get-EmitCount -Queue 'kimi' -SubDir 'open') 'bo: Next kimi emits one open handoff'
Assert-Equal 1 (Get-EmitCount -Queue 'kiro' -SubDir 'open') 'bo: Next kiro emits one open handoff'
$boKimi = Get-EmitFile -Queue 'kimi' -SubDir 'open' -SlugPattern 'bo-next'
Assert-Equal $true ($null -ne $boKimi) 'bo: kimi Next file exists'
$boKimiContent = Get-Content -Path $boKimi.FullName -Raw
Assert-Equal $true ($boKimiContent -match '(?m)^Sender:\s*claude\s*$') 'bo: Next sender is claude'
Assert-Equal $true ($boKimiContent -match '(?m)^Recipient:\s*kimi\s*$') 'bo: Next recipient is kimi'
Assert-Equal $true ($boKimiContent -match '(?m)^Auto:\s*yes\s*$') 'bo: Next auto recipient is Auto: yes'

# (bp) Next: to a cockpit writes Auto: no so the dispatcher leaves it for the cockpit
$bpDone = New-DoneHandoff -CliName 'opencode' -Slug 'bp-cockpit' -ExtraLines 'Next: kimi-cockpit'
Emit-NextStageHandoff -ProjectDir $emitWork -CliName 'opencode' -HandoffPath $bpDone
$bpFile = Get-EmitFile -Queue 'kimi' -SubDir 'open' -SlugPattern 'bp-cockpit'
Assert-Equal $true ($null -ne $bpFile) 'bp: Next cockpit emits a handoff'
$bpContent = Get-Content -Path $bpFile.FullName -Raw
Assert-Equal $true ($bpContent -match '(?m)^Recipient:\s*kimi-cockpit\s*$') 'bp: cockpit recipient identity'
Assert-Equal $true ($bpContent -match '(?m)^Auto:\s*no\s*$') 'bp: cockpit handoff is Auto: no'

# (bq) Deploy: yes emits an opencode handoff
$bqDone = New-DoneHandoff -CliName 'claude' -Slug 'bq-deploy' -ExtraLines 'Deploy: yes'
Emit-NextStageHandoff -ProjectDir $emitWork -CliName 'claude' -HandoffPath $bqDone
Assert-Equal 1 (Get-EmitCount -Queue 'opencode' -SubDir 'open') 'bq: Deploy emits one open handoff'
$bqFile = Get-EmitFile -Queue 'opencode' -SubDir 'open' -SlugPattern 'bq-deploy'
Assert-Equal $true ($null -ne $bqFile) 'bq: deploy file exists'
$bqContent = Get-Content -Path $bqFile.FullName -Raw
Assert-Equal $true ($bqContent -match '(?m)^Sender:\s*claude\s*$') 'bq: deploy sender is claude'
Assert-Equal $true ($bqContent -match '(?m)^Recipient:\s*opencode\s*$') 'bq: deploy recipient is opencode'
Assert-Equal $true ($bqContent -match '(?m)^Auto:\s*yes\s*$') 'bq: deploy handoff is Auto: yes'

# (br) FinalReview: <actor> emits a review handoff with eight-actor identities
$brDone = New-DoneHandoff -CliName 'kiro' -Slug 'br-final' -ExtraLines 'FinalReview: claude'
Emit-NextStageHandoff -ProjectDir $emitWork -CliName 'kiro' -HandoffPath $brDone
$brFile = Get-EmitFile -Queue 'claude' -SubDir 'review' -SlugPattern 'br-final'
Assert-Equal $true ($null -ne $brFile) 'br: final-review file exists'
$brContent = Get-Content -Path $brFile.FullName -Raw
Assert-Equal $true ($brContent -match '(?m)^Sender:\s*kiro\s*$') 'br: final-review sender is kiro'
Assert-Equal $true ($brContent -match '(?m)^Recipient:\s*claude\s*$') 'br: final-review recipient is claude'

try {
    Remove-Item -Path $emitWork -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Could not remove test emit workspace '$emitWork': $_"
}

# -- (p) REAL invoke path: a native child that writes stderr AND exits non-zero --
#     This is the regression the mocked tests can't see. We drive the actual
#     $script:InvokeCli (captured before the mock) with the call-site EAP='Stop'
#     the supervisor loop uses. Override Get-HeadlessCmd so the spawned command is
#     a real native process (cmd) that writes stderr and returns exit 3.
#     Get-HeadlessCmd returns an argv ARRAY (exe + args) since the injection fix;
#     the stub mirrors that contract (cmd, /c, <command>).
$origHeadless = ${function:Get-HeadlessCmd}
function Get-HeadlessCmd { param([string]$CliName, [string]$Prompt) return @('cmd', '/c', 'echo boom 1>&2 & exit 3') }
$ErrorActionPreference = 'Stop'   # replicate the loop's call-site EAP
$pThrew = $false
$pCode = $null
try {
    $pCode = & $script:RealInvokeCli 'claude' 'ignored-prompt'
} catch {
    $pThrew = $true
}
${function:Get-HeadlessCmd} = $origHeadless
Assert-Equal $false $pThrew 'p: real InvokeCli (stderr+nonzero) does NOT throw under EAP=Stop'
Assert-Equal 3 $pCode 'p: real InvokeCli returns the child exit code (3)'
Assert-Equal 'Stop' $ErrorActionPreference 'p: ErrorActionPreference restored to Stop after the call'

# -- (q) Test-ClaimBlocks: foreign-host claim past the staleness window -> reclaim --
#     pid probe says "alive", but the host differs so the pid is untrusted; the ts
#     is older than ProjectClaimStaleMinutes -> stale -> do not block.
$script:TestPidAlive = { param([int]$ProcessId) return $true }
$claimP = Get-ClaimPath -ProjectDir $work -CliName 'claude'
$foreignClaim = [ordered]@{
    project = (Split-Path -Leaf $work)
    cli     = 'claude'
    pid     = 999999
    host    = 'some-other-host'
    ts      = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$foreignClaim | ConvertTo-Json -Compress | Set-Content -Path $claimP -Encoding utf8 -NoNewline
Assert-Equal $false (Test-ClaimBlocks -ProjectDir $work -CliName 'claude' -MyPid $PID) 'q: foreign-host claim past window -> Test-ClaimBlocks false (reclaim)'

# -- (r) Test-ClaimBlocks: same-host, live pid, fresh ts -> block (legit worker) --
$freshClaim = [ordered]@{
    project = (Split-Path -Leaf $work)
    cli     = 'claude'
    pid     = 999999
    host    = [System.Net.Dns]::GetHostName()
    ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$freshClaim | ConvertTo-Json -Compress | Set-Content -Path $claimP -Encoding utf8 -NoNewline
Assert-Equal $true (Test-ClaimBlocks -ProjectDir $work -CliName 'claude' -MyPid $PID) 'r: same-host live-pid fresh claim -> Test-ClaimBlocks true (block)'
Remove-Claim -ProjectDir $work -CliName 'claude'

# -- (s) Test-HandoffQuarantined: an EXPIRED quarantine ages out -> false (one retry) --
$hexp = New-KimiHandoff -Slug 's-expired'
$sPath = Get-HandoffQuarantinePath -Recipient 'kimi' -HandoffPath $hexp
$expiredRec = [ordered]@{
    handoff        = Get-HandoffBasename -HandoffPath $hexp
    recipient      = 'kimi'
    attempts       = 3
    quarantined    = $true
    quarantined_at = (Get-Date).ToUniversalTime().AddMinutes(-120).ToString('yyyy-MM-ddTHH:mm:ssZ')
    first_attempt  = (Get-Date).ToUniversalTime().AddMinutes(-200).ToString('yyyy-MM-ddTHH:mm:ssZ')
    last_attempt   = (Get-Date).ToUniversalTime().AddMinutes(-120).ToString('yyyy-MM-ddTHH:mm:ssZ')
    last_error     = 'transient'
}
$expiredRec | ConvertTo-Json -Compress | Set-Content -Path $sPath -Encoding utf8 -NoNewline
Assert-Equal $false (Test-HandoffQuarantined -Recipient 'kimi' -HandoffPath $hexp) 's: expired quarantine (old quarantined_at) -> Test-HandoffQuarantined false'

# -- (t) a FRESH quarantine (quarantined_at = now) is still active -> true --
$freshRec = [ordered]@{
    handoff        = Get-HandoffBasename -HandoffPath $hexp
    recipient      = 'kimi'
    attempts       = 3
    quarantined    = $true
    quarantined_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    first_attempt  = (Get-Date).ToUniversalTime().AddMinutes(-200).ToString('yyyy-MM-ddTHH:mm:ssZ')
    last_attempt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    last_error     = 'transient'
}
$freshRec | ConvertTo-Json -Compress | Set-Content -Path $sPath -Encoding utf8 -NoNewline
Assert-Equal $true (Test-HandoffQuarantined -Recipient 'kimi' -HandoffPath $hexp) 't: fresh quarantine -> Test-HandoffQuarantined true'
Clear-HandoffAttempts -Recipient 'kimi' -HandoffPath $hexp

# -- (u/v) exit-code contract helper: intent -> 0, crash -> non-zero --
Assert-Equal 0 (Get-StopExitCode -Intent $true) 'u: intentional stop -> Get-StopExitCode 0'
Assert-Equal $true ((Get-StopExitCode -Intent $false) -ne 0) 'v: crash -> Get-StopExitCode non-zero'

# -- (w) F2: headless Claude argv carries --dangerously-skip-permissions, --
# -- NOT the weaker --permission-mode acceptEdits (which auto-denies Bash    --
# -- calls outside settings.local.json's allow-list with no human headless   --
# -- to approve them). --
$claudeArgv = @(Get-HeadlessCmd -CliName 'claude' -Prompt 'test-prompt')
Assert-Equal $true ($claudeArgv -contains '--dangerously-skip-permissions') 'w: headless claude argv contains --dangerously-skip-permissions'
Assert-Equal $false ($claudeArgv -contains '--permission-mode') 'w: headless claude argv no longer contains --permission-mode'

# -- (x) F2 parity guard: pane-runner's Get-HeadlessCmd claude form MUST match --
# -- dispatch-handoffs.sh's headless_cmd claude form. Two files stating the   --
# -- same launch flags is exactly the class of bug that motivated this fix   --
# -- (the two invocations had already drifted once) - so this test extracts  --
# -- the bash HEADLESS_ARGV line for claude and fails LOUDLY on any drift.   --
$dispatchSh = Join-Path $here '..\..\.ai\tools\dispatch-handoffs.sh'
$dispatchSh = [System.IO.Path]::GetFullPath($dispatchSh)
if (Test-Path $dispatchSh) {
    $shLine = (Get-Content -Path $dispatchSh) | Where-Object { $_ -match 'claude\)\s*HEADLESS_ARGV=\(claude\s+-p\s+"\$prompt"\s+(.+)\)\s*;;' }
    if ($shLine) {
        $shFlags = $Matches[1].Trim()
    } else {
        $shFlags = $null
    }
    # PowerShell argv for claude, flags only (drop exe, '-p', and the prompt).
    $psFlags = ($claudeArgv | Select-Object -Skip 3) -join ' '
    Assert-Equal $psFlags $shFlags 'x: parity guard - pane-runner vs dispatch-handoffs.sh claude headless flags match'
} else {
    # dispatch-handoffs.sh not found relative to this file (e.g. running the
    # flat install copy without the .ai/ sibling) -- do not fail loudly for a
    # missing comparison target, but do not silently pass either.
    $script:fail++
    Write-Host "FAIL  x: parity guard - could not locate dispatch-handoffs.sh at $dispatchSh" -ForegroundColor Red
}

# -- (y) Invoke-HandoffRun resolves the worktree BEFORE invoking the CLI, and --
# -- the CLI is invoked with cwd == that worktree, NOT $ProjectDir. This is   --
# -- the worktree-per-CLI fix itself: assert the mock InvokeCli actually saw  --
# -- the worktree path, not the primary checkout ($work). --
$script:mockCalls = 0; $script:mockDeleteOnCall = 1; $script:mockWtFails = $false; $script:mockBranchFails = $false
$script:lastInvokeCwd = $null
$hy = New-TestHandoff -Slug 'y-worktree-cwd'
$script:mockHandoffPath = $hy
$ry = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $hy -MaxContinues 5
Assert-Equal 'DONE' $ry.Result 'y: worktree-cwd test -> handoff still completes (DONE)'
Assert-Equal $script:mockWtPath $script:lastInvokeCwd 'y: InvokeCli cwd == the CLI worktree path'
Assert-Equal $false ($script:lastInvokeCwd -eq $work) 'y: InvokeCli cwd is NOT $ProjectDir (primary checkout)'

# -- (z) worktree failure -> WORKTREE_FAIL, CLI NEVER invoked, no fallback to  --
# -- $ProjectDir. This is the ACCEPTANCE assertion for the whole fix: a       --
# -- worktree that cannot be established must never degrade to running in    --
# -- the primary checkout. --
$script:mockWtFails = $true
$script:mockCalls = 0
$syncBackBeforeZ = $script:syncBackCalls.Count
$hz = New-TestHandoff -Slug 'z-worktree-fail'
$script:mockHandoffPath = $hz
$rz = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $hz -MaxContinues 5
Assert-Equal 'WORKTREE_FAIL' $rz.Result 'z: worktree setup failure -> Result=WORKTREE_FAIL'
Assert-Equal 0 $rz.Invocations 'z: worktree setup failure -> CLI NEVER invoked (Invocations=0)'
Assert-Equal 0 $script:mockCalls 'z: worktree setup failure -> mock InvokeCli call count is 0 (no fallback run)'
Assert-Equal $true (Test-Path $hz) 'z: worktree setup failure -> handoff stays OPEN (file still present)'
Assert-Equal $syncBackBeforeZ $script:syncBackCalls.Count 'z: worktree setup failure -> SyncBackAi NOT called (no sync-back on failed dispatch)'
$script:mockWtFails = $false

# -- (aa) declared-base-branch failure -> WORKTREE_FAIL, CLI NEVER invoked --
$script:mockBranchFails = $true
$script:mockCalls = 0
$syncBackBeforeAA = $script:syncBackCalls.Count
$haa = New-TestHandoff -Slug 'aa-branch-fail'
$script:mockHandoffPath = $haa
$raa = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $haa -MaxContinues 5
Assert-Equal 'WORKTREE_FAIL' $raa.Result 'aa: declared-base-branch failure -> Result=WORKTREE_FAIL'
Assert-Equal 0 $raa.Invocations 'aa: declared-base-branch failure -> CLI NEVER invoked'
Assert-Equal 0 $script:mockCalls 'aa: declared-base-branch failure -> mock InvokeCli call count is 0'
Assert-Equal $syncBackBeforeAA $script:syncBackCalls.Count 'aa: declared-base-branch failure -> SyncBackAi NOT called (no sync-back on failed dispatch)'
$script:mockBranchFails = $false

# -- (ab) Get-DeclaredBase reads a handoff's Base: field; discovers the repo's  --
# -- default branch offline-first when absent (origin/HEAD, origin/main, main, --
# -- HEAD); never hardcodes origin/master.                                     --

# Helper: create a minimal project with a handoff file and a bare remote whose
# default branch is $DefaultBranch. Returns @{ Project = <path>; Origin = <path> }.
function New-BaseDiscoveryProject {
    param([string]$DefaultBranch)
    $proj = Join-Path $env:TEMP ("pane-runner-base-" + [guid]::NewGuid().ToString('N'))
    $origin = Join-Path $env:TEMP ("pane-runner-origin-" + [guid]::NewGuid().ToString('N') + '.git')
    New-Item -ItemType Directory -Path $proj -Force | Out-Null
    New-Item -ItemType Directory -Path $origin -Force | Out-Null
    git init --quiet --bare $origin
    git init --quiet $proj
    git -C $proj config user.email 'test@example.com'
    git -C $proj config user.name 'test'
    New-Item -ItemType Directory -Path (Join-Path $proj '.ai/handoffs/to-claude/open') -Force | Out-Null
    'seed' | Set-Content -Path (Join-Path $proj 'seed.txt')
    git -C $proj add -A
    git -C $proj commit --quiet -m 'seed'
    git -C $proj branch -M $DefaultBranch
    git -C $proj remote add origin $origin
    git -C $proj push --quiet -u origin $DefaultBranch
    # Set origin/HEAD locally without querying the remote, so the offline-first
    # resolution path is exercised and the test stays deterministic.
    git -C $proj remote set-head origin $DefaultBranch *>$null
    return @{ Project = $proj; Origin = $origin }
}

# Explicit Base: is always read verbatim.
$habExplicit = Join-Path $openDir 'ab-with-base.md'
@(
    "# Test handoff ab-with-base", "Status: OPEN", "Sender: claude-code",
    "Recipient: claude-code", "Created: 2026-07-09 00:00", "Auto: yes", "Risk: A",
    "Base: origin/develop", "", "## Goal", "test"
) -join "`n" | Set-Content -Path $habExplicit -Encoding utf8
Assert-Equal 'origin/develop' (Get-DeclaredBase-Real -HandoffPath $habExplicit) 'ab: Base: origin/develop is read verbatim'

# Repo whose default branch is master -> resolves to origin/master.
$infoMaster = New-BaseDiscoveryProject -DefaultBranch 'master'
$habMaster = Join-Path $infoMaster.Project '.ai/handoffs/to-claude/open/ab-master.md'
@(
    "# Test handoff ab-master", "Status: OPEN", "Sender: claude-code",
    "Recipient: claude-code", "Created: 2026-07-09 00:00", "Auto: yes", "Risk: A",
    "", "## Goal", "test"
) -join "`n" | Set-Content -Path $habMaster -Encoding utf8
Assert-Equal 'origin/master' (Get-DeclaredBase-Real -HandoffPath $habMaster) 'ab: repo default=master -> origin/master'

# Repo whose default branch is main -> resolves to origin/main (the bug we fixed).
$infoMain = New-BaseDiscoveryProject -DefaultBranch 'main'
$habMain = Join-Path $infoMain.Project '.ai/handoffs/to-claude/open/ab-main.md'
@(
    "# Test handoff ab-main", "Status: OPEN", "Sender: claude-code",
    "Recipient: claude-code", "Created: 2026-07-09 00:00", "Auto: yes", "Risk: A",
    "", "## Goal", "test"
) -join "`n" | Set-Content -Path $habMain -Encoding utf8
Assert-Equal 'origin/main' (Get-DeclaredBase-Real -HandoffPath $habMain) 'ab: repo default=main -> origin/main'

# Stale local refs are refreshed before resolution: push a new commit, rewind
# the local origin/main ref and break origin/HEAD, then prove Get-DeclaredBase
# fetches and returns origin/main pointing at the latest commit.
'second' | Set-Content -Path (Join-Path $infoMain.Project 'second.txt')
git -C $infoMain.Project add -A
git -C $infoMain.Project commit --quiet -m 'second on main'
$latestMainSha = git -C $infoMain.Project rev-parse HEAD
git -C $infoMain.Project push --quiet origin main
# Rewind local refs to simulate a stale/missing cache.
git -C $infoMain.Project update-ref refs/remotes/origin/main "$($latestMainSha.Substring(0,7))~1"
git -C $infoMain.Project symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/does-not-exist

$habStale = Join-Path $infoMain.Project '.ai/handoffs/to-claude/open/ab-stale.md'
@(
    "# Test handoff ab-stale", "Status: OPEN", "Sender: claude-code",
    "Recipient: claude-code", "Created: 2026-07-09 00:00", "Auto: yes", "Risk: A",
    "", "## Goal", "test"
) -join "`n" | Set-Content -Path $habStale -Encoding utf8
$resolvedStale = Get-DeclaredBase-Real -HandoffPath $habStale
Assert-Equal 'origin/main' $resolvedStale 'ab-stale: resolves origin/main after fetch'
$resolvedStaleSha = git -C $infoMain.Project rev-parse "$resolvedStale"
Assert-Equal $latestMainSha $resolvedStaleSha 'ab-stale: resolved base points at latest commit'

Remove-Item -Path $habExplicit -Force -ErrorAction SilentlyContinue
# These temp clones sometimes hold a git handle just long enough for Remove-Item
# to report "Access is denied". Swallow the error; the temp paths are harmless.
try { Remove-Item -Path $infoMaster.Project, $infoMaster.Origin -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item -Path $infoMain.Project, $infoMain.Origin -Recurse -Force -ErrorAction SilentlyContinue } catch {}

# -- (ac)/(ad): real-sandbox tests exercising the REAL (unmocked)              --
# -- Get-CliWorktreePathReal / Ensure-DeclaredBaseBranchReal / wt-bootstrap.sh  --
# -- path, mirroring test-dispatch-worktree.sh's sandbox pattern: a bare       --
# -- "origin" + a primary checkout cloned from it, with .wt/ as a SIBLING of   --
# -- the sandbox project (not $env:TEMP directly) so worktree_path_for's path  --
# -- arithmetic matches production. Skips (does not fail) if bash/git are      --
# -- unavailable, matching the fail-open posture of other environment-gated    --
# -- checks in this suite.
# Resolve bash the way PRODUCTION now does (Resolve-GitBash), not via a bare
# `Get-Command bash`. The old probe here trusted PATH and then SKIPPED when it got
# WSL bash — so in the very environment the panes run in, this block quietly
# tested nothing. Pinning Git Bash means these real-worktree tests actually RUN
# there. A genuinely bash-less box still skips (never crashes the suite).
$bashCmd = Resolve-GitBash
$gitCmd  = Get-Command git -ErrorAction SilentlyContinue
$wtBootstrapPath = Join-Path $here '..\..\scripts\wt-bootstrap.sh'
$wtBootstrapPath = [System.IO.Path]::GetFullPath($wtBootstrapPath)
# Still prove it by a real (harmless, --help) invocation rather than trusting the
# resolver's word for it — wt-bootstrap.sh takes Windows paths as arguments.
$bashUsable = $false
if ($bashCmd -and (Test-Path $wtBootstrapPath)) {
    try {
        & $bashCmd $wtBootstrapPath --help *> $null
        $bashUsable = ($LASTEXITCODE -eq 0)
    } catch { $bashUsable = $false }
}
if ($bashCmd -and $gitCmd -and $bashUsable -and (Test-Path $wtBootstrapPath)) {
    $sandbox = Join-Path $env:TEMP ("pane-runner-wt-sandbox-" + [guid]::NewGuid().ToString('N'))
    $sandboxParent = Join-Path $sandbox 'parent'
    $primary = Join-Path $sandboxParent 'proj'
    New-Item -ItemType Directory -Path $primary -Force | Out-Null
    Push-Location $primary
    try {
        git init --quiet .
        git config user.email 'test@example.com'
        git config user.name 'test'
        New-Item -ItemType Directory -Path (Join-Path $primary '.ai/handoffs/to-kiro/open') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $primary '.ai/activity') -Force | Out-Null
        'log v1' | Set-Content -Path (Join-Path $primary '.ai/activity/log.md')
        'seed' | Set-Content -Path (Join-Path $primary 'seed.txt')
        git add -A
        git commit --quiet -m seed
        git branch -M master

        $originBare = Join-Path $sandboxParent 'origin.git'
        git init --quiet --bare $originBare
        git remote add origin $originBare
        git push --quiet -u origin master

        # HEAD before ANY worktree/dispatch activity -- the regression assertion
        # for (ad) compares against this.
        $primaryHeadBefore = git rev-parse HEAD

        # (ac) Get-CliWorktreePathReal creates a real worktree; a 2nd call reuses it
        # (idempotent, matches wt-bootstrap.sh's own reuse contract).
        $realWt1 = Get-CliWorktreePathReal -ProjectDir $primary -CliName 'kiro'
        Assert-Equal $true ($null -ne $realWt1 -and (Test-Path $realWt1)) 'ac: Get-CliWorktreePathReal creates a real, usable worktree'
        $realWt2 = Get-CliWorktreePathReal -ProjectDir $primary -CliName 'kiro'
        Assert-Equal $realWt1 $realWt2 'ac: 2nd call reuses the SAME worktree path (idempotent)'

        # (ac) Ensure-DeclaredBaseBranchReal cuts exec/<cli>/<slug> from the
        # declared base, not ambient HEAD -- even when the worktree's ambient
        # HEAD is left on a DIFFERENT branch first.
        Push-Location $realWt1
        git checkout --quiet -b 'some-other-branch' 2>$null
        Pop-Location
        $baseOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'ac-test-slug' -Base 'origin/master' -ProjectDir $primary
        Assert-Equal $true $baseOk 'ac: Ensure-DeclaredBaseBranchReal succeeds'
        Push-Location $realWt1
        $branchNow = git branch --show-current
        Pop-Location
        Assert-Equal 'exec/kiro/ac-test-slug' $branchNow 'ac: branch cut is exec/<cli>/<slug> (not the pre-existing other branch)'

        # (ac) dirty-tree refusal: uncommitted changes on ANY branch -> reused
        # as-is, no new branch cut (mirrors dispatch-handoffs.sh's WARN-and-reuse).
        Push-Location $realWt1
        'dirty' | Set-Content -Path (Join-Path $realWt1 'dirty.txt')
        $dirtyBranchBefore = git branch --show-current
        Pop-Location
        $dirtyOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'should-not-cut' -Base 'origin/master' -ProjectDir $primary
        Assert-Equal $true $dirtyOk 'ac: dirty tree -> Ensure-DeclaredBaseBranchReal still returns true (WARN + reuse)'
        Push-Location $realWt1
        $dirtyBranchAfter = git branch --show-current
        Pop-Location
        Assert-Equal $dirtyBranchBefore $dirtyBranchAfter 'ac: dirty tree -> branch NOT changed (refused to cut over uncommitted work)'
        Remove-Item -Path (Join-Path $realWt1 'dirty.txt') -Force -ErrorAction SilentlyContinue

        # -- (au) NATIVE-STDERR REGRESSION: git fetch that ACTUALLY FETCHES, under --
        # -- $ErrorActionPreference='Stop' (the runner's real script-level EAP).    --
        #
        # git writes ordinary progress to STDERR: `git fetch` emits "From <remote>"
        # whenever it retrieves refs, `git checkout` emits "Switched to a new
        # branch". Under EAP=Stop, PS 5.1 promotes a native command's stderr record
        # to a TERMINATING NativeCommandError — and `*> $null` does NOT suppress
        # that promotion (the throw precedes the redirect). So a perfectly
        # SUCCESSFUL fetch would throw and blow up the whole branch cut, surfacing
        # as an opaque WORKTREE_FAIL.
        #
        # Why every existing test missed it: (ac) above has a real origin, but
        # NOTHING EVER CHANGES ON IT — a fetch with nothing to fetch writes no
        # stderr and never throws. The bug is only reachable when the remote has
        # actually moved. So: advance the bare origin behind the worktree's back,
        # then cut a branch under EAP=Stop. Against the unguarded function this
        # throws; with the EAP guard it returns $true.
        $auClone = Join-Path $sandboxParent 'mover'
        git clone --quiet $originBare $auClone
        Push-Location $auClone
        git config user.email 'test@example.com'
        git config user.name 'test'
        'moved' | Set-Content -Path (Join-Path $auClone 'moved.txt')
        git add -A
        git commit --quiet -m 'advance origin so the next fetch has something to say'
        git push --quiet origin master
        Pop-Location

        # Reset the worktree to a clean, non-exec branch so the cut actually runs.
        Push-Location $realWt1
        git checkout --quiet -B 'au-clean-base' 2>$null
        Pop-Location

        $auThrew = $false
        $auOk = $false
        $auPrevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'   # exactly what pane-runner.ps1 sets at load
        try {
            $auOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'au-stderr-slug' -Base 'origin/master' -ProjectDir $primary
        } catch {
            $auThrew = $true
            Write-Host "    (au) threw: $($_.Exception.GetType().Name): $(($_.Exception.Message -split "`n")[0])" -ForegroundColor DarkYellow
        } finally {
            $ErrorActionPreference = $auPrevEAP
        }
        Assert-Equal $false $auThrew 'au: PROVE-THE-FIX - a real (stderr-emitting) git fetch under EAP=Stop does NOT throw NativeCommandError'
        Assert-Equal $true $auOk 'au: branch cut still succeeds when the remote has actually moved'
        Push-Location $realWt1
        $auBranch = git branch --show-current
        Pop-Location
        Assert-Equal 'exec/kiro/au-stderr-slug' $auBranch 'au: cut landed on exec/<cli>/<slug> from the freshly-fetched origin/master'

        # (au2) anti-rot: the EAP guard must stay in the function. Without it the
        # suite still passes from a repo whose origin happens to be up to date,
        # which is exactly how this shipped.
        $auSrc = ${function:Ensure-DeclaredBaseBranchReal}.ToString()
        Assert-Equal $true ($auSrc -match "ErrorActionPreference\s*=\s*'Continue'") `
            'au2: anti-rot - Ensure-DeclaredBaseBranchReal still forces EAP=Continue around its native git calls'
        Assert-Equal $true ($auSrc -match '\$ErrorActionPreference\s*=\s*\$prevEAP') `
            'au3: anti-rot - Ensure-DeclaredBaseBranchReal restores the prior EAP in finally'

        # (bk) Base: main regression — the primary checkout has local `main` and the
        # worktree is on a different branch, so a naive resolve-inside-worktree would
        # fail. With the explicit ProjectDir fix, Base: main must still resolve and
        # cut exec/<cli>/<slug> from it. This reproduces the production failure where
        # a return handoff addressed to claude carried Base: main and the claude
        # worktree had no local main branch.
        Push-Location $primary
        git branch -M main
        git push --quiet -u origin main
        git remote set-head origin main
        Pop-Location
        Push-Location $realWt1
        git checkout --quiet -B 'bk-not-main' 2>$null
        Pop-Location
        $bkOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'bk-main-base-slug' -Base 'main' -ProjectDir $primary
        Assert-Equal $true $bkOk 'bk: Base: main resolves via explicit ProjectDir'
        Push-Location $realWt1
        $bkBranch = git branch --show-current
        Pop-Location
        Assert-Equal 'exec/kiro/bk-main-base-slug' $bkBranch 'bk: branch cut from Base: main lands on exec/<cli>/<slug>'

        # (ad) THE REGRESSION TEST: two concurrent Invoke-HandoffRun calls for two
        # DIFFERENT CLIs, each resolving its OWN real worktree via the real
        # (unmocked) functions, must never perturb each other's HEAD/files, and
        # the PRIMARY checkout's HEAD must be unchanged throughout. This is the
        # Kimi-in-the-primary-checkout incident, reproduced and asserted against.
        $script:GetCliWorktreePath = { param([string]$ProjectDir, [string]$CliName) return (Get-CliWorktreePathReal -ProjectDir $ProjectDir -CliName $CliName) }
        $script:EnsureDeclaredBaseBranch = { param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base, [string]$ProjectDir) return (Ensure-DeclaredBaseBranchReal -WtPath $WtPath -CliName $CliName -Slug $Slug -Base $Base -ProjectDir $ProjectDir) }

        $adOpenKiro = Join-Path $primary '.ai/handoffs/to-kiro/open'
        $adOpenClaude = Join-Path $primary '.ai/handoffs/to-claude/open'
        New-Item -ItemType Directory -Path $adOpenClaude -Force | Out-Null
        function New-SandboxHandoff {
            param([string]$Dir, [string]$Slug)
            $p = Join-Path $Dir "$Slug.md"
            @("# $Slug", "Status: OPEN", "Sender: claude-code", "Recipient: x", "Created: 2026-07-09 00:00", "Auto: yes", "Risk: A", "", "## Goal", "test") -join "`n" | Set-Content -Path $p -Encoding utf8
            return $p
        }
        $adHandoffKiro = New-SandboxHandoff -Dir $adOpenKiro -Slug 'ad-kiro-run'
        $adHandoffClaude = New-SandboxHandoff -Dir $adOpenClaude -Slug 'ad-claude-run'

        # Each CLI's InvokeCli: write a marker file INTO ITS OWN worktree cwd,
        # then delete its own handoff (simulating self-retire) -- proving each
        # ran in ITS OWN tree and never touched the other's.
        $script:InvokeCli = {
            param([string]$CliName, [string]$Prompt, [string]$Cwd = (Get-Location).Path)
            "ran in $CliName worktree" | Set-Content -Path (Join-Path $Cwd "marker-$CliName.txt")
            $target = if ($CliName -eq 'kiro') { $adHandoffKiro } else { $adHandoffClaude }
            Remove-Item -Path $target -Force -ErrorAction SilentlyContinue
            return 0
        }

        $rKiro = Invoke-HandoffRun -ProjectDir $primary -CliName 'kiro' -HandoffPath $adHandoffKiro -MaxContinues 1
        $rClaudeAuto = Invoke-HandoffRun -ProjectDir $primary -CliName 'claude' -HandoffPath $adHandoffClaude -MaxContinues 1

        Assert-Equal 'DONE' $rKiro.Result 'ad: kiro run completes DONE in its own worktree'
        Assert-Equal 'DONE' $rClaudeAuto.Result 'ad: claude run completes DONE in its own worktree'

        $kiroWt = Get-CliWorktreePathFor -ProjectDir $primary -CliName 'kiro'
        $claudeWt = Get-CliWorktreePathFor -ProjectDir $primary -CliName 'claude'
        Assert-Equal $true (Test-Path (Join-Path $kiroWt 'marker-kiro.txt')) 'ad: kiro marker landed in the KIRO worktree'
        Assert-Equal $true (Test-Path (Join-Path $claudeWt 'marker-claude.txt')) 'ad: claude marker landed in the CLAUDE worktree'
        Assert-Equal $false (Test-Path (Join-Path $kiroWt 'marker-claude.txt')) 'ad: claude marker did NOT leak into the kiro worktree'
        Assert-Equal $false (Test-Path (Join-Path $claudeWt 'marker-kiro.txt')) 'ad: kiro marker did NOT leak into the claude worktree'
        Assert-Equal $false (Test-Path (Join-Path $primary 'marker-kiro.txt')) 'ad: kiro marker did NOT land in the PRIMARY checkout'
        Assert-Equal $false (Test-Path (Join-Path $primary 'marker-claude.txt')) 'ad: claude marker did NOT land in the PRIMARY checkout'

        $primaryHeadAfter = git rev-parse HEAD
        Assert-Equal $primaryHeadBefore $primaryHeadAfter 'ad: PRIMARY checkout HEAD unchanged after both dispatches (the incident regression)'

        # restore the (a-x) mocks for anything running after this block
        $script:GetCliWorktreePath = {
            param([string]$ProjectDir, [string]$CliName)
            $script:lastWtCliName = $CliName
            if ($script:mockWtFails) { return $null }
            return $script:mockWtPath
        }
        $script:EnsureDeclaredBaseBranch = {
            param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base, [string]$ProjectDir)
            $script:lastBranchArgs = @{ WtPath = $WtPath; CliName = $CliName; Slug = $Slug; Base = $Base; ProjectDir = $ProjectDir }
            if ($script:mockBranchFails) { return $false }
            return $true
        }
        $script:InvokeCli = {
            param([string]$CliName, [string]$Prompt, [string]$Cwd = (Get-Location).Path)
            $script:mockCalls++
            $script:lastInvokeCwd = $Cwd
            if ($script:mockDeleteOnCall -gt 0 -and $script:mockCalls -eq $script:mockDeleteOnCall) {
                Remove-Item -Path $script:mockHandoffPath -Force
            }
            return 0
        }

        # -- (av) ADR-0016 SNAPSHOT-COPY REGRESSION: the dispatcher copies canonical
        # .ai/ into the worktree as ordinary files and syncs changes back. There
        # is NO junction, so git cannot follow a reparse point and destroy
        # canonical .ai/ state. Use the real sandbox worktree and the real
        # SnapshotAi/SyncBackAi hooks.
        $script:SnapshotAi = {
            param([string]$ProjectDir, [string]$WtPath)
            $bash = Resolve-GitBash
            $sync = Join-Path $ProjectDir '.ai/tools/sync-ai-state.sh'
            & $bash $sync snapshot "$ProjectDir/.ai" "$WtPath/.ai" 2>&1 | ForEach-Object { Write-Host "  [snapshot-ai] $_" -ForegroundColor DarkGray }
            return ($LASTEXITCODE -eq 0)
        }
        $script:SyncBackAi = {
            param([string]$ProjectDir, [string]$WtPath)
            $bash = Resolve-GitBash
            $sync = Join-Path $ProjectDir '.ai/tools/sync-ai-state.sh'
            & $bash $sync sync-back "$WtPath" "$ProjectDir" 2>&1 | ForEach-Object { Write-Host "  [sync-back-ai] $_" -ForegroundColor DarkGray }
        }

        # Ensure the sync-ai-state.sh tool exists in the sandbox project so the
        # real hooks can find it.
        $avTools = Join-Path $primary '.ai/tools'
        New-Item -ItemType Directory -Path $avTools -Force | Out-Null
        Copy-Item -Path (Join-Path $here '../../.ai/tools/sync-ai-state.sh') -Destination $avTools
        $avOpen = Join-Path $primary '.ai/handoffs/to-kimi/open'
        New-Item -ItemType Directory -Path $avOpen -Force | Out-Null
        $avHandoff = Join-Path $avOpen 'av-snapshot.md'
        @("# av-snapshot", "Status: OPEN", "Sender: test", "Recipient: kimi-cli", "Created: 2026-07-17 00:00", "Auto: yes", "Risk: A", "", "## Goal", "snapshot-copy probe") -join "`n" | Set-Content -Path $avHandoff -Encoding utf8

        # Mock CLI writes a report into the worktree's snapshot .ai/ and deletes
        # the canonical handoff.
        $script:InvokeCli = {
            param([string]$CliName, [string]$Prompt, [string]$Cwd = (Get-Location).Path)
            New-Item -ItemType Directory -Path (Join-Path $Cwd '.ai/reports') -Force | Out-Null
            'synced report from worktree' | Set-Content -Path (Join-Path $Cwd '.ai/reports/av-synced.md')
            Remove-Item -Path $avHandoff -Force -ErrorAction SilentlyContinue
            return 0
        }

        # Use the real worktree and branch-cut functions for this regression test.
        $script:GetCliWorktreePath = { param([string]$ProjectDir, [string]$CliName) return (Get-CliWorktreePathReal -ProjectDir $ProjectDir -CliName $CliName) }
        $script:EnsureDeclaredBaseBranch = { param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base, [string]$ProjectDir) return (Ensure-DeclaredBaseBranchReal -WtPath $WtPath -CliName $CliName -Slug $Slug -Base $Base -ProjectDir $ProjectDir) }

        $avWt = Get-CliWorktreePathFor -ProjectDir $primary -CliName 'kimi'
        $avResult = Invoke-HandoffRun -ProjectDir $primary -CliName 'kimi' -HandoffPath $avHandoff -MaxContinues 1
        Assert-Equal 'DONE' $avResult.Result 'av: snapshot-copy handoff completes DONE'
        Assert-Equal $true (Test-Path (Join-Path $primary '.ai/reports/av-synced.md')) 'av: report written in worktree .ai/ synced back to canonical'
        Assert-Equal $false (Test-Path (Join-Path $avWt '.ai')) 'av: worktree .ai/ removed after sync-back'

        # Restore the (a-x) mocks.
        $script:GetCliWorktreePath = {
            param([string]$ProjectDir, [string]$CliName)
            $script:lastWtCliName = $CliName
            if ($script:mockWtFails) { return $null }
            return $script:mockWtPath
        }
        $script:EnsureDeclaredBaseBranch = {
            param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base, [string]$ProjectDir)
            $script:lastBranchArgs = @{ WtPath = $WtPath; CliName = $CliName; Slug = $Slug; Base = $Base; ProjectDir = $ProjectDir }
            if ($script:mockBranchFails) { return $false }
            return $true
        }
        $script:SnapshotAi = {
            param([string]$ProjectDir, [string]$WtPath)
            $script:snapshotCalls += @{ ProjectDir = $ProjectDir; WtPath = $WtPath }
            return $true
        }
        $script:SyncBackAi = {
            param([string]$ProjectDir, [string]$WtPath)
            $script:syncBackCalls += @{ ProjectDir = $ProjectDir; WtPath = $WtPath }
        }

    } finally {
        Pop-Location
        try { git -C $primary worktree prune 2>$null | Out-Null } catch {}
        try { Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
} else {
    Write-Host "SKIP  ac/ad: no USABLE bash for wt-bootstrap.sh (present bash may be WSL, which cannot see Windows paths - see README's documented gotcha) - skipping real-sandbox worktree tests" -ForegroundColor DarkGray
}

# -- (ae/af/ag) idle heartbeat (F1) --
# Shadow the Write-Host cmdlet with a capturing function for these tests only;
# Write-IdleHeartbeat's boolean return carries the emit/throttle decision, and
# the captured line carries the content. Removed again right after (ag).
$script:hostLines = @()
function Write-Host {
    param([object]$Object, $ForegroundColor)
    $script:hostLines += [string]$Object
    # Forward to the real cmdlet so test PASS/FAIL lines stay visible while the
    # heartbeat line is captured for assertion.
    if ($ForegroundColor) { Microsoft.PowerShell.Utility\Write-Host -Object $Object -ForegroundColor $ForegroundColor } else { Microsoft.PowerShell.Utility\Write-Host -Object $Object }
}

# (ae) first idle poll emits immediately, and the line names the CLI + a timestamp
$script:hostLines = @()
$hbLast = $null
$emitted = Write-IdleHeartbeat -CliName 'kimi' -LastEmitted ([ref]$hbLast)
Assert-Equal $true $emitted 'ae: first idle poll emits the heartbeat'
Assert-Equal $true ($script:hostLines[0] -match '\[kimi\]') 'ae: heartbeat line contains the CLI name'
Assert-Equal $true ($script:hostLines[0] -match '\(\d{2}:\d{2}:\d{2}\)') 'ae: heartbeat line contains a timestamp'

# (af) throttled: 10 rapid idle polls emit exactly ONE heartbeat, not one per poll
$script:hostLines = @()
$hbLast2 = $null
$emitCount = 0
for ($i = 0; $i -lt 10; $i++) { if (Write-IdleHeartbeat -CliName 'kimi' -LastEmitted ([ref]$hbLast2)) { $emitCount++ } }
Assert-Equal 1 $emitCount 'af: 10 rapid idle polls -> exactly 1 heartbeat (throttled, not every poll)'

# (ag) once the interval has elapsed, the next idle poll emits again
$hbLast2 = (Get-Date).AddSeconds(-($script:IdleHeartbeatSeconds + 1))
$emitted = Write-IdleHeartbeat -CliName 'kimi' -LastEmitted ([ref]$hbLast2)
Assert-Equal $true $emitted 'ag: heartbeat re-emits once IdleHeartbeatSeconds has elapsed'

Remove-Item -Path function:Write-Host -Force

# -- (ah/ai) structural guards on the supervisor loop (F1) --
$runnerSrc = Get-Content -Path $runner -Raw
# (ah) the heartbeat is idle-only: exactly one call site, inside the null-handoff branch
$hbRefs = ([regex]::Matches($runnerSrc, 'Write-IdleHeartbeat -CliName')).Count
Assert-Equal 1 $hbRefs 'ah: Write-IdleHeartbeat has exactly one call site'
Assert-Equal $true ($runnerSrc -match 'if \(\$null -eq \$handoff\) \{\s*Write-IdleHeartbeat') 'ah: heartbeat fires only in the no-handoff (idle) branch'
# (ai) the idle->busy transition prints a picked-up line, AFTER the claim is won
$idxPick = $runnerSrc.IndexOf('-- picked up')
$idxClaim = $runnerSrc.IndexOf('if (-not (Claim-Handoff')
Assert-Equal $true ($idxPick -ge 0) 'ai: picked-up line present on the idle->busy transition'
Assert-Equal $true ($idxPick -gt $idxClaim) 'ai: picked-up line prints only after the claim is won'

# -- (aj) Enable/Restore-DispatchGuardEnv round trip (F3 + auto-pane identity) --
$env:AI_HANDOFF_DISPATCH = 'outer-value'
$env:AI_HANDOFF_AUTO     = 'outer-auto'
$prev = Enable-DispatchGuardEnv
Assert-Equal 'outer-value' $prev.Dispatch 'aj: Enable-DispatchGuardEnv returns the prior Dispatch value'
Assert-Equal 'outer-auto'   $prev.Auto     'aj: Enable-DispatchGuardEnv returns the prior Auto value'
Assert-Equal '1' $env:AI_HANDOFF_DISPATCH 'aj: Enable-DispatchGuardEnv sets AI_HANDOFF_DISPATCH=1'
Assert-Equal '1' $env:AI_HANDOFF_AUTO     'aj: Enable-DispatchGuardEnv sets AI_HANDOFF_AUTO=1'
Restore-DispatchGuardEnv -Previous $prev
Assert-Equal 'outer-value' $env:AI_HANDOFF_DISPATCH 'aj: Restore-DispatchGuardEnv restores the prior Dispatch value'
Assert-Equal 'outer-auto'   $env:AI_HANDOFF_AUTO     'aj: Restore-DispatchGuardEnv restores the prior Auto value'
Remove-Item -Path Env:\AI_HANDOFF_DISPATCH
Remove-Item -Path Env:\AI_HANDOFF_AUTO
$prevUnset = Enable-DispatchGuardEnv
Assert-Equal $true (($null -eq $prevUnset.Dispatch) -and ($null -eq $prevUnset.Auto)) 'aj: prior value is $null when the var was unset'
Restore-DispatchGuardEnv -Previous $prevUnset
Assert-Equal $false (Test-Path Env:\AI_HANDOFF_DISPATCH) 'aj: restore removes AI_HANDOFF_DISPATCH when it was previously unset'
Assert-Equal $false (Test-Path Env:\AI_HANDOFF_AUTO)     'aj: restore removes AI_HANDOFF_AUTO when it was previously unset'

# -- (ak) REAL invoke path: the spawned child actually inherits AI_HANDOFF_DISPATCH=1 --
#     Stub Get-HeadlessCmd with a real native child (cmd, like test p - never a
#     real CLI) that exits 7 ONLY if the guard var reached its environment.
#     InvokeCli returns the child exit code, so the env assertion needs no
#     output capture. Also proves the runner env is cleaned up afterwards, AND
#     (the point of this rebase) that the worktree-cwd param does not disturb
#     the env-guard behavior when both are exercised through the SAME call.
$origHeadlessCc = ${function:Get-HeadlessCmd}
function Get-HeadlessCmd { param([string]$CliName, [string]$Prompt) return @('cmd', '/c', 'if "%AI_HANDOFF_DISPATCH%"=="1" if "%AI_HANDOFF_AUTO%"=="1" (exit 7) else (exit 9)') }
$ccCode = & $script:RealInvokeCli 'claude' 'ignored-prompt'
${function:Get-HeadlessCmd} = $origHeadlessCc
Assert-Equal 7 $ccCode 'ak: child spawned by real InvokeCli sees AI_HANDOFF_DISPATCH=1 and AI_HANDOFF_AUTO=1 (exit 7)'
Assert-Equal $false (Test-Path Env:\AI_HANDOFF_DISPATCH) 'ak: AI_HANDOFF_DISPATCH removed from runner env after the call'
Assert-Equal $false (Test-Path Env:\AI_HANDOFF_AUTO)     'ak: AI_HANDOFF_AUTO removed from runner env after the call'

# -- (al) GUARD: the assignments must never silently disappear from the source --
#     Removing AI_HANDOFF_DISPATCH from the child env re-arms the nested
#     self-dispatch race (F3); if it is ever dropped, this test fails loudly.
#     AI_HANDOFF_AUTO tells a cockpit binary it is acting as the auto pane.
Assert-Equal $true ($runnerSrc.Contains('$env:AI_HANDOFF_DISPATCH = ''1''')) 'al: GUARD - AI_HANDOFF_DISPATCH=1 assignment present in pane-runner source'
Assert-Equal $true ($runnerSrc.Contains('$env:AI_HANDOFF_AUTO     = ''1''')) 'al: GUARD - AI_HANDOFF_AUTO=1 assignment present in pane-runner source'

# -- (am) THE INTERLEAVE PROOF (this rebase's own acceptance test): a single --
# -- real InvokeCli call must honor BOTH the worktree cwd param AND the      --
# -- AI_HANDOFF_DISPATCH env guard AT THE SAME TIME. Prior tests (y)/(ad)    --
# -- prove cwd alone; (ak) proves the env guard alone with the DEFAULT cwd.  --
# -- This proves neither wrapper silently drops or reorders the other.      --
$amDir = Join-Path $env:TEMP ("pane-runner-interleave-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $amDir -Force | Out-Null
try {
    $origHeadlessAm = ${function:Get-HeadlessCmd}
    function Get-HeadlessCmd { param([string]$CliName, [string]$Prompt) return @('cmd', '/c', 'if "%AI_HANDOFF_DISPATCH%"=="1" (echo %CD%>cwd.txt & exit 7) else (exit 9)') }
    $amCode = & $script:RealInvokeCli 'claude' 'ignored-prompt' $amDir
    ${function:Get-HeadlessCmd} = $origHeadlessAm
    Assert-Equal 7 $amCode 'am: interleave - env guard fires (exit 7) with an explicit non-default cwd passed too'
    $amCwdFile = Join-Path $amDir 'cwd.txt'
    Assert-Equal $true (Test-Path $amCwdFile) 'am: interleave - child actually ran IN $amDir (cwd.txt written there, not elsewhere)'
    if (Test-Path $amCwdFile) {
        $amSeenCwd = (Get-Content -Path $amCwdFile -Raw).Trim().TrimEnd('\')
        Assert-Equal ($amDir.TrimEnd('\')) $amSeenCwd 'am: interleave - child process cwd (%CD%) equals the Cwd param, not the caller location'
    }
    Assert-Equal $false (Test-Path Env:\AI_HANDOFF_DISPATCH) 'am: interleave - AI_HANDOFF_DISPATCH still cleaned up from runner env with a non-default cwd too'
    Assert-Equal $false (Test-Path Env:\AI_HANDOFF_AUTO)     'am: interleave - AI_HANDOFF_AUTO also cleaned up from runner env with a non-default cwd too'
} finally {
    try { Remove-Item -Path $amDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

# -- (an) REAL invoke path: the spawned child inherits UTF-8 locale env vars (S3-1) --
#     Guards the root-cause fix for cp1252 em-dash corruption: any bash/PowerShell
#     subprocess the CLI spawns must see C.UTF-8 so non-ASCII chars are UTF-8.
$origHeadlessAn = ${function:Get-HeadlessCmd}
function Get-HeadlessCmd { param([string]$CliName, [string]$Prompt) return @('cmd', '/c', 'if "%LC_ALL%"=="C.UTF-8" if "%LANG%"=="C.UTF-8" (exit 7) else (exit 9)') }
$anCode = & $script:RealInvokeCli 'claude' 'ignored-prompt'
${function:Get-HeadlessCmd} = $origHeadlessAn
Assert-Equal 7 $anCode 'an: child spawned by real InvokeCli sees LC_ALL=C.UTF-8 and LANG=C.UTF-8 (exit 7)'
Assert-Equal $false (Test-Path Env:\LC_ALL) 'an: LC_ALL removed from runner env after the call'
Assert-Equal $false (Test-Path Env:\LANG) 'an: LANG removed from runner env after the call'

# -- (ao) REAL invoke path: timeout kills a hung child and returns sentinel 124. --
#     opencode run --auto does not self-exit after one prompt; without a hard cap
#     the pane runner would block forever and never poll again.
$origHeadlessAo = ${function:Get-HeadlessCmd}
function Get-HeadlessCmd { param([string]$CliName, [string]$Prompt) return @('powershell', '-NoProfile', '-Command', 'Start-Sleep -Seconds 10') }
$aoStart = Get-Date
$aoCapture = Join-Path $env:TEMP ("pane-runner-ao-capture-" + [guid]::NewGuid().ToString('N') + ".log")
$script:CliOutputCapturePath = $aoCapture
try {
    $aoCode = & $script:RealInvokeCli 'opencode' 'ignored-prompt' (Get-Location).Path 2
    $aoElapsed = (Get-Date) - $aoStart
    Assert-Equal $script:CliTimeoutExitCode $aoCode 'ao: timeout path returns sentinel 124'
    Assert-Equal $true ($aoElapsed.TotalSeconds -lt 8) 'ao: timeout killed child before 10s elapsed'
    Assert-Equal $true (Test-Path $aoCapture) 'ao: capture file was written'
} finally {
    $script:CliOutputCapturePath = $null
    try { Remove-Item -Path $aoCapture -Force -ErrorAction SilentlyContinue } catch {}
    ${function:Get-HeadlessCmd} = $origHeadlessAo
}

# -- (an-at) FLAT-INSTALL TOPOLOGY: the deployed shape, which was NEVER tested. --
#
# THE REGRESSION THIS GUARDS (2026-07-12, total fleet outage): the resolver had a
# single candidate, $PSScriptRoot/../../scripts/wt-bootstrap.sh, on the assumption
# that $PSScriptRoot is always <repo>/tools/4ai-panes/. sync-4ai-panes-install.ps1
# deploys the pane tools FLAT into ~/.rwn-auto/rwn-4AI-panes/, where that resolves
# to ~/scripts/ — nonexistent. Every pane-runner failed worktree setup and
# quarantined every handoff: kimi, kiro, opencode and claude, all of them.
#
# The old test suite passed the whole time, because every worktree test mocks
# $script:GetCliWorktreePath and therefore never reaches the resolver — and the
# suite only ever ran FROM the repo tree, where the broken path happens to
# resolve. A test that only runs in the repo tree is not testing what we ship.
#
# So these tests build a synthetic sandbox with each topology and drive the
# resolver DIRECTLY, with $ScriptRoot as a parameter (never a read of the real
# $PSScriptRoot). (an) is the prove-the-bug assertion: it asserts the OLD
# single-candidate expression finds NOTHING under a flat $ScriptRoot — i.e. it
# reproduces the outage — and the rest assert the new resolver survives it.
$sandbox = Join-Path $env:TEMP ("pane-runner-flatinstall-" + [guid]::NewGuid().ToString('N'))
$origFrameworkEnv = $env:RWN_FRAMEWORK_REPO
try {
    # Flat install dir (the DEPLOYED shape): siblings only, no ../../scripts/.
    # $sandbox/install/rwn-4AI-panes -> ../../ = $sandbox, and we never create
    # $sandbox/scripts, so candidate #2 is guaranteed absent for this $ScriptRoot.
    $flatRoot = Join-Path $sandbox 'install/rwn-4AI-panes'
    New-Item -ItemType Directory -Path $flatRoot -Force | Out-Null

    # A project that HAS its own scripts/wt-bootstrap.sh (candidate #1).
    $projWith = Join-Path $sandbox 'project-with-scripts'
    New-Item -ItemType Directory -Path (Join-Path $projWith 'scripts') -Force | Out-Null
    $projBootstrap = Join-Path $projWith 'scripts/wt-bootstrap.sh'
    Set-Content -Path $projBootstrap -Value '#!/usr/bin/env bash' -Encoding utf8

    # A project that does NOT (an adopter today: install-template.sh did not ship it).
    $projBare = Join-Path $sandbox 'project-bare'
    New-Item -ItemType Directory -Path $projBare -Force | Out-Null

    # A framework source repo (candidate #3, reached via RWN_FRAMEWORK_REPO).
    $fwRepo = Join-Path $sandbox 'framework-repo'
    New-Item -ItemType Directory -Path (Join-Path $fwRepo 'scripts') -Force | Out-Null
    $fwBootstrap = Join-Path $fwRepo 'scripts/wt-bootstrap.sh'
    Set-Content -Path $fwBootstrap -Value '#!/usr/bin/env bash' -Encoding utf8

    # A repo-tree checkout: <repo>/tools/4ai-panes -> ../../scripts EXISTS (candidate #2).
    $repoTreeRoot = Join-Path $sandbox 'repo-tree/tools/4ai-panes'
    New-Item -ItemType Directory -Path $repoTreeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'repo-tree/scripts') -Force | Out-Null
    $repoTreeBootstrap = Join-Path $sandbox 'repo-tree/scripts/wt-bootstrap.sh'
    Set-Content -Path $repoTreeBootstrap -Value '#!/usr/bin/env bash' -Encoding utf8

    # A framework repo path that does NOT exist (to prove the fail-loud path).
    $fwMissing = Join-Path $sandbox 'no-such-framework-repo'

    # (an) PROVE THE BUG: the OLD resolver's one and only candidate, evaluated
    # against the flat-install $ScriptRoot, does not exist. This is the outage.
    $oldResolverPath = Join-Path $flatRoot '../../scripts/wt-bootstrap.sh'
    Assert-Equal $false (Test-Path -LiteralPath $oldResolverPath) `
        'an: PROVE-THE-BUG - old single-candidate ($ScriptRoot/../../scripts) does NOT resolve under the flat install dir'

    # (ao) PROVE THE FIX: same flat $ScriptRoot, and the new resolver still finds
    # the bootstrap via the target project's own copy (candidate #1).
    $env:RWN_FRAMEWORK_REPO = $fwMissing
    $resolvedProj = Resolve-WtBootstrapPath -ProjectDir $projWith -ScriptRoot $flatRoot
    Assert-Equal $true ($null -ne $resolvedProj -and (Test-Path -LiteralPath $resolvedProj)) `
        'ao: PROVE-THE-FIX - flat install resolves wt-bootstrap.sh via $ProjectDir/scripts (candidate #1)'
    Assert-Equal (Resolve-Path -LiteralPath $projBootstrap).Path (Resolve-Path -LiteralPath $resolvedProj).Path `
        'ao2: flat install picks the TARGET PROJECT copy specifically'

    # (ap) Flat install + a project with NO scripts/ (an adopter): falls through
    # to the framework repo via RWN_FRAMEWORK_REPO (candidate #3). This is the
    # case that actually carries the deployed launcher for adopter projects.
    $env:RWN_FRAMEWORK_REPO = $fwRepo
    $resolvedFw = Resolve-WtBootstrapPath -ProjectDir $projBare -ScriptRoot $flatRoot
    Assert-Equal (Resolve-Path -LiteralPath $fwBootstrap).Path (Resolve-Path -LiteralPath $resolvedFw).Path `
        'ap: flat install + bare project resolves via $RWN_FRAMEWORK_REPO (candidate #3)'

    # (aq) The repo-tree/dev case (candidate #2) must still work — no regression
    # on the topology that worked before. Bare project, framework env -> missing.
    $env:RWN_FRAMEWORK_REPO = $fwMissing
    $resolvedRepo = Resolve-WtBootstrapPath -ProjectDir $projBare -ScriptRoot $repoTreeRoot
    Assert-Equal (Resolve-Path -LiteralPath $repoTreeBootstrap).Path (Resolve-Path -LiteralPath $resolvedRepo).Path `
        'aq: repo-tree checkout still resolves via $ScriptRoot/../../scripts (candidate #2, no regression)'

    # (ar) Candidate ORDER: the target project's own copy beats the framework repo.
    $env:RWN_FRAMEWORK_REPO = $fwRepo
    $resolvedOrder = Resolve-WtBootstrapPath -ProjectDir $projWith -ScriptRoot $flatRoot
    Assert-Equal (Resolve-Path -LiteralPath $projBootstrap).Path (Resolve-Path -LiteralPath $resolvedOrder).Path `
        'ar: candidate order - the target project''s own copy wins over the framework repo'

    # (as) FAIL LOUD: nothing exists anywhere -> $null (never a silent guess).
    $env:RWN_FRAMEWORK_REPO = $fwMissing
    $resolvedNone = Resolve-WtBootstrapPath -ProjectDir $projBare -ScriptRoot $flatRoot
    Assert-Equal $null $resolvedNone `
        'as: fail-loud - no candidate exists anywhere -> $null (no silent fallback)'
    $candidates = @(Get-WtBootstrapCandidates -ProjectDir $projBare -ScriptRoot $flatRoot)
    Assert-Equal 3 $candidates.Count 'as2: fail-loud - all 3 candidates are reportable to the operator'

    # (at) ANTI-ROT WIRING GUARD: $script:InvokeWtBootstrap must go THROUGH the
    # multi-candidate resolver, not re-hardcode a single path. This cannot be
    # asserted by calling it (it reads the REAL $PSScriptRoot, where candidate #2
    # exists in the repo tree and would shell out to bash), so assert on its
    # source — the same technique test-selector-e2e.ps1's "Guard 0" uses for the
    # RWN_FRAMEWORK_REPO contract. Without this, someone "simplifies" the resolver
    # back to one hardcoded path and the suite still passes from the repo tree,
    # which is exactly how the 2026-07-12 outage shipped green.
    $wtSrc = $script:InvokeWtBootstrap.ToString()
    Assert-Equal $true ($wtSrc -match 'Resolve-WtBootstrapPath') `
        'at: anti-rot - InvokeWtBootstrap resolves via Resolve-WtBootstrapPath (not a hardcoded path)'
    Assert-Equal $false ($wtSrc -match '\$bootstrap\s*=\s*Join-Path\s+\$PSScriptRoot') `
        'at2: anti-rot - the old single-candidate $PSScriptRoot/../../scripts assignment is gone'
} finally {
    if ($null -eq $origFrameworkEnv) { Remove-Item Env:RWN_FRAMEWORK_REPO -ErrorAction SilentlyContinue }
    else { $env:RWN_FRAMEWORK_REPO = $origFrameworkEnv }
    try { Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

# ---------------------------------------------------------------------------
# (au-ax) GIT BASH PINNING — the 2026-07-12 fleet outage.
#
# The panes' `bash` resolved to WSL's C:\Windows\System32\bash.exe (persisted
# PATH puts system32 first; Git ships only ...\Git\cmd, which has git.exe but NO
# bash.exe). WSL bash re-parses its args as a shell string, eating the
# backslashes of the Windows path it is handed:
#   C:\Users\...\wt-bootstrap.sh -> C:Users...wt-bootstrap.sh  (exit 127)
# Every headless dispatch died there, three strikes, whole fleet quarantined.
#
# The bitter part: the hazard is documented at ~line 463 of THIS file and the
# (ac)/(ad) block SKIPS on WSL bash — but the PRODUCTION resolver never got the
# same guard. Knowledge in the repo, acted on only by the test. These cases put
# the guard where it belongs: on the resolver itself.
# ---------------------------------------------------------------------------

# (au) prove-the-bug / prove-the-fix: even when a WSL-shaped path is the ONLY
# probe candidate, the resolver must REJECT it and fall through to real Git Bash.
# The old code (`Get-Command bash` first, no rejection) returned it.
$wslShaped = Join-Path $env:WINDIR 'System32\bash.exe'
$resolvedWithWslProbe = Resolve-GitBash -ProbePaths @($wslShaped)
Assert-Equal $false ($resolvedWithWslProbe -eq $wslShaped) `
    'au: Resolve-GitBash REJECTS a WSL System32\bash.exe candidate'
Assert-Equal $true ($null -eq $resolvedWithWslProbe -or $resolvedWithWslProbe -notmatch '(?i)System32') `
    'au2: Resolve-GitBash never returns anything under System32'

# (av) Store/WindowsApps alias is rejected the same way.
$storeShaped = 'C:\Users\x\AppData\Local\Microsoft\WindowsApps\bash.exe'
Assert-Equal $false ((Resolve-GitBash -ProbePaths @($storeShaped)) -eq $storeShaped) `
    'av: Resolve-GitBash REJECTS a WindowsApps (Store alias) candidate'

# (aw) preference: on a box with Git for Windows, the resolver finds Git Bash —
# by probe, or derived from git.exe — even with a poisoned probe list.
$gitBashResolved = Resolve-GitBash -ProbePaths @($wslShaped)
if (Get-Command git -ErrorAction SilentlyContinue) {
    Assert-Equal $true ($null -ne $gitBashResolved) 'aw: Git present -> Resolve-GitBash resolves a bash'
    Assert-Equal $true ($gitBashResolved -match '(?i)bash\.exe$') 'aw2: resolved candidate is a bash.exe'
    Assert-Equal $true ($gitBashResolved -notmatch '(?i)System32|WindowsApps') 'aw3: resolved bash is NOT WSL/Store'
} else {
    Write-Host "  SKIP aw: git not on PATH" -ForegroundColor Yellow
}

# (ax) THE PROOF THE OLD TESTS NEVER HAD: a REAL, non-stubbed invocation. Every
# existing bash assertion in this suite stubs $script:InvokeWtBootstrap — which
# is precisely why a resolver that could never launch bash shipped green. Run
# the ACTUAL resolved Git Bash against the ACTUAL wt-bootstrap.sh and require
# exit 0 + a usage banner, with the Windows backslash path UNCONVERTED (proving
# path conversion was never the fix).
$axBootstrap = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\scripts\wt-bootstrap.sh'))
$axBash = Resolve-GitBash
if ($axBash -and (Test-Path $axBootstrap)) {
    $prevEAPax = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $axOut = & $axBash $axBootstrap --help 2>&1 | Out-String
        $axExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEAPax }
    Assert-Equal 0 $axExit 'ax: REAL invocation - resolved Git Bash runs wt-bootstrap.sh --help, exit 0'
    Assert-Equal $true ($axOut -match 'wt-bootstrap\.sh') 'ax2: REAL invocation - usage banner came back'
    Assert-Equal $false ($axOut -match 'No such file or directory') `
        'ax3: REAL invocation - no WSL backslash-eating "No such file" failure'
} else {
    Write-Host "  SKIP ax: no Git Bash or wt-bootstrap.sh on this box" -ForegroundColor Yellow
}

# (ay) ANTI-ROT: InvokeWtBootstrap must go through Resolve-GitBash, and the old
# unguarded `Get-Command bash` must never come back. Source-level, same technique
# as (at) — a future "simplification" back to Get-Command bash re-breaks the fleet.
$wtSrc2 = $script:InvokeWtBootstrap.ToString()
Assert-Equal $true ($wtSrc2 -match 'Resolve-GitBash') `
    'ay: anti-rot - InvokeWtBootstrap resolves bash via Resolve-GitBash'
Assert-Equal $false ($wtSrc2 -match 'Get-Command\s+bash') `
    'ay2: anti-rot - the unguarded `Get-Command bash` is gone from InvokeWtBootstrap'

# ---------------------------------------------------------------------------
# (ba-be) PANE LIVENESS HEARTBEAT SIDECAR — fleet-health.sh's dead-man's switch.
# The supervisor loop writes .ai/.heartbeat-<cli>.json once per poll cycle;
# fleet-health.sh treats a missing/stale file as "queue unwatched" (STALL).
# ---------------------------------------------------------------------------

# (ba) Write-Heartbeat writes the sidecar with the full contract field set.
$hbPath = Get-HeartbeatPath -ProjectDir $work -CliName 'kimi'
Write-Heartbeat -ProjectDir $work -CliName 'kimi' -MyPid $PID -CurrentHandoff 'idle'
Assert-Equal $true (Test-Path $hbPath) 'ba: Write-Heartbeat writes .ai/.heartbeat-<cli>.json'
$hb = Get-Content -Path $hbPath -Raw | ConvertFrom-Json
Assert-Equal 'kimi' $hb.cli 'ba2: sidecar carries cli'
Assert-Equal $PID $hb.pid 'ba3: sidecar carries the writer pid'
Assert-Equal ([System.Net.Dns]::GetHostName()) $hb.host 'ba4: sidecar carries the host'
Assert-Equal 'idle' $hb.handoff 'ba5: idle cycle records handoff=''idle'''
$hbTs = [datetime]::MinValue
Assert-Equal $true ([datetime]::TryParse([string]$hb.ts, [ref]$hbTs)) 'ba6: ts parses as a datetime'
Assert-Equal $true (((Get-Date).ToUniversalTime() - $hbTs.ToUniversalTime()).TotalMinutes -lt 1) 'ba7: ts is current (UTC)'

# (bb) atomic write: temp+rename leaves NO .tmp.<pid> debris — the half-written
#      file a concurrent reader (fleet-health.sh) could catch is the entire
#      point of the Write-Claim pattern this mirrors.
$hbDir = Split-Path -Parent $hbPath
$tmpLeftovers = @(Get-ChildItem -Path $hbDir -Filter '.heartbeat-kimi.json.tmp.*' -File -ErrorAction SilentlyContinue)
Assert-Equal 0 $tmpLeftovers.Count 'bb: atomic temp+rename leaves no .tmp debris'

# (bc) a busy cycle records the current handoff leaf.
Write-Heartbeat -ProjectDir $work -CliName 'kimi' -MyPid $PID -CurrentHandoff '202607130251-pane-liveness-watchdog.md'
$hb2 = Get-Content -Path $hbPath -Raw | ConvertFrom-Json
Assert-Equal '202607130251-pane-liveness-watchdog.md' $hb2.handoff 'bc: busy cycle records the handoff leaf'

# (bd) rewriting over an existing sidecar is a clean replace (Move-Item -Force):
#      still valid JSON afterwards, still no debris.
$tmpLeftovers2 = @(Get-ChildItem -Path $hbDir -Filter '.heartbeat-kimi.json.tmp.*' -File -ErrorAction SilentlyContinue)
Assert-Equal 0 $tmpLeftovers2.Count 'bd: rewrite over an existing sidecar leaves no debris'
Assert-Equal $true ($null -ne $hb2.ts) 'bd2: rewritten sidecar is still valid JSON'

# (be) ANTI-ROT WIRING GUARD: the supervisor loop must write the heartbeat once
#      per poll cycle, fail-open — source-level, same technique as (at)/(ay).
#      Without this, deleting the call makes fleet-health.sh blind while this
#      suite stays green.
$loopSrc = (Get-Command Start-PaneRunner).Definition
Assert-Equal $true ($loopSrc -match 'Write-Heartbeat') 'be: anti-rot - Start-PaneRunner calls Write-Heartbeat'
Assert-Equal $true ($loopSrc -match 'try\s*\{[\s\S]*?Write-Heartbeat[\s\S]*?\}\s*catch') 'be2: anti-rot - the heartbeat write is fail-open (try/catch)'

# (bf) ANTI-ROT WIRING GUARD: stale worktree fail-fast (ADR-0004 disarm).
#      A pane whose branch is behind the resolved default branch must refuse to
#      start, because a junctioned .ai/ lets any checkout/restore/stash write stale
#      blobs back into the primary.
$freshSrc = (Get-Command Assert-WorktreeFresh).Definition
Assert-Equal $true ($freshSrc -match 'Resolve-DefaultBase') 'bf: Assert-WorktreeFresh resolves the default base instead of hardcoding origin/master'
Assert-Equal $true ($freshSrc -match 'HEAD\.\.\$base') 'bf1: Assert-WorktreeFresh measures HEAD..$base'
Assert-Equal $true ($loopSrc -match 'Assert-WorktreeFresh') 'bf2: Start-PaneRunner invokes the freshness guard before polling'

# (bf3) FAIL-CLOSED: when the default base cannot be resolved, Assert-WorktreeFresh
#       refuses to start rather than silently allowing an unverifiable worktree.
$emptyProj = Join-Path $env:TEMP ("pane-runner-empty-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $emptyProj -Force | Out-Null
git init --quiet $emptyProj
Assert-Equal $false (Assert-WorktreeFresh -ProjectDir $emptyProj) 'bf3: unresolvable default base -> Assert-WorktreeFresh returns $false'

# (bg-bi) REGRESSION for handoff 202607140930 (malformed -Cli spawns malformed
#         supervisors): [ValidateSet('claude','kimi','kiro','opencode')] on
#         pane-runner.ps1's $Cli parameter must reject an empty string and a
#         truncated value ('k') at PARAMETER BIND TIME, in a REAL child process
#         -- before Start-PaneRunner's loop, before any handoff logic runs, and
#         before a heartbeat/claim file is ever written. This is the "second
#         layer" defensive guard the handoff asked for; the array-unroll fix
#         (fleet-supervisor.ps1, commit f9c6536) closed the construction-site
#         root cause, but nothing previously proved the bind-time guard itself
#         actually rejects a malformed value instead of silently accepting it.
$bgWork = Join-Path ([System.IO.Path]::GetTempPath()) "pr-cli-bind-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $bgWork -Force | Out-Null

# Helper: run a script as a REAL child process with the given -Cli value and
# return (exit code, combined stdout+stderr text). Uses -File + an argument
# array (not -Command) so no nested-quoting fragility on Windows paths. Always
# quotes the -Cli value explicitly so an EMPTY string survives ProcessStartInfo
# argument-string construction instead of vanishing (which would silently turn
# "-Cli ''" into "-Cli -ProjectDir ...", the exact malformed-argv shape this
# regression exists to probe).
function Invoke-CliBindProbe {
    param([string]$ScriptPath, [string]$CliValue, [string[]]$ExtraArgs = @())
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $quotedCli = "`"$CliValue`""
    $argList = @('-NoProfile', '-NonInteractive', '-File', "`"$ScriptPath`"", '-Cli', $quotedCli, '-ProjectDir', "`"$bgWork`"") + $ExtraArgs
    $psi.Arguments = $argList -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; Output = "$stdout`n$stderr" }
}

# (bg) empty string -> bind-time rejection, non-zero exit, no pane-runner output.
$bg = Invoke-CliBindProbe -ScriptPath $runner -CliValue '' -ExtraArgs @('-NoRun')
Assert-Equal $true ($bg.ExitCode -ne 0) 'bg: pane-runner rejects empty -Cli at bind time (non-zero exit)'
Assert-Equal $true ($bg.Output -match 'ValidateSet|Cannot validate argument') 'bg2: rejection is a ValidateSet parameter-binding error, not a runtime crash'
Assert-Equal $false ($bg.Output -match 'pane-runner\s+project=') 'bg3: the pane-runner banner never printed - rejected before any loop logic ran'

# (bh) truncated single-char value ('k', the exact byte the scalar-unroll bug
#      produced for 'kimi'/'kiro') -> same bind-time rejection.
$bh = Invoke-CliBindProbe -ScriptPath $runner -CliValue 'k' -ExtraArgs @('-NoRun')
Assert-Equal $true ($bh.ExitCode -ne 0) 'bh: pane-runner rejects truncated -Cli ''k'' at bind time (non-zero exit)'
Assert-Equal $true ($bh.Output -match 'ValidateSet|Cannot validate argument') 'bh2: rejection is a ValidateSet parameter-binding error'

# (bi) same two cases against run-pane-supervised.ps1 -- the process the
#      handoff's evidence (PID 75960 CLI='k', PID 46512 empty -Cli) actually
#      named.
$supervisorPath = Join-Path $here 'run-pane-supervised.ps1'
$bi = Invoke-CliBindProbe -ScriptPath $supervisorPath -CliValue ''
Assert-Equal $true ($bi.ExitCode -ne 0) 'bi: run-pane-supervised rejects empty -Cli at bind time (non-zero exit)'
Assert-Equal $true ($bi.Output -match 'ValidateSet|Cannot validate argument') 'bi2: rejection is a ValidateSet parameter-binding error'
Assert-Equal $false ($bi.Output -match 'supervisor up:') 'bi3: the supervisor banner never printed - rejected before any respawn logic ran'

$bj = Invoke-CliBindProbe -ScriptPath $supervisorPath -CliValue 'k'
Assert-Equal $true ($bj.ExitCode -ne 0) 'bj: run-pane-supervised rejects truncated -Cli ''k'' at bind time (non-zero exit)'
Assert-Equal $true ($bj.Output -match 'ValidateSet|Cannot validate argument') 'bj2: rejection is a ValidateSet parameter-binding error'

try { Remove-Item -Path $bgWork -Recurse -Force -ErrorAction SilentlyContinue } catch {}

# -- cleanup + summary --
try { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item -Path $script:mockWtPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
Write-Host ""
Write-Host "==== pane-runner tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
