---
Status: OPEN
Sender: claude-cockpit
Recipient: claude-cockpit
Created: 2026-07-20 16:00 (UTC+7)
Auto: no
Risk: A
Base: origin/main
Observed-in: main@30d641d
---

# Context export: six-actor model reversion completed

## Summary of work just completed

The framework actor model has been reverted from eight actors to six actors.
Canonical actors now are:
- claude-cockpit
- kimi-cockpit
- claude
- kimi
- kiro
- opencode

Removed identities: `kiro-cockpit`, `opencode-cockpit`.

## Changes landed on main

- `eabba85` — `revert(actor-model): six-actor model, remove kiro-cockpit and opencode-cockpit`
  - SSOT `.ai/instructions/operating-prompt/principles.md`
  - `.ai/handoffs/README.md` and `.ai/handoffs/template.md`
  - `docs/specs/saja-akun-cli-workflow.md` and `docs/guides/example-handoff-chain.md`
  - Regenerated replicas via `sync-replicas.sh`
  - Tooling: `dispatch-handoffs.sh`, `claim-handoff.sh`, `release-handoff.sh`, `fleet-health.sh`, `test-fleet-health.sh`, `wt-bootstrap.sh`, `pane-runner.ps1`, `test-pane-runner.ps1`, `test-dispatch-owner-for.sh`
  - Removed legacy `.ai/handoffs/to-kiro-cockpit/` and `.ai/handoffs/to-opencode-cockpit/` queue dirs
  - `CHANGELOG.md` entry under Unreleased
- `dc6544b` — `chore(kiro): update contract for six-actor model (#129)`
  - `.kiro/steering/00-ai-contract.md` activity-log identity changed from `kiro-cockpit` to `kiro`
- `6ece4e9` — activity-log entry for the reversion
- `30d641d` — `chore(release): bump framework version to 0.0.51`
  - `tools/multi-cli-install/package.json`: 0.0.50 → 0.0.51
  - `CHANGELOG.md`: promoted Unreleased six-actor entry to `[0.0.51]`

## Sync status

- `pane-runner.ps1` and `test-pane-runner.ps1` were synced to `~/.rwn-auto/rwn-4AI-panes` at commit `eabba85`.
- Since `30d641d` only touched `package.json` and `CHANGELOG.md`, the `.rwn-auto/` pane-runner copy is still current.

## Verification evidence

Run from repo root at `main@30d641d`:

```bash
bash .ai/tools/sync-replicas.sh --check   # 24 replicas, Drift: 0
bash .ai/tests/test-dispatch-owner-for.sh # 16 passed, 0 failed
bash .ai/tools/test-fleet-health.sh       # 11 passed, 0 failed
bash .ai/tools/lint-handoff.sh            # OK
powershell -ExecutionPolicy Bypass -File tools/4ai-panes/test-pane-runner.ps1  # 195 passed, 0 failed
```

`fleet-health.sh` reports only expected stale-worktree warnings for claude/kimi/opencode worktrees behind `origin/main` (normal after main advances).

## GitHub status

- PR #129 merged.
- Latest `main` push `30d641d`: `gates` ✅ and `release` ✅ workflows completed successfully.

## Recommended next actions for Claude orchestrator

1. Review open issues/PRs for any remaining actor-model drift (e.g., docs/specs that still mention eight actors).
2. Refresh stale worktrees before next dispatch:
   ```bash
   bash .ai/tools/fleet-health.sh
   ```
3. Consider running a smoke-test handoff chain through claude → kimi → kiro → opencode → claude to confirm the six-actor routing works end-to-end.
4. The `to-kiro-cockpit` and `to-opencode-cockpit` worktrees no longer exist; confirm no stale pane-runner configs reference them.

## On completion

Move this handoff to `.ai/handoffs/to-claude/done/` and prepend a brief activity-log entry if you act on it.
