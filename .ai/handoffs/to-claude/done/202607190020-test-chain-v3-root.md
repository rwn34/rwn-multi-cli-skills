# Test chain v3 — confirm sync-back fix end-to-end
Status: DONE
Sender: kimai-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 07:20 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@3af1e03
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Re-run the six-actor handoff chain after the sync-ai-state.sh cross-recipient
sync-back fix. Confirm that all three child autos run, all three returns reach
claude-auto, and the chain closes at claude-cockpit -> kimi-cockpit.

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
   File: `.ai/handoffs/to-kimi/open/${ts}-test-chain-v3-kimai-echo.md`
   ```markdown
   # Test chain v3 — kimai-auto echo marker
   Status: OPEN
   Sender: claude-auto
   Recipient: kimai-auto
   Owner: kimai-auto
   Created: 2026-07-19 07:20 (UTC+7)
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
      - Handoff: ${ts}-test-chain-v3-kimai-echo
      - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
      ```
   2. Create a return handoff in `.ai/handoffs/to-claude/open/${ts}-test-chain-v3-kimai-return.md`
      with `Recipient: claude-auto`, `Sender: kimai-auto`, `Auto: yes`, `Risk: A`,
      `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, and the aggregation goal below.
   3. Self-retire this handoff to `.ai/handoffs/to-kimi/done/`.

   ## Aggregation goal (paste into the return handoff)
   Check if all three marker files exist:
   `.ai/reports/test-chain-v3-kimai.md`, `.ai/reports/test-chain-v3-kiro.md`,
   `.ai/reports/test-chain-v3-opencode.md`. If all exist, create the final handoff
   `.ai/handoffs/to-claude-cockpit/open/${ts}-test-chain-v3-final-to-cockpit.md` with
   `Recipient: claude-cockpit`, `Sender: claude-auto`, `Auto: no`, `Risk: B`,
   `Observed-in: main@3af1e03`, `Evidence: VERIFIED`, summarizing the three markers
   and instructing claude-cockpit to manually create a closing handoff to kimai-cockpit.
   If not all exist, self-retire this return handoff to `.ai/handoffs/to-claude/done/`.

   ## Report back with
   - Paths of the marker file and the return handoff created.
   ```

   ### Child 2 — kiro-auto
   File: `.ai/handoffs/to-kiro/open/${ts}-test-chain-v3-kiro-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: kiro-auto`
   - marker file: `.ai/reports/test-chain-v3-kiro.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-v3-kiro-return.md`
   - `Sender: kiro-auto`

   ### Child 3 — opencode-auto
   File: `.ai/handoffs/to-opencode/open/${ts}-test-chain-v3-opencode-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: opencode-auto`
   - marker file: `.ai/reports/test-chain-v3-opencode.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-v3-opencode-return.md`
   - `Sender: opencode-auto`

3. Self-retire this root handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- After all three children finish, confirm all three marker files exist in `.ai/reports/`.
- Confirm `to-claude/open/` contains all three return handoffs (the sync-back fix
  should prevent any of them from being deleted by another worktree).
- Dry-run the aggregator returns:
  ```bash
  bash .ai/tools/dispatch-handoffs.sh --only claude
  ```

## Next step / future note
The final `to-claude-cockpit` handoff is intentionally `Auto: no` so the owner can
manually trigger `claude-cockpit` to create the closing handoff to `kimai-cockpit`.

## Activity log template
    ## 2026-07-19 07:20 (UTC+7) - claude-auto
    - Action: created test-chain-v3 child handoffs per 202607190020-test-chain-v3-root
    - Files: .ai/handoffs/to-kimi/open/${ts}-test-chain-v3-kimai-echo.md, .ai/handoffs/to-kiro/open/${ts}-test-chain-v3-kiro-echo.md, .ai/handoffs/to-opencode/open/${ts}-test-chain-v3-opencode-echo.md
    - Decisions: used parallel child handoffs with claude-auto aggregator returns to verify sync-back fix

## When complete
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-claude/done/` yourself once the child handoffs are created.
If blocked, leave the file in `open/`, change Status to `BLOCKED`, and append a
`## Blocker` section with verbatim error messages.

## Result (claude-auto, 2026-07-19 07:25 UTC+7)
Assigned steps complete. Used UTC filename timestamp `202607190025` for the
three children (root filename was `202607190020`).

Children created:
- `.ai/handoffs/to-kimi/open/202607190025-test-chain-v3-kimai-echo.md` (Recipient: kimai-auto)
- `.ai/handoffs/to-kiro/open/202607190025-test-chain-v3-kiro-echo.md` (Recipient: kiro-auto)
- `.ai/handoffs/to-opencode/open/202607190025-test-chain-v3-opencode-echo.md` (Recipient: opencode-auto)

Remaining chain is executor-driven: each child auto writes its marker to
`.ai/reports/test-chain-v3-<actor>.md` and files a `to-claude/open/…-return.md`.
The sync-back fix (kimai-cockpit, 2026-07-19 07:19 UTC+7 + regression test case 10)
should now keep all three returns alive in `to-claude/open/` instead of being
deleted cross-recipient — that is the end-to-end behavior this chain verifies.
Dispatch of the children was NOT triggered by this session (assigned scope was
child creation + self-retire only); run `bash .ai/tools/dispatch-handoffs.sh --exec`
to execute the chain live and confirm the fix.
