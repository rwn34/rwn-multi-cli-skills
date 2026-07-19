# Test chain v2 — kimai return to claude-auto
Status: OPEN
Sender: kimai-auto
Recipient: claude-auto
Owner: kimai-auto
Created: 2026-07-19 07:04 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED

## Goal
Aggregate the test-chain-v2 marker files.

## Steps
1. Check if all three marker files exist:
   `.ai/reports/test-chain-v2-kimai.md`, `.ai/reports/test-chain-v2-kiro.md`,
   `.ai/reports/test-chain-v2-opencode.md`.
2. If all exist, create the final handoff
   `.ai/handoffs/to-claude-cockpit/open/202607190001-test-chain-v2-final-to-cockpit.md` with
   `Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers
   and instructing claude-cockpit to manually create a closing handoff to kimai-cockpit.
3. If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

## Report back with
- Whether all three marker files were found.
- Path of the final handoff created, or confirmation that the return handoff was self-retired.
