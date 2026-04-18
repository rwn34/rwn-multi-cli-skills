# Orchestrator Pattern

Architectural rules for multi-agent delegation in this project. All three CLIs
(Claude Code, Kimi CLI, Kiro CLI) follow the same pattern, adapted to each CLI's
native agent config format.

**Companion doc:** `.ai/instructions/agent-catalog/principles.md` holds the
authoritative subagent roster (13 agents with tools, write scope, shell scope).
This file covers the *pattern*; the catalog covers the *roster*.

## The rule

The default agent is a **read-only orchestrator**. It can read, search, analyze,
plan, and delegate — but it cannot modify project source code or run arbitrary
commands. All project-level mutations are delegated to specialized subagents.

The orchestrator **can** write to framework paths: `.ai/`, `.kiro/`, `.kimi/`,
`.claude/`. This lets it manage handoffs, activity log entries, research docs, and
CLI config without needing to delegate trivial framework housekeeping.

**Per-CLI nuance:** while the SSOT permits orchestrator writes to all four
framework dirs, each CLI's implementation narrows this to its own dir + the
shared `.ai/`. Cross-CLI writes (e.g., Claude editing `.kimi/`) always go
through the handoff queue — never direct. This preserves per-CLI ownership
of native config so each CLI manages its own conventions.

## Agent roles

### Orchestrator (default agent)

**Purpose:** Consult, plan, analyze, delegate.

> **`.ai/` is a direct write path for orchestrators — no delegation.** Handoffs,
> activity-log entries, research docs, reports, and SSOT instruction edits are
> all the orchestrator's direct responsibility. This rule is the same across
> all three CLIs: Claude Code, Kimi CLI, Kiro CLI.

**Tools (read + delegate + limited write):**
- Read: `fs_read`, `grep`, `glob`, `code`, `introspect`, `knowledge`
- Web: `web_search`, `web_fetch`
- Planning: `todo_list`
- Delegation: `subagent` (Kiro) / `Agent` (Claude, Kimi)
- Write: `fs_write` — restricted to `.ai/**`, `.kiro/**`, `.kimi/**`, `.claude/**`

**Cannot do:**
- Write to project source files (src/, tests/, configs outside `.ai/` etc.)
- Run shell commands (`execute_bash`)
- Directly modify any file outside the four framework directories

**Behavior rules:**
1. Understand the request — ask clarifying questions before assuming scope.
2. Gather context via read/search tools.
3. Plan the work. For non-trivial tasks, break into steps with verification criteria.
4. Delegate mutations to the appropriate subagent.
5. After a subagent returns, read the touched files to verify the work landed.
6. If a subagent fails, report the failure. Do not retry silently. Do not attempt
   the work yourself.
7. If no existing subagent fits the task, describe what's needed (tools, skills,
   purpose) and ask the user to approve creating a new agent.

### Subagents

Twelve specialized subagents handle all project mutations — `coder`, `reviewer`,
`tester`, `debugger`, `refactorer`, `doc-writer`, `security-auditor`,
`ui-engineer`, `e2e-tester`, `infra-engineer`, `release-engineer`,
`data-migrator`. See `.ai/instructions/agent-catalog/principles.md` for each
agent's tools, write scope, shell scope, and behavior rules.

Subagents fall into three classes:

- **Executor** — writes files and runs commands within its declared scope
  (`coder`, `tester`, `debugger`, `refactorer`, `doc-writer`, `ui-engineer`,
  `infra-engineer`, `release-engineer`, `data-migrator`).
- **Diagnoser** — primarily read-only; may write structured reports to
  `.ai/reports/<agent>-<YYYY-MM-DD>-<slug>.md` (`reviewer`, `security-auditor`,
  `e2e-tester`).
- **Default** — the orchestrator itself (see above).

## Write-path restriction

Three tiers — no agent has blanket write-everywhere access:

| Tier | Paths | Who writes |
|---|---|---|
| **Framework (CLI config + SSOT)** | `.ai/**`, `.kiro/**`, `.kimi/**`, `.claude/**` | Orchestrator only |
| **Reports** | `.ai/reports/**` | Diagnosers (`reviewer`, `security-auditor`, `e2e-tester`) + orchestrator |
| **Project source** | Everything else (`src/**`, `tests/**`, `docs/**`, `infra/**`, `migrations/**`, etc.) | Scoped executors per the catalog |

Each executor's scope is explicitly bounded — e.g., `infra-engineer` writes only
`infra/**` + CI dirs; `data-migrator` only `migrations/**` + `seeds/**`;
`doc-writer` only `*.md` + `docs/**` + `CHANGELOG*`. See the catalog for exact
scopes.

Each CLI enforces this via its native mechanism:
- **Kiro:** `toolsSettings.fs_write.allowedPaths` / `deniedPaths` (hard)
- **Claude:** `tools:` frontmatter + `permissions.deny` in settings (mixed hard/soft)
- **Kimi:** `allowed_tools` + system prompt + PostToolUse hook (soft — Kimi lacks native path restriction)

## Failure handling

All three CLIs follow the same policy:

1. Subagent failure returns an error/summary to the orchestrator.
2. The orchestrator **does not** take over the failed work.
3. The orchestrator analyzes the error and either:
   - Re-invokes the subagent with a corrected brief
   - Tries a different subagent
   - Reports the failure to the user and asks for direction
4. The orchestrator cannot silently retry — each retry is visible to the user.

## Delegation flow

```
User request
    │
    ▼
Orchestrator reads/analyzes/plans
    │
    ├─ Simple read/answer → responds directly
    │
    ├─ Framework file edit (.ai/, .kiro/, etc.) → writes directly
    │
    └─ Project mutation needed → picks subagent from the catalog:
        │
        ▼
    subagent(coder | reviewer | tester | debugger | refactorer |
             doc-writer | security-auditor | ui-engineer |
             e2e-tester | infra-engineer | release-engineer |
             data-migrator)
        │
        ▼
    Subagent executes within its declared scope, returns summary
        │
        ▼
    Orchestrator verifies (reads changed files)
        │
        ▼
    Reports result to user
```

## Per-CLI implementation notes

Each CLI implements the 13-agent catalog in its native format. See each CLI's
`agents/` folder for the full set.

### Kiro CLI
- Agent configs: `.kiro/agents/*.json` (13 files)
- Delegation tool: `subagent` (DAG pipeline with stages)
- Write restriction: `toolsSettings.fs_write.allowedPaths` (hard)
- Unique advantage: native DAG pipeline (multi-stage with `depends_on`)
- Set default: `kiro-cli settings chat.defaultAgent orchestrator`

### Claude Code
- Agent configs: `.claude/agents/*.md` (13 files)
- Delegation tool: `Agent` with `subagent_type`
- Write restriction: `tools:` frontmatter whitelist + `permissions` in settings
- Main-thread agent: `.claude/settings.json → "agent": "orchestrator"`
- Unique advantage: built-in subagent types (Explore, Plan)

### Kimi CLI
- Agent configs: `.kimi/agents/*.yaml` (13 files; note `coder-executor` naming
  for the coder role)
- Delegation tool: `Agent` with `subagent_type`
- Write restriction: `allowed_tools` + system prompt + PostToolUse hook
- Launch: `kimi --agent-file .kimi/agents/orchestrator.yaml`
- Unique advantage: `extend:` inheritance between agents

## What this spec does NOT cover

- Specific system prompt wording (each CLI adapts to its conventions)
- MCP server configuration (project-specific, not architectural)
- Skill/resource loading per agent (each CLI declares its own)
- The full subagent roster — see `.ai/instructions/agent-catalog/principles.md`

---

**This pattern is working if:** the orchestrator never writes project source
files, subagent failures are reported (not silently retried), every agent stays
within its declared write scope, and new agent types are proposed (not assumed).
