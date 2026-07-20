# Opencode auto smoke test v3
Status: OPEN
Sender: kimi-cli
Recipient: opencode
Created: 2026-07-20 11:00 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED
Observed-in: main@HEAD

## Goal
Verify opencode auto can write a return handoff and finish quickly.

## Steps
1. Write a return handoff to `.ai/handoffs/to-claude/open/202607201100-opencode-auto-smoke-test-v3-return.md` with:
   - Status: OPEN
   - Sender: opencode
   - Recipient: claude
   - Body: "opencode auto smoke test v3 return"
2. Update this handoff's status to DONE.

## Verification
- Return handoff exists in `to-claude/open/`.
- This handoff's Status is DONE.
