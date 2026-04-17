# Sync orchestrator-pattern instruction to Kimi CLI
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 16:15

## Goal
Sync the new orchestrator-pattern instruction from `.ai/instructions/` into Kimi
CLI's native steering format. This is the unified architecture spec for the read-only
orchestrator + subagent delegation pattern all three CLIs will follow.

## Current state
- `.ai/instructions/orchestrator-pattern/principles.md` exists (SSOT)
- `.kimi/steering/orchestrator-pattern.md` does not exist yet

## Target state
- `.kimi/steering/orchestrator-pattern.md` — copy of principles.md (always-loaded)

## Steps

1. Read `.ai/instructions/orchestrator-pattern/principles.md`.

2. Copy it to `.kimi/steering/orchestrator-pattern.md`:
   ```bash
   cp .ai/instructions/orchestrator-pattern/principles.md .kimi/steering/orchestrator-pattern.md
   ```

3. Verify the file exists and content matches SSOT.

## Verification
- (a) `.kimi/steering/orchestrator-pattern.md` exists
- (b) Content matches `.ai/instructions/orchestrator-pattern/principles.md`

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Synced orchestrator-pattern instruction to Kimi steering per handoff 004 from kiro-cli.
    - Files: .kimi/steering/orchestrator-pattern.md (new)
    - Decisions: —

## Report back with
- (a) File path created
- (b) Confirmation content matches SSOT

## When complete
Kiro-cli validates. Move to `.ai/handoffs/to-kimi/done/`.