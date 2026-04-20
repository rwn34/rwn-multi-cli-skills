# Research orchestrator/delegation architecture for Claude Code
Status: DONE
Completed: 2026-04-17 16:05 — claude-code
Output: .ai/research/orchestrator-claude.md
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 15:50

## Goal
Research and document how Claude Code can implement an orchestrator/delegation
architecture where the main agent is read-only (consults, plans, analyzes) and
delegates all mutations (file writes, shell commands) to specialized subagents.
Produce a concrete design doc — not implementation yet.

## Background — the architecture we're designing

Across all three CLIs, we want the same pattern:

```
Orchestrator (default agent)
  Can: read, search, analyze, plan
  Cannot: write files, run shell
  Delegates via: subagent tool
  If no agent fits: suggests creating a new one

Spawns:
  coder    — write, shell, code
  reviewer — read-only, code
  (future agents as needed)
```

Key rules:
1. Orchestrator never writes or runs commands — only reads, plans, delegates
2. Each subagent has specific tools, skills, and optionally MCP servers
3. If no existing subagent can handle a task, orchestrator recommends creating one
   (describes tools, skills, purpose) and waits for user approval
4. Subagent failure does NOT cause orchestrator to take over — it reports the failure

## What we need from Claude Code

1. **Research Claude's `Agent` tool / `subagent_type`** — how does Claude Code spawn
   subagents? What's the config format? Can the main agent be restricted to read-only
   tools while subagents have write access? Document:
   - How to define subagent types in Claude's config
   - How the main agent invokes them
   - What happens when a subagent fails (does the main agent retry? take over? report?)
   - Can subagents have different tool sets than the main agent?

2. **Research Claude's tool restriction model** — can you restrict the main agent to
   specific tools (e.g. read, grep, glob, code, Agent) while giving subagents broader
   tools? Or does Claude Code use a different mechanism (e.g. `allowedTools`)?

3. **Assess feasibility** — given Claude Code's current capabilities, how close can we
   get to the architecture above? Document:
   - What works out of the box
   - What requires workarounds
   - What's not possible today (limitations)

4. **Produce a design doc** — write `.ai/research/orchestrator-claude.md` with:
   - Claude Code's subagent/delegation model (how it works)
   - Proposed agent configs (orchestrator + at least one executor)
   - Tool restriction strategy
   - Failure handling behavior
   - Known limitations
   - Comparison to Kiro's model (reference `.ai/cli-map.md` for Kiro's approach)

## Context (reference only, not binding)
Kiro's model: agents are JSON files in `.kiro/agents/`. The `subagent` tool spawns
them by name. Tools are restricted per-agent via the `tools` array. Kiro has no
agent inheritance — each agent config is standalone. The orchestrator would be a
project-local agent with read-only tools + `subagent`. See `.kiro/agents/project.json`
for the current (non-orchestrator) config.

## Steps
1. Research Claude Code's Agent tool, subagent types, and tool restriction model.
2. Test whether a Claude agent can be restricted to read-only tools while spawning
   subagents with write tools (if testable in this project).
3. Write `.ai/research/orchestrator-claude.md` with findings and proposed design.
4. Prepend activity log entry.

## Verification
- (a) `.ai/research/orchestrator-claude.md` exists and covers: subagent model,
  tool restriction, failure handling, limitations, proposed config shapes.
- (b) The doc is honest about what Claude Code can and can't do — no aspirational
  features presented as current capabilities.

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Researched orchestrator/delegation architecture for Claude Code per handoff 001 from kiro-cli. Wrote .ai/research/orchestrator-claude.md.
    - Files: .ai/research/orchestrator-claude.md (new)
    - Decisions: <key findings — what works, what doesn't>

## Report back with
- (a) Path to the design doc
- (b) Summary: can Claude Code do read-only orchestrator + write-capable subagents?
- (c) Key limitations discovered
- (d) Recommended next steps

## When complete
Kiro-cli validates by reading `.ai/research/orchestrator-claude.md`. On success,
move this file to `.ai/handoffs/to-claude/done/`.