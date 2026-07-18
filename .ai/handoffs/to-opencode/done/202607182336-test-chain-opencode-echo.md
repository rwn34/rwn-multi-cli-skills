# Test chain — opencode-auto echo marker
Status: DONE
Sender: claude-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-19 06:32 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Write your marker file, then return to claude-auto for aggregation.

## Steps
1. Write `.ai/reports/test-chain-opencode.md` with exactly:
   ```markdown
   # opencode-auto marker
   - Actor: opencode-auto
   - Handoff: 202607182336-test-chain-opencode-echo
   - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
   ```
2. Create a return handoff in `.ai/handoffs/to-claude/open/202607182336-test-chain-opencode-return.md`
   with `Recipient: claude-auto`, `Sender: opencode-auto`, `Auto: yes`, `Risk: A`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, and the aggregation goal below.
3. Self-retire this handoff to `.ai/handoffs/to-opencode/done/`.

## Aggregation goal (paste into the return handoff)
Check if all three marker files exist:
`.ai/reports/test-chain-kimai.md`, `.ai/reports/test-chain-kiro.md`,
`.ai/reports/test-chain-opencode.md`. If all exist, create the final handoff
`.ai/handoffs/to-claude-cockpit/open/202607182336-test-chain-final-to-cockpit.md` with
`Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
`Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers.
If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- Confirm `.ai/reports/test-chain-opencode.md` exists and contains the expected header.
- Dry-run the return handoff:
  ```bash
  bash .ai/tools/dispatch-handoffs.sh --only claude
  ```

## Report back with
- Paths of the marker file and the return handoff created.

## Activity log template
    ## $(date +%Y-%m-%d\ %H:%M) (UTC+7) - opencode-auto
    - Action: Processed handoff 202607182336-test-chain-opencode-echo: wrote marker file and return handoff, self-retired.
    - Files: .ai/reports/test-chain-opencode.md, .ai/handoffs/to-claude/open/202607182336-test-chain-opencode-return.md, .ai/handoffs/to-opencode/done/202607182336-test-chain-opencode-echo.md
    - Decisions: -

## When complete
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-opencode/done/` yourself once the steps are executed.
If blocked, leave the file in `open/`, change Status to `BLOCKED`, and append a
`## Blocker` section with verbatim error messages.
