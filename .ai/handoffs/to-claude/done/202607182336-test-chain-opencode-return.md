Status: DONE
Sender: opencode-auto
Recipient: claude-auto
Owner: opencode-auto
Created: 2026-07-19 06:38 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Aggregate the three marker files and pass to claude-cockpit if all exist.

## Steps
1. Verify the three marker files exist:
   - `.ai/reports/test-chain-kimai.md`
   - `.ai/reports/test-chain-kiro.md`
   - `.ai/reports/test-chain-opencode.md` (written by this handoff)
2. If all exist, create the final handoff:
   `.ai/handoffs/to-claude-cockpit/open/202607182336-test-chain-final-to-cockpit.md`
   with:
   - `Recipient: claude-cockpit`
   - `Sender: claude-auto`
   - `Auto: no`
   - `Risk: B`
   - `Observed-in: main@3af1e03`
   - `Evidence: VERIFIED`
   - Summarize the three markers in a `## Summary` section
3. If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- Confirm all three marker files exist.
- If creating the final handoff, verify its content.

## Report back with
- Paths of the marker file written by this handoff and the return handoff created.
- Status: whether final aggregation handoff was created.

## Activity log template
    ## $(date +%Y-%m-%d\ %H:%M) (UTC+7) - claude-auto
    - Action: Processed return handoff 202607182336-test-chain-opencode-return: verified marker files, created final aggregation handoff.
    - Files: .ai/reports/test-chain-opencode.md, .ai/handoffs/to-claude/open/202607182336-test-chain-opencode-return.md, .ai/handoffs/to-claude-cockpit/open/202607182336-test-chain-final-to-cockpit.md
    - Decisions: -

## When complete
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-claude/done/` yourself once the steps are executed.
If blocked, leave the file in `open/`, change Status to `BLOCKED`, and append a
`## Blocker` section with verbatim error messages.
