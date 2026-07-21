# Test chain v7 — aggregate child returns and emit final handoff
Status: OPEN
Sender: claude-cockpit
Recipient: claude
Owner: claude
Created: 2026-07-21 17:05 (UTC+7)
Auto: yes
Risk: B
Observed-in: main@9797a1f16f70eff2edc9b714945db6ff31f20218
Evidence: VERIFIED (three child handoffs written to to-kimi/open, to-kiro/open, to-opencode/open at 9797a1f; see root handoff 20260721T085700Z-test-chain-v7-root.md)

## Goal

Collect the three echo returns from the v7 chain children and emit exactly one
final handoff to `kimi-cockpit`. This is the dedicated aggregator stage of the
root → children → aggregator → next pattern in `.ai/handoffs/README.md`.

## Current state

Root handoff `20260721T085700Z-test-chain-v7-root.md` fanned out to:

| Child handoff | Expected return file | Expected marker |
|---|---|---|
| `to-kimi/open/20260721T085700Z-test-chain-v7-kimai-echo.md` | `to-claude/open/20260721T085700Z-test-chain-v7-kimi-return.md` | `CHAINV7-KIMI-7f3a91` |
| `to-kiro/open/20260721T085700Z-test-chain-v7-kiro-echo.md` | `to-claude/open/20260721T085700Z-test-chain-v7-kiro-return.md` | `CHAINV7-KIRO-2c85de` |
| `to-opencode/open/20260721T085700Z-test-chain-v7-opencode-echo.md` | `to-claude/open/20260721T085700Z-test-chain-v7-opencode-return.md` | `CHAINV7-OPENCODE-b40e6c` |

## Steps

1. Check for all three return files in `.ai/handoffs/to-claude/open/` (also check
   `.ai/handoffs/to-claude/done/` in case a return was auto-retired by
   `reconcile-done-handoffs.sh`).
2. **If fewer than three are present:** do NOT aggregate and do NOT emit the final
   handoff. Leave this file `Status: OPEN` in place, note in your activity-log
   entry which children are still missing, and stop. The next dispatcher poll
   re-runs this handoff. Partial aggregation is a failure, not a partial success.
3. **If all three are present:** verify each marker with
   `grep -n "CHAINV7-" <return file>` and keep the pasted output. Then create
   `.ai/handoffs/to-kimi-cockpit/open/20260721T085700Z-test-chain-v7-final-to-kimi-cockpit.md`
   stating that the chain completed, listing all three markers and the return
   file paths, and naming any child that needed a retry.
4. Retire the three return handoffs to `.ai/handoffs/to-claude/done/` with
   `Status: DONE`.
5. Prepend an activity-log entry (identity `claude`), then self-retire this file
   to `.ai/handoffs/to-claude/done/` with `Status: DONE`.

## Verification

- (a) `ls .ai/handoffs/to-claude/open .ai/handoffs/to-claude/done` — paste output.
- (b) `grep -rn "CHAINV7-" .ai/handoffs/` — paste output; all three markers must appear.
- (c) `bash .ai/tools/lint-handoff.sh` on the final handoff — paste output, must pass.

## Next step / future note

The final handoff goes to `kimi-cockpit`, which owns the orchestrator seat as of
2026-07-21 and validates the chain post-hoc. If a pane never returns, report which
one and whether the dispatcher refreshed its worktree — that, not a silently short
marker list, is the deliverable.

## Report back with
- (a) the three marker lines, pasted from grep
- (b) the final handoff path
- (c) any child that failed to return, with the dispatch-failure report path if one exists
