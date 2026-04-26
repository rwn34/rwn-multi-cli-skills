# AI Contract

Multiple AI CLIs work in this project (Claude Code = you, Kimi CLI, Kiro CLI). They
share state via `.ai/` so no CLI has to copy-paste another's output to stay coherent.

## Your identity for the activity log: `claude-code`

## Single source of truth

`.ai/instructions/` is canonical. Your `.claude/skills/...` files are replicas. If they
disagree, `.ai/instructions/` wins — see `.ai/sync.md` to regenerate.

## Cross-CLI activity log — `.ai/activity/log.md`

**Read** at the start of non-trivial work. Newest entries are at the top — scan recent
ones to see what other CLIs did here.

**Prepend** one entry after completing substantive work (file edits, running tests,
non-obvious decisions, finishing a task):

    ## YYYY-MM-DD HH:MM — claude-code
    - Action: <one-line summary>
    - Files: <paths, or "—">
    - Decisions: <non-obvious choices, or "—">

**Timestamp rule:** `HH:MM` = your current local wall-clock time at the moment you
prepend (finish time of the work, not start time). Prepend order is the authoritative
sequencing across CLIs; timestamps are annotations and may not sort monotonically if
clocks drift.

Terse — one short paragraph max. One entry per substantive action, not per file edit.
Never rewrite prior entries. Do not log trivial reads.

## Cross-CLI handoffs

When you need Kimi or Kiro to execute a change in their own folder, write a
paste-ready file to `.ai/handoffs/to-<kimi|kiro>/open/NNN-slug.md`. See
`.ai/handoffs/README.md` + `template.md` for the protocol. Before starting new
non-trivial work, glance at `.ai/handoffs/to-claude/open/` — anything there is a
task addressed to you.

## Root file policy

Repo root is strict. Permitted root files are listed in
`docs/architecture/0001-root-file-exceptions.md` — the authoritative ADR. If you
need to create a file at root and it is not covered, surface to the user for ADR
amendment before writing. The `PreToolUse` hook at
`.claude/hooks/pretool-write-edit.sh` will otherwise block the write.

## Archive folders (do not read during routine work)

Folders matching `.ai/**/archive/` (`.ai/activity/archive/`,
`.ai/research/archive/`, and any future archive subfolders under `.ai/`) contain
historical content that has been rolled out of the live files. Do NOT read them
in routine operations — not for activity-log scans, research lookups, or any
automatic glance. The `UserPromptSubmit` hook only injects from
`.ai/activity/log.md`, so the archive is already skipped in the auto path.

Only read archive folders when the user explicitly references historical activity
or archived research (e.g., "what did we decide in Q1?", "pull up the old
orchestrator design"). See each archive folder's `README.md` for the archival
protocol if you're asked to perform an archive move.

## Installed skills

- `karpathy-guidelines` — auto-activates on coding tasks via its description. See
  `.claude/skills/karpathy-guidelines/SKILL.md`.

## CodeGraph (Claude's code-knowledge-graph tool)

CodeGraph is a local SQLite knowledge graph of this codebase, queryable via MCP.
It parses source with tree-sitter and exposes structural lookups (symbols, callers,
callees, impact, search) — typical exploration drops from 10+ file reads to 1
graph query. Repo: https://github.com/colbymchenry/codegraph. Install:
`npx @colbymchenry/codegraph`.

### When CodeGraph is active

If `.codegraph/` exists, prefer the graph for structural questions before reading
files:

1. Spawn an Explore agent for broad questions ("how does X work?", "what calls Y?")
   and tell it: "This project has CodeGraph initialized. Use `codegraph_explore` /
   `codegraph_context` as your PRIMARY tool — it returns full source sections in
   one call."
2. Do NOT re-read files that the graph already returned source for.
3. Fall back to `Grep`/`Glob`/`Read` only for files the graph flags as "additional
   relevant" or when the graph returns no results.
4. The main session may use lightweight tools directly: `codegraph_search`,
   `codegraph_callers`, `codegraph_callees`, `codegraph_impact`, `codegraph_node`.

### When CodeGraph is NOT active

If `.codegraph/` doesn't exist, ask the user once at the start of substantive
exploration work:

> "This project doesn't have CodeGraph initialized. Want me to run
> `npx @colbymchenry/codegraph` to build a graph for faster exploration?"

### Quick reference

| Tool | Use for |
|---|---|
| `codegraph_explore` | Primary exploration — full source sections in one call |
| `codegraph_context` | Build task context from natural-language prompt |
| `codegraph_search` | Find symbols by name (FTS5) |
| `codegraph_callers` | Who calls this symbol |
| `codegraph_callees` | What this symbol calls |
| `codegraph_impact` | What's affected by changing a symbol |
| `codegraph_node` | Single symbol details + source |

(Run `codegraph --help` after install for the authoritative tool list.)

### Limitations

- Dynamic imports, reflection, and runtime-generated calls are invisible to static analysis.
- **Embeddings are not supported** — CodeGraph is FTS5-only. For semantic similarity,
  KimiGraph or KiroGraph (their respective CLIs' tools) offer opt-in vector search.
- Index is auto-synced via OS file watcher. If the watcher misses changes, run the
  manual sync command (`codegraph sync` or equivalent — check `codegraph --help`).
- CodeGraph's installer registers MCP globally in `~/.claude.json` by default;
  prefer migrating the entry to project-local `.mcp.json` for portability.

### Cross-CLI parity

This project also has KimiGraph (`.kimigraph/`) for Kimi CLI and KiroGraph
(`.kirograph/`) for Kiro CLI — same architecture, different host CLIs. **Claude
never writes to `.kimigraph/` or `.kirograph/`** (enforced by
`.claude/hooks/pretool-write-edit.sh`). See
`.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` for the full plan.
