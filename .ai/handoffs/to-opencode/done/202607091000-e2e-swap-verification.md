# E2E swap verification — prove the OpenCode lane end-to-end
Status: DONE
Sender: claude-code
Recipient: opencode
Created: 2026-07-09 10:00
Auto: yes
Risk: A

## Goal
Prove the Crush→OpenCode swap works through the real pipeline: contract loads,
report lane writable, activity log reachable, handoff protocol followed.

## Current state
OpenCode is newly installed as the fourth CLI (contract at
`.opencode/contract.md`, guard plugin at `.opencode/plugin/framework-guard.js`).
No OpenCode-authored report exists yet.

## Target state
A report at `.ai/reports/opencode-2026-07-09-e2e-verification.md`, an activity
log entry by `opencode`, and this handoff moved to `done/` with Status DONE.

## Steps
1. Write a report to `.ai/reports/opencode-2026-07-09-e2e-verification.md`
   stating, from your own contract (do not guess):
   - your identity for the activity log,
   - your writable lane (the exact writable paths),
   - the four Stage-2 deploy conditions, quoted or closely paraphrased.
2. Prepend an activity-log entry to `.ai/activity/log.md` per your contract's
   template (identity `opencode`, reference this handoff filename).
3. Edit this handoff file: change `Status: OPEN` to `Status: DONE`, then move
   it to `.ai/handoffs/to-opencode/done/` (same filename).

## Verification
- (a) Report file exists at the exact path above and lists identity, lane, and
      all four Stage-2 conditions.
- (b) `.ai/activity/log.md` has a new top entry signed `opencode`.
- (c) This file lives in `.ai/handoffs/to-opencode/done/` with `Status: DONE`.

## Next step / future note
On success Claude retires CRUSH.md/.crush.json. If the contract or guard paths
change, this verification is stale and must be rerun.

## Activity log template
    ## 2026-07-09 HH:MM — opencode
    - Action: E2E swap verification report per handoff 202607091000-e2e-swap-verification
    - Files: .ai/reports/opencode-2026-07-09-e2e-verification.md
    - Decisions: —

## Report back with
- (a) the report file path
- (b) the four Stage-2 conditions as you wrote them
- (c) confirmation of the handoff move to done/

## When complete
Sender validates by reading the report and the activity log. On success this
file lives in `.ai/handoffs/to-opencode/done/`. On failure, leave in `open/`,
set Status BLOCKED, append `## Blocker` with verbatim errors.
