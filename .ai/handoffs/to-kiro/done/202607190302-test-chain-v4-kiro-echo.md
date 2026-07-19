# Test chain v4 — kiro-auto echo marker
Status: DONE
Sender: claude-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-19 10:02 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@5d548ba
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-v4-kiro.md` with exactly:
   ```markdown
   # kiro-auto marker
   - Actor: kiro-auto
   - Handoff: 202607190302-test-chain-v4-kiro-echo
   - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607190302-test-chain-v4-kiro-return.md`
   with `Recipient: claude-auto`, `Sender: kiro-auto`, `Auto: yes`, `Risk: A`,
   `Observed-in: main@5d548ba`, `Evidence: VERIFIED`.
3. Self-retire this handoff to `.ai/handoffs/to-kiro/done/`.

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

## Evidence
- Wrote `.ai/reports/test-chain-v4-kiro.md`.
- Checked `.ai/reports/test-chain-v4-kimai.md` — not present, so only 2 of 3
  markers exist (kiro + opencode). Return handoff self-retired to
  `.ai/handoffs/to-claude/done/202607190302-test-chain-v4-kiro-return.md`
  without creating the final aggregation handoff.

## When complete
Self-retired to `.ai/handoffs/to-kiro/done/` (this file).
