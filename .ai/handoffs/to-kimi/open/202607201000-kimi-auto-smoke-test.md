# Kimi auto smoke test
Status: OPEN
Sender: kimi-cli
Recipient: kimi
Created: 2026-07-20 10:00 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED
Observed-in: main@HEAD

## Goal
Verify kimi auto accepts and processes a handoff.

## Steps
1. Write a return handoff to `.ai/handoffs/to-claude/open/202607201000-kimi-auto-smoke-test-return.md` with:
   - Status: OPEN
   - Sender: kimi
   - Recipient: claude
   - Body: "kimi auto smoke test return"
2. Move this handoff to `.ai/handoffs/to-kimi/done/202607201000-kimi-auto-smoke-test.md` with Status: DONE.

## Verification
- Return handoff exists in `to-claude/open/`.
- This handoff is in `to-kimi/done/` with Status DONE.
