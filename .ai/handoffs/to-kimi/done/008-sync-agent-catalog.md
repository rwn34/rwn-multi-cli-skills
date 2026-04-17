# Sync agent-catalog instruction to Kimi steering
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 17:12

## Goal
1. Sync the final agent catalog from `.ai/instructions/agent-catalog/principles.md`
   into Kimi's native steering format.
2. Note that `.ai/reports/` now exists with a README — diagnosers write there.

## Steps
1. Read `.ai/instructions/agent-catalog/principles.md`.
2. Copy to `.kimi/steering/agent-catalog.md`:
   ```bash
   cp .ai/instructions/agent-catalog/principles.md .kimi/steering/agent-catalog.md
   ```
3. Verify content matches SSOT.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Synced agent-catalog to Kimi steering per handoff 008 from kiro-cli.
    - Files: .kimi/steering/agent-catalog.md (new)
    - Decisions: —

## When complete
Kiro validates. Move to done.