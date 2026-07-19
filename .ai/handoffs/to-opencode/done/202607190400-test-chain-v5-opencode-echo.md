# Test chain v5 — opencode-auto echo marker
Status: OPEN
Sender: claude-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-19 11:00 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@06178f5
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-v5-opencode.md` with exactly:
   ```markdown
   # opencode-auto marker
   - Actor: opencode-auto
   - Handoff: 202607190400-test-chain-v5-opencode-echo
   - Written: 2026-07-19 11:00 (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607190400-test-chain-v5-opencode-return.md` with:
   - Sender: opencode-auto, Recipient: claude-auto, Owner: claude-auto, Auto: yes, Risk: A
   - Observed-in: main@06178f5, Evidence: VERIFIED
   - Body instructing claude-auto to check all three markers and create the final handoff to kimi-cockpit if all markers exist and the final handoff is absent.
3. Self-retire this original handoff to `.ai/handoffs/to-opencode/done/`.
