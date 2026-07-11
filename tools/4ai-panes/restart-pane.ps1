# restart-pane.ps1 - re-enter the self-driving pane loop in THIS pane.
# Use after Ctrl-C or an exit dropped the pane to a bare prompt. Pane-local:
# it starts the runner ONLY for this pane's CLI and does not touch other panes
# (each pane is its own process + claim-lock). With no -Cli, it infers the CLI
# from $env:RWN_PANE_CLI (stamped by the runner/supervisor when the pane launched).
#
# By default it re-enters via run-pane-supervised.ps1 (auto-resurrection: a crashed
# runner respawns) when that script is present, so a manual restart is also
# self-healing. Pass -Supervised:$false to run the bare pane-runner directly.
param(
    [string]$Cli = $env:RWN_PANE_CLI,
    [string]$ProjectDir = (Get-Location).Path,
    [string]$Owner = '',
    [int]$MaxContinues = 5,
    [int]$PollSeconds = 10,
    [switch]$Supervised = $true
)
. (Join-Path $PSScriptRoot 'fleet-clis.ps1')   # SINGLE SOURCE: $FleetClis
if ([string]::IsNullOrWhiteSpace($Cli) -or ($FleetClis -notcontains $Cli)) {
    Write-Host "restart-pane: pass -Cli claude|kimi|kiro|opencode (or run inside a pane where RWN_PANE_CLI is set). Got: '$Cli'" -ForegroundColor Yellow
    exit 1
}
$runner = Join-Path $PSScriptRoot 'pane-runner.ps1'
if (-not (Test-Path $runner)) {
    Write-Host "restart-pane: pane-runner.ps1 not found next to this script ($runner)." -ForegroundColor Red
    exit 1
}
$supervisor = Join-Path $PSScriptRoot 'run-pane-supervised.ps1'
$target = if ($Supervised -and (Test-Path $supervisor)) { $supervisor } else { $runner }
& $target -Cli $Cli -ProjectDir $ProjectDir -Owner $Owner -MaxContinues $MaxContinues -PollSeconds $PollSeconds
exit $LASTEXITCODE
