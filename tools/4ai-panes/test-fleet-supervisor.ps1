# test-fleet-supervisor.ps1 - Pester-free harness for fleet-supervisor.ps1.
#
# Drives the supervisor against synthetic heartbeat files in a temp directory
# so no real fleet, Telegram, or wt.exe is touched. Asserts:
#   (A) fresh heartbeat       -> ALIVE (healthy, no action)
#   (B) stale heartbeat       -> DOWN
#   (C) missing heartbeat     -> DOWN
#   (D) live fleet            -> NEVER relaunched (false-positive guard)
#   (E) down + open handoffs  -> alert fires AND relaunch attempted
#   (F) down + empty queue    -> alert only, no relaunch
#   (G) alive + NOT CAPABLE   -> alert only, NEVER relaunched
#   (H) backoff + circuit breaker -> repeated failures back off, eventually give up
#   (I) alert dedupe          -> N polls with same state = ONE alert
#   (J) install/uninstall     -> WhatIf constructs the task correctly

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$supervisor = Join-Path $here 'fleet-supervisor.ps1'

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
function Assert-True {
    param($Actual, [string]$Name)
    Assert-Equal $true ([bool]$Actual) $Name
}
function Assert-False {
    param($Actual, [string]$Name)
    Assert-Equal $false ([bool]$Actual) $Name
}

# -- temp workspace --
$work = Join-Path $env:TEMP ("fleet-supervisor-test-" + [guid]::NewGuid().ToString('N'))
$hbDir = Join-Path $work 'heartbeats'
$stateDir = Join-Path $work 'state'
$projDir = Join-Path $work 'test-project'
New-Item -ItemType Directory -Path $hbDir -Force | Out-Null
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $projDir '.ai\handoffs\to-kimi\open') -Force | Out-Null

# Track mock calls for assertion.
$script:alertLog = @()
$script:relaunchLog = @()

# Dot-source the supervisor with -NoRun -DryRun, overriding paths.
. $supervisor -NoRun -DryRun -HeartbeatDir $hbDir -StateDir $stateDir -ToolsDir $here `
    -MaxRelaunchAttempts 3 -BackoffBaseMinutes 0.001 -BackoffMaxMinutes 0.01

# Override the hooks to capture calls instead of sending real alerts/relaunches.
$script:SupervisorSendAlert = {
    param([string]$Project, [string]$Message)
    $script:alertLog += @{ Project = $Project; Message = $Message }
}
$script:SupervisorRelaunch = {
    param([string]$ProjectDir)
    $script:relaunchLog += @{ ProjectDir = $ProjectDir }
    return $true   # simulate successful relaunch
}

# -- helpers --

# Write a synthetic heartbeat file.
function Write-TestHeartbeat {
    param(
        [string]$Project = 'test-project',
        [string]$Cli = 'kimi',
        [string]$ProjectDir = $projDir,
        [string]$State = 'idle',
        [string]$Outcome = '',
        [int]$ConsecFailures = 0,
        [int]$AgeSeconds = 0
    )
    $ts = ((Get-Date).ToUniversalTime().AddSeconds(-$AgeSeconds)).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $invokeTs = if ($Outcome) { $ts } else { '' }
    $obj = [ordered]@{
        project              = $Project
        cli                  = $Cli
        pid                  = 99999
        host                 = 'TESTHOST'
        ts                   = $ts
        state                = $State
        project_dir          = $ProjectDir
        last_invoke_ts       = $invokeTs
        last_invoke_outcome  = $Outcome
        consecutive_failures = $ConsecFailures
    }
    $path = Join-Path $hbDir "${Project}__${Cli}.json"
    $json = $obj | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($path, $json)
}

# Write an open handoff file for the test project.
function Write-TestHandoff {
    param([string]$Recipient = 'kimi', [string]$Name = '202607131200-test-handoff.md')
    $dir = Join-Path $projDir ".ai\handoffs\to-$Recipient\open"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content = @"
# Test handoff
Status: OPEN
Auto: yes
Risk: B

Test handoff for supervisor testing.
"@
    Set-Content -Path (Join-Path $dir $Name) -Value $content -Encoding utf8
}

# Remove all handoff files for the test project.
function Clear-TestHandoffs {
    $dir = Join-Path $projDir '.ai\handoffs'
    if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force }
}

# Remove all heartbeat files.
function Clear-TestHeartbeats {
    Get-ChildItem -Path $hbDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

# Remove the supervisor state file.
function Clear-TestState {
    $sf = Join-Path $stateDir 'state.json'
    if (Test-Path $sf) { Remove-Item -Path $sf -Force }
}

# Reset all test state between scenarios.
function Reset-TestState {
    Clear-TestHeartbeats
    Clear-TestState
    Clear-TestHandoffs
    $script:alertLog = @()
    $script:relaunchLog = @()
    Remove-Item Env:\RWN_FLEET_SUPERVISOR_PROVENANCE -ErrorAction SilentlyContinue
}

# ============================================================================
# (A) fresh heartbeat -> ALIVE (healthy, no action)
# ============================================================================
Reset-TestState
# Fresh heartbeats for all canonical fleet CLIs.
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 5
Write-TestHeartbeat -Cli 'kiro' -AgeSeconds 10
Write-TestHeartbeat -Cli 'opencode' -AgeSeconds 8
$a = Invoke-SupervisorCheck
# All heartbeats are for the same project -> one project entry, healthy.
Assert-Equal 1 @($a).Count 'A: fresh heartbeats, same project -> one entry'
Assert-Equal 'none' ($a | Where-Object { $_.Project -eq 'test-project' }).Action `
    'A: fresh heartbeats -> no action (healthy)'

# ============================================================================
# (B) stale heartbeat -> DOWN
# ============================================================================
Reset-TestState
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 120   # stale (> 90s threshold)
$b = Invoke-SupervisorCheck
$bProj = $b | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 'alert' $bProj.Action 'B: stale heartbeat -> alert (fleet down)'
Assert-True ($bProj.Detail -match 'DOWN') 'B: alert mentions DOWN'

# ============================================================================
# (C) missing heartbeat + open handoffs -> DOWN + relaunch
# ============================================================================
Reset-TestState
# No heartbeats at all. The supervisor reads the install provenance; point it
# at the test project and create an open handoff so a relaunch is warranted.
$provPath = Join-Path $work 'provenance.json'
@{ source_repo = $projDir } | ConvertTo-Json -Compress | Set-Content -Path $provPath -NoNewline
$env:RWN_FLEET_SUPERVISOR_PROVENANCE = $provPath
Write-TestHandoff -Recipient 'kimi' -Name '202607131200-test-handoff.md'
$c = Invoke-SupervisorCheck
$cProj = $c | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 1 $c.Count 'C: no heartbeats + provenance handoff -> one synthesized project'
Assert-Equal 'down' $cProj.State 'C: synthesized project is down'
Assert-Equal 'alert+relaunch' $cProj.Action 'C: down + open handoffs -> alert+relaunch'
Remove-Item -Path $provPath -Force -ErrorAction SilentlyContinue

# ============================================================================
# (D) live fleet is NEVER relaunched (the false-positive case)
# ============================================================================
Reset-TestState
# Fresh heartbeats for ALL panes + open handoffs. The fleet is alive and
# healthy. Even with open handoffs, it must NOT be relaunched.
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 3 -Outcome 'success'
Write-TestHeartbeat -Cli 'claude' -AgeSeconds 5 -Outcome 'success'
Write-TestHeartbeat -Cli 'kiro' -AgeSeconds 8 -Outcome 'success'
Write-TestHeartbeat -Cli 'opencode' -AgeSeconds 2 -Outcome 'success'
Write-TestHandoff -Recipient 'kimi'
$d = Invoke-SupervisorCheck
$dProj = $d | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 'none' $dProj.Action 'D: live fleet + open handoffs -> NO action (false-positive guard)'
Assert-Equal 0 $script:relaunchLog.Count 'D: live fleet -> zero relaunch attempts'
Assert-Equal 0 $script:alertLog.Count 'D: live fleet -> zero alerts'

# ============================================================================
# (E) down + open handoffs -> alert fires AND relaunch is attempted
# ============================================================================
Reset-TestState
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 120   # stale
Write-TestHandoff -Recipient 'kimi'
$e = Invoke-SupervisorCheck
$eProj = $e | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 'alert+relaunch' $eProj.Action 'E: down + open handoffs -> alert+relaunch'
Assert-Equal 1 $script:alertLog.Count 'E: exactly one alert fired'
Assert-Equal 1 $script:relaunchLog.Count 'E: exactly one relaunch attempted'

# ============================================================================
# (F) down + empty queue -> alert only, no relaunch
# ============================================================================
Reset-TestState
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 120   # stale
# No handoffs written -> empty queue
$f = Invoke-SupervisorCheck
$fProj = $f | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 'alert' $fProj.Action 'F: down + empty queue -> alert only'
Assert-Equal 1 $script:alertLog.Count 'F: alert fired'
Assert-Equal 0 $script:relaunchLog.Count 'F: NO relaunch (empty queue)'

# ============================================================================
# (G) alive + NOT CAPABLE -> alert only, NEVER relaunched
# ============================================================================
Reset-TestState
# One CLI is alive-but-incapable; the others are healthy. With zero dead CLIs
# the state must be 'incapable' and relaunch is never attempted.
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 5 -Outcome 'auth_failure' -ConsecFailures 5
Write-TestHeartbeat -Cli 'kiro' -AgeSeconds 5 -Outcome 'success'
Write-TestHeartbeat -Cli 'opencode' -AgeSeconds 5 -Outcome 'success'
Write-TestHandoff -Recipient 'kimi'
$g = Invoke-SupervisorCheck
$gProj = $g | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 'alert' $gProj.Action 'G: alive + NOT CAPABLE -> alert only'
Assert-True ($gProj.Detail -match 'NOT CAPABLE') 'G: alert names the capability failure'
Assert-True ($gProj.Detail -match 'auth_failure') 'G: alert names the reason (auth_failure)'
Assert-Equal 0 $script:relaunchLog.Count 'G: NEVER relaunched (dead API key is not fixed by relaunch)'

# ============================================================================
# (H) backoff + circuit breaker
# ============================================================================
Reset-TestState
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 120
Write-TestHandoff -Recipient 'kimi'

# First check: should alert + relaunch (attempt 1/3)
$h1 = Invoke-SupervisorCheck
$h1Proj = $h1 | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 'alert+relaunch' $h1Proj.Action 'H: first check -> alert+relaunch (attempt 1)'
Assert-Equal 1 $script:relaunchLog.Count 'H: one relaunch after first check'

# Second check: state is now 'down' (not new), so no alert. But backoff allows
# another relaunch (0.001min base = 0.06s, which has elapsed).
Start-Sleep -Milliseconds 100   # let the tiny backoff expire
$h2 = Invoke-SupervisorCheck
$h2Proj = $h2 | Where-Object { $_.Project -eq 'test-project' }
# State didn't change (still down), so no new alert. But relaunch is allowed.
Assert-Equal 2 $script:relaunchLog.Count 'H: second relaunch after backoff expires'

# Third check: another relaunch (attempt 3/3)
Start-Sleep -Milliseconds 200
$h3 = Invoke-SupervisorCheck
Assert-Equal 3 $script:relaunchLog.Count 'H: third relaunch (attempt 3 = max)'

# Fourth check: circuit breaker tripped -> give-up alert
Start-Sleep -Milliseconds 500
$h4 = Invoke-SupervisorCheck
$h4Proj = $h4 | Where-Object { $_.Project -eq 'test-project' }
Assert-Equal 3 $script:relaunchLog.Count 'H: NO fourth relaunch (circuit breaker)'
# The give-up alert should fire on state transition to 'give-up'
$giveUpAlerts = @($script:alertLog | Where-Object { $_.Message -match 'GAVE UP' })
Assert-True ($giveUpAlerts.Count -ge 1) 'H: give-up alert fired after circuit breaker'

# ============================================================================
# (I) alert dedupe: N polls with same state = ONE alert
# ============================================================================
Reset-TestState
Write-TestHeartbeat -Cli 'kimi' -AgeSeconds 120
# No handoffs -> alert only, no relaunch
$i1 = Invoke-SupervisorCheck
$alertsAfterFirst = $script:alertLog.Count
Assert-Equal 1 $alertsAfterFirst 'I: first poll -> one alert'

# Poll again (same state: down, no handoffs). Should NOT alert again.
$i2 = Invoke-SupervisorCheck
Assert-Equal $alertsAfterFirst $script:alertLog.Count 'I: second poll -> NO new alert (deduped)'

$i3 = Invoke-SupervisorCheck
Assert-Equal $alertsAfterFirst $script:alertLog.Count 'I: third poll -> still NO new alert (deduped)'

# ============================================================================
# (J) install/uninstall WhatIf
# ============================================================================
$installScript = Join-Path $here 'install-fleet-supervisor.ps1'
$uninstallScript = Join-Path $here 'uninstall-fleet-supervisor.ps1'

Assert-True (Test-Path $installScript) 'J: install script exists'
Assert-True (Test-Path $uninstallScript) 'J: uninstall script exists'

# WhatIf should succeed without error and print the task details.
$installOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -WhatIf 2>&1 | Out-String
Assert-True ($installOut -match 'WHAT-IF') 'J: install -WhatIf prints WhatIf message'
Assert-True ($installOut -match 'RWN-FleetSupervisor') 'J: install -WhatIf names the task'
Assert-True ($installOut -match 'Interactive') 'J: install -WhatIf specifies Interactive logon type'

# Uninstall WhatIf (task not registered -> should report "not registered").
$uninstallOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -WhatIf 2>&1 | Out-String
Assert-True ($uninstallOut -match 'not registered' -or $uninstallOut -match 'WHAT-IF') `
    'J: uninstall reports not-registered or WhatIf'

# ============================================================================
# cleanup + summary
# ============================================================================
Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== fleet-supervisor tests: $script:pass passed, $script:fail failed ====" -ForegroundColor Cyan
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
