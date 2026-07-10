# Test handoff — count 1+3 and hand back
Status: DONE
Sender: claude-code
Recipient: opencode
Created: 2026-07-09 22:20
Auto: yes
Risk: A

## Goal
A round-trip liveness test of the handoff pipeline. Prove OpenCode can receive a
handoff, execute a trivial task, and hand a result back to Claude.

## Current state
No test artifact exists. This is the outbound leg from claude-code.

## Target state
OpenCode has computed 1+3 and written a return handoff to
`.ai/handoffs/to-claude/open/` reporting the answer.

## Steps
1. Compute 1 + 3.
2. Write a return handoff to
   `.ai/handoffs/to-claude/open/YYYYMMDDHHMM-test-count-reply-opencode.md`
   following `.ai/handoffs/template.md`. Set Sender: opencode, Recipient: claude-code,
   Risk: A, Auto: yes. In the body, state the result of 1+3.
3. Prepend a one-line entry to `.ai/activity/log.md` (identity: `opencode`).

## Verification
- (a) Confirm the arithmetic result (1+3 = 4) appears in your return handoff file.

## Next step / future note
Once Claude reads your reply handoff and confirms the value, this test handoff is
moved to `to-opencode/done/`. This validates the OpenCode→Claude return path.

## Activity log template
    ## YYYY-MM-DD HH:MM — opencode
    - Action: per handoff 202607092220-test-count-roundtrip — computed 1+3, wrote reply handoff
    - Files: .ai/handoffs/to-claude/open/<reply>.md
    - Decisions: —

## Report back with
- (a) The result of 1+3.
- (b) The path of the return handoff you wrote.

## When complete
Sender (claude-code) validates by reading the return handoff. On success, moves this
file to `.ai/handoffs/to-opencode/done/`.
