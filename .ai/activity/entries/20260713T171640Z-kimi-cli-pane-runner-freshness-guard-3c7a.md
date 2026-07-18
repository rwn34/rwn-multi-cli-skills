## 2026-07-13 17:16 — kimi-cli
- Action: Implemented and merged Option A from the stale-worktree proposal: `pane-runner.ps1` now refuses to start if its worktree branch is behind `origin/master` (PR #90, 4a8f234). Added `Assert-WorktreeFresh`, anti-rot wiring tests `bf`/`bf2`, and a CHANGELOG Fixed bullet. Test suite: 147/0.
- Files: `tools/4ai-panes/pane-runner.ps1`, `tools/4ai-panes/test-pane-runner.ps1`, `CHANGELOG.md`.
- Decisions: The guard exits cleanly (exit 0) so the supervisor does not endlessly respawn a stale pane; it prints the exact stop/rebase/recreate/restart steps. This does not refresh the currently-running 4 stale pane worktrees, but it prevents any new stale start and forces action on the next restart. The deeper fix (read-only or copy-based .ai/) remains future work.
