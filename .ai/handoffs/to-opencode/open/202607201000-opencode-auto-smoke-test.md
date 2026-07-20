# Opencode auto smoke test
Status: OPEN
Sender: kimi-cli
Recipient: opencode
Created: 2026-07-20 10:00 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED
Observed-in: main@HEAD

## Goal
Verify opencode auto accepts and processes a handoff.

## Steps
1. Write a return handoff to `.ai/handoffs/to-claude/open/202607201000-opencode-auto-smoke-test-return.md` with:
   - Status: OPEN
   - Sender: opencode
   - Recipient: claude
   - Body: "opencode auto smoke test return"
2. Move this handoff to `.ai/handoffs/to-opencode/done/202607201000-opencode-auto-smoke-test.md` with Status: DONE.

## Verification
- Return handoff exists in `to-claude/open/`.
- This handoff is in `to-opencode/done/` with Status DONE.
