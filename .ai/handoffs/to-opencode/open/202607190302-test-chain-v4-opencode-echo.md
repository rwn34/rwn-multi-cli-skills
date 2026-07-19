# Test chain v4 — opencode-auto echo marker
Status: OPEN
Sender: claude-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-19 10:02 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@5d548ba
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-v4-opencode.md` with exactly:
   ```markdown
   # opencode-auto marker
   - Actor: opencode-auto
   - Handoff: 202607190302-test-chain-v4-opencode-echo
   - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607190302-test-chain-v4-opencode-return.md`
   with `Recipient: claude-auto`, `Sender: opencode-auto`, `Auto: yes`, `Risk: A`,
   `Observed-in: main@5d548ba`, `Evidence: VERIFIED`.
3. Self-retire this handoff to `.ai/handoffs/to-opencode/done/`.

## Aggregation goal (paste into the return handoff)
Check if all three marker files exist:
`.ai/reports/test-chain-v4-kimai.md`, `.ai/reports/test-chain-v4-kiro.md`,
`.ai/reports/test-chain-v4-opencode.md`. If all exist AND
`.ai/handoffs/to-kimi-cockpit/open/202607190302-test-chain-v4-final-to-kimi-cockpit.md`
does NOT already exist, create it with `Recipient: kimi-cockpit`,
`Sender: claude-auto`, `Auto: no`, `Risk: B`, `Observed-in: main@5d548ba`,
`Evidence: VERIFIED`, summarizing the three markers and instructing
kimi-cockpit to acknowledge and self-retire.
If not all markers exist, OR the final handoff already exists, self-retire
this return handoff to `.ai/handoffs/to-claude/done/`.
