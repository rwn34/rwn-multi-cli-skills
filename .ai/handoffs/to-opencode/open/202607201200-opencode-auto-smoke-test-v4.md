# Opencode auto smoke test v4
Status: OPEN
Sender: kimi-cli
Recipient: opencode
Created: 2026-07-20 12:00 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED
Observed-in: main@HEAD

## Goal
Verify opencode auto accepts and processes a handoff end-to-end after the sync-ai-state race fix.

## Steps
1. Write a return handoff to `.ai/handoffs/to-claude/open/202607201200-opencode-auto-smoke-test-v4-return.md` with:
   - Status: OPEN
   - Sender: opencode
   - Recipient: claude
   - Body: "opencode auto smoke test v4 return"
2. Update this handoff's status to DONE and move it to `.ai/handoffs/to-opencode/done/202607201200-opencode-auto-smoke-test-v4.md`.
3. Prepend a brief activity-log entry.

## Verification
- Return handoff exists in `to-claude/open/`.
- This handoff is in `to-opencode/done/` with Status DONE.
- Activity-log entry was prepended.
