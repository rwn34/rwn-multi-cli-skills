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

# -- cleanup + summary --
Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== pane-runner tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
