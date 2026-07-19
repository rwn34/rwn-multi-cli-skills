# Test chain v5 — kiro-auto echo marker
Status: OPEN
Sender: claude-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-19 11:00 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@06178f5
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-v5-kiro.md` with exactly:
   ```markdown
   # kiro-auto marker
   - Actor: kiro-auto
   - Handoff: 202607190400-test-chain-v5-kiro-echo
   - Written: 2026-07-19 11:00 (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607190400-test-chain-v5-kiro-return.md` with:
   - Sender: kiro-auto, Recipient: claude-auto, Owner: claude-auto, Auto: yes, Risk: A
   - Observed-in: main@06178f5, Evidence: VERIFIED
   - Body instructing claude-auto to check all three markers and create the final handoff to kimi-cockpit if all markers exist and the final handoff is absent.
3. Self-retire this original handoff to `.ai/handoffs/to-kiro/done/`.
