# v6 test chain — aggregator
Status: OPEN
Sender: claude
Recipient: opencode
Owner: claude
Created: 2026-07-19 13:30 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (ls .ai/handoffs/to-claude/open/202607190630-test-chain-v6-*-return.md)
Observed-in: main@HEAD

## Goal
Collect the three child return handoffs and emit the final handoff to kimi-cockpit. If any return is missing, leave this handoff OPEN and exit without creating the final handoff.

## Steps
1. Verify these three files exist:
   - `.ai/handoffs/to-claude/open/202607190630-test-chain-v6-kimi-return.md`
   - `.ai/handoffs/to-claude/open/202607190630-test-chain-v6-kiro-return.md`
   - `.ai/handoffs/to-claude/open/202607190630-test-chain-v6-opencode-return.md`
   If any are missing, stop and leave this handoff OPEN.
2. Create the final handoff at `.ai/handoffs/to-kimi-cockpit/open/202607190630-test-chain-v6-final.md` with:
   - `Status: OPEN`
   - `Sender: opencode`
   - `Recipient: kimi-cockpit`
   - `Evidence: VERIFIED (ls ...-return.md)`
   - A `## Result` section listing all three return markers.
3. Self-retire this handoff to `.ai/handoffs/to-opencode/done/202607190630-test-chain-v6-aggregate.md` with `Status: DONE`.

## Verification
- (a) `test -f .ai/handoffs/to-kimi-cockpit/open/202607190630-test-chain-v6-final.md`
- (b) This handoff is in `.ai/handoffs/to-opencode/done/` with `Status: DONE`.

## Report back with
- The exact content of the final handoff.
