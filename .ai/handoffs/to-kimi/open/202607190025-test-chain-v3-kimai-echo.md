# Test chain v3 — kimai-auto echo marker
Status: OPEN
Sender: claude-auto
Recipient: kimai-auto
Owner: kimai-auto
Created: 2026-07-19 07:25 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-v3-kimai.md` with exactly:
   ```markdown
   # kimai-auto marker
   - Actor: kimai-auto
   - Handoff: 202607190025-test-chain-v3-kimai-echo
   - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607190025-test-chain-v3-kimai-return.md`
   with `Recipient: claude-auto`, `Sender: kimai-auto`, `Auto: yes`, `Risk: A`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, and the aggregation goal below.
3. Self-retire this handoff to `.ai/handoffs/to-kimi/done/`.

## Aggregation goal (paste into the return handoff)
Check if all three marker files exist:
`.ai/reports/test-chain-v3-kimai.md`, `.ai/reports/test-chain-v3-kiro.md`,
`.ai/reports/test-chain-v3-opencode.md`. If all exist, create the final handoff
`.ai/handoffs/to-claude-cockpit/open/202607190025-test-chain-v3-final-to-cockpit.md` with
`Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
`Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers
and instructing claude-cockpit to manually create a closing handoff to kimai-cockpit.
If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

## Report back with
- Paths of the marker file and the return handoff created.
