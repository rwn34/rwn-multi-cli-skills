# Opencode auto smoke test v2
Status: DONE
Sender: kimi-cli
Recipient: opencode
Created: 2026-07-20 10:30 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED
Observed-in: main@HEAD

## Goal
Verify opencode auto accepts and processes a minimal handoff without hanging on large reads.

## Steps
1. Write a return handoff to `.ai/handoffs/to-claude/open/202607201030-opencode-auto-smoke-test-v2-return.md` with:
   - Status: OPEN
   - Sender: opencode
   - Recipient: claude
   - Body: "opencode auto smoke test v2 return"
2. Update this handoff's status to DONE and move it to `.ai/handoffs/to-opencode/done/202607201030-opencode-auto-smoke-test-v2.md`.

## Verification
- Return handoff exists in `to-claude/open/`.
- This handoff is in `to-opencode/done/` with Status DONE.
