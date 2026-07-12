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
#   (ab) Get-DeclaredBase reads a handoff's Base: field; defaults to origin/master
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
    param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base)
    $script:lastBranchArgs = @{ WtPath = $WtPath; CliName = $CliName; Slug = $Slug; Base = $Base }
    if ($script:mockBranchFails) { return $false }
    return $true
}

# -- (a) done on first run --
$script:mockCalls = 0; $script:mockDeleteOnCall = 1
$h = New-TestHandoff -Slug 'a-first'
$script:mockHandoffPath = $h
$r = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $h -MaxContinues 5
Assert-Equal 'DONE' $r.Result 'a: done on first run -> Result=DONE'
Assert-Equal 0 $r.Continues 'a: done on first run -> 0 continues'
Assert-Equal 1 $r.Invocations 'a: done on first run -> 1 invocation'

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
$won = Claim-Handoff -Recipient 'claude' -HandoffPath $hc -Owner 'claude-auto'
Assert-Equal $true $won 'g: first Claim-Handoff wins -> true'
$sidecar = Get-HandoffClaimPath -Recipient 'claude' -HandoffPath $hc
Assert-Equal $true (Test-Path $sidecar) 'g: sidecar written on win'

# (h) second Claim-Handoff by a DIFFERENT owner loses while the first is live
$won2 = Claim-Handoff -Recipient 'claude' -HandoffPath $hc -Owner 'claude-code'
Assert-Equal $false $won2 'h: 2nd claim (different owner, live) loses -> false'

# (i) a STALE claim (old claimed_at) is reclaimable
$stale = [ordered]@{
    handoff    = Get-HandoffBasename -HandoffPath $hc
    recipient  = 'claude'
    owner      = 'kiro-cli'
    pid        = $PID
    host       = [System.Net.Dns]::GetHostName()
    claimed_at = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$stale | ConvertTo-Json -Compress | Set-Content -Path $sidecar -Encoding utf8 -NoNewline
$reclaimed = Claim-Handoff -Recipient 'claude' -HandoffPath $hc -Owner 'claude-auto'
Assert-Equal $true $reclaimed 'i: stale (old claimed_at) claim is reclaimable -> true'

# (j) Release-Handoff removes the sidecar
Release-Handoff -Recipient 'claude' -HandoffPath $hc
Assert-Equal $false (Test-Path $sidecar) 'j: Release-Handoff removes the sidecar'

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
$hz = New-TestHandoff -Slug 'z-worktree-fail'
$script:mockHandoffPath = $hz
$rz = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $hz -MaxContinues 5
Assert-Equal 'WORKTREE_FAIL' $rz.Result 'z: worktree setup failure -> Result=WORKTREE_FAIL'
Assert-Equal 0 $rz.Invocations 'z: worktree setup failure -> CLI NEVER invoked (Invocations=0)'
Assert-Equal 0 $script:mockCalls 'z: worktree setup failure -> mock InvokeCli call count is 0 (no fallback run)'
Assert-Equal $true (Test-Path $hz) 'z: worktree setup failure -> handoff stays OPEN (file still present)'
$script:mockWtFails = $false

# -- (aa) declared-base-branch failure -> WORKTREE_FAIL, CLI NEVER invoked --
$script:mockBranchFails = $true
$script:mockCalls = 0
$haa = New-TestHandoff -Slug 'aa-branch-fail'
$script:mockHandoffPath = $haa
$raa = Invoke-HandoffRun -ProjectDir $work -CliName 'claude' -HandoffPath $haa -MaxContinues 5
Assert-Equal 'WORKTREE_FAIL' $raa.Result 'aa: declared-base-branch failure -> Result=WORKTREE_FAIL'
Assert-Equal 0 $raa.Invocations 'aa: declared-base-branch failure -> CLI NEVER invoked'
Assert-Equal 0 $script:mockCalls 'aa: declared-base-branch failure -> mock InvokeCli call count is 0'
$script:mockBranchFails = $false

# -- (ab) Get-DeclaredBase reads a handoff's Base: field; defaults to          --
# -- origin/master when absent (mirrors dispatch-handoffs.sh base_for()).     --
$hab1 = New-TestHandoff -Slug 'ab-no-base'
Assert-Equal 'origin/master' (Get-DeclaredBase -HandoffPath $hab1) 'ab: no Base: field -> defaults to origin/master'
$hab2Path = Join-Path $openDir 'ab-with-base.md'
@(
    "# Test handoff ab-with-base", "Status: OPEN", "Sender: claude-code",
    "Recipient: claude-code", "Created: 2026-07-09 00:00", "Auto: yes", "Risk: A",
    "Base: origin/develop", "", "## Goal", "test"
) -join "`n" | Set-Content -Path $hab2Path -Encoding utf8
Assert-Equal 'origin/develop' (Get-DeclaredBase -HandoffPath $hab2Path) 'ab: Base: origin/develop is read verbatim'
Remove-Item -Path $hab1, $hab2Path -Force -ErrorAction SilentlyContinue

# -- (ac)/(ad): real-sandbox tests exercising the REAL (unmocked)              --
# -- Get-CliWorktreePathReal / Ensure-DeclaredBaseBranchReal / wt-bootstrap.sh  --
# -- path, mirroring test-dispatch-worktree.sh's sandbox pattern: a bare       --
# -- "origin" + a primary checkout cloned from it, with .wt/ as a SIBLING of   --
# -- the sandbox project (not $env:TEMP directly) so worktree_path_for's path  --
# -- arithmetic matches production. Skips (does not fail) if bash/git are      --
# -- unavailable, matching the fail-open posture of other environment-gated    --
# -- checks in this suite.
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
$gitCmd  = Get-Command git -ErrorAction SilentlyContinue
$wtBootstrapPath = Join-Path $here '..\..\scripts\wt-bootstrap.sh'
$wtBootstrapPath = [System.IO.Path]::GetFullPath($wtBootstrapPath)
# A 'bash' on PATH is not necessarily USABLE for this: on Windows it may resolve
# to WSL bash (System32\bash.exe), which cannot see Windows-style paths the way
# Git Bash does (README.md's own documented gotcha: WSL bash wants /mnt/c/...,
# Git Bash wants /c/...). wt-bootstrap.sh takes Windows paths as arguments, so
# probe with a real (harmless, --help) invocation rather than trusting presence
# on PATH — a WSL bash here must SKIP this block, not crash the whole suite.
$bashUsable = $false
if ($bashCmd -and (Test-Path $wtBootstrapPath)) {
    try {
        & $bashCmd.Source $wtBootstrapPath --help *> $null
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
        $baseOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'ac-test-slug' -Base 'origin/master'
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
        $dirtyOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'should-not-cut' -Base 'origin/master'
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
            $auOk = Ensure-DeclaredBaseBranchReal -WtPath $realWt1 -CliName 'kiro' -Slug 'au-stderr-slug' -Base 'origin/master'
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

        # (ad) THE REGRESSION TEST: two concurrent Invoke-HandoffRun calls for two
        # DIFFERENT CLIs, each resolving its OWN real worktree via the real
        # (unmocked) functions, must never perturb each other's HEAD/files, and
        # the PRIMARY checkout's HEAD must be unchanged throughout. This is the
        # Kimi-in-the-primary-checkout incident, reproduced and asserted against.
        $script:GetCliWorktreePath = { param([string]$ProjectDir, [string]$CliName) return (Get-CliWorktreePathReal -ProjectDir $ProjectDir -CliName $CliName) }
        $script:EnsureDeclaredBaseBranch = { param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base) return (Ensure-DeclaredBaseBranchReal -WtPath $WtPath -CliName $CliName -Slug $Slug -Base $Base) }

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
            param([string]$WtPath, [string]$CliName, [string]$Slug, [string]$Base)
            $script:lastBranchArgs = @{ WtPath = $WtPath; CliName = $CliName; Slug = $Slug; Base = $Base }
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
    } finally {
        Pop-Location
        try { git -C $primary worktree prune 2>$null | Out-Null } catch {}
        Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
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

# -- (aj) Enable/Restore-DispatchGuardEnv round trip (F3) --
$env:AI_HANDOFF_DISPATCH = 'outer-value'
$prev = Enable-DispatchGuardEnv
Assert-Equal 'outer-value' $prev 'aj: Enable-DispatchGuardEnv returns the prior value'
Assert-Equal '1' $env:AI_HANDOFF_DISPATCH 'aj: Enable-DispatchGuardEnv sets AI_HANDOFF_DISPATCH=1'
Restore-DispatchGuardEnv -Previous $prev
Assert-Equal 'outer-value' $env:AI_HANDOFF_DISPATCH 'aj: Restore-DispatchGuardEnv restores the prior value'
Remove-Item -Path Env:\AI_HANDOFF_DISPATCH
$prevUnset = Enable-DispatchGuardEnv
Assert-Equal $true ($null -eq $prevUnset) 'aj: prior value is $null when the var was unset'
Restore-DispatchGuardEnv -Previous $prevUnset
Assert-Equal $false (Test-Path Env:\AI_HANDOFF_DISPATCH) 'aj: restore removes the var when it was previously unset'

# -- (ak) REAL invoke path: the spawned child actually inherits AI_HANDOFF_DISPATCH=1 --
#     Stub Get-HeadlessCmd with a real native child (cmd, like test p - never a
#     real CLI) that exits 7 ONLY if the guard var reached its environment.
#     InvokeCli returns the child exit code, so the env assertion needs no
#     output capture. Also proves the runner env is cleaned up afterwards, AND
#     (the point of this rebase) that the worktree-cwd param does not disturb
#     the env-guard behavior when both are exercised through the SAME call.
$origHeadlessCc = ${function:Get-HeadlessCmd}
function Get-HeadlessCmd { param([string]$CliName, [string]$Prompt) return @('cmd', '/c', 'if "%AI_HANDOFF_DISPATCH%"=="1" (exit 7) else (exit 9)') }
$ccCode = & $script:RealInvokeCli 'claude' 'ignored-prompt'
${function:Get-HeadlessCmd} = $origHeadlessCc
Assert-Equal 7 $ccCode 'ak: child spawned by real InvokeCli sees AI_HANDOFF_DISPATCH=1 (exit 7)'
Assert-Equal $false (Test-Path Env:\AI_HANDOFF_DISPATCH) 'ak: AI_HANDOFF_DISPATCH removed from runner env after the call'

# -- (al) GUARD: the assignment must never silently disappear from the source --
#     Removing AI_HANDOFF_DISPATCH from the child env re-arms the nested
#     self-dispatch race (F3); if it is ever dropped, this test fails loudly.
Assert-Equal $true ($runnerSrc.Contains('$env:AI_HANDOFF_DISPATCH = ''1''')) 'al: GUARD - AI_HANDOFF_DISPATCH=1 assignment present in pane-runner source'

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
} finally {
    Remove-Item -Path $amDir -Recurse -Force -ErrorAction SilentlyContinue
}

# -- (an-at) FLAT-INSTALL TOPOLOGY: the deployed shape, which was NEVER tested. --
#
# THE REGRESSION THIS GUARDS (2026-07-12, total fleet outage): the resolver had a
# single candidate, $PSScriptRoot/../../scripts/wt-bootstrap.sh, on the assumption
# that $PSScriptRoot is always <repo>/tools/4ai-panes/. sync-4ai-panes-install.ps1
# deploys the pane tools FLAT into ~/.rwn-auto/rwn-4AI-panes/, where that resolves
# to ~/scripts/ — nonexistent. Every pane-runner failed worktree setup and
# quarantined every handoff: kimi, kiro, opencode and claude-auto, all of them.
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
    Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# -- cleanup + summary --
Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $script:mockWtPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== pane-runner tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
