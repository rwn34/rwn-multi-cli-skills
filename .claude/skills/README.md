# `.claude/skills/`

Claude Code skills installed for this project. Each skill is a directory with at minimum a `SKILL.md` file (YAML frontmatter: `name`, `description`; then a markdown body). Claude loads the metadata at session start; the body loads only when the skill's `description` matches an active task.

## Current skills

| Skill | What it does | SSOT |
|---|---|---|
| `karpathy-guidelines/` | Behavioural coding rules — think-first, surgical changes, simplicity, goal-driven. Auto-activates on coding tasks. | `.ai/instructions/karpathy-guidelines/principles.md` + `examples.md` |
| `orchestrator-pattern/` | Architecture rules for multi-agent delegation (read-only orchestrator + executor/diagnoser subagents, write-path restrictions, failure handling). | `.ai/instructions/orchestrator-pattern/principles.md` |
| `agent-catalog/` | The 13-agent catalog (orchestrator + 12 subagents) with tool allowlists, write scopes, shell restrictions, and behavior rules. | `.ai/instructions/agent-catalog/principles.md` |

Each of the three has a sibling in `.kimi/steering/` and `.kiro/steering/` — same content, adapted to each CLI's native format. All regenerated from `.ai/instructions/`; see `.ai/sync.md` for the map and copy commands.

## Adding a new skill

1. **Decide whether it's cross-CLI or Claude-only.**
   - **Cross-CLI** (karpathy-guidelines, orchestrator-pattern, etc.): write the canonical body to `.ai/instructions/<name>/principles.md`. Add a sync-map row to `.ai/sync.md`. Send handoffs to Kimi and Kiro so they replicate into their native formats (their equivalents are steering-files or resource-files, not skills-as-such).
   - **Claude-only**: skip the SSOT step; write directly to `.claude/skills/<name>/SKILL.md`.

2. **Write `.claude/skills/<name>/SKILL.md`**:

        ---
        name: <name>
        description: <one paragraph — specific enough to trigger on the right tasks, generic enough to catch related phrasings. Claude uses this to decide when to auto-load the body.>
        ---

        <!-- Optional: provenance comment line pointing at SSOT. -->
        <!-- SSOT: .ai/instructions/<name>/principles.md — regenerate via .ai/sync.md -->

        # <Skill title>

        <body — the actual content Claude loads when the description matches>

3. **Bundled files** (e.g. `EXAMPLES.md`) go in the same directory. Reference them from `SKILL.md` by filename — Claude loads them lazily when the skill body prompts it to.

4. **Log the addition** in `.ai/activity/log.md` and (if cross-CLI) file handoffs to the other CLIs.

## Skills vs agents vs hooks

- **Skills** are *content* Claude loads into its reasoning context — behavioral rules, reference material, domain knowledge.
- **Agents** (`.claude/agents/`) are *personas* Claude runs as, each with its own tool allowlist and system prompt. Agents reference skills by name in their "Skills" sections.
- **Hooks** (`.claude/hooks/`) are *harness-level automation* — bash scripts that run at lifecycle events (pre-tool, post-tool, session start, stop) without going through the model.

A skill's effect comes from Claude reading it and changing behavior. A hook's effect is deterministic (blocks/injects regardless of the model). Use the right one for the job — skills for discretion, hooks for enforcement.

## Updating an existing skill

If SSOT-backed (see table): edit `.ai/instructions/<name>/principles.md` (or `examples.md`) and re-run the copy commands in `.ai/sync.md` to regenerate the CLI-native copies. Handoff to Kimi/Kiro if the changes affect their replicas too.

If Claude-only: edit `SKILL.md` in place. Log the edit.
