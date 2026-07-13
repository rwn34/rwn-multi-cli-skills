# test-claim-handoff.ps1 - Pester-free harness for the cockpit claim tools
# (.ai/tools/claim-handoff.sh + release-handoff.sh) and their interaction with
# the REAL pane-runner qualification path.
#
# Sibling of test-pane-runner.ps1 on purpose: that suite is owned by another
# in-flight handoff; this file drives the same dot-sourced pane-runner.ps1
# functions (Get-QualifyingHandoff, the :594-596 gate) without re-implementing
# the predicate. Conventions (sandbox, assert framework, pass/fail counting,
# summary line) mirror test-pane-runner.ps1.
#
# Asserts:
#   (c1) pre-condition: the REAL Get-QualifyingHandoff picks a fresh
#        Auto:yes / Risk:B / OPEN handoff
#   (c2) claim-handoff.sh claims it: exit 0, Auto: flipped to no, sidecar
#        written under .ai/handoffs/.claims/
#   (c3) the REAL Get-QualifyingHandoff now SKIPS it (returns $null) — the
#        pane-vs-cockpit boundary, proven through pane-runner's own gate
#   (c4) REFUSE: a live foreign pid holds the claim -> exit non-zero, Auto:
#        untouched, sidecar still names the foreign owner
#   (c5) RECLAIM: that pid dies (same host) -> claim succeeds, sidecar is ours
#   (c6) IDEMPOTENT: claim again -> exit 0, handoff bytes unchanged, still
#        exactly one sidecar
#   (c7) ROUND-TRIP: release-handoff.sh -> exit 0, Auto: yes restored, sidecar
#        gone, and the REAL Get-QualifyingHandoff picks the handoff up again
#   (c8) FAIL-CLOSED: a Status: DONE handoff is refused (exit non-zero)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $here 'pane-runner.ps1'

# Load pane-runner functions without starting the supervisor loop — this is the
# REAL qualification gate (:594-596), not a test re-implementation.
. $runner -Cli kimi -ProjectDir $here -NoRun

$claimTool   = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\.ai\tools\claim-handoff.sh'))
$releaseTool = [System.IO.Path]::GetFullPath((Join-Path $here '..\..\.ai\tools\release-handoff.sh'))

# -- tiny assert framework (same shape as test-pane-runner.ps1) --
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

# -- real Git Bash via the production resolver (the same one wt-bootstrap uses) --
$bash = Resolve-GitBash
if (-not $bash) {
    Write-Host "  SKIP all: no Git Bash resolvable on this box (Resolve-GitBash = null)" -ForegroundColor Yellow
    Write-Host "==== claim-handoff tests: 0 passed, 0 failed (SKIPPED - no Git Bash) ====" -ForegroundColor Cyan
    exit 0
}
Assert-Equal $true (Test-Path $claimTool)   'c0: claim-handoff.sh exists at .ai/tools/'
Assert-Equal $true (Test-Path $releaseTool) 'c0b: release-handoff.sh exists at .ai/tools/'

# Run a claim tool through REAL Git Bash; returns @{ Out; Code }. EAP is relaxed
# around the native call (same pattern as test (ax)) so a non-zero exit is data,
# not a terminating error.
function Invoke-ClaimTool {
    param([string]$Tool, [string]$HandoffPath)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $bash $Tool $HandoffPath 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEAP }
    return @{ Out = $out; Code = $code }
}

# -- temp workspace: mirrors the real .ai/handoffs layout under a sandbox root --
$work = Join-Path $env:TEMP ("claim-handoff-test-" + [guid]::NewGuid().ToString('N'))
$openDir = Join-Path $work ".ai/handoffs/to-kimi/open"
New-Item -ItemType Directory -Path $openDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $work ".ai/handoffs/.claims") -Force | Out-Null

function New-TestHandoff {
    param([string]$Slug, [string]$Auto = 'yes', [string]$Risk = 'B', [string]$Status = 'OPEN')
    $p = Join-Path $openDir "$Slug.md"
    @(
        "# Test handoff $Slug",
        "Status: $Status",
        "Sender: claude-code",
        "Recipient: kimi-cli",
        "Created: 2026-07-13 10:00",
        "Auto: $Auto",
        "Risk: $Risk",
        "",
        "## Goal",
        "scratch - never dispatched"
    ) -join "`n" | Set-Content -Path $p -Encoding utf8
    return $p
}

function Get-AutoLine {
    param([string]$HandoffPath)
    return ((Get-Content -Path $HandoffPath -TotalCount 20) -match '^\s*Auto:') -join ''
}

function Get-ClaimSidecar {
    param([string]$HandoffPath)
    return (Get-HandoffClaimPath -Recipient 'kimi' -HandoffPath $HandoffPath)
}

try {
    # -- (c1) pre-condition: the REAL pane qualification gate picks it up --
    $h = New-TestHandoff -Slug '202607131000-c1-roundtrip'
    $picked = Get-QualifyingHandoff -ProjectDir $work -CliName 'kimi'
    Assert-Equal $h $picked 'c1: REAL Get-QualifyingHandoff picks the fresh Auto:yes/Risk:B handoff'

    # -- (c2) claim it: exit 0, Auto: no, sidecar written --
    $r = Invoke-ClaimTool -Tool $claimTool -HandoffPath $h
    Assert-Equal 0 $r.Code 'c2: claim-handoff.sh exits 0'
    Assert-Equal 'Auto: no' (Get-AutoLine $h).Trim() 'c2b: Auto: flipped to no on disk'
    $sc = Get-ClaimSidecar $h
    Assert-Equal $true (Test-Path $sc) 'c2c: claim sidecar written under .ai/handoffs/.claims/'

    # -- (c3) the REAL gate now SKIPS it --
    $picked = Get-QualifyingHandoff -ProjectDir $work -CliName 'kimi'
    Assert-Equal $null $picked 'c3: REAL Get-QualifyingHandoff SKIPS the claimed (Auto:no) handoff'

    # -- (c4) REFUSE: a live foreign pid holds the claim --
    Get-ChildItem -Path $openDir -Filter '*.md' | Remove-Item -Force
    Get-ChildItem -Path (Join-Path $work ".ai/handoffs/.claims") -Filter '*.json' -ErrorAction SilentlyContinue | Remove-Item -Force
    $h2 = New-TestHandoff -Slug '202607131001-c4-refuse'
    $proc = Start-Process -PassThru -WindowStyle Hidden -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 120'
    $hostName = [System.Net.Dns]::GetHostName()
    $freshTs = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $sc2 = Get-ClaimSidecar $h2
    @{ handoff = [System.IO.Path]::GetFileNameWithoutExtension($h2); recipient = 'kimi';
       owner = 'other-pane'; pid = $proc.Id; host = $hostName; claimed_at = $freshTs } |
        ConvertTo-Json -Compress | Set-Content -Path $sc2 -Encoding utf8
    $r = Invoke-ClaimTool -Tool $claimTool -HandoffPath $h2
    Assert-Equal $true ($r.Code -ne 0) 'c4: live foreign pid -> claim REFUSED (non-zero exit)'
    Assert-Equal $true ($r.Out -match 'REFUSED') 'c4b: refusal names itself on stderr/stdout'
    Assert-Equal 'Auto: yes' (Get-AutoLine $h2).Trim() 'c4c: refused claim left Auto: yes untouched'
    Assert-Equal $true ((Get-Content $sc2 -Raw) -match '"owner":\s*"other-pane"') 'c4d: sidecar still names the foreign owner'

    # -- (c5) RECLAIM: that pid dies on the same host -> stale -> claim succeeds --
    Stop-Process -Id $proc.Id -Force
    $dead = $false
    for ($i = 0; $i -lt 50; $i++) {
        if ($null -eq (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { $dead = $true; break }
        Start-Sleep -Milliseconds 100
    }
    Assert-Equal $true $dead 'c5: precondition - foreign pid is confirmed dead'
    $r = Invoke-ClaimTool -Tool $claimTool -HandoffPath $h2
    Assert-Equal 0 $r.Code 'c5b: dead same-host pid -> claim RECLAIMS (exit 0)'
    Assert-Equal $true ((Get-Content $sc2 -Raw) -match '"owner":\s*"kimi-cli"') 'c5c: sidecar is now ours'
    Assert-Equal 'Auto: no' (Get-AutoLine $h2).Trim() 'c5d: Auto: flipped to no'

    # -- (c6) IDEMPOTENT: claim again -> exit 0, handoff bytes unchanged, one sidecar --
    $bytesBefore = [System.IO.File]::ReadAllBytes($h2)
    $r = Invoke-ClaimTool -Tool $claimTool -HandoffPath $h2
    Assert-Equal 0 $r.Code 'c6: second claim exits 0 (idempotent)'
    $bytesAfter = [System.IO.File]::ReadAllBytes($h2)
    Assert-Equal $true ([System.Linq.Enumerable]::SequenceEqual($bytesBefore, $bytesAfter)) `
        'c6b: handoff bytes unchanged by the second claim'
    $sidecarCount = @(Get-ChildItem -Path (Join-Path $work ".ai/handoffs/.claims") -Filter '*.json').Count
    Assert-Equal 1 $sidecarCount 'c6c: still exactly one sidecar'

    # -- (c7) ROUND-TRIP: release -> Auto: yes, sidecar gone, REAL gate picks it up --
    $r = Invoke-ClaimTool -Tool $releaseTool -HandoffPath $h2
    Assert-Equal 0 $r.Code 'c7: release-handoff.sh exits 0'
    Assert-Equal 'Auto: yes' (Get-AutoLine $h2).Trim() 'c7b: Auto: restored to yes'
    Assert-Equal $false (Test-Path $sc2) 'c7c: sidecar removed'
    $picked = Get-QualifyingHandoff -ProjectDir $work -CliName 'kimi'
    Assert-Equal $h2 $picked 'c7d: ROUND-TRIP - REAL Get-QualifyingHandoff picks the released handoff again'

    # -- (c8) FAIL-CLOSED: Status: DONE is refused --
    Get-ChildItem -Path $openDir -Filter '*.md' | Remove-Item -Force
    $h3 = New-TestHandoff -Slug '202607131002-c8-done' -Status 'DONE'
    $r = Invoke-ClaimTool -Tool $claimTool -HandoffPath $h3
    Assert-Equal $true ($r.Code -ne 0) 'c8: Status: DONE handoff -> claim REFUSED'
} finally {
    if ($proc -and $null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "==== claim-handoff tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
