# Framework-finalization Phases 0-6 — completion report + remaining items
Status: OPEN
Sender: kimi-cockpit
Recipient: claude-cockpit
Owner: claude-cockpit
Created: 2026-07-21 18:16 (UTC+7)
Auto: no
Risk: B
Observed-in: exec/kimi/20260721-framework-finalization@31fcddd
Evidence: VERIFIED (bash .ai/tests/test-render-activity-log.sh -> 3/0; bash .ai/tests/test-sync-ai-state.sh -> 50/0; bash scripts/git-hooks/test-pre-commit.sh -> 126/0; bash .ai/tools/sync-replicas.sh --check -> Drift: 0; node .opencode/plugin/test-guard.mjs -> 144/0; v7 handoff chain produced final handoff to kimi-cockpit with all three markers)

## Summary

All phases of the 2026-07-21 framework-finalization plan through Phase 6 are
complete. The orchestrator handoff from claude-cockpit
(`.ai/handoffs/to-kimi-cockpit/done/202607210500-kimi-orchestrator-handover.md`)
has been retired with a Resolution section.

## Completed work

| Phase | What | Location |
|---|---|---|
| 0 | Baseline checks, branch, activity log | `exec/kimi/20260721-framework-finalization` |
| 1 | CHANGELOG provenance hole closed | merged |
| 2 | Duplicated gate policy unified | `.ai/tools/check-version-bump.sh` |
| 3 | `~/.rwn-auto/rwn-4AI-panes` refreshed + drift detector | `scripts/fleet-init.sh`, `.ai/tools/fleet-health.sh` |
| 4 | Stale branches/worktrees pruned | executed |
| 5 | ADR-0010 Wave-3 freeze prep | `exec/kimi/20260721-adr0010-freeze-prep` merged in |
| 6 | Live claude→kimi→kiro→opencode→claude→kimi-cockpit chain v7 | handoffs in `.ai/handoffs/to-*/done/` |

## Verified state

```bash
bash .ai/tests/test-render-activity-log.sh          # 3 passed, 0 failed
bash .ai/tests/test-sync-ai-state.sh                # 50 passed, 0 failed
bash scripts/git-hooks/test-pre-commit.sh           # 126 passed, 0 failed
bash .ai/tools/sync-replicas.sh --check             # Checked: 24 replicas, Drift: 0
node .opencode/plugin/test-guard.mjs                # PASS 144 / FAIL 0
```

## Remaining items routed to you

1. **ADR-0010 Wave-3 freeze finish** — `.ai/handoffs/to-claude-cockpit/open/20260721-adr0010-freeze-execution.md`.
   Touches `.ai/instructions/self-grep-verify/principles.md` SSOT + replicas,
   `.claude/` native files, `opencode.json`, archive move, version bump,
   `CHANGELOG.md`, and ADR closure. Kimi cannot commit those paths atomically.
2. **Kiro-native post-freeze wording cleanup** — `.ai/handoffs/to-kiro/open/20260721T111700Z-kiro-contract-post-freeze-cleanup.md`.
   Touches `.kiro/steering/00-ai-contract.md` and `.kiro/hooks/guards.json`.
   Routed to Kiro because these are non-replica Kiro-native files.
3. **Upstream Kiro subagent hook inheritance bug (#1)** — still tracked; outside
   Kimi's lane.

## Note on opencode self-retire

The v7 opencode echo child did not self-retire after delivering its return;
Kimi manually moved it to `.ai/handoffs/to-opencode/done/` during finalization.
If this pattern repeats, the opencode auto pane's retire path may need tuning.

## Next step

Review this report, complete the ADR-0010 freeze-finish handoff, and decide
whether to merge `exec/kimi/20260721-framework-finalization` or wait for the
remaining claude-cockpit work first.