# Test chain v2 — verify sync-back no longer deletes in-flight returns
Status: DONE (steps executed) — VERIFICATION FAILED, regression reproduced

## Verification result (claude-auto, 2026-07-19 07:08 UTC+7)
Assigned steps completed: three child echo handoffs created (ts=202607190001),
root self-retired to done/, dispatcher dry-run listed all three. Then ran
`bash .ai/tools/dispatch-handoffs.sh --exec` to execute the chain live.

**The test's stated goal FAILED — sync-back still deletes in-flight handoffs.**
Only the kimi child launched. Its worktree sync-back removed BOTH the still-pending
`to-kiro/open/202607190001-test-chain-v2-kiro-echo.md` and
`to-opencode/open/202607190001-test-chain-v2-opencode-echo.md` as "handoff
retirement" — neither was ever dispatched. Verified against the live tree: both
files are gone; only the kimi marker + kimi return survived. The 06:58 hash-guard
fix protects handoffs that CHANGED since the snapshot but not unchanged in-flight
handoffs addressed to OTHER recipients. Filed bug handoff
`.ai/handoffs/to-kimi/open/202607190008-fix-syncback-cross-recipient-deletion.md`.
Sender: kimai-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 06:59 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Re-run the six-actor handoff chain after the sync-ai-state.sh fix. Verify that
kimai-auto and kiro-auto return handoffs in `to-claude/open/` survive
opencode-auto's sync-back, so claude-auto can process all three returns and the
chain closes cleanly.

```text
kimai-cockpit
  └── claude-auto  (this handoff)
        ├── kimai-auto
        ├── kiro-auto
        ├── opencode-auto
        └── claude-auto  (aggregator returns)
              └── claude-cockpit  (manual trigger)
                    └── kimai-cockpit
```

## Steps

1. Determine the current UTC timestamp for filenames:
   ```bash
   ts=$(date -u +%Y%m%d%H%M)
   echo "$ts"
   ```

2. Create three parallel child handoffs. Replace `${ts}` with the value from step 1.

   ### Child 1 — kimai-auto
   File: `.ai/handoffs/to-kimi/open/${ts}-test-chain-v2-kimai-echo.md`
   ```markdown
   # Test chain v2 — kimai-auto echo marker
   Status: OPEN
   Sender: claude-auto
   Recipient: kimai-auto
   Owner: kimai-auto
   Created: 2026-07-19 06:59 (UTC+7)
   Auto: yes
   Risk: A
   Observed-in: main@3af1e03
   Evidence: VERIFIED (framework routing smoke test — no file-level claims)

   ## Goal
   Write your marker file, then return to claude-auto for aggregation.

   ## Steps
   1. Write `.ai/reports/test-chain-v2-kimai.md` with exactly:
      ```markdown
      # kimai-auto marker
      - Actor: kimai-auto
      - Handoff: ${ts}-test-chain-v2-kimai-echo
      - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
      ```
   2. Create a return handoff in `.ai/handoffs/to-claude/open/${ts}-test-chain-v2-kimai-return.md`
      with `Recipient: claude-auto`, `Sender: kimai-auto`, `Auto: yes`, `Risk: A`,
      `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, and the aggregation goal below.
   3. Self-retire this handoff to `.ai/handoffs/to-kimi/done/`.

   ## Aggregation goal (paste into the return handoff)
   Check if all three marker files exist:
   `.ai/reports/test-chain-v2-kimai.md`, `.ai/reports/test-chain-v2-kiro.md`,
   `.ai/reports/test-chain-v2-opencode.md`. If all exist, create the final handoff
   `.ai/handoffs/to-claude-cockpit/open/${ts}-test-chain-v2-final-to-cockpit.md` with
   `Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers
   and instructing claude-cockpit to manually create a closing handoff to kimai-cockpit.
   If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

   ## Report back with
   - Paths of the marker file and the return handoff created.
   ```

   ### Child 2 — kiro-auto
   File: `.ai/handoffs/to-kiro/open/${ts}-test-chain-v2-kiro-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: kiro-auto`
   - marker file: `.ai/reports/test-chain-v2-kiro.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-v2-kiro-return.md`
   - `Sender: kiro-auto`

   ### Child 3 — opencode-auto
   File: `.ai/handoffs/to-opencode/open/${ts}-test-chain-v2-opencode-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: opencode-auto`
   - marker file: `.ai/reports/test-chain-v2-opencode.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-v2-opencode-return.md`
   - `Sender: opencode-auto`

3. Self-retire this root handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- After dispatching the three child handoffs, confirm that `to-claude/open/` still
  contains the kimai and kiro return handoffs even after opencode-auto syncs back.
- Dry-run the dispatcher to confirm all returns are discovered:
  ```bash
  bash .ai/tools/dispatch-handoffs.sh --only claude
  ```

## Next step / future note
The final `to-claude-cockpit` handoff is intentionally `Auto: no` so the owner can
manually trigger `claude-cockpit` to create the closing handoff to `kimai-cockpit`.

## Activity log template
    ## 2026-07-19 06:59 (UTC+7) - claude-auto
    - Action: created test-chain-v2 child handoffs per 202607182359-test-chain-v2-root
    - Files: .ai/handoffs/to-kimi/open/${ts}-test-chain-v2-kimai-echo.md, .ai/handoffs/to-kiro/open/${ts}-test-chain-v2-kiro-echo.md, .ai/handoffs/to-opencode/open/${ts}-test-chain-v2-opencode-echo.md
    - Decisions: used parallel child handoffs with claude-auto aggregator returns to stress-test sync-back deletion guard

## When complete
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-claude/done/` yourself once the child handoffs are created.
If blocked, leave the file in `open/`, change Status to `BLOCKED`, and append a
`## Blocker` section with verbatim error messages.
