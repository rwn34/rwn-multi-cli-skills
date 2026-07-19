# v6 test chain — aggregator
Status: OPEN
Sender: claude
Recipient: opencode
Owner: opencode
Created: 2026-07-19 19:30 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (test echo aggregation — no file-level assertion)

<!-- Fan-out aggregator (see README §Fan-out). This is the SINGLE actor that
     decides the continuation. It runs only after all three child returns are
     present. opencode is used as aggregator to avoid the self-addressed-handoff
     rejection (a claude aggregator writing a claude final). -->

## Goal
Collect the three v6 echo child returns and emit exactly one final handoff, so
only one actor plans the continuation.

## Preconditions (do NOT proceed until all present)
- `.ai/handoffs/to-claude/open/202607190630-test-chain-v6-kimi-return.md`
- `.ai/handoffs/to-claude/open/202607190630-test-chain-v6-kiro-return.md`
- `.ai/handoffs/to-claude/open/202607190630-test-chain-v6-opencode-return.md`

If any is missing, leave this handoff OPEN and do nothing (the dispatcher will
re-poll). Do not partially aggregate.

## Steps
1. Read the three child returns above and confirm each `## Result` line
   (`kimi-echo`, `kiro-echo`, `opencode-echo`).
2. Create the final handoff at
   `.ai/handoffs/to-kimi-cockpit/open/202607190630-test-chain-v6-final.md`
   with `Sender: opencode`, `Recipient: kimi-cockpit`, `Status: OPEN`, and a
   `## Result` section listing all three collected markers.
3. Retire the three child returns from `.ai/handoffs/to-claude/open/` to
   `.ai/handoffs/to-claude/done/` (set each `Status: DONE`).
4. Self-retire this aggregator: set `Status: DONE` and move it to
   `.ai/handoffs/to-opencode/done/`.

## Verification
- (a) `ls .ai/handoffs/to-kimi-cockpit/open/202607190630-test-chain-v6-final.md` exists.
- (b) The three child returns are in `.ai/handoffs/to-claude/done/`.
- (c) This aggregator appears in `.ai/handoffs/to-opencode/done/` with `Status: DONE`.

## Next step / future note
The kimi-cockpit session processes the final handoff to close the v6 chain.
If a child return never arrives, this aggregator stays OPEN by design — that is
the intended back-pressure, not a failure to fix here.

## Report back with
- Path of the created final handoff.
- The three collected markers.
- Grep proof that the child returns and this aggregator are retired.
