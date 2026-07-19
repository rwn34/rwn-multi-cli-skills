Status: OPEN
Sender: kimai-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 07:25 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED

# Test chain v3 — kimai-auto return

## Goal
Check if all three marker files exist:
`.ai/reports/test-chain-v3-kimai.md`, `.ai/reports/test-chain-v3-kiro.md`,
`.ai/reports/test-chain-v3-opencode.md`. If all exist, create the final handoff
`.ai/handoffs/to-claude-cockpit/open/202607190025-test-chain-v3-final-to-cockpit.md` with
`Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
`Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers
and instructing claude-cockpit to manually create a closing handoff to kimai-cockpit.
If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.
