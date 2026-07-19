# v6 test chain — root fan-out
Status: OPEN
Sender: kimai-cockpit
Recipient: claude
Owner: kimai-cockpit
Created: 2026-07-19 13:30 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (bash .ai/tests/test-sync-ai-state.sh -> 39 passed, 0 failed; bash .ai/tests/test-dispatch-worktree.sh -> TBD)
Observed-in: main@HEAD

## Goal
Run a clean fan-out test of the snapshot-copy dispatcher: create three parallel child echo handoffs to kimi, kiro and opencode, plus a separate aggregator handoff to opencode. Do NOT aggregate inside the children.

## Steps
1. Create three child handoffs in:
   - `.ai/handoffs/to-kimi/open/202607190630-test-chain-v6-kimi-echo.md`
   - `.ai/handoffs/to-kiro/open/202607190630-test-chain-v6-kiro-echo.md`
   - `.ai/handoffs/to-opencode/open/202607190630-test-chain-v6-opencode-echo.md`
   Each child must write a return handoff to `.ai/handoffs/to-claude/open/` named `202607190630-test-chain-v6-<cli>-return.md` and self-retire.
2. Create an aggregator handoff in `.ai/handoffs/to-opencode/open/202607190630-test-chain-v6-aggregate.md` (Sender: claude, Recipient: opencode) that waits for all three return files, then creates the final handoff to `.ai/handoffs/to-kimi-cockpit/open/202607190630-test-chain-v6-final.md`. Use opencode as the aggregator to avoid the self-addressed-handoff rejection.
3. Self-retire this root handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- (a) `ls .ai/handoffs/to-kimi/open/202607190630-test-chain-v6-kimi-echo.md .ai/handoffs/to-kiro/open/202607190630-test-chain-v6-kiro-echo.md .ai/handoffs/to-opencode/open/202607190630-test-chain-v6-opencode-echo.md .ai/handoffs/to-opencode/open/202607190630-test-chain-v6-aggregate.md` all exist.
- (b) This handoff appears in `.ai/handoffs/to-claude/done/202607190630-test-chain-v6-root.md` with `Status: DONE`.

## Report back with
- Paths of the four created handoffs.
- Grep proof that the root handoff is retired.

## Next step / future note
After this handoff, run `bash .ai/tools/dispatch-handoffs.sh --exec --only kimi --one`, then the same for kiro and opencode (can be parallel), then `bash .ai/tools/dispatch-handoffs.sh --exec --only opencode --one` for the aggregator, then process the final handoff in the kimi-cockpit session.
