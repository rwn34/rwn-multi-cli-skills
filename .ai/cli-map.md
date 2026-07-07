# CLI Concept Crosswalk

How each AI CLI's native concepts map to the shared `.ai/` framework. Versioned here so
any CLI (or a future CLI added to this project) can reconstruct the mapping without
re-deriving it from tool documentation.

## The shared mental model

All three CLIs have the same abstract structure with different names and paths:

```
EAGER layer  (loaded at session start, always in context)
    root config / agent spec
    steering / always-loaded memory
    hooks registered for lifecycle events
    tool schemas (built-in + MCP)

LAZY layer  (metadata eager, body on-demand)
    skills / resources / powers — metadata visible from start,
                                  body loaded when the model decides it's relevant
    subagents                   — listed from start, spawned by Agent tool
```

Loading order is roughly: root config → steering → skill metadata → MCP schemas →
lifecycle hooks fire → subagents spawn on demand.

## Per-CLI mapping

| Abstract concept | Claude Code | Kimi CLI | Kiro CLI |
|---|---|---|---|
| **Session-root config** | `.claude/settings.json` + `.claude/settings.local.json` | `agent.yaml` | `.kiro/agents/project.json` (project-local; extends kiro_default) |
| **Always-loaded steering** | `/CLAUDE.md` (project) + `~/.claude/CLAUDE.md` (user) | `.kimi/steering/*.md` + `AGENTS.md` | `.kiro/steering/*.md` |
| **On-demand instruction** | `.claude/skills/<name>/SKILL.md` + bundled files (trigger: `description` frontmatter match) | `.kimi/resource/*.md` (trigger: referenced by agent) **or** a Power bundle (trigger: keyword match) | Skill declared via `skill://` URI in agent config; default agent has `skill://.kiro/skills/*/SKILL.md` baked in |
| **Tool providers** | MCP servers in settings | MCP servers in agent config | MCP servers in agent config |
| **Agent isolation** | `Agent` tool with `subagent_type` | subagent tool | subagent tool |
| **Lifecycle automation** | `.claude/settings.json → hooks` (Stop, PreToolUse, UserPromptSubmit, etc.) | hooks inside a Power or in agent spec | `agentSpawn` + `stop` hooks in `.kiro/agents/project.json` (scripts in `.kiro/hooks/`) |
| **Tool schemas always visible** | built-in + MCP | built-in + MCP | built-in + MCP |

## How this project's karpathy-guidelines is shaped per CLI

| | Claude Code | Kimi CLI | Kiro CLI |
|---|---|---|---|
| Principles (4 rules) | `.claude/skills/karpathy-guidelines/SKILL.md` (triggered) | `.kimi/steering/karpathy-guidelines.md` (always) | `.kiro/steering/karpathy-guidelines.md` (always) |
| Examples (worked anti-patterns) | `.claude/skills/karpathy-guidelines/EXAMPLES.md` (alongside skill) | `.kimi/resource/karpathy-guidelines-examples.md` (on-demand) | `.kiro/skills/karpathy-guidelines/SKILL.md` (triggered — skill body; loaded via default-agent URI `skill://.kiro/skills/*/SKILL.md`) |

Why it differs per CLI: we use each CLI's most idiomatic on-demand channel. Claude's
skill body holds everything because Claude activates the whole skill at once. Kimi
splits steering (always) and resource (on-demand) because its steering is cheap and its
resource channel is clean. Kiro uses always-loaded steering for principles and
triggered skill for examples, mirroring Kimi's split but through Kiro's skill URI
mechanism instead of a separate resource folder.

## Kiro nuance: skills are config-driven, not folder-magic

Kiro does NOT auto-scan `.kiro/skills/` as a magic folder. Skills load only when an
agent config declares them via `skill://` URIs in the `resources` array.

- **Default agent (`kiro_default`)** has `skill://.kiro/skills/*/SKILL.md` baked in, so
  any SKILL.md dropped at that path loads automatically.
- **Custom agents** must declare the URI explicitly. Example:

      "resources": [
        "skill://.kiro/skills/karpathy-guidelines/SKILL.md"
      ]

This project relies on the default agent. If you switch to a custom Kiro agent,
replicate the default agent's skill URIs or declare them manually.

## Known divergences (intentional, not bugs)

- **Activity log is now hook-enforced for all three CLIs.** Claude uses
  `UserPromptSubmit` + `Stop`, Kimi uses `UserPromptSubmit` + `Stop`, Kiro uses
  `agentSpawn` + `stop`. Kiro's `stop` fires per-turn (not session-end — Kiro has no
  session-end event), so the mtime-based reminder may fire multiple times in a long
  session. This is acceptable — the reminder is non-blocking.
- **Claude loads karpathy principles lazily; Kimi and Kiro load them eagerly.** Claude
  Code's skill auto-activation is reliable enough that we can scope karpathy-guidelines
  to coding tasks only. Kimi/Kiro default-load the principles because their always-loaded
  steering is cheaper per-turn than their trigger-matching skill activation.

## Headless (one-shot) invocation per CLI

Used by `.ai/tools/dispatch-handoffs.sh` for `Auto: yes` handoffs. Flags vary
by CLI version — verify locally before relying on these:

| CLI | Headless form |
|---|---|
| Claude Code | `claude -p "<prompt>" --permission-mode acceptEdits` |
| Kimi CLI | `kimi --agent-file .kimi/agents/orchestrator.yaml -p "<prompt>"` (verify flag) |
| Kiro CLI | `kiro-cli chat --no-interactive "<prompt>"` (verify flag) |
| Crush | `crush run "<prompt>"` |

## Crush (narrow-scope 4th CLI — ADR-0002)

Crush is onboarded as a **narrow ops/release operator** (see
`docs/architecture/0002-cli-role-topology.md`), not a full framework peer. Its
mapping is deliberately minimal:

| Abstract concept | Crush |
|---|---|
| **Session-root config** | `.crush.json` (project root — MCP wiring) |
| **Always-loaded steering** | `CRUSH.md` (project root — Crush reads root context files natively) |
| **On-demand instruction** | none (context files only — no skill/resource channel) |
| **Agent isolation** | none (no subagent roster; single-agent CLI) |
| **Lifecycle automation** | none (no hook layer — boundaries are prompt-enforced via `CRUSH.md` SAFETY RULES) |
| **Activity-log identity** | `crush` |
| **Handoff inbox** | `.ai/handoffs/to-crush/open/` |

**Custodianship:** Crush cannot self-manage framework files. Claude Code
maintains `CRUSH.md` and `.crush.json` (ADR-0001 custodianship note). Crush has
no SSOT replicas — its contract is self-contained in `CRUSH.md` — so it does
not participate in `.ai/tools/check-ssot-drift.sh`.

## Adding a new CLI to this project

1. Identify the CLI's native: (a) always-loaded folder, (b) on-demand/skill channel, (c) lifecycle hooks.
2. Add a row to the mapping tables above.
3. Create a CLI contract file at its always-loaded path, following the same protocol as
   existing contracts (identify, SSOT rule, activity log read/prepend).
4. Mirror the karpathy-guidelines content per the split that fits the CLI (always vs
   on-demand).
5. Add a shim / breadcrumb if any CLI file lives outside the CLI's folder (see
   `.claude/00-ai-contract.md` for the pattern).
6. Update `.ai/sync.md` map and copy commands.
