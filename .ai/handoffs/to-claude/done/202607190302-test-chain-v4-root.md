# Test chain v4 — distribute to all autos, aggregate back to claude-auto, final to kimi-cockpit
Status: DONE
Sender: kimi-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 10:02 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@5d548ba
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
Stress-test the six-actor chain with a different cockpit close:
claude-auto distributes work to kimai-auto, kiro-auto, and opencode-auto,
waits for all three returns, then emits the final handoff to **kimi-cockpit**
(instead of claude-cockpit).

```text
kimai-cockpit
  └── claude-auto  (this handoff)
        ├── kimai-auto
        ├── kiro-auto
        ├── opencode-auto
        └── claude-auto  (aggregator returns)
              └── kimi-cockpit  (manual trigger / owner-close)
```

## Steps

1. Determine the current UTC timestamp for filenames:
   ```bash
   ts=$(date -u +%Y%m%d%H%M)
   echo "$ts"
   ```

2. Create three parallel child handoffs. Replace `${ts}` with the value from step 1.

   ### Child 1 — kimai-auto
   File: `.ai/handoffs/to-kimi/open/${ts}-test-chain-v4-kimai-echo.md`
   ```markdown
   # Test chain v4 — kimai-auto echo marker
   Status: OPEN
   Sender: claude-auto
   Recipient: kimai-auto
   Owner: kimai-auto
   Created: 2026-07-19 10:02 (UTC+7)
   Auto: yes
   Risk: A
   Observed-in: main@5d548ba
   Evidence: VERIFIED (framework routing smoke test — no file-level claims)

   ## Goal
   Write your marker file, then return to claude-auto for aggregation.

   ## Steps
   1. Write `.ai/reports/test-chain-v4-kimai.md` with exactly:
      ```markdown
      # kimai-auto marker
      - Actor: kimai-auto
      - Handoff: ${ts}-test-chain-v4-kimai-echo
      - Written: $(date +%Y-%m-%d\ %H:%M) (UTC+7)
      ```
   2. Create a return handoff in `.ai/handoffs/to-claude/open/${ts}-test-chain-v4-kimai-return.md`
      with `Recipient: claude-auto`, `Sender: kimai-auto`, `Auto: yes`, `Risk: A`,
      `Observed-in: main@5d548ba`, `Evidence: VERIFIED`.
   3. Self-retire this handoff to `.ai/handoffs/to-kimi/done/`.

   ## Aggregation goal (paste into the return handoff)
   Check if all three marker files exist:
   `.ai/reports/test-chain-v4-kimai.md`, `.ai/reports/test-chain-v4-kiro.md`,
   `.ai/reports/test-chain-v4-opencode.md`. If all exist AND
   `.ai/handoffs/to-kimi-cockpit/open/${ts}-test-chain-v4-final-to-kimi-cockpit.md`
   does NOT already exist, create it with `Recipient: kimi-cockpit`,
   `Sender: claude-auto`, `Auto: no`, `Risk: B`, `Observed-in: main@5d548ba`,
   `Evidence: VERIFIED`, summarizing the three markers and instructing
   kimi-cockpit to acknowledge and self-retire.
   If not all markers exist, OR the final handoff already exists, self-retire
   this return handoff to `.ai/handoffs/to-claude/done/`.
   ```

   ### Child 2 — kiro-auto
   File: `.ai/handoffs/to-kiro/open/${ts}-test-chain-v4-kiro-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: kiro-auto`
   - marker file: `.ai/reports/test-chain-v4-kiro.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-v4-kiro-return.md`
   - `Sender: kiro-auto`

   ### Child 3 — opencode-auto
   File: `.ai/handoffs/to-opencode/open/${ts}-test-chain-v4-opencode-echo.md`
   Same pattern as Child 1, but:
   - `Recipient: opencode-auto`
   - marker file: `.ai/reports/test-chain-v4-opencode.md`
   - return handoff: `.ai/handoffs/to-claude/open/${ts}-test-chain-v4-opencode-return.md`
   - `Sender: opencode-auto`

3. Self-retire this root handoff to `.ai/handoffs/to-claude/done/`.

## Verification
- After all three children finish, confirm all three marker files exist in `.ai/reports/`.
- Confirm a final handoff exists in `.ai/handoffs/to-kimi-cockpit/open/`.
- The final handoff is `Auto: no`; it waits for kimi-cockpit to acknowledge.

## Activity log template
    ## 2026-07-19 10:02 (UTC+7) - claude-auto
    - Action: created test-chain-v4 child handoffs per 202607190302-test-chain-v4-root
    - Files: .ai/handoffs/to-kimi/open/${ts}-test-chain-v4-kimai-echo.md, .ai/handoffs/to-kiro/open/${ts}-test-chain-v4-kiro-echo.md, .ai/handoffs/to-opencode/open/${ts}-test-chain-v4-opencode-echo.md
    - Decisions: final handoff routes to kimi-cockpit instead of claude-cockpit to test cross-cockpit chain

## When complete
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-claude/done/` yourself once the child handoffs are created.
If blocked, leave the file in `open/`, change Status to `BLOCKED`, and append a
`## Blocker` section with verbatim error messages.

## Report (claude-auto, 2026-07-19)
Created all three parallel child handoffs, reusing the root UTC timestamp
`202607190302` for the `${ts}` slot (v3 precedent — keeps the whole chain
under one identifier and avoids a shell-clock dependency):
- `.ai/handoffs/to-kimi/open/202607190302-test-chain-v4-kimai-echo.md`
- `.ai/handoffs/to-kiro/open/202607190302-test-chain-v4-kiro-echo.md`
- `.ai/handoffs/to-opencode/open/202607190302-test-chain-v4-opencode-echo.md`

Each child echoes a marker to `.ai/reports/test-chain-v4-<actor>.md`, files a
`…-return.md` back to `to-claude/open/`, and carries the aggregation logic that
emits the final `Auto: no` `Risk: B` handoff to `to-kimi-cockpit/open/` once all
three markers exist. Self-retire move to `to-claude/done/` delegated to
infra-engineer (no shell in the orchestrator).
