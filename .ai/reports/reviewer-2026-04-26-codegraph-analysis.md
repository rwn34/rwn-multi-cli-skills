# CodeGraph Analysis Report

**Reviewer:** kiro-cli (analyze-codegraph session)
**Date:** 2026-04-26
**Repo:** https://github.com/colbymchenry/codegraph
**Stars:** 516+ | **Commits:** 237+ | **License:** MIT

---

## Summary

CodeGraph is a local-first code knowledge graph tool designed specifically for Claude Code. It parses source code using tree-sitter into a SQLite database, then exposes that graph via MCP (Model Context Protocol) tools. The core value proposition: **92–94% reduction in tool calls** during codebase exploration, because Claude can query the pre-indexed graph instead of reading files one by one.

The tool is the most mature of the three CLI-branded code graph tools (CodeGraph for Claude, KiroGraph for Kiro, KimiGraph for Kimi) and serves as the reference implementation for the "tree-sitter → SQLite → MCP" pattern.

---

## What It Does

### Purpose
Gives Claude Code a pre-built understanding of a codebase's structure — symbols, call graphs, imports, exports, type hierarchies — so it can answer structural questions ("what calls this function?", "what does this module export?") via fast SQLite queries instead of reading and parsing files at runtime.

### Features
- **AST-based indexing** of 19+ languages via tree-sitter (including niche: Svelte, Liquid, Pascal/Delphi)
- **SQLite knowledge graph** with FTS5 full-text search
- **8 MCP tools** exposed to Claude Code for querying the graph
- **File watcher** for auto-sync using native OS events (FSEvents on macOS, inotify on Linux, ReadDirectoryChangesW on Windows)
- **Interactive installer** via `npx @colbymchenry/codegraph`
- **Benchmark suite** with published results across 6 codebases

### MCP Tools (8)
Based on the tool's documentation and the research in this project:
1. Symbol lookup (find definitions by name)
2. Symbol search (fuzzy/FTS5 search across codebase)
3. Call graph traversal (callers/callees)
4. Import/export analysis
5. File symbol listing (all symbols in a file)
6. Type hierarchy (inheritance chains)
7. Reference finding
8. Codebase overview/statistics

---

## How It Works

### Architecture

```
Source files → tree-sitter parser → AST nodes
                                      ↓
                              SQLite DB (.codegraph/codegraph.db)
                                      ↓
                              MCP server (stdio transport)
                                      ↓
                              Claude Code (MCP client)
```

### Tech Stack
- **Language:** TypeScript/JavaScript (npm package)
- **Parser:** tree-sitter (WASM grammars for cross-platform)
- **Storage:** SQLite (single file, `.codegraph/codegraph.db`)
- **Search:** FTS5 (SQLite's built-in full-text search)
- **Transport:** MCP over stdio
- **File watching:** Native OS file-system events
- **Distribution:** npm (`@colbymchenry/codegraph`)

### Data Flow
1. On install/first run: walks the project tree, parses each file with the appropriate tree-sitter grammar, extracts symbols (functions, classes, methods, variables, imports, exports), and stores them with relationships in SQLite.
2. File watcher detects changes → re-parses affected files → updates graph incrementally.
3. Claude Code connects to the MCP server → issues tool calls → gets structured results from SQLite queries.

### Integration with Claude Code
- **Install:** `npx @colbymchenry/codegraph` runs an interactive installer
- **Config:** writes MCP server config to `~/.claude.json` (global) by default
- **Runtime:** MCP server runs as a child process, communicating via stdio
- **Usage:** Claude automatically discovers and uses the graph tools when they're registered in MCP config

---

## Code Quality and Completeness Assessment

### Strengths

| # | Strength | Details |
|---|---|---|
| 1 | **Proven benchmarks** | 92–94% tool-call reduction across 6 real codebases. This is the strongest differentiator — no other code graph tool has published comparable benchmarks. |
| 2 | **Broad language support** | 19+ languages including niche ones (Svelte, Liquid, Pascal/Delphi). Covers most real-world polyglot projects. |
| 3 | **Simple install UX** | Single `npx` command with interactive setup. Low barrier to adoption. |
| 4 | **Native file watching** | Uses OS-level events (not polling), so incremental sync is fast and low-overhead. |
| 5 | **npm distribution** | Proper package on npm, versioned, installable globally or per-project. More mature distribution than source-only alternatives. |
| 6 | **SQLite as storage** | Battle-tested, zero-config, single-file DB. No external services needed. Portable across machines (though DB should be regenerated, not copied). |
| 7 | **MIT license** | No licensing friction for any use case. |
| 8 | **Active development** | 237+ commits, 516+ stars indicates real community traction and ongoing maintenance. |

### Weaknesses / Issues

| # | Severity | Issue | Details |
|---|---|---|---|
| 1 | **Medium** | No semantic/vector search | FTS5 only. Cannot do "find functions similar to X" or semantic similarity queries. KimiGraph and KiroGraph both offer vector search as opt-in. For structural queries (the primary use case), this doesn't matter. For exploratory/semantic queries, it's a gap. |
| 2 | **Medium** | Global config default | Installer writes to `~/.claude.json` rather than project-local `.mcp.json`. This creates invisible per-machine state that breaks the "everything in the project" principle. Project-local config is possible but not the documented default path. |
| 3 | **Medium** | Lowest MCP tool count | 8 tools vs KimiGraph's 12 vs KiroGraph's 17. Missing: dead code detection, cycle detection, architecture analysis, coupling metrics, graph export/dashboard, snapshot/diff. These are "nice to have" rather than core, but the gap is real for advanced use cases. |
| 4 | **Low** | No architecture analysis | Cannot analyze package coupling, identify hotspots, or detect surprising cross-module connections. KiroGraph offers all of these. |
| 5 | **Low** | No snapshot/diff capability | Cannot track structural changes over time. KiroGraph offers snapshot comparison. |
| 6 | **Low** | No interactive dashboard | No visual graph exploration. KiroGraph generates offline HTML dashboards. |
| 7 | **Low** | Single-CLI lock-in | Designed exclusively for Claude Code. Cannot be used by Kimi or Kiro without MCP bridge workarounds. This is by design (each CLI gets its own tool) but limits cross-CLI utility. |

### Completeness
CodeGraph is **complete for its stated purpose**: structural code understanding for Claude Code. It does the core job (parse → index → query) well and has the benchmarks to prove it. The missing features (semantic search, architecture analysis, dashboards) are additive — they'd make it better but their absence doesn't make it broken.

---

## Comparison with Alternatives

| Dimension | CodeGraph | KimiGraph | KiroGraph |
|---|---|---|---|
| **Maturity** | High (516★) | Medium (owner-maintained) | Early (44★) |
| **Languages** | 19+ | 13+ | 16+ |
| **MCP tools** | 8 | 12 | 17 |
| **Search** | FTS5 only | FTS5 + sqlite-vec | FTS5 + 6 engines |
| **Unique features** | Benchmarks, simplest install | Signature search, 4-tier lookup | Architecture analysis, dashboard, snapshots |
| **Distribution** | npm | npm (owner-controlled) | Source-only |
| **Auto-sync** | OS file watcher | OS file watcher | Kiro hooks (event-driven) |
| **Semantic search** | No | Yes (opt-in) | Yes (6 backends) |

---

## Risk Assessment for Adoption

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Tool abandoned by maintainer | Low (active, 516★) | High | MIT license allows forking; core is simple enough to maintain |
| Breaking npm release | Low-Medium | Medium | Pin version in install scripts; test before upgrading |
| Index staleness (watcher misses) | Medium | Low | Manual `sync` command available; document in steering |
| Global config conflicts | Medium | Low | Migrate to project-local `.mcp.json` after install |
| DB size on large codebases | Low | Low | Typically 1–5 MB per 100 files; gitignored |
| tree-sitter grammar bugs | Low | Low | Affects all three tools equally (shared dependency) |

---

## Recommendations

1. **Adopt CodeGraph for Claude Code** — it's the most mature option, has proven benchmarks, and the simplest install path. The 92–94% tool-call reduction is the primary value driver.

2. **Migrate MCP config to project-local `.mcp.json`** after running the installer. Don't rely on global `~/.claude.json` for team projects.

3. **Start structural-only** — FTS5 is sufficient for the core use case. Semantic search can be added later if needed (via KimiGraph or KiroGraph for their respective CLIs).

4. **Pin the npm version** in any install scripts to avoid surprise breaking changes.

5. **Gitignore the DB, commit config.json** — the DB regenerates per-machine; the config ensures consistent indexing settings across contributors.

6. **Document the global-config gotcha** — new contributors need to know to run the installer or manually configure MCP.

7. **Don't expect architecture analysis** — if you need coupling metrics, hotspot detection, or structural change tracking, those are KiroGraph features, not CodeGraph features. Use the right tool for the right CLI.

---

## Verdict

**CodeGraph is a solid, mature, well-benchmarked tool that does one thing well: gives Claude Code fast structural understanding of a codebase.** It's not the most feature-rich code graph tool available, but it's the most proven. The 92–94% tool-call reduction benchmark is its killer feature — no competitor has published comparable numbers.

For this project's multi-CLI framework, CodeGraph is the right choice for Claude Code's graph tool. It integrates cleanly with the existing safety hooks (no event conflicts), fits the ADR-0001 root-file policy (as a dot-directory under Category E), and the gitignore strategy is straightforward.

The main gap — no semantic search — is acceptable because structural queries are where 90%+ of the token savings come from. If semantic search becomes a need, it's available via KimiGraph and KiroGraph for their respective CLIs.

---

## Methodology Note

This analysis was conducted without direct access to the codegraph repository source code. It is based on:
- Detailed research documents in `.ai/research/codegraph-kirograph-adoption-plan.md` and `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md`
- The handoff document at `.ai/handoffs/to-claude/done/202604211025-plan-codegraph-kirograph-adoption.md`
- The tool's public documentation and npm listing
- Comparison data gathered by Claude and Kimi CLIs during prior research sessions

A deeper source-code-level analysis (reviewing individual TypeScript files, test coverage, error handling patterns, SQL schema design) would require cloning the repository. This report covers architecture, features, integration, and fitness-for-purpose based on available information.
