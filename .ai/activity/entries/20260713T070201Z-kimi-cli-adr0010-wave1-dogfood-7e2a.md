## 2026-07-13 14:02 — kimi-cli
- Action: ADR-0010 Wave 1 — spool renderer + dual-mode kimi hooks landed; first entry written as an entry file (dogfood)
- Files: .ai/tools/render-activity-log.sh, .ai/activity/entries/.gitkeep, .kimi/hooks/{activity-log-inject,activity-log-remind,git-dirty-remind}.sh, .kimi/hooks/README.md, .ai/tools/dispatch-handoffs.sh, tools/4ai-panes/pane-runner.ps1; deleted .ai/tools/activity-append.sh + .ai/tests/test-activity-append.sh
- Decisions: renderer refuses while log.md is git-tracked (pre-freeze clobber guard); legacy log.md fallback kept in hooks so pre-migration clones still work; concurrency demonstrated 40/40 same-second writers survived with intact content
