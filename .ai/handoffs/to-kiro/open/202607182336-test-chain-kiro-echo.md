# Test chain — kiro-auto echo marker
Status: OPEN
Sender: claude-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-19 06:36 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-kiro.md` with exactly:
   ```markdown
   # kiro-auto marker
   - Actor: kiro-auto
   - Handoff: 202607182336-test-chain-kiro-echo
   - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607182336-test-chain-kiro-return.md`
   with `Recipient: claude-auto`, `Sender: kiro-auto`, `Auto: yes`, `Risk: A`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, and the aggregation goal below.
3. Self-retire this handoff to `.ai/handoffs/to-kiro/done/`.

## Aggregation goal (paste into the return handoff)
Check if all three marker files exist:
`.ai/reports/test-chain-kimai.md`, `.ai/reports/test-chain-kiro.md`,
`.ai/reports/test-chain-opencode.md`. If all exist, create the final handoff
`.ai/handoffs/to-claude-cockpit/open/202607182336-test-chain-final-to-cockpit.md` with
`Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
`Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers.
If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

## Report back with
- Paths of the marker file and the return handoff created.
