# v6 test chain — root fan-out
Status: DONE
Sender: kimai-cockpit
Recipient: claude
Owner: kimai-cockpit
Created: 2026-07-19 13:30 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (bash .ai/tests/test-sync-ai-state.sh -> 39 passed, 0 failed; bash .ai/tests/test-dispatch-worktree.sh -> TBD)
Observed-in: main@HEAD

## Goal
Run a clean fan-out test of the snapshot-copy dispatcher: create three parallel child echo handoffs to kimai-auto, kiro-auto and opencode-auto, plus a separate aggregator handoff to claude-auto. Do NOT aggregate inside the children.

## Steps
1. Create three child handoffs in:
   - `.ai/handoffs/to-kimai-auto/open/202607190630-test-chain-v6-kimai-echo.md`
   - `.ai/handoffs/to-kiro-auto/open/202607190630-test-chain-v6-kiro-echo.md`
   - `.ai/handoffs/to-opencode-auto/open/202607190630-test-chain-v6-opencode-echo.md`
   Each child must write a return handoff to `.ai/handoffs/to-claude-auto/open/` named `202607190630-test-chain-v6-<cli>-return.md` and self-retire.
2. Create an aggregator handoff in `.ai/handoffs/to-opencode-auto/open/202607190630-test-chain-v6-aggregate.md` (Sender: claude-auto, Recipient: opencode-auto) that waits for all three return files, then creates the final handoff to `.ai/handoffs/to-kimai-cockpit/open/202607190630-test-chain-v6-final.md`. Use opencode-auto as the aggregator to avoid the self-addressed-handoff rejection.
3. Self-retire this root handoff to `.ai/handoffs/to-claude-auto/done/`.

## Verification
- (a) `ls .ai/handoffs/to-kimai-auto/open/202607190630-test-chain-v6-kimai-echo.md .ai/handoffs/to-kiro-auto/open/202607190630-test-chain-v6-kiro-echo.md .ai/handoffs/to-opencode-auto/open/202607190630-test-chain-v6-opencode-echo.md .ai/handoffs/to-claude-auto/open/202607190630-test-chain-v6-aggregate.md` all exist.
- (b) This handoff appears in `.ai/handoffs/to-claude-auto/done/202607190630-test-chain-v6-root.md` with `Status: DONE`.

## Report back with
- Paths of the four created handoffs.
- Grep proof that the root handoff is retired.

## Next step / future note
After this handoff, run `bash .ai/tools/dispatch-handoffs.sh --exec --only kimai --one`, then the same for kiro and opencode (can be parallel), then `bash .ai/tools/dispatch-handoffs.sh --exec --only claude --one` for the aggregator, then process the final handoff in the kimai-cockpit session.

## Completion (claude-code, 2026-07-19)
Processed by claude-code (cockpit). The fan-out was **already staged** by a prior
pass (file mtimes 13:37–13:51) and is internally coherent, so I converged on it
rather than re-creating duplicates (the fan-out anti-duplication rule in
README §"Fan-out: root → children → aggregator → next" prohibits two child sets /
two final-emitters). Steps 1–2 are satisfied; Step 3 (this retirement) is now done.

Four staged artifacts (all `Status: OPEN`, awaiting dispatch):
- `.ai/handoffs/to-kimi/open/202607190630-test-chain-v6-kimi-echo.md`  (Recipient: kimai-auto)
- `.ai/handoffs/to-kiro/open/202607190630-test-chain-v6-kiro-echo.md`  (Recipient: kiro-auto)
- `.ai/handoffs/to-opencode/open/202607190630-test-chain-v6-opencode-echo.md`  (Recipient: opencode-auto)
- `.ai/handoffs/to-opencode/open/202607190630-test-chain-v6-aggregate.md`  (Sender: claude-auto, Recipient: opencode-auto)

Plus a pre-staged final at `.ai/handoffs/to-kimai-cockpit/open/202607190630-test-chain-v6-final.md`.
No `*-return.md` files exist yet (children not dispatched) — expected pre-dispatch state.

### Deviation flag for sender (kimai-cockpit) — validate before dispatch
The children/aggregator live in the **real dispatcher-polled queue dirs**
(`to-kimi/`, `to-kiro/`, `to-opencode/`) — not the literal `to-*-auto/open/`
paths named in Steps 1–2 and Verification (a). Reason: per README §Layout +
§"Six-actor cockpit / auto model", the queue directories are named after the
four CLIs (`to-claude/`, `to-kimi/`, `to-kiro/`, `to-opencode/`); the `-auto`
suffix is a *Sender/Recipient identity* value, not a directory name, and the
`to-*-auto/` dirs on disk contain only `done/`, no `open/`. So Verification (a)'s
literal `-auto/open/` paths do not (and, by convention, should not) exist.
If you specifically intended physical `-auto/open/` queue dirs, re-open this and
say so — I did not duplicate to avoid a double-dispatch race.

Retired to `.ai/handoffs/to-claude-auto/done/` per Verification (b).
