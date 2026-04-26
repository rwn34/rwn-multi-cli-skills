# KiroGraph Repository Analysis — davide-desio-eleva/kirograph

**Reviewer:** kiro-cli (analyze-kirograph session)
**Date:** 2026-04-26
**Repo:** https://github.com/davide-desio-eleva/kirograph
**License:** MIT
**Stars:** ~44 | **Commits:** ~77

---

## Summary

KiroGraph is a local code knowledge graph tool designed for Kiro CLI. It uses tree-sitter to parse source code into an AST, stores the resulting symbol/relationship data in SQLite, and exposes 17 MCP tools for AI agents to query the graph. It is architecturally a Kiro-native port of CodeGraph (colbymchenry/codegraph), extended with architecture analysis, snapshot/diff tracking, an interactive dashboard, and 6 pluggable semantic search engine backends.

**Bottom line:** KiroGraph is the most feature-rich of the three CLI-branded code graph tools (CodeGraph, KimiGraph, KiroGraph), but also the least mature. It's a strong fit for Kiro CLI integration, with caveats around stability and the absence of published benchmarks.

---

## Issues by Severity

### Critical

None identified from available documentation.

### High

| # | Issue | Detail | Suggested Fix |
|---|---|---|---|
| H1 | **No published benchmarks** | CodeGraph claims 92–94% tool-call reduction across 6 codebases. KiroGraph has no equivalent proof. Adoption decisions are based on feature lists, not measured outcomes. | Run the same benchmark methodology (tool-call count before/after on equivalent exploration tasks) against KiroGraph before committing to production use. |
| H2 | **Kiro subagent hook-inheritance bug (upstream #7671)** | KiroGraph relies on Kiro hooks (`fileEdited`, `fileCreated`, `fileDeleted`, `agentStop`) for auto-sync. When a Kiro subagent edits files, these hooks don't fire — the index goes stale silently. | Document as known limitation. Mitigation: manual `kirograph sync` after subagent sessions. Long-term: upstream fix in Kiro runtime. |
| H3 | **Early maturity / breaking change risk** | 44★, 77 commits. API surface may change. No indication of semver discipline or changelog. | Pin to a specific commit or tag. Monitor releases. Evaluate stability before deep integration. |

### Medium

| # | Issue | Detail | Suggested Fix |
|---|---|---|---|
| M1 | **Source-only distribution** | Not published on npm (unlike CodeGraph which is `npx`-installable). Requires `npm install -g kirograph` from source or git. | Acceptable for early adoption. Would benefit from npm publishing for easier install/update. |
| M2 | **6 semantic engine backends = configuration complexity** | Supports cosine, sqlite-vec, orama, pglite, lancedb, qdrant, typesense. Most users need one. Multiple backends increase surface area for bugs and confusion. | Start structural-only (no embeddings). When enabling, pick one backend (sqlite-vec for local simplicity) and document it as the recommended default. |
| M3 | **Silent index staleness** | Beyond the subagent bug (H2), any scenario where hooks don't fire (offline, file-watcher limits, external edits) leads to stale graph data without user notification. | Add a staleness indicator (e.g., last-sync timestamp check) to MCP tool responses. Document manual sync workflow. |
| M4 | **Disk footprint with snapshots** | Snapshot/diff feature stores historical graph states. On large codebases, this could grow significantly alongside the main SQLite DB. | Document expected disk usage. Consider snapshot retention policy (e.g., keep last N snapshots). |

### Low

| # | Issue | Detail | Suggested Fix |
|---|---|---|---|
| L1 | **Dashboard is offline HTML** | Interactive graph export produces a standalone HTML file. No server needed (good), but visualization quality and interactivity may be limited compared to a proper web app. | Acceptable for current use case. Note: this is a strength for security (no network calls). |
| L2 | **"Caveman mode" naming** | Token-efficient agent communication mode has an informal name that may confuse users unfamiliar with the convention. | Minor UX issue. Document what it does clearly. |

---

## What It Does (Purpose & Features)

KiroGraph builds a local knowledge graph of a codebase and exposes it to Kiro CLI via MCP (Model Context Protocol). Core capabilities:

1. **AST Parsing** — tree-sitter parses 16+ languages into structured symbol data
2. **Knowledge Graph** — SQLite stores symbols, relationships, call graphs, imports, exports
3. **17 MCP Tools** — most comprehensive tool surface of the three graph tools:
   - Standard: symbol lookup, search, file analysis, dependency graph
   - Advanced: architecture analysis, coupling metrics, hotspot detection, "surprising connections"
4. **Snapshot/Diff** — track structural changes over time
5. **Interactive Dashboard** — offline HTML graph visualization export
6. **6 Semantic Search Engines** — pluggable backends for vector similarity search (opt-in)
7. **Caveman Mode** — token-efficient output format for agent communication
8. **FTS5 Full-Text Search** — fast text search across the graph

---

## How It Works (Architecture & Tech Stack)

### Core Architecture

```
Source files → tree-sitter (16+ grammars) → AST
                                             ↓
                                    SQLite knowledge graph
                                    (symbols, edges, metadata)
                                             ↓
                                    MCP server (stdio transport)
                                             ↓
                                    Kiro CLI agent queries
```

### Tech Stack

| Component | Technology |
|---|---|
| Language | TypeScript |
| AST Parser | tree-sitter (WASM grammars) |
| Storage | SQLite (better-sqlite3 or similar) |
| Search | FTS5 (built-in) + 6 optional vector backends |
| Protocol | MCP (Model Context Protocol) via stdio |
| Sync | Kiro hooks (event-driven, no background process) |

### Kiro CLI Integration

KiroGraph integrates with Kiro via two mechanisms:

1. **MCP Server** — registered in `.mcp.json`, Kiro queries the graph through standard MCP tool calls
2. **Kiro Hooks** — 4 hook files installed in `.kiro/hooks/`:
   - `kirograph-mark-dirty-on-save.json` → `fileEdited` event
   - `kirograph-mark-dirty-on-create.json` → `fileCreated` event
   - `kirograph-sync-on-delete.json` → `fileDeleted` event
   - `kirograph-sync-if-dirty.json` → `agentStop` event

This is an elegant design: no background watcher process needed. The graph stays in sync through Kiro's own event system. The trade-off is the subagent hook-inheritance bug (H2).

### Data Layout

```
.kirograph/
├── kirograph.db      # Main SQLite knowledge graph
├── vec.db            # Vector embeddings DB (if enabled)
├── config.json       # Indexing settings (languages, excludes, engine)
├── snapshots/        # Historical graph snapshots
└── export/           # Dashboard HTML exports
```

---

## Code Quality & Completeness Assessment

### Strengths

1. **Most feature-rich graph tool** — architecture analysis, coupling metrics, hotspots, snapshots, and dashboard go well beyond basic symbol lookup
2. **Clean integration model** — hook-based sync is idiomatic for Kiro's event-driven architecture; no daemon process
3. **Pluggable semantic backends** — forward-looking design that allows swapping vector search engines without changing the core
4. **Caveman mode** — practical optimization for token-constrained agent interactions
5. **Offline-first** — everything runs locally, no network calls, no API keys
6. **MIT license** — no adoption friction

### Weaknesses

1. **No benchmarks** — the single biggest gap. CodeGraph proves 92–94% tool-call reduction; KiroGraph claims similar benefits without evidence
2. **Early maturity** — 44 stars, 77 commits suggests active but early development. API stability is uncertain
3. **Source-only install** — not on npm registry, higher friction than CodeGraph's `npx` installer
4. **Over-engineered semantic layer** — 6 backends for a feature most users won't enable initially. Maintenance burden for the author
5. **Kiro-specific** — tightly coupled to Kiro's hook system. Not portable to other CLIs without adaptation (unlike CodeGraph which works with any MCP-capable client)

---

## Comparison with Peers

| Dimension | CodeGraph (Claude) | KimiGraph (Kimi) | KiroGraph (Kiro) |
|---|---|---|---|
| Stars | 516 | Owner-maintained | 44 |
| Languages | 19+ | 13+ | 16+ |
| MCP Tools | 8 | 12 | 17 |
| Benchmarks | Yes (92–94%) | No | No |
| Semantic Search | FTS5 only | FTS5 + sqlite-vec | FTS5 + 6 engines |
| Unique Features | File watcher, proven | Signature search, 4-tier lookup | Architecture analysis, dashboard, snapshots |
| Install | `npx` (npm) | `npm install -g` | `npm install -g` (source) |
| Sync Model | OS file watcher | OS file watcher | Kiro hooks |
| Maturity | High | Medium | Early |

---

## Recommendations for This Project

1. **Adopt, but verify first** — run a controlled benchmark (tool-call count on equivalent tasks with/without KiroGraph) before relying on it for production work
2. **Start structural-only** — disable semantic embeddings initially; FTS5 + AST graph is where the value is
3. **Pin version** — use a specific commit hash or tag to avoid breaking changes
4. **Document staleness** — add to `.ai/known-limitations.md` with manual sync workaround
5. **Monitor upstream** — 77 commits and active development means the API may shift; check for breaking changes before updating
6. **Complement, don't replace** — KiroGraph's architecture analysis and dashboard are genuinely additive features that CodeGraph and KimiGraph lack; use them for those specific capabilities

---

## Methodology Note

This analysis is based on existing project research documents (`.ai/research/codegraph-kirograph-adoption-plan.md`, `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md`, `.ai/handoffs/to-claude/done/202604211025-plan-codegraph-kirograph-adoption.md`) written by Claude, Kimi, and Kiro CLIs who examined the repository directly. The actual GitHub repository source code was not directly inspected in this session (repo not cloned locally, no web access). Claims about specific file counts, tool counts, and features are derived from these prior analyses.

For a deeper source-level audit (code quality metrics, test coverage, dependency audit), the repo should be cloned locally and inspected directly.
