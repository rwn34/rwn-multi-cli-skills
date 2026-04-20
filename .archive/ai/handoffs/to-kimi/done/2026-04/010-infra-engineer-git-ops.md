# Update infra-engineer: add git operations to shell scope
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 18:09

## Goal
Update Kimi's infra-engineer agent to include git operations in its shell scope.
The orchestrator has no shell — it delegates git add/commit/push/branch/merge to
infra-engineer.

## What changed in SSOT
`.ai/instructions/agent-catalog/principles.md`:
- infra-engineer shell scope: "plan/validate/build only" → "plan/validate/build + git operations"
- New behavior rule 8: infra-engineer handles git on behalf of orchestrator

## Steps
1. Update `.kimi/agents/infra-engineer.yaml` and `.kimi/agents/system/infra-engineer.md`:
   - Add git commands to the system prompt's allowed shell scope
   - Update description to mention git operations
2. Sync `.kimi/steering/agent-catalog.md` from the updated SSOT:
   ```bash
   cp .ai/instructions/agent-catalog/principles.md .kimi/steering/agent-catalog.md
   ```
3. Prepend activity log entry

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Updated infra-engineer to include git operations per handoff 010 from kiro-cli.
    - Files: .kimi/agents/infra-engineer.yaml (edit), .kimi/agents/system/infra-engineer.md (edit), .kimi/steering/agent-catalog.md (sync)
    - Decisions: —

## When complete
Move to done.