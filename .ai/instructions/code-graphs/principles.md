# Code knowledge graphs

Local code-knowledge-graph rules for this project. All four CLIs (Claude Code,
Kimi CLI, Kiro CLI, Crush) run all three graph tools — CodeGraph, KimiGraph,
and KiroGraph — with MCP wired in each CLI's native config format. Each graph
indexes the same source code into its own dot-directory, queried via its own
MCP server.

A code graph parses the project with **tree-sitter**, stores symbols and edges
(callers, callees, imports, type relationships) in a local **SQLite** database,
and exposes lookups over **MCP**. Typical structural exploration drops from 10+
file reads to a single graph query — that is the entire point of the tool.

**Companion docs:**
- `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` — full design
  rationale, tool comparison, adoption decisions.
- `.ai/known-limitations.md` — Kiro subagent hook-inheritance bug + general
  index-staleness notes.

## The rule

When a graph is **active** for the running CLI, prefer it for structural
questions before reading files. "How does X work?", "what calls Y?", "what
breaks if I change Z?" — these are graph queries, not file reads.

When a graph is **not active**, ask the user **once** at the start of
substantive exploration whether to install it. Don't ask again in the same
session.

Do **not** re-read files the graph already returned source for. Only fall back
to grep/glob/file-reads when:
1. The graph flags a file under "additional relevant files" (it didn't include
   the source inline), or
2. The graph returned no results for the query.

## Per-CLI graph mapping

| CLI | Graph tool | Local dir | Repo |
|---|---|---|---|
| Claude Code | CodeGraph | `.codegraph/` | https://github.com/colbymchenry/codegraph |
| Kimi CLI | KimiGraph | `.kimigraph/` | https://github.com/rwn34/kimigraph |
| Kiro CLI | KiroGraph | `.kirograph/` | https://github.com/davide-desio-eleva/kirograph |
| Crush | any (all 3 wired) | same dirs | same repos |

All three graph MCP servers are wired in **every** CLI config:

| CLI | Config file | Graphs registered |
|---|---|---|
| Claude Code | `.mcp.json` (project root) | codegraph, kirograph, kimigraph |
| Kimi CLI | `~/.kimi/mcp.json` (global) | kimigraph, kirograph, codegraph |
| Kiro | `.kiro/settings/mcp.json` (project) | kirograph, codegraph, kimigraph |
| Crush | `.crush.json` (project root) | codegraph, kirograph, kimigraph |

Tool name prefixes match the graph: `codegraph_*`, `kimigraph_*`, `kirograph_*`.

## Write boundaries

Each CLI writes only to its own graph dir. Cross-graph writes are blocked at the
tool layer by each CLI's `pretool-write-edit` hook. Never edit another CLI's
`.X-graph/` directly — if you genuinely need a change there, send a handoff
to that CLI.

The `config.json` inside each graph dir is committed (it captures shared
indexing preferences); everything else under each graph dir is gitignored.

## When the graph is active — usage rules

1. **Spawn an Explore agent for broad questions.** For "how does X work?",
   "trace the auth flow", "find everything that touches the payment webhook",
   delegate to an explorer subagent and tell it explicitly: *"This project has
   `<GraphName>` initialized. Use the CLI's `*_explore` / `*_context` MCP tool
   as your PRIMARY tool — it returns full source sections in one call."*
2. **Don't re-read returned files.** The graph's exploration tools embed source
   sections directly in their response. Reading them again with a file tool
   wastes tokens for no new information.
3. **Lightweight lookups can be called directly.** The main agent doesn't need
   to spawn a subagent for `*_search`, `*_callers`, `*_callees`, `*_impact`, or
   `*_node` — those are cheap, scoped queries.
4. **Auto-sync mechanisms vary by CLI:**
   - Claude (CodeGraph) and Kimi (KimiGraph) use OS file-watcher events
     (FSEvents / inotify / ReadDirectoryChangesW).
   - Kiro (KiroGraph) uses Kiro's `fileEdited` / `fileCreated` / `fileDeleted`
     / `agentStop` hooks.
5. **Run a manual sync if results look stale.** Each tool ships a `sync`
   subcommand (`codegraph sync`, `kimigraph sync`, `kirograph sync`).

## When the graph is NOT active

If the CLI's graph dir doesn't exist, ask the user once at the start of
substantive exploration:

> "This project doesn't have `<GraphName>` initialized. Want me to run
> `<install-cmd>` to build a graph for faster exploration?"

Substitute the active CLI's tool name and install command from the per-CLI
reference below. If the user declines, fall back to grep/glob/file reads for
the rest of the session and don't re-prompt.

## Per-CLI tool reference

### Claude — CodeGraph (FTS5 only)

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

CodeGraph is **FTS5-only** — no semantic/vector search. For semantic
similarity, use Kimi or Kiro (their tools support it as an opt-in). Run
`codegraph --help` after install for the authoritative tool list.

### Crush — all 3 graphs wired

**Config:** `.crush.json` at project root, `mcp` key with `type: "stdio"`.

Crush uses the same MCP server binaries as the other CLIs. All three graph
tools are available with the same tool names and prefixes. No graph-specific
install step — the MCP config is project-level and the binaries are global.

### Kimi — KimiGraph (FTS5 + sqlite-vec semantic)

**Install:** `npm install -g rwn-kimigraph` then `kimigraph install`

| Tool | Use for |
|---|---|
| `kimigraph_explore` | Primary exploration — full source sections in one call |
| `kimigraph_search` | Find symbols by name |
| `kimigraph_context` | Build task context from natural language |
| `kimigraph_callers` | Who calls this symbol |
| `kimigraph_callees` | What this symbol calls |
| `kimigraph_impact` | What's affected by changing a symbol |
| `kimigraph_node` | Single symbol details + source |
| `kimigraph_path` | Shortest path between two symbols |
| `kimigraph_dead_code` | Symbols with zero references (advisory) |
| `kimigraph_cycles` | Circular dependency chains (advisory) |
| `kimigraph_signature_search` | Find functions by type signature |
| `kimigraph_status` | Index health and stats |

KimiGraph adds a 4-tier search (exact → FTS5 → semantic KNN → LIKE fallback)
and signature-based lookup (e.g., `string -> boolean`). Semantic embeddings are
opt-in via `enableEmbeddings: true` in `.kimigraph/config.json`.

### Kiro — KiroGraph (6 semantic engines + architecture analysis)

**Install:** `kirograph install` (from source — not yet on npm)

| Tool | Use for |
|---|---|
| `kirograph_context` | Primary exploration — full source sections from natural language |
| `kirograph_search` | Find symbols by name |
| `kirograph_callers` | Who calls this symbol |
| `kirograph_callees` | What this symbol calls |
| `kirograph_impact` | What's affected by changing a symbol |
| `kirograph_node` | Single symbol details + source |
| `kirograph_type_hierarchy` | Class/interface inheritance tree |
| `kirograph_path` | Shortest path between two symbols |
| `kirograph_dead_code` | Symbols with zero references (advisory) |
| `kirograph_circular_deps` | Circular import chains (advisory) |
| `kirograph_files` | Indexed file tree with filters |
| `kirograph_status` | Index health and stats |
| `kirograph_hotspots` | Most-connected symbols by edge degree |
| `kirograph_surprising` | Non-obvious cross-file connections |
| `kirograph_diff` | Compare current graph vs saved snapshot |
| `kirograph_architecture` | Package graph + layers (opt-in) |
| `kirograph_coupling` | Ca/Ce/instability metrics (opt-in) |
| `kirograph_package` | Inspect a single package (opt-in) |

KiroGraph is the most feature-rich of the three: 6 semantic engine backends
(cosine, sqlite-vec, orama, pglite, lancedb, qdrant, typesense), architecture
analysis with package coupling metrics, and a snapshot/diff capability. Both
embeddings (`enableEmbeddings`) and architecture analysis (`enableArchitecture`)
are opt-in via `.kirograph/config.json`.

## Limitations

**Common to all three:**
- Dynamic imports, reflection, and runtime-generated calls are invisible to
  static analysis. The graph sees only what tree-sitter can parse.
- Auto-sync watchers can miss changes under load — run the tool's `sync`
  subcommand if results look stale.
- First index of a large repo is slow; incremental updates are fast.

**Claude / CodeGraph specific:**
- No embeddings / no semantic search (FTS5 only).

**Kimi / KimiGraph specific:**
- On Windows, indexing many languages may need
  `NODE_OPTIONS="--max-old-space-size=4096"` to avoid V8 zone OOM.

**Kiro / KiroGraph specific:**
- Kiro subagent writes do **not** fire hooks (platform bug #7671), so
  KiroGraph's hook-based auto-sync misses subagent edits. Run `kirograph sync`
  manually after subagent work if the index seems stale. See
  `.ai/known-limitations.md` for the full hook-inheritance entry.

## Adoption status

At adoption, all three graphs run **structural-only** — no embeddings, no
heavy model downloads. This delivers the benchmarked 90%+ tool-call reduction
from structural indexing alone, with the option to enable semantic similarity
later via each tool's `config.json`.

For the full design rationale (why all three CLIs adopt in parallel rather
than phased, MCP placement decisions, hook coexistence, gitignore strategy),
see `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md`.

---

**This pattern is working if:** AI agents prefer graph queries over file
reads for structural questions, every CLI writes only to its own graph dir,
and stale-index incidents trigger a manual sync rather than silent wrong
answers.
