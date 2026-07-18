# Test chain — kimai-auto return marker
Status: OPEN
Sender: kimai-auto
Recipient: claude-auto
Owner: kimai-auto
Created: 2026-07-19 06:39 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED

## Goal
Aggregate the three marker files and create the final cockpit handoff if all exist.

## Steps
1. Check if all three marker files exist:
   `.ai/reports/test-chain-kimai.md`, `.ai/reports/test-chain-kiro.md`,
   `.ai/reports/test-chain-opencode.md`.
2. If all exist, create the final handoff
   `.ai/handoffs/to-claude-cockpit/open/202607182336-test-chain-final-to-cockpit.md` with
   `Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers.
3. If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

## Report back with
- Whether all three marker files were found.
- Path of the final handoff created, or confirmation that the return handoff was retired.
