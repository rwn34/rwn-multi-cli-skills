# Kimi CLI Agents

Agent configuration for Kimi CLI in this project. Uses Kimi-native `extend:`
inheritance and YAML configs.

## Quick start

Launch the orchestrator from project root:

```bash
kimi --agent-file .kimi/agents/orchestrator.yaml
```

The orchestrator is read-only. It plans and delegates to subagents for all
project-level mutations.

## Architecture

```
.kimi/agents/
├── orchestrator.yaml          # Root agent — read-only, delegates everything
├── coder-executor.yaml        # Writes code, runs tests
├── reviewer.yaml              # Read-only code review
├── tester.yaml                # Test execution and coverage
├── debugger.yaml              # Bug diagnosis, small fixes
├── refactorer.yaml            # Structural changes
├── doc-writer.yaml            # Documentation
├── security-auditor.yaml      # Security scans
├── ui-engineer.yaml           # UI/UX components
├── e2e-tester.yaml            # End-to-end tests
├── infra-engineer.yaml        # CI/CD, Docker, git ops
├── release-engineer.yaml      # Version bumps, tags
├── data-migrator.yaml         # Database migrations
└── system/
    ├── orchestrator.md        # System prompts (one per agent)
    ├── coder-executor.md
    └── ...
```

## The `extend:` mechanism

Kimi agents can inherit from other agents via `extend:`:

```yaml
agent:
  extend: default        # Inherit all default tools + behavior
  name: my-agent
  system_prompt_path: ./system/my-agent.md
```

Or extend a custom parent:

```yaml
agent:
  extend: ./base-executor.yaml   # Inherit from a project-local base
  name: specialized-agent
```

**Merging rules:**
- `tools` / `allowed_tools` / `exclude_tools` are **overwritten**, not merged.
- `system_prompt_path` is overwritten.
- `subagents` are overwritten.

This means if a child wants to add one tool to the parent's list, it must list
all of them. Use `exclude_tools` to remove specific ones instead.

## Adding a new agent

1. Create `your-agent.yaml`:

   ```yaml
   version: 1
   agent:
     extend: default
     name: your-agent
     system_prompt_path: ./system/your-agent.md
     allowed_tools:
       - "kimi_cli.tools.shell:Shell"
       - "kimi_cli.tools.file:ReadFile"
       - "kimi_cli.tools.file:WriteFile"
       # ... list all tools this agent needs
   ```

2. Create `system/your-agent.md` with the system prompt.

3. Register the agent in `orchestrator.yaml` under `subagents:`:

   ```yaml
   subagents:
     your-agent:
       path: ./your-agent.yaml
       description: "What this agent does and when to use it."
   ```

4. **Restart Kimi** with `kimi --agent-file .kimi/agents/orchestrator.yaml`.
   Agent configs are loaded once at session start; mid-session changes are not
   picked up.

## Tool restriction

Kimi enforces tool access via three fields:

| Field | Behavior |
|-------|----------|
| `allowed_tools` | Explicit allowlist — only these tools are loaded |
| `exclude_tools` | Remove specific tools from the effective list |
| `tools` | Full explicit list (legacy; `allowed_tools` is preferred) |

**Example:** A read-only reviewer gets no `WriteFile` or `Shell`:

```yaml
agent:
  extend: default
  allowed_tools:
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:Glob"
    - "kimi_cli.tools.file:Grep"
  exclude_tools:
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:WriteFile"
    - "kimi_cli.tools.file:StrReplaceFile"
```

The LLM literally never sees the blocked tool schemas — this is hard enforcement,
not prompt-based.

## System prompts

All system prompts live in `system/*.md`. They are **external file references**
(via `system_prompt_path`), not inline in the YAML. This keeps configs readable
and enables markdown editing in any editor.

Each system prompt should include:
- Agent identity and purpose
- Scope (what paths/tools are allowed)
- Rules (behavioral constraints)
- Docs resource section (what `docs/` files to read for context)

See `system/orchestrator.md` for the canonical example.

## Nesting restriction

**Subagents cannot spawn other subagents.** The `Agent` tool checks
`role != "root"` and returns an error if a subagent tries to call it. The
orchestrator must sequence subagents directly.

## Restart requirement

Any change to `.kimi/agents/*.yaml`, `~/.kimi/config.toml`, or hook scripts
requires a **fresh Kimi session** to take effect. Steering files
(`.kimi/steering/*.md`) are read dynamically and do not require restart.
