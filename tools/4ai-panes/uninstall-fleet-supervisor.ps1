# uninstall-fleet-supervisor.ps1 - Remove the fleet supervisor scheduled task.
# Pair of install-fleet-supervisor.ps1. Scripted + reversible.
#
# Usage:
#   powershell -File uninstall-fleet-supervisor.ps1 [-WhatIf]

param(
    [string]$TaskName = 'RWN-FleetSupervisor',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host "Task '$TaskName' is not registered. Nothing to do." -ForegroundColor DarkGray
    exit 0
}

if ($WhatIf) {
    Write-Host "WHAT-IF: would remove scheduled task '$TaskName'." -ForegroundColor Yellow
    exit 0
}

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Green
} catch {
    Write-Host "ERROR removing task: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
