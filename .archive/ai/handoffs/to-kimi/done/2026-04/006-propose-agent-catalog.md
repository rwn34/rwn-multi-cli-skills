# Propose 10 specialized subagents for the orchestrator pattern
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 16:40

## Goal
Propose 10 specialized subagents (beyond the orchestrator) for the multi-CLI
project. Each agent should have a clear purpose, tool allowlist, tool restrictions,
and trigger description (when the orchestrator should spawn it).

The user is asking all three CLIs to propose independently, then we converge.

## Context
- The orchestrator pattern is defined in `.ai/instructions/orchestrator-pattern/principles.md`
- Kiro has proposed its 10 in chat (not yet written to a file)
- The user wants to compare all three proposals and merge

## What to produce
Write `.ai/research/agent-catalog-kimi.md` with a table of 10 agents:

For each agent:
1. Name (kebab-case, e.g. `coder`, `reviewer`)
2. One-line purpose
3. Tools allowed (specific tool names for Kimi CLI)
4. Tools denied / restrictions (path restrictions, command restrictions)
5. When the orchestrator spawns it (trigger description)

Also include:
- Your rationale for the selection
- Any agents you think are essential vs nice-to-have
- Whether you'd recommend starting with all 10 or a smaller core set

## Verification
- (a) `.ai/research/agent-catalog-kimi.md` exists with 10 agents
- (b) Each agent has all 5 fields filled in

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Proposed 10 specialized subagents per handoff from kiro-cli.
    - Files: .ai/research/agent-catalog-kimi.md (new)
    - Decisions: <which agents, core vs nice-to-have split>

## When complete
User reviews all three proposals and we converge.