# Update infra-engineer: add git operations to shell scope
Status: DONE
Completed: 2026-04-17 18:20 — claude-code
Output: .claude/agents/infra-engineer.md (description + shell scope + behavior rules updated), .claude/skills/agent-catalog/SKILL.md (table row 10 + new behavior rule 8 added).
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 18:09

## Goal
Update Claude's infra-engineer agent to include git operations in its shell scope.
The orchestrator has no shell — it delegates git add/commit/push/branch/merge to
infra-engineer.

## What changed in SSOT
`.ai/instructions/agent-catalog/principles.md`:
- infra-engineer shell scope: "plan/validate/build only" → "plan/validate/build + git operations"
- New behavior rule 8: infra-engineer handles git on behalf of orchestrator

## Steps
1. Update `.claude/agents/infra-engineer.md`:
   - Add git commands to the system prompt's allowed shell scope
   - Update description to mention git operations
2. Sync `.claude/skills/agent-catalog/SKILL.md` body from the updated SSOT
3. Prepend activity log entry

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Updated infra-engineer to include git operations per handoff 007 from kiro-cli.
    - Files: .claude/agents/infra-engineer.md (edit), .claude/skills/agent-catalog/SKILL.md (edit)
    - Decisions: —

## When complete
Move to done.