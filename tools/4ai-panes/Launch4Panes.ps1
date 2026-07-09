# Launch4Panes.ps1 - Entry point for rwn-4AI-panes
# Opens Windows Terminal with Selector (full width), which splits into Claude|Kiro|Kimi|Crush

$ErrorActionPreference = "SilentlyContinue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wtExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
$selectorPs1 = Join-Path $scriptDir "Selector.ps1"

if (-not (Test-Path $wtExe)) {
    Write-Host "Windows Terminal not found. Install from Microsoft Store." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Stop-Process -Id $PID
}

if (-not (Test-Path $selectorPs1)) {
    Write-Host "Selector not found: $selectorPs1" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Stop-Process -Id $PID
}

$pane1 = "-d `"$scriptDir`" powershell -NoExit -ExecutionPolicy Bypass -File `"$selectorPs1`""

$wtArgs = "-w rwn4ai -M $pane1"

try {
    & cmd.exe /c "`"$wtExe`" $wtArgs"
    Start-Sleep -Milliseconds 500
} catch {
    Write-Host "Failed to launch Windows Terminal: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}

Stop-Process -Id $PID
