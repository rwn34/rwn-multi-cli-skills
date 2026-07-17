## 2026-07-18 13:14 (UTC+7) — kimi-cli
- Action: Implement ADR-0016 snapshot-copy model for .ai/ shared state: replace junction with dispatcher-owned copy/sync-back; update wt-bootstrap.sh, dispatch-handoffs.sh, pane-runner.ps1 and their regression tests.
- Files: scripts/wt-bootstrap.sh, .ai/tools/dispatch-handoffs.sh, .ai/tools/sync-ai-state.sh, tools/4ai-panes/pane-runner.ps1, tools/4ai-panes/test-pane-runner.ps1, .ai/tests/test-dispatch-worktree.sh, .ai/tests/test-sync-ai-state.sh, docs/specs/ai-snapshot-sync.md
- Decisions: sync-ai-state.sh fallback order: handoff Base: > origin/HEAD > origin/main > main > HEAD; sync-back copies new/changed files, replays handoff deletions only, commits canonical changes; worktree .ai/ removed after sync-back to eliminate junction reverse-write hazard.

## 2026-07-17 22:30 (UTC+7) — opencode
- Action: Handoff 202607171720-update-activity-log-format-hyphen processed — correctly routed as Claude Code responsibility due to lane guard (.opencode/contract.md is custodian file owned by Claude, not OpenCode)
- Files: —
- Decisions: —
+