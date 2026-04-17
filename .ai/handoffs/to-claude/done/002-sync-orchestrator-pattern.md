# Sync orchestrator-pattern instruction to Claude Code
Status: DONE
Completed: 2026-04-17 16:45 — claude-code
Output: .claude/skills/orchestrator-pattern/SKILL.md (174 lines / 6,868 bytes; body byte-for-byte identical to SSOT)
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 16:15

## Goal
Sync the new orchestrator-pattern instruction from `.ai/instructions/` into Claude
Code's native skill format. This is the unified architecture spec for the read-only
orchestrator + subagent delegation pattern all three CLIs will follow.

## Current state
- `.ai/instructions/orchestrator-pattern/principles.md` exists (SSOT)
- `.claude/skills/orchestrator-pattern/` does not exist yet

## Target state
- `.claude/skills/orchestrator-pattern/SKILL.md` — Claude skill with frontmatter +
  principles.md body

## Steps

1. Read `.ai/instructions/orchestrator-pattern/principles.md`.

2. Create `.claude/skills/orchestrator-pattern/SKILL.md` with this frontmatter:

   ```
   ---
   name: orchestrator-pattern
   description: Architecture rules for multi-agent delegation — read-only orchestrator
     delegates mutations to specialized subagents (coder, reviewer). Covers agent roles,
     write-path restrictions (.ai/.kiro/.kimi/.claude only for orchestrator), failure
     handling, delegation flow, and per-CLI implementation notes. Use when setting up
     agents, reviewing delegation behavior, or debugging orchestrator/subagent interactions.
   ---
   ```

   Then append a provenance comment:
   ```
   <!-- SSOT: .ai/instructions/orchestrator-pattern/principles.md — regenerate via .ai/sync.md -->
   ```

   Then append the full body of principles.md.

3. Verify the file exists and starts with correct frontmatter.

## Verification
- (a) `.claude/skills/orchestrator-pattern/SKILL.md` exists with frontmatter + body
- (b) Body matches `.ai/instructions/orchestrator-pattern/principles.md`

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Synced orchestrator-pattern instruction to Claude skill per handoff 002 from kiro-cli.
    - Files: .claude/skills/orchestrator-pattern/SKILL.md (new)
    - Decisions: <any frontmatter wording changes>

## Report back with
- (a) File path created
- (b) Confirmation body matches SSOT

## When complete
Kiro-cli validates. Move to `.ai/handoffs/to-claude/done/`.