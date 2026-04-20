# Implement 13-agent configs for Claude Code
Status: DONE
Completed: 2026-04-17 17:50 — claude-code
Output: .claude/agents/*.md (13 new) + .claude/settings.json (agent: orchestrator). Validation handoff at .ai/handoffs/to-kiro/open/004-validate-claude-agent-configs.md.
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 17:21

## Goal
Create the actual agent config files for all 13 agents (orchestrator + 12 subagents)
in Claude Code's native format. Use your own conventions and mechanisms — the spec
defines WHAT each agent does, not HOW you implement it.

## Source of truth
`.ai/instructions/agent-catalog/principles.md` — the full spec with tools, write
scopes, shell scopes, and behavior rules for each agent.

## What to produce

1. Agent config files in `.claude/agents/` for all 13 agents:
   `orchestrator.md`, `coder.md`, `reviewer.md`, `tester.md`, `debugger.md`,
   `refactorer.md`, `doc-writer.md`, `security-auditor.md`, `ui-engineer.md`,
   `e2e-tester.md`, `infra-engineer.md`, `release-engineer.md`, `data-migrator.md`

2. Wire `"agent": "orchestrator"` in `.claude/settings.json` so orchestrator is
   the default main-thread agent.

3. Each agent must have:
   - Correct `tools:` whitelist matching the spec
   - System prompt encoding the behavior rules from the spec
   - Write/shell restrictions enforced via whatever Claude mechanism works best
     (frontmatter, permissions, prompt, hooks — your call)

4. Use Claude-native conventions:
   - Lean on built-in subagents (Explore, Plan) where they overlap
   - Use `permissions.deny` or prompt discipline for path restrictions
   - Adapt tool names to Claude's naming (`Read`, `Edit`, `Write`, `Bash`, etc.)

## Verification
- (a) All 13 `.claude/agents/*.md` files exist
- (b) Each agent's `tools:` matches the spec's tool list (adapted to Claude names)
- (c) `orchestrator` is set as default in settings.json
- (d) System prompts encode the behavior rules

## After completion
Write a handoff to `.ai/handoffs/to-kiro/open/` so kiro-cli can validate:

    004-validate-claude-agent-configs.md

Include in the handoff:
- List of all files created
- Any deviations from the spec (tool name mappings, enforcement mechanism choices)
- Any Claude-specific limitations discovered during implementation

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Implemented 13 agent configs for Claude Code per handoff 006 from kiro-cli.
    - Files: .claude/agents/*.md (13 new), .claude/settings.json (edit)
    - Decisions: <enforcement mechanisms chosen, deviations from spec>