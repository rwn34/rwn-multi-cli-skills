# install-fleet-supervisor.ps1 - Register the fleet supervisor as a Windows
# Task Scheduler task. Scripted + reversible (pair: uninstall-fleet-supervisor.ps1).
#
# The task runs fleet-supervisor.ps1 periodically (default every 1 minute) to
# check fleet pane heartbeats, alert on failure, and relaunch dead panes.
#
# Critical: the task MUST run "only when the user is logged on" + interactive.
# A task running in session 0 (or "run whether user is logged on or not")
# CANNOT open an interactive Windows Terminal window. This was verified
# empirically — see the handoff report.
#
# Usage:
#   powershell -File install-fleet-supervisor.ps1 [-IntervalMinutes 1] [-WhatIf]

param(
    [int]$IntervalMinutes = 1,
    [string]$TaskName = 'RWN-FleetSupervisor',
    [string]$ToolsDir = $PSScriptRoot,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$supervisorScript = Join-Path $ToolsDir 'fleet-supervisor.ps1'
if (-not (Test-Path $supervisorScript)) {
    Write-Host "ERROR: fleet-supervisor.ps1 not found at $supervisorScript" -ForegroundColor Red
    exit 1
}

# Build the task action: run fleet-supervisor.ps1 in a visible PowerShell window.
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$supervisorScript`""

# Trigger: repeat every N minutes, indefinitely.
# Trigger: repeat every N minutes. RepetitionDuration = 10 years (effectively
# indefinite — TimeSpan.MaxValue is rejected by Task Scheduler on some systems).
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration ([TimeSpan]::FromDays(3650))

# Principal: run as the current user, ONLY when logged on (Interactive).
# This is required for the task to be able to open Windows Terminal windows.
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

# Settings: don't start if on battery (laptop), restart on failure.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Fleet supervisor: detect dead panes, alert owner via Telegram, relaunch fleet. See tools/4ai-panes/fleet-supervisor.ps1.'

if ($WhatIf) {
    Write-Host "WHAT-IF: would register scheduled task '$TaskName':" -ForegroundColor Yellow
    Write-Host "  Script:   $supervisorScript"
    Write-Host "  Interval: every $IntervalMinutes minute(s)"
    Write-Host "  LogonType: Interactive (only when user is logged on)"
    Write-Host "  User:     $env:USERDOMAIN\$env:USERNAME"
    Write-Host ""
    Write-Host "To register for real, run without -WhatIf."
    exit 0
}

try {
    Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
    Write-Host "Registered scheduled task '$TaskName' (every ${IntervalMinutes}min, interactive)." -ForegroundColor Green
    Write-Host "  Script: $supervisorScript"
    Write-Host "  To remove: powershell -File $(Join-Path $ToolsDir 'uninstall-fleet-supervisor.ps1')"
} catch {
    Write-Host "ERROR registering task: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "You may need to run this script from an elevated PowerShell prompt." -ForegroundColor Yellow
    exit 1
}
