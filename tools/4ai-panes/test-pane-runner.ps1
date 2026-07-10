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

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $here 'pane-runner.ps1'

# Load functions without starting the supervisor loop.
. $runner -Cli claude -ProjectDir $here -NoRun

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
    param([string]$CliName, [string]$Prompt)
    $script:mockCalls++
    if ($script:mockDeleteOnCall -gt 0 -and $script:mockCalls -eq $script:mockDeleteOnCall) {
        Remove-Item -Path $script:mockHandoffPath -Force
    }
    return 0
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

# -- cleanup + summary --
Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== pane-runner tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
