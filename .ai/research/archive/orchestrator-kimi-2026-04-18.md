# Orchestrator/Delegation Architecture Research — Kimi CLI

**Scope:** Research-only design doc for how Kimi CLI can implement a read-only orchestrator that delegates mutations to specialized subagents.

---

## 1. Kimi CLI's Subagent/Delegation Model

### How subagents work

Kimi CLI spawns subagents via the built-in **`Agent`** tool (`kimi_cli.tools.agent:Agent`). Key mechanics:

- **Invocation:** The root agent calls `Agent(description, prompt, subagent_type="coder")`. The `subagent_type` must match a name registered in the `LaborMarket`.
- **Registration:** Subagent types are registered automatically when the root agent loads its spec. Any entry under `subagents:` in the root `agent.yaml` becomes a registerable type. Each entry points to a child `agent.yaml` file.
- **Inheritance:** Child agents can `extend: default` (built-in) or `extend: ./another-agent.yaml` (custom). Merging is field-by-field; `tools` and `subagents` are overwritten, not merged.
- **Runtime isolation:** Each subagent gets its own `KimiSoul`, its own conversation context (persisted to disk under the session directory), and its own `DenwaRenji`. The parent only sees the final text summary returned by the subagent.
- **Nesting restriction:** **Subagents cannot spawn other subagents.** The `Agent` tool checks `self._runtime.role != "root"` and returns `ToolError` if a subagent tries to call it.

### Subagent lifecycle

1. Root agent calls `Agent` → `ForegroundSubagentRunner.run()`
2. Runner builds the subagent from its `AgentTypeDefinition` (loaded from the child YAML)
3. `prepare_soul()` restores context, loads system prompt, writes prompt snapshot
4. `run_with_summary_continuation()` executes the soul turn
5. On success: runner returns `ToolOk` with `agent_id`, `status: completed`, and `[summary]` block
6. On failure: runner returns `ToolError` with a message and brief code (e.g., `Max steps reached`, `Agent run error`)

Background mode (`run_in_background=true`) is also supported; it returns a `task_id` and the parent must later call `TaskOutput` to retrieve the result.

---

## 2. Tool Restriction Strategy

### Agent-level tool lists

Kimi restricts tools **per agent spec** via three fields:

| Field | Behavior |
|-------|----------|
| `tools` | Full explicit list of tools this agent may use |
| `allowed_tools` | Shorthand alias; if set, it overrides `tools` during `load_agent()` |
| `exclude_tools` | Remove specific tools from the effective list |

From `soul/agent.py`:

```python
tools = agent_spec.allowed_tools if agent_spec.allowed_tools is not None else agent_spec.tools
if agent_spec.exclude_tools:
    tools = [tool for tool in tools if tool not in agent_spec.exclude_tools]
toolset.load_tools(tools, tool_deps)
```

### What this means for the orchestrator pattern

**Orchestrator (read-only)** — Give it only read/search/plan tools + the `Agent` tool:

```yaml
tools:
  - "kimi_cli.tools.agent:Agent"
  - "kimi_cli.tools.file:ReadFile"
  - "kimi_cli.tools.file:Glob"
  - "kimi_cli.tools.file:Grep"
  - "kimi_cli.tools.web:SearchWeb"
  - "kimi_cli.tools.web:FetchURL"
  - "kimi_cli.tools.plan.enter:EnterPlanMode"
  - "kimi_cli.tools.plan:ExitPlanMode"
  - "kimi_cli.tools.ask_user:AskUserQuestion"
  - "kimi_cli.tools.todo:SetTodoList"
```

**Executor subagent (write-capable)** — Give it `Shell`, `WriteFile`, `StrReplaceFile`, etc.:

```yaml
agent:
  extend: default
  allowed_tools:
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:WriteFile"
    - "kimi_cli.tools.file:StrReplaceFile"
    - "kimi_cli.tools.file:Glob"
    - "kimi_cli.tools.file:Grep"
    - "kimi_cli.tools.web:SearchWeb"
    - "kimi_cli.tools.web:FetchURL"
  exclude_tools:
    - "kimi_cli.tools.agent:Agent"
```

### Enforcement guarantees

- **Hard enforcement:** The orchestrator literally cannot call `WriteFile` or `Shell` because those tool classes are not loaded into its `KimiToolset`. The LLM does not see their schemas.
- **No capability leakage:** Subagents run in isolated souls; even if they share the same `Runtime` copy, their toolset is built independently from their own agent spec.

---

## 3. Proposed Agent Configs

### Option A: Project-local `agent.yaml` (recommended)

Place an `orchestrator.yaml` at project root (or under `.kimi/agents/`) and launch Kimi with:

```bash
kimi --agent-file ./orchestrator.yaml
```

**`orchestrator.yaml`**

```yaml
version: 1
agent:
  name: orchestrator
  system_prompt_path: ./orchestrator-system.md
  tools:
    - "kimi_cli.tools.agent:Agent"
    - "kimi_cli.tools.ask_user:AskUserQuestion"
    - "kimi_cli.tools.todo:SetTodoList"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:ReadMediaFile"
    - "kimi_cli.tools.file:Glob"
    - "kimi_cli.tools.file:Grep"
    - "kimi_cli.tools.web:SearchWeb"
    - "kimi_cli.tools.web:FetchURL"
    - "kimi_cli.tools.plan.enter:EnterPlanMode"
    - "kimi_cli.tools.plan:ExitPlanMode"
  subagents:
    coder:
      path: ./coder-executor.yaml
      description: "General software engineering: read/write files, run commands, return summary."
    explore:
      path: ./explore-executor.yaml
      description: "Fast read-only codebase exploration."
    plan:
      path: ./plan-executor.yaml
      description: "Implementation planning and architecture design."
```

**`coder-executor.yaml`**

```yaml
version: 1
agent:
  extend: default
  name: coder-executor
  system_prompt_path: ./coder-executor-system.md
  allowed_tools:
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:ReadMediaFile"
    - "kimi_cli.tools.file:Glob"
    - "kimi_cli.tools.file:Grep"
    - "kimi_cli.tools.file:WriteFile"
    - "kimi_cli.tools.file:StrReplaceFile"
    - "kimi_cli.tools.web:SearchWeb"
    - "kimi_cli.tools.web:FetchURL"
  exclude_tools:
    - "kimi_cli.tools.agent:Agent"
    - "kimi_cli.tools.ask_user:AskUserQuestion"
    - "kimi_cli.tools.todo:SetTodoList"
    - "kimi_cli.tools.plan.enter:EnterPlanMode"
    - "kimi_cli.tools.plan:ExitPlanMode"
  subagents:
```

**`explore-executor.yaml`** and **`plan-executor.yaml`** — Same pattern, scoped to their respective tool sets (explore read-only, plan no-shell/no-write).

### Option B: Global config override (less portable)

Add a custom agent definition to `~/.kimi/config.toml` is **not supported**. Kimi does not store agent YAMLs inside `config.toml`; it only references them via `--agent-file`. Therefore, project-local YAMLs are the correct mechanism.

---

## 4. Failure Handling Behavior

### What happens when a subagent fails

Kimi's `ForegroundSubagentRunner` catches failures in `run_soul_checked` and returns a `SoulRunFailure` object, which is converted to a `ToolError` returned to the root agent:

- `MaxStepsReached` → `ToolError(message="Max steps ... reached", brief="Max steps reached")`
- `ChatProviderError` / `APIStatusError` → `ToolError(message="LLM provider error ...", brief="LLM provider error")`
- Generic `Exception` → `ToolError(message="Unexpected error ...", brief="Agent run error")`
- Empty output → `ToolError(message="Agent completed but produced no output.", brief="Empty agent output")`

**Critical behavior:** The orchestrator receives this as a **normal tool result with `is_error=True`**. It does **not** automatically retry, escalate, or cause the main agent to take over. The orchestrator must explicitly decide what to do next (retry, try a different subagent, report to user, etc.).

### Background subagents

If `run_in_background=true`, the `Agent` tool returns immediately with a task ID. Failures are stored in the `BackgroundTaskManager` and surfaced later when the parent calls `TaskOutput`. The orchestrator must poll or wait for the notification.

### Recommended failure-handling policy for the orchestrator

Encode this in the orchestrator's system prompt:

> If a subagent returns an error, do not attempt to fix the issue yourself by using write/shell tools. Instead, analyze the error and decide: (1) retry the same subagent with a clarified prompt, (2) delegate to a different subagent type, or (3) report the failure to the user and ask for direction.

---

## 5. Known Limitations

### Limitations that exist today

1. **No dynamic subagent creation at runtime.**
   - The `LaborMarket` is populated once when the root agent loads. If a task doesn't fit existing subagents, the orchestrator cannot create a new subagent type on the fly. It can only recommend that the user create a new YAML and restart the session.

2. **Subagent descriptions are static.**
   - The `Agent` tool renders subagent types from the `LaborMarket` using the `description` and `when_to_use` fields baked into the YAML. The orchestrator cannot pass runtime context to mutate these descriptions.

3. **No granular tool policy beyond allow/exclude lists.**
   - Kimi does not support "policy rules" like "Shell is allowed but only read-only commands." The `explore` subagent relies on system-prompt instructions (`NEVER use Shell for file creation...`) rather than hard enforcement.

4. **Subagents cannot nest.**
   - A `coder` subagent cannot spawn its own `explore` subagent. If a coding task needs exploration, the orchestrator must do the exploration itself or spawn an `explore` subagent first, then pass the findings to `coder`.

5. **Session restart required to pick up new agent files.**
   - If the orchestrator recommends creating a new subagent YAML, the file won't be loaded until a new Kimi session starts with `--agent-file` pointing to the updated orchestrator.

6. **MCP servers are loaded for all agents in a runtime.**
   - MCP tools are loaded into the root runtime and, while each agent builds its own `KimiToolset`, MCP config is propagated through the shared `Runtime`. In practice this is fine, but there's no per-subagent MCP exclusion today.

### What's NOT a limitation

- **Read-only orchestrator + write-capable subagents is fully achievable.** Kimi's `tools`/`allowed_tools`/`exclude_tools` arrays provide hard enforcement.
- **Failure isolation works.** Subagent crashes do not crash the orchestrator.

---

## 6. Comparison to Kiro's Model

| Dimension | Kimi CLI | Kiro CLI |
|-----------|----------|----------|
| **Config format** | `agent.yaml` (YAML, supports `extend`) | `.kiro/agents/project.json` (JSON, no inheritance) |
| **Subagent registry** | `subagents:` block in root `agent.yaml` | Declared inline in agent JSON under `subagents` or referenced |
| **Tool restriction** | `tools` / `allowed_tools` / `exclude_tools` arrays | `tools` array (string list, `"*"` means all) |
| **Invocation** | `Agent` tool with `subagent_type` string | `subagent` tool with agent name |
| **Nesting** | Prohibited (root-only `Agent` tool) | Prohibited (similar guard) |
| **Inheritance** | Yes — `extend: default` or `extend: ./file.yaml` | No — each agent config is standalone |
| **Dynamic creation** | Not possible without session restart | Not possible without editing agent JSON |
| **Failure return** | `ToolError` returned to parent | Error object returned to parent |

**Key difference:** Kimi's `extend` mechanism makes it easier to maintain an orchestrator family. You can define a base executor that extends `default`, then create specialized variants with small tool-list deltas. Kiro requires duplicating the full agent JSON for each variant.

**Key similarity:** Both enforce the orchestrator pattern through **absence of tools** rather than runtime policy checks. If the orchestrator spec omits `WriteFile`, the LLM simply never sees it.

---

## 7. Recommended Next Steps

1. **Create `orchestrator.yaml` + `coder-executor.yaml` + `explore-executor.yaml` + `plan-executor.yaml`** in `.kimi/agents/` (or project root).
2. **Write matching system prompts** that encode the delegation rules (orchestrator must never write; subagent must summarize; failure handling policy).
3. **Test in a fresh Kimi session** with `kimi --agent-file .kimi/agents/orchestrator.yaml`:
   - Verify the orchestrator cannot see `WriteFile` / `Shell`
   - Verify the `coder` subagent can write files
   - Verify subagent failures return as `ToolError` to the orchestrator
4. **Decide on background vs foreground** for long-running tasks. Kimi supports both; the orchestrator should default to foreground unless the user explicitly requests background.
5. **Document the launch command** in `.ai/cli-map.md` or `AGENTS.md` so other CLIs know how Kimi's orchestrator is started.

---

## 8. Honest Feasibility Assessment

**How close can Kimi CLI get to the target architecture?**

- **~95% achievable today.**
  - Read-only orchestrator: ✅ hard-enforced via tool lists
  - Write-capable subagents: ✅ standard built-in behavior
  - Delegation via `Agent` tool: ✅ native feature
  - Failure isolation: ✅ works out of the box
  - No takeover on failure: ✅ the orchestrator receives an error and must decide

- **The remaining ~5%** is dynamic subagent creation and runtime tool policy refinement. These require session restarts and static YAML edits, which is acceptable for a project-level convention but not as fluid as a fully runtime-adaptive system.
