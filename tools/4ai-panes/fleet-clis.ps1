# fleet-clis.ps1 - SINGLE SOURCE for the fleet CLI list.
#
# To add a CLI, update THIS file plus the per-CLI command switches in
# pane-runner.ps1 (Get-HeadlessCmd/Get-InteractiveCmd/Get-DefaultOwner) which
# carry CLI-specific launch flags and cannot be derived from the list alone.
#
# Dot-source this file (resolve via $PSScriptRoot so it works BOTH in the repo
# tree and in the flat install dir, where every tool file sits side by side):
#     . (Join-Path $PSScriptRoot 'fleet-clis.ps1')

$script:FleetClis      = @('claude', 'kimi', 'kiro', 'opencode')                              # canonical lowercase
$script:FleetCliProper = @{ claude = 'Claude'; kimi = 'Kimi'; kiro = 'Kiro'; opencode = 'OpenCode' }   # lower -> Proper
