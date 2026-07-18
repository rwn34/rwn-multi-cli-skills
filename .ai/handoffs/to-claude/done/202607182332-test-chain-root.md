# Test chain root — distribute to all four autos and return to claude-cockpit
Status: DONE
Sender: kimai-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 06:32 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Demonstrate the six-actor handoff chain requested by the owner:

```text
kimai-cockpit
  └── claude-auto  (this handoff)
        ├── kimai-auto
        ├── kiro-auto
        ├── opencode-auto
        └── claude-auto  (aggregator return)
              └── claude-cockpit  (manual trigger)
                    └── kimai-cockpit
```

You are the root dispatcher. Create three parallel child handoffs, then self-retire.
The child autos will each write a marker file and return to you. The last return will
hand the result off to `claude-cockpit` as an `Auto: no` handoff for the owner to
relay to `kimai-cockpit`.

## Steps

1. Determine the current UTC timestamp for filenames:
   ```bash
   ts=$(date -u +%Y%m%d%H%M)
   echo "$ts"
   ```

2. Create the three child handoffs. Replace `${ts}` with the value from step 1.

   ### Child 1 — kimai-auto
   File: `.ai/handoffs/to-kimi/open/${ts}-test-chain-kimai-echo.md`
   ```markdown
   # Test chain — kimai-auto echo marker
   Status: OPEN
   Sender: claude-auto
   Recipient: kimai-auto
   Owner: kimai-auto
   Created: 2026-07-19 06:32 (UTC+7)
   Auto: yes
   Risk: A
   Observed-in: main@3af1e03
   Evidence: VERIFIED (framework routing smoke test — no file-level claims)

   ## Goal
   Write your marker file, then return to claude-auto for aggregation.

   ## Steps
   1. Write `.ai/reports/test-chain-kimai.md` with exactly:
      ```markdown
      # kimai-auto marker
      - Actor: kimai-auto
      - Handoff: ${ts}-test-chain-kimai-echo
      - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
      ```
   2. Create a return handoff in `.ai/handoffs/to-claude/open/${ts}-test-chain-kimai-return.md`
      with `Recipient: claude-auto`, `Sender: kimai-auto`, `Auto: yes`, `Risk: A`,
      `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, and the aggregation goal below.
   3. Self-retire this handoff to `.ai/handoffs/to-kimi/done/`.

   ## Aggregation goal (paste into the return handoff)
   Check if all three marker files exist:
   `.ai/reports/test-chain-kimai.md`, `.ai/reports/test-chain-kiro.md`,
   `.ai/reports/test-chain-opencode.md`. If all exist, create the final handoff
   `.ai/handoffs/to-claude-cockpit/open/${ts}-test-chain-final-to-cockpit.md` with
   `Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers.
   If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

   ## Report back with
   - Paths of the marker file and the return handoff created.
   ```

   ### Child 2 — kiro-auto
   File: `.ai/handoffs/to-kiro/open/${ts}-test-chain-kiro-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: kiro-auto`
   - marker file: `.ai/reports/test-chain-kiro.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-kiro-return.md`
   - `Sender: kiro-auto`

   ### Child 3 — opencode-auto
   File: `.ai/handoffs/to-opencode/open/${ts}-test-chain-opencode-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: opencode-auto`
   - marker file: `.ai/reports/test-chain-opencode.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-opencode-return.md`
   - `Sender: opencode-auto`

3. Self-retire this root handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- Dry-run the dispatcher to confirm the child handoffs are discovered:
  ```bash
  bash .ai/tools/dispatch-handoffs.sh --only kimi
  bash .ai/tools/dispatch-handoffs.sh --only kiro
  bash .ai/tools/dispatch-handoffs.sh --only opencode
  ```

## Next step / future note
The final `to-claude-cockpit` handoff is intentionally `Auto: no` so the owner can
manually trigger `claude-cockpit` to create the closing handoff to `kimai-cockpit`.
If this test loops, the likely cause is a return handoff with `Sender == Recipient`.

## Activity log template
    ## 2026-07-19 06:32 (UTC+7) - claude-auto
    - Action: created test-chain child handoffs per 202607182332-test-chain-root
    - Files: .ai/handoffs/to-kimi/open/${ts}-test-chain-kimai-echo.md, .ai/handoffs/to-kiro/open/${ts}-test-chain-kiro-echo.md, .ai/handoffs/to-opencode/open/${ts}-test-chain-opencode-echo.md
    - Decisions: used parallel child handoffs with claude-auto aggregator returns

## When complete
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-claude/done/` yourself once the child handoffs are created.
If blocked, leave the file in `open/`, change Status to `BLOCKED`, and append a
`## Blocker` section with verbatim error messages.

## Evidence (claude-auto, 2026-07-19 06:36 UTC+7)
ts = `202607182336` (UTC), base HEAD = `3af1e03` (matches Observed-in).
Three parallel child handoffs created:
- `.ai/handoffs/to-kimi/open/202607182336-test-chain-kimai-echo.md`
- `.ai/handoffs/to-kiro/open/202607182336-test-chain-kiro-echo.md`
- `.ai/handoffs/to-opencode/open/202607182336-test-chain-opencode-echo.md`

Each instructs the recipient auto to write its marker report and file a
`to-claude/open/…-return.md` aggregator handoff back to claude-auto; the last
return (all three markers present) emits the `Auto: no` final handoff to
`claude-cockpit`. Root self-retired to `to-claude/done/`.
