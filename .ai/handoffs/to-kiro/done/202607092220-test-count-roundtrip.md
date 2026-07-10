# Test handoff — count 1+3 and hand back
Status: DONE
<!-- kiro-cli 2026-07-09 22:16: computed 1+3=4; wrote reply handoff
     .ai/handoffs/to-claude/open/202607092216-test-count-reply-kiro.md.
     Awaiting claude-code validation + move to to-kiro/done/. -->
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 22:20
Auto: yes
Risk: A

## Goal
A round-trip liveness test of the handoff pipeline. Prove Kiro CLI can receive a
handoff, execute a trivial task, and hand a result back to Claude.

## Current state
No test artifact exists. This is the outbound leg from claude-code.

## Target state
Kiro has computed 1+3 and written a return handoff to
`.ai/handoffs/to-claude/open/` reporting the answer.

## Steps
1. Compute 1 + 3.
2. Write a return handoff to
   `.ai/handoffs/to-claude/open/YYYYMMDDHHMM-test-count-reply-kiro.md`
   following `.ai/handoffs/template.md`. Set Sender: kiro-cli, Recipient: claude-code,
   Risk: A, Auto: yes. In the body, state the result of 1+3.
3. Prepend a one-line entry to `.ai/activity/log.md` (identity: `kiro-cli`).

## Verification
- (a) Confirm the arithmetic result (1+3 = 4) appears in your return handoff file.

## Next step / future note
Once Claude reads your reply handoff and confirms the value, this test handoff is
moved to `to-kiro/done/`. This validates the Kiro→Claude return path.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: per handoff 202607092220-test-count-roundtrip — computed 1+3, wrote reply handoff
    - Files: .ai/handoffs/to-claude/open/<reply>.md
    - Decisions: —

## Report back with
- (a) The result of 1+3.
- (b) The path of the return handoff you wrote.

## When complete
Sender (claude-code) validates by reading the return handoff. On success, moves this
file to `.ai/handoffs/to-kiro/done/`.
