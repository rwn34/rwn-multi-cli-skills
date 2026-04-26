# KimiGraph Repository Analysis

**Reviewer:** kiro-cli (analyze-kimigraph session)
**Date:** 2026-04-26
**Repository:** rwn34/kimigraph (local clone at `C:/Users/rwn34/Code/rwn-kimigraph`)
**Version:** v0.3.0 (npm: `rwn-kimigraph`)

---

## Summary

KimiGraph is a **local-first code knowledge graph** designed for Kimi Code CLI. It parses source code using tree-sitter WASM grammars, stores symbols and relationships in SQLite (with FTS5 + sqlite-vec for semantic search), and exposes the graph via 11 MCP tools. The project is well-engineered, feature-complete through Phase 5, and has strong test coverage (118 tests across 25 files). It is a serious, production-quality tool — not a prototype.

---

## What It Does

**Purpose:** Replace 10+ file-read tool calls during AI-assisted code exploration with a single graph query. One `kimigraph_explore` call returns full source sections for relevant symbols in <3 seconds.

**Key features:**
- AST-based extraction via tree-sitter WASM for 13 languages + protobuf
- SQLite graph DB with WAL mode, FTS5 full-text search, sqlite-vec 768-dim semantic vectors
- 4-tier search: exact match → FTS5 → semantic (nomic-embed-text-v1.5) → LIKE fallback
- Cross-file reference resolution for JS/TS, Python, Go, Java, Rust imports
- Graph traversal: callers, callees, impact radius, shortest path, dead code, cycles
- File watcher with debounced auto-sync (2s)
- MCP server (stdio JSON-RPC) with 11 tools
- CLI with init, index, sync, watch, query, callers, callees, impact, context, serve, install/uninstall
- Auto-writes `.kimi/AGENTS.md` to guide Kimi CLI toward graph tools

---

## Architecture & Tech Stack

| Layer | Technology | Files |
|-------|-----------|-------|
| Language | TypeScript (strict mode, ES2022 target, CommonJS) | `tsconfig.json` |
| Build | esbuild (custom `scripts/build.ts`) | `scripts/build.ts` |
| Test | Vitest | `vitest.config.ts`, 25 test files |
| DB | better-sqlite3 + sqlite-vec | `src/db/` |
| Parsing | web-tree-sitter + tree-sitter-wasms | `src/extraction/` |
| Embeddings | @huggingface/transformers (optional dep) | `src/embeddings/` |
| MCP | Custom stdio JSON-RPC transport | `src/mcp/` |
| CLI | Commander.js | `src/bin/kimigraph.ts` |
| CI | GitHub Actions (3 OS × 3 Node versions = 9 matrix) | `.github/workflows/ci.yml` |

**Source structure is clean and well-organized:**
```
src/
  index.ts           — Main KimiGraph class (public API)
  types.ts           — All TypeScript interfaces
  config.ts          — Config management
  errors.ts          — Error classes + logging
  utils.ts           — Shared utilities
  directory.ts       — .kimigraph/ directory management
  watcher.ts         — File watcher
  db/                — SQLite connection, schema, query builder
  extraction/        — Tree-sitter parsing + .scm query files (12 languages)
  graph/             — BFS traversal algorithms
  context/           — Natural-language context builder
  resolution/        — Cross-file reference resolver
  embeddings/        — HuggingFace model wrapper
  mcp/               — MCP server, transport, tool definitions
  bin/               — CLI entry point
```

---

## Code Quality Assessment

### Strengths

1. **Comprehensive type system.** All interfaces are centralized in `types.ts`. Strict TypeScript with `noImplicitAny`, `noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`, `noFallthroughCasesInSwitch`.

2. **Well-structured error hierarchy.** `KimiGraphError` → `DatabaseError`, `ParseError`, `ConfigError`, `SearchError`. Proper error propagation throughout.

3. **Robust DB layer.** WAL mode, busy timeout (120s), memory-mapped I/O (256MB), FTS5 triggers for automatic index sync, parameterized queries throughout (no SQL injection risk).

4. **Incremental sync is smart.** Only re-parses changed files (content hash comparison). Preserves embeddings for unchanged nodes. Prunes dangling edges post-resolve.

5. **Concurrency safety.** `Mutex` on indexing operations prevents concurrent index/sync corruption.

6. **Honest limitations section.** The README is unusually transparent about what doesn't work (dynamic imports, reflection, macros, etc.) and what's been fixed. This is rare and valuable.

7. **118 tests across 25 files.** Coverage spans extraction, resolution, graph traversal, MCP tools, embeddings, watcher, DB operations, and language-specific edge cases.

8. **CI matrix is thorough.** 9 combinations (Ubuntu/Windows/macOS × Node 18/20/22) on every push.

9. **MCP connection LRU cache.** Max 10 connections with `kg.close()` on eviction — prevents handle leaks in long-running servers.

10. **Self-indexing test.** `self-index.test.ts` indexes KimiGraph's own source code as a validation.

### Issues

#### High Severity

1. **`require()` for native modules without type safety** — `src/db/index.ts:10-13`
   ```typescript
   const Database = require('better-sqlite3');
   const sqliteVec = require('sqlite-vec');
   ```
   The `db` field is typed `any`. All DB method calls (`prepare`, `exec`, `run`, `get`, `all`) are untyped. A typo in a method name or wrong parameter count would only surface at runtime.
   
   **Suggested fix:** Use `@types/better-sqlite3` (it exists) and type the `db` field properly. If sqlite-vec lacks types, create a minimal `.d.ts`.

2. **Transaction implementation is manual and fragile** — `src/db/index.ts:73-82`
   ```typescript
   this.db.prepare('BEGIN').run();
   try {
     const result = fn();
     this.db.prepare('COMMIT').run();
     return result;
   } catch (err) {
     this.db.prepare('ROLLBACK').run();
     throw err;
   }
   ```
   `better-sqlite3` has a built-in `db.transaction()` that handles savepoints and nesting correctly. The manual approach doesn't support nested transactions and could leave the DB in a bad state if `ROLLBACK` itself throws.
   
   **Suggested fix:** Use `this.db.transaction(fn)()` from better-sqlite3's API.

#### Medium Severity

3. **Embedding model is an optional dependency but failure path is noisy** — `src/embeddings/model.ts`
   If `@huggingface/transformers` isn't installed, the error message is thrown during `load()`. But the `getEmbedder()` singleton is created eagerly in `searchNodes()`, meaning the error surfaces during search, not during init. Users may not understand why search fails.
   
   **Suggested fix:** Check for the optional dependency at init time and set a flag, rather than throwing during search.

4. **`extractFromSource` is a 1000+ line function** — `src/extraction/index.ts`
   The extraction orchestrator handles all 13 languages in a single file (~41KB). While the tree-sitter queries are externalized to `.scm` files, the post-processing logic (node creation, edge creation, docstring extraction, anonymous function naming) is monolithic.
   
   **Suggested fix:** Consider extracting language-specific post-processing into separate modules or at least splitting the file into logical sections with clear boundaries.

5. **No input validation on MCP tool arguments** — `src/mcp/tools.ts`
   Tool handlers trust that `args.query` is a string, `args.limit` is a number, etc. A malformed MCP request could cause unexpected errors.
   
   **Suggested fix:** Add basic type guards at the top of each handler.

6. **Windows OOM during indexing is a known issue** — README Troubleshooting
   Loading 10+ WASM grammars exhausts V8 zone memory. The workaround (`--max-old-space-size=4096`) is documented but the root cause (grammar accumulation) is unresolved. This affects the primary use case (multi-language repos on Windows).

7. **`package.json` uses caret ranges for all dependencies** — `package.json`
   ```json
   "better-sqlite3": "^12.9.0",
   "commander": "^12.1.0",
   ```
   For a tool that ships native binaries (better-sqlite3, sqlite-vec), caret ranges risk breaking changes on minor bumps. The lockfile mitigates this for direct installs, but global installs (`npm install -g`) may resolve differently.
   
   **Suggested fix:** Pin exact versions for native dependencies at minimum.

#### Low Severity

8. **`process.env.KIMIGRAPH_VERSION` fallback in MCP server** — `src/mcp/server.ts:8`
   ```typescript
   const SERVER_INFO = { name: 'kimigraph', version: process.env.KIMIGRAPH_VERSION || require('../../package.json').version };
   ```
   The `require('../../package.json')` path is fragile — it depends on the file being at exactly `dist/mcp/server.js`. If the build output structure changes, this breaks silently.

9. **Polling fallback in watcher uses hardcoded directory exclusions** — `src/watcher.ts:100-102`
   The polling `walk()` function hardcodes `['node_modules', '.git', 'dist', 'build', '.kimigraph', 'target']` instead of using the configurable `excludePatterns`. The `fs.watch` path correctly uses `isExcludedPath()`.

10. **No `.npmignore` or explicit `files` field coverage check** — `package.json`
    The `files` field includes `["dist", "README.md"]` which is correct, but the `dist/` directory includes `.d.ts.map` files (source maps for declarations) that add ~20KB of unnecessary weight to the npm package.

11. **`GITHUB_ISSUE_URL.txt`, `UPSTREAM_ISSUE.md`, `add_logging_v2.py`, `inspect_memory.py`, `add_group_mem_logging.py`** — repo root
    These appear to be debugging/investigation artifacts that should be in `.gitignore` or cleaned up. They clutter the repo root.

12. **`src/.kimigraph/` and `src/.kimi/` directories exist in the source tree** — These are runtime artifacts from self-indexing that probably shouldn't be committed. They contain a 1.7MB SQLite database.

---

## Kimi CLI Integration

The integration is well-designed:

1. **`kimigraph init`** writes `.kimi/AGENTS.md` with structured instructions telling Kimi to prefer graph tools over file reads.
2. **`kimigraph install`** auto-detects the environment and writes `~/.kimi/mcp.json` with the correct command (direct binary or `node <path>`).
3. **11 MCP tools** cover the full exploration workflow: search, explore, context, callers, callees, impact, node, path, dead code, cycles, status, signature search.
4. **Pre-query sync** (`syncIfDirty()`) ensures the graph is fresh before every MCP tool call.
5. **Connection LRU cache** (max 10) handles multi-project scenarios without leaking handles.

The main limitation is that Kimi CLI may ignore the `.kimi/AGENTS.md` instructions — there's no programmatic hook to force tool selection. This is acknowledged in the README.

---

## Notable Strengths

- **Scope discipline.** The project knows what it is and what it isn't. The "Honest Limitations" section is exemplary.
- **Performance-conscious.** SQLite WAL mode, mmap, FTS5, batched embeddings, debounced watcher, LRU cache.
- **13-language support** with tree-sitter queries is impressive for a single-developer project.
- **Self-documenting.** README is 26KB with architecture diagrams, benchmarks, troubleshooting, and a detailed roadmap.
- **Cross-platform CI.** 9-matrix GitHub Actions ensures it works everywhere.

---

## Notable Weaknesses

- **Monolithic extraction module** (~41KB single file) will become harder to maintain as languages are added.
- **`any` types in DB layer** undermine TypeScript's value in the most critical module.
- **No integration test with actual Kimi CLI** — the MCP tools are tested in isolation but not end-to-end with a real MCP client.
- **Windows OOM** is a real usability issue for the target audience (developers with multi-language repos).
- **Repo hygiene** — debugging artifacts and runtime databases committed to the repo.

---

## Recommendations

1. **Type the DB layer.** Install `@types/better-sqlite3` and eliminate `any` from `DatabaseConnection`.
2. **Use better-sqlite3's native `transaction()`.** It handles nesting and is more robust.
3. **Pin native dependency versions.** At least `better-sqlite3` and `sqlite-vec`.
4. **Split `extraction/index.ts`.** Extract language-specific post-processing into separate files.
5. **Clean up repo root.** Remove or `.gitignore` the debugging artifacts and runtime databases.
6. **Add MCP integration test.** Spawn the server, send JSON-RPC messages, verify responses.
7. **Investigate Windows OOM.** Consider lazy-loading grammars (only load when a file of that language is encountered) instead of loading all at init.
