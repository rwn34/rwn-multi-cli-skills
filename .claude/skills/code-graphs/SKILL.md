---
name: code-graphs
description: Local code-knowledge-graph rules — prefer CodeGraph MCP queries (codegraph_*) over file reads for structural questions. Use when exploring the codebase, tracing callers/callees/impact, asking "how does X work?", or when a .codegraph dir exists. KimiGraph/KiroGraph were removed 2026-07-09 (ADR-0003 amendment) — no other CLI has a graph.
---

<!-- SSOT: .ai/instructions/code-graphs/principles.md — regenerate via .ai/sync.md -->

# Code knowledge graphs

Local code-knowledge-graph rules for this project, per
`docs/architecture/0003-code-graph-rationalization.md` (amended 2026-07-09:
**single-graph topology**): **CodeGraph (Claude) is the only code-knowledge
graph.** KimiGraph and KiroGraph were REMOVED entirely on 2026-07-09 by owner
directive — MCP registrations, steering files, `.kimigraph/`/`.kirograph/`
dirs, global npm binaries, and the `tools/kirograph/` source clone. Rationale:
both malfunctioned more than they worked (MCP load warnings in dispatched
sessions, recurring repair handoffs); maintenance cost exceeded value. There
is no re-enable path short of a fresh ADR.

A code graph parses the project with **tree-sitter**, stores symbols and edges
(callers, callees, imports, type relationships) in a local **SQLite** database,
and exposes lookups over **MCP**. Typical structural exploration drops from 10+
file reads to a single graph query — that is the entire point of the tool.

**Companion docs:**
- `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` — historical
  design rationale (three-graph era, superseded).
- `.ai/known-limitations.md` — index-staleness notes.

## The rule

For **Claude Code** (the only CLI with a graph): when `.codegraph/` exists,
prefer the graph for structural questions before reading files. "How does X
work?", "what calls Y?", "what breaks if I change Z?" — these are graph
queries, not file reads.

When `.codegraph/` does not exist, ask the user **once** at the start of
substantive exploration whether to install it. Don't ask again in the same
session.

Do **not** re-read files the graph already returned source for. Only fall back
to grep/glob/file-reads when:
1. The graph flags a file under "additional relevant files" (it didn't include
   the source inline), or
2. The graph returned no results for the query.

**All other CLIs** (Kimi, Kiro, OpenCode): no graph lane. Use your native
search tools (grep/glob/file reads). Do not install or wire any graph MCP —
superseded tools removed 2026-07-09; a new graph for any CLI requires a fresh
ADR.

## Graph mapping (post-2026-07-09)

| CLI | Graph tool | Local dir | Status |
|---|---|---|---|
| Claude Code | CodeGraph | `.codegraph/` | **active** (repo: https://github.com/colbymchenry/codegraph) |
| Kimi CLI | none | — | KimiGraph REMOVED 2026-07-09 (owner directive, ADR-0003 amendment) |
| Kiro CLI | none | — | KiroGraph REMOVED 2026-07-09 (owner directive, ADR-0003 amendment) |
| OpenCode | none | — | no graph lane (ops/release role, ADR-0002) |

MCP wiring: `.mcp.json` (project root, Claude) registers `codegraph` — nothing
else, nowhere else. Tool name prefix: `codegraph_*`.

**Kill criterion (unchanged, now proven):** any graph that fails MCP twice in
a month, or goes unused for a month, is disabled rather than repaired
(ADR-0003). KimiGraph and KiroGraph met it.

## Write boundaries

Only Claude writes to `.codegraph/` (its own graph dir). The `config.json`
inside is committed (shared indexing preferences); everything else under it is
gitignored. `.kimigraph/`/`.kirograph/` no longer exist; hook rules blocking
writes there are retained as tombstones against accidental recreation.

## When the graph is active — usage rules (Claude)

1. **Spawn an Explore agent for broad questions.** For "how does X work?",
   "trace the auth flow", "find everything that touches the payment webhook",
   delegate to an explorer subagent and tell it explicitly: *"This project has
   CodeGraph initialized. Use `codegraph_explore` / `codegraph_context` as
   your PRIMARY tool — it returns full source sections in one call."*
2. **Don't re-read returned files.** The graph's exploration tools embed source
   sections directly in their response. Reading them again with a file tool
   wastes tokens for no new information.
3. **Lightweight lookups can be called directly.** The main agent doesn't need
   to spawn a subagent for `codegraph_search`, `codegraph_callers`,
   `codegraph_callees`, `codegraph_impact`, or `codegraph_node` — those are
   cheap, scoped queries.
4. **Auto-sync** uses OS file-watcher events (FSEvents / inotify /
   ReadDirectoryChangesW). **Run `codegraph sync` if results look stale** —
   watchers can miss changes under load.

## When the graph is NOT active (Claude)

If `.codegraph/` doesn't exist, ask the user once at the start of substantive
exploration:

> "This project doesn't have CodeGraph initialized. Want me to run
> `npx @colbymchenry/codegraph` to build a graph for faster exploration?"

If the user declines, fall back to grep/glob/file reads for the rest of the
session and don't re-prompt.

## Tool reference — CodeGraph (FTS5 only)

**Install:** `npx @colbymchenry/codegraph`

| Tool | Use for |
|---|---|
| `codegraph_explore` | Primary exploration — full source sections in one call |
| `codegraph_context` | Build task context from natural-language prompt |
| `codegraph_search` | Find symbols by name (FTS5) |
| `codegraph_callers` | Who calls this symbol |
| `codegraph_callees` | What this symbol calls |
| `codegraph_impact` | What's affected by changing a symbol |
| `codegraph_node` | Single symbol details + source |

Run `codegraph --help` after install for the authoritative tool list.

## Limitations

- Dynamic imports, reflection, and runtime-generated calls are invisible to
  static analysis. The graph sees only what tree-sitter can parse.
- Auto-sync watchers can miss changes under load — run `codegraph sync` if
  results look stale.
- First index of a large repo is slow; incremental updates are fast.
- No embeddings / no semantic search (FTS5 only). Semantic similarity can be
  enabled later via the tool's `config.json` if a need is demonstrated.

## Adoption status

- 2026-07-07 (ADR-0003): rationalized — CodeGraph active, KimiGraph/KiroGraph
  demoted to optional-off, cross-wiring ended.
- 2026-07-09 (ADR-0003 amendment, owner directive): single-graph topology —
  KimiGraph and KiroGraph removed entirely. Exploration payoff concentrates in
  the architect/orchestrator lane (ADR-0002); executors receive precise briefs
  and rarely need whole-repo structural queries; the removed graphs generated
  recurring MCP/PATH/staleness maintenance and dispatched-session load
  warnings.

Historical design rationale (the original all-three-in-parallel adoption):
`.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md`.

---

**This pattern is working if:** Claude prefers graph queries over file reads
for structural questions, no CLI recreates a removed graph dir, and
stale-index incidents trigger `codegraph sync` rather than silent wrong
answers.
