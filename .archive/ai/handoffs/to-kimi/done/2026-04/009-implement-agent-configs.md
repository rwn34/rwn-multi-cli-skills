# Implement 13-agent configs for Kimi CLI
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 17:21

## Goal
Create the actual agent config files for all 13 agents (orchestrator + 12 subagents)
in Kimi CLI's native format. Use your own conventions and mechanisms — the spec
defines WHAT each agent does, not HOW you implement it.

## Source of truth
`.ai/instructions/agent-catalog/principles.md` — the full spec with tools, write
scopes, shell scopes, and behavior rules for each agent.

## What to produce

1. Agent config files in `.kimi/agents/` for all 13 agents:
   `orchestrator.yaml`, `coder-executor.yaml`, `reviewer.yaml`, `tester.yaml`,
   `debugger.yaml`, `refactorer.yaml`, `doc-writer.yaml`, `security-auditor.yaml`,
   `ui-engineer.yaml`, `e2e-tester.yaml`, `infra-engineer.yaml`,
   `release-engineer.yaml`, `data-migrator.yaml`

2. System prompt files for each agent (inline or separate `.md` files — your call).

3. Each agent must have:
   - Correct `allowed_tools` / `exclude_tools` matching the spec
   - System prompt encoding the behavior rules from the spec
   - Write/shell restrictions enforced via whatever Kimi mechanism works best
     (tool lists, prompt discipline, PostToolUse hooks — your call)

4. Use Kimi-native conventions:
   - Use `extend: default` inheritance where it reduces duplication
   - Use Kimi tool names (`Shell`, `ReadFile`, `WriteFile`, `StrReplaceFile`, etc.)
   - Register subagents in the orchestrator's `subagents:` block
   - Use hooks for path/command restriction where tool-level restriction isn't enough

## Verification
- (a) All 13 agent YAML files exist
- (b) Each agent's tool list matches the spec (adapted to Kimi names)
- (c) Orchestrator's `subagents:` block lists all 12 subagents
- (d) System prompts encode the behavior rules

## After completion
Write a handoff to `.ai/handoffs/to-kiro/open/` so kiro-cli can validate:

    004-validate-kimi-agent-configs.md

Include in the handoff:
- List of all files created
- Any deviations from the spec (tool name mappings, enforcement mechanism choices)
- Any Kimi-specific limitations discovered during implementation

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Implemented 13 agent configs for Kimi CLI per handoff 009 from kiro-cli.
    - Files: .kimi/agents/*.yaml (13 new), system prompt files
    - Decisions: <enforcement mechanisms chosen, deviations from spec>