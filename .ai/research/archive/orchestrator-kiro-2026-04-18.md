# Orchestrator / Delegation Architecture — Kiro CLI

Research doc covering Kiro CLI's subagent/delegation model, tool restriction, failure
handling, and a proposed read-only-orchestrator + write-capable-subagents setup.
**Design only — not implementation.**

## Executive summary

Kiro CLI can fully support the target architecture using native mechanisms. Key pieces:

1. **Per-agent tool whitelisting** — `tools` array in agent JSON. Missing tools are
   invisible to the LLM (schema-level enforcement).
2. **Two delegation mechanisms** — `subagent` (DAG pipeline with stages) and
   `session-management` (persistent sessions with messaging). The `subagent` tool is
   the primary mechanism for orchestrator delegation.
3. **`toolsSettings.crew`** — controls which agents can be used as pipeline stages
   (`availableAgents`) and which are auto-approved (`trustedAgents`).
4. **`summary` tool** — subagents use this to report results back to the parent.

## How Kiro's subagent model works

### Agent definition

File location: `.kiro/agents/<name>.json` (project-local) or `~/.kiro/agents/<name>.json`
(user-level). Local takes precedence over global with same name.

Structure: JSON with `name`, `description`, `tools`, `resources`, `hooks`, `mcpServers`,
`prompt`, `toolsSettings`, etc. See Agent Configuration docs for full schema.

Key fields for orchestrator pattern:
- `tools` — string array, whitelist of available tools. `"*"` means all.
- `toolsSettings.crew.availableAgents` — which agents can be spawned as pipeline stages
- `toolsSettings.crew.trustedAgents` — agents auto-approved without user confirmation
- `prompt` — system prompt (inline or `file:///path`)

### Subagent invocation (primary mechanism)

The `subagent` tool (alias: `agent_crew`) spawns a DAG pipeline of stages:

```json
{
  "task": "Add rate limiting to the API",
  "mode": "blocking",
  "stages": [
    {
      "name": "implement",
      "role": "coder",
      "prompt_template": "Implement {task}"
    }
  ]
}
```

Each stage:
- `name` — unique identifier
- `role` — must match an agent config name (e.g. `coder` → `.kiro/agents/coder.json`)
- `prompt_template` — task brief; `{task}` expands to the overall task
- `depends_on` — array of stage names that must complete first

Stages with no dependencies start in parallel. Dependent stages wait. This forms a DAG.

### Session management (lower-level, advanced)

The `session-management` tool provides persistent sessions with messaging:
- `spawn_session` — spawn a named session with a specific agent
- `send_message` / `read_messages` — inter-session messaging
- `interrupt` — redirect a running session
- `inject_context` — silently add context to a session
- `manage_group` — group sessions, broadcast messages
- `revive_session` — restart a terminated session

This is more powerful but more complex. The `subagent` tool is sufficient for the
orchestrator pattern. Session management is useful for long-running, interactive
multi-agent workflows.

**Note:** The session management tool is "not included in the default tool set for
regular agents" — it's used internally by the orchestration layer. Including it in
the orchestrator's tools list may require explicit declaration.

### How subagents report back

Subagents use the `summary` tool (automatically available to subagents, excluded from
main agent):

```json
{
  "taskDescription": "Implement rate limiting",
  "contextSummary": "Found existing middleware pattern in src/middleware/",
  "taskResult": "Added rate-limit.ts, tests pass, 3 files changed"
}
```

The main agent receives this as the stage result.

## Tool restriction — what works

| Mechanism | What it does | Scope |
|---|---|---|
| `tools` array | Hard-whitelists which tools the agent sees. Missing tools don't exist in schema. | Per-agent |
| `allowedTools` | Auto-approves listed tools (no confirmation prompt). Does NOT add tools — they must be in `tools` first. | Per-agent |
| `toolsSettings.fs_write.allowedPaths` | Restricts write tool to specific paths | Per-agent |
| `toolsSettings.fs_write.deniedPaths` | Blocks write tool from specific paths | Per-agent |
| `toolsSettings.execute_bash.allowedCommands` | Restricts shell to specific commands | Per-agent |
| `toolsSettings.execute_bash.autoAllowReadonly` | Auto-approves read-only shell commands | Per-agent |
| `toolsSettings.crew.availableAgents` | Controls which agents can be spawned as stages | Per-agent |
| `toolsSettings.crew.trustedAgents` | Auto-approves specific agents without confirmation | Per-agent |

For the orchestrator: omit `fs_write`, `execute_bash`, and any other mutation tools
from the `tools` array. The LLM literally cannot see or call them.

## Failure handling

### What happens when a subagent/stage fails

Per the `subagent` tool docs:
- Each stage runs as a persistent session
- Stages that fail surface their error in the pipeline results
- The orchestrator receives the results and decides what to do
- No automatic retry or takeover

### Recommended failure policy (encode in orchestrator prompt)

> If a subagent stage fails, do not attempt the work yourself. Analyze the error,
> then either: (1) re-invoke the pipeline with a corrected prompt, (2) report the
> failure to the user and ask for direction.

The orchestrator physically cannot take over — it has no write/shell tools.

## Proposed configs

### `.kiro/agents/orchestrator.json`

```json
{
  "name": "orchestrator",
  "description": "Read-only orchestrator. Plans, analyzes, delegates mutations to specialized agents.",
  "prompt": "file://.kiro/prompts/orchestrator.md",
  "tools": [
    "fs_read", "grep", "glob", "code", "introspect", "knowledge",
    "web_search", "web_fetch", "todo_list", "subagent"
  ],
  "allowedTools": ["fs_read", "grep", "glob", "code", "introspect", "knowledge"],
  "toolsSettings": {
    "crew": {
      "availableAgents": ["coder", "reviewer"],
      "trustedAgents": ["reviewer"]
    }
  },
  "resources": [
    "file://AGENTS.md",
    "file://README.md",
    "file://.kiro/steering/**/*.md",
    "skill://.kiro/skills/*/SKILL.md"
  ],
  "hooks": {
    "agentSpawn": [
      {
        "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" .kiro/hooks/activity-log-inject.sh"
      }
    ],
    "stop": [
      {
        "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" .kiro/hooks/activity-log-remind.sh"
      }
    ]
  },
  "keyboardShortcut": "ctrl+shift+o",
  "welcomeMessage": "Orchestrator mode. I can read, search, plan, and delegate. What do you need?"
}
```

### `.kiro/agents/coder.json`

```json
{
  "name": "coder",
  "description": "Writes code, runs commands, executes tests. Spawned by orchestrator for mutation tasks.",
  "prompt": "file://.kiro/prompts/coder.md",
  "tools": [
    "fs_read", "fs_write", "execute_bash", "grep", "glob", "code"
  ],
  "allowedTools": ["fs_read", "grep", "glob", "code"],
  "toolsSettings": {
    "execute_bash": {
      "autoAllowReadonly": true
    }
  },
  "resources": [
    "file://.kiro/steering/karpathy-guidelines.md",
    "skill://.kiro/skills/*/SKILL.md"
  ]
}
```

### `.kiro/agents/reviewer.json`

```json
{
  "name": "reviewer",
  "description": "Read-only code review. Correctness, style, security, test coverage. No writes.",
  "prompt": "file://.kiro/prompts/reviewer.md",
  "tools": [
    "fs_read", "grep", "glob", "code", "introspect"
  ],
  "allowedTools": ["fs_read", "grep", "glob", "code", "introspect"],
  "resources": [
    "file://.kiro/steering/karpathy-guidelines.md",
    "skill://.kiro/skills/*/SKILL.md"
  ]
}
```

### Orchestrator system prompt (`.kiro/prompts/orchestrator.md`)

```markdown
You are the orchestrator for this project. Your job:

1. Understand the user's request — ask clarifying questions before assuming scope.
2. Gather context via read/grep/glob — build a grounded mental model.
3. Plan the work. For non-trivial tasks, break into steps with verification criteria.
4. Delegate mutations to subagents via the subagent tool:
   - `coder` — for file edits, shell commands, test runs
   - `reviewer` — for read-only code review
   - If no existing agent fits: describe what's needed (tools, purpose, skills),
     ask the user to approve creating one. Do NOT attempt the work yourself.
5. After a subagent returns, read the touched files to verify the work landed.
   If something is off, report to the user — do not patch directly.
6. If a subagent fails, report the failure and cause. Do not retry silently.

You do NOT have fs_write, execute_bash, or any mutation tools. Attempting to mutate
state yourself is a bug — always delegate.
```

## Proposed workflow

1. User: "add rate limiting to the API"
2. Orchestrator reads API code, finds middleware patterns, drafts a plan
3. Orchestrator presents plan to user, asks for approval
4. User approves
5. Orchestrator invokes subagent pipeline:
   ```json
   {
     "task": "Add rate limiting middleware to the API",
     "stages": [
       {"name": "implement", "role": "coder", "prompt_template": "<detailed brief>"},
       {"name": "review", "role": "reviewer", "prompt_template": "Review the rate limiting implementation", "depends_on": ["implement"]}
     ]
   }
   ```
6. Coder writes code, runs tests → summary returned
7. Reviewer reads changed files → summary returned
8. Orchestrator reads both summaries + verifies files, reports to user

## Known limitations

1. **No agent inheritance.** Each agent JSON is standalone. Shared config (resources,
   hooks) must be duplicated across agents. Unlike Kimi's `extend:` mechanism.

2. **No dynamic agent creation at runtime.** If the orchestrator recommends a new
   agent, the user must create the JSON file and restart the session.

3. **Session restart required for agent changes.** New/modified agent JSONs are
   discovered at session start, not hot-reloaded.

4. **Subagent nesting not documented.** The docs don't explicitly state whether a
   coder subagent can spawn its own sub-subagents. Based on the `summary` tool being
   "only available to subagents" and the session-management tool being "not included
   in the default tool set," nesting is likely restricted. Needs testing.

5. **No granular shell policy.** `execute_bash.allowedCommands` restricts to specific
   commands, but there's no "read-only shell" mode. The coder either has shell or
   doesn't.

6. **`subagent` tool uses DAG model.** Single-stage delegation works but requires the
   pipeline wrapper (`stages` array with one entry). There's no simple
   `spawn("coder", "do this")` shorthand.

7. **Skill scoping across agents.** Each agent declares its own `resources` array.
   Skills loaded by the orchestrator are NOT automatically visible to subagents.
   Each agent must declare the skills it needs.

## Comparison to Claude and Kimi

| Axis | Kiro CLI | Claude Code | Kimi CLI |
|---|---|---|---|
| Config format | JSON (`.kiro/agents/`) | Markdown + YAML (`.claude/agents/`) | YAML (`agent.yaml`) |
| Main-agent selector | `--agent` flag or `chat.defaultAgent` | `settings.json → "agent"` | `--agent-file` flag |
| Subagent tool | `subagent` (DAG pipeline) | `Agent` (single invocation) | `Agent` (single invocation) |
| Pipeline/DAG support | ✅ Native (stages + depends_on) | ❌ Manual chaining | ❌ Manual chaining |
| Tool restriction | `tools` array (schema-level) | `tools:` frontmatter (schema-level) | `tools`/`allowed_tools`/`exclude_tools` |
| Agent inheritance | ❌ | ❌ | ✅ (`extend:`) |
| Crew config | `toolsSettings.crew` | Not documented | Not applicable |
| Session management | ✅ (advanced, separate tool) | Not documented | Background mode only |

**Kiro's unique advantage:** Native DAG pipeline support. The orchestrator can define
multi-stage workflows with dependencies in a single invocation. Claude and Kimi must
chain individual subagent calls manually.

**Kiro's disadvantage vs Kimi:** No agent inheritance. Config duplication across agents.

## Confidence notes

- **High confidence:** Agent config format, `tools` array enforcement, `subagent` tool
  parameters, `summary` tool, `toolsSettings.crew` — all from official Kiro docs.
- **Medium confidence:** Failure handling specifics. The docs describe the pipeline
  model but don't detail exact error propagation. Needs testing.
- **Lower confidence:** Subagent nesting behavior. Not explicitly documented as
  allowed or prohibited. Needs testing.
- **Not tested:** Whether `session-management` tool can be explicitly added to an
  agent's tools list for advanced orchestration patterns.

No aspirational features in this doc — everything proposed uses documented Kiro mechanisms.