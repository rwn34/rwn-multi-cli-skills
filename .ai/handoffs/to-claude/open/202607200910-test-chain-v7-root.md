# v7 test chain — root fan-out (corrected queues)
Status: OPEN
Sender: kimi-cli
Recipient: claude
Created: 2026-07-20 09:10 (UTC+7)
Auto: yes
Risk: A
Evidence: HYPOTHESIS (unverified)
Observed-in: main@HEAD

## Goal
Run a clean fan-out test of the snapshot-copy dispatcher. Create three parallel child echo handoffs to kimi, kiro and opencode, plus an aggregator handoff to opencode. Returns must land in the canonical `to-claude/open/` queue (there is no `to-claude-auto/` queue).

## Steps
1. Create three child handoffs in:
   - `.ai/handoffs/to-kimi/open/202607200910-test-chain-v7-kimi-echo.md`
   - `.ai/handoffs/to-kiro/open/202607200910-test-chain-v7-kiro-echo.md`
   - `.ai/handoffs/to-opencode/open/202607200910-test-chain-v7-opencode-echo.md`
   Each child must write a return handoff to `.ai/handoffs/to-claude/open/202607200910-test-chain-v7-<cli>-return.md` and self-retire to `.ai/handoffs/to-<cli>/done/`.
2. Create an aggregator handoff in `.ai/handoffs/to-opencode/open/202607200910-test-chain-v7-aggregate.md` (Sender: claude, Recipient: opencode) that waits for all three return files in `.ai/handoffs/to-claude/open/`, then creates the final handoff to `.ai/handoffs/to-kimi-cockpit/open/202607200910-test-chain-v7-final.md` and self-retires.
3. Self-retire this root handoff to `.ai/handoffs/to-claude/done/202607200910-test-chain-v7-root.md` with Status: DONE.

## Verification
- (a) The four child/aggregator handoffs exist in their respective `open/` queues.
- (b) This root handoff appears in `.ai/handoffs/to-claude/done/` with `Status: DONE`.

## Report back with
- Paths of the four created handoffs.
- Paths of the three return handoffs after they are created.
- Grep proof that the root handoff is retired.
