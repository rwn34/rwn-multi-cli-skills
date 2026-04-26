# Unified Code Graph Adoption Plan (v2 — 3-CLI parity)

**Status:** APPROVED for execution (Kimi input incorporated; pending Claude + Kiro acknowledgment)
**Author:** kimi-cli (evolving Claude's v1 draft + Kiro's original handoff)
**Date:** 2026-04-26

---

## Executive summary

All three major CLI-branded code graph tools solve the same problem with the same core architecture:

```
tree-sitter AST parse → SQLite knowledge graph → MCP tools → AI CLI
```

| Tool | CLI | Maturity | Languages | Semantic | Special sauce |
|---|---|---|---|---|---|
| **CodeGraph** | Claude | High (516★, benchmarks) | 19+ | FTS5 only | 94% tool-call reduction, proven |
| **KimiGraph** | Kimi | Medium (owner-maintained) | 13+ | FTS5 + sqlite-vec | Signature search, 4-tier lookup |
| **KiroGraph** | Kiro | Early (44★, rapid dev) | 16+ | FTS5 + 6 engines | Architecture analysis, dashboard, snapshots |

**Key insight:** because the user owns `rwn34/kimigraph`, Kimi is NOT asymmetric. All three CLIs get first-class graph support. This changes the v1 plan's central assumption.

**Decision:** adopt all three tools in parallel, structural-only start, unified framework integration.

---

## Why parallel (not phased)

Claude's v1 plan argued for phased CodeGraph-first because:
- CodeGraph is mature; KiroGraph is experimental
- Two new deps = coupled failure modes
- Wanted to verify ≥50% tool-call reduction before expanding

**Kimi's counter:** these concerns are valid for external dependencies, but less so here because:
1. **KimiGraph is owner-controlled** — we can patch/fix Kimi-specific issues without waiting upstream
2. **All three share the same architecture** — failure modes are correlated (tree-sitter, SQLite, MCP), so phased verification doesn't isolate risk
3. **Framework integration cost is the bottleneck** — doing it once for all three is less total work than three sequential waves
4. **User explicitly asked for "better"** — leaving Kimi without graph support while Claude gets it contradicts the framework's parity principle

**Mitigation for risk:** start structural-only (no embeddings). That's where the 90%+ savings come from, and it removes the 130MB model-download variable.

---

## Tool-by-tool review

### CodeGraph (Claude)

**Strengths:**
- Best real-world benchmarks (92–94% tool-call reduction across 6 codebases)
- Simplest install: `npx @colbymchenry/codegraph` interactive installer
- File-watcher auto-sync using native OS events (FSEvents/inotify/ReadDirectoryChangesW)
- 19 languages including niche ones (Svelte, Liquid, Pascal/Delphi)

**Gaps vs others:**
- No semantic/vector search (FTS5 only)
- No architecture analysis, dashboard, or snapshots
- MCP tool count lowest (8 vs KimiGraph's 12 vs KiroGraph's 17)
- Global `~/.claude.json` config by default (project-local possible but not documented)

**Verdict:** adopt as-is. It's the reference implementation for "does the core job well."

### KimiGraph (Kimi)

**Strengths:**
- `sqlite-vec` for 768-dim semantic search (opt-in)
- 4-tier search: exact → FTS5 → semantic KNN → LIKE fallback
- Signature search (`string -> boolean`) for type-aware lookup
- 12 MCP tools including `dead_code`, `cycles`, `path`
- Honest limitations doc (rare and valuable)
- Owner-maintained (`rwn34`) — patch latency is under our control

**Gaps vs KiroGraph:**
- No architecture analysis or package coupling metrics
- No graph export/dashboard
- No snapshot/diff capability
- Single semantic engine (sqlite-vec) vs KiroGraph's 6

**Verdict:** adopt. The signature search and 4-tier lookup are unique assets. Owner control means we can extend it to match KiroGraph's features over time.

### KiroGraph (Kiro)

**Strengths:**
- Most feature-rich: architecture analysis, coupling metrics, hotspots, surprising connections
- Interactive graph export dashboard (offline HTML, no server)
- Snapshot/diff for structural change tracking
- 6 semantic engine backends (cosine, sqlite-vec, orama, pglite, lancedb, qdrant, typesense)
- Kiro hooks integration (no background watcher process needed)
- Caveman mode for token-efficient agent communication
- 17 MCP tools (most comprehensive)

**Gaps vs CodeGraph:**
- No published benchmark suite proving tool-call reduction
- Early maturity (44★, may have breaking changes)
- Kiro subagent hook-inheritance bug affects auto-sync for subagent writes

**Verdict:** adopt. The architecture analysis and dashboard are genuinely additive. The hook-based sync is elegant for Kiro's event model.

---

## Framework integration decisions

### 1. ADR-0001 amendment (Category E — AI framework)

Add three entries under Category E:

```markdown
- `.codegraph/` — CodeGraph local knowledge graph (Claude Code tool)
- `.kirograph/` — KiroGraph local knowledge graph (Kiro CLI tool)
- `.kimigraph/` — KimiGraph local knowledge graph (Kimi CLI tool)
```

All three are framework-adjacent dot-directories. Same category, same rationale.

### 2. `.gitignore` updates

Gitignore everything inside each tool dir EXCEPT `config.json`:

```gitignore
# Code knowledge graphs — local DBs and caches; keep config.json for shared settings
.codegraph/*
!.codegraph/config.json
.kirograph/*
!.kirograph/config.json
.kimigraph/*
!.kimigraph/config.json
```

Rationale: DB files can exceed 100 MB on large codebases and should not be committed. Config files contain indexing preferences (languages, exclude patterns) that teams should share.

### 3. MCP config placement

**Decision:** project-local `.mcp.json` for all three.

Each tool registers its own MCP server in `.mcp.json`:

```json
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["serve", "--mcp"]
    },
    "kimigraph": {
      "command": "kimigraph",
      "args": ["serve", "--mcp"]
    },
    "kirograph": {
      "command": "kirograph",
      "args": ["serve", "--mcp"]
    }
  }
}
```

This fits the framework's "everything a project needs is in the project" principle. Global config creates invisible per-machine state.

**Caveat:** CodeGraph's installer defaults to `~/.claude.json`. After running the installer, manually migrate the config block to `.mcp.json`.

### 4. Hook coexistence

| CLI | Our hooks | Graph hooks | Conflict? |
|---|---|---|---|
| Claude | `pretool-write-edit.sh` (preToolUse) | CodeGraph file watcher (OS-level, no hooks) | None |
| Kimi | `pretool-write-edit.sh` (postToolUse) | KimiGraph file watcher (OS-level, no hooks) | None |
| Kiro | `preToolUse` × 4 matchers | `fileEdited`, `fileCreated`, `fileDeleted`, `agentStop` | None — different events |

All three coexist without collision. The Kiro subagent hook-inheritance bug affects KiroGraph's auto-sync for subagent writes. Document in `.ai/known-limitations.md`.

### 5. Write boundaries

| CLI | Can write to | Cannot write to |
|---|---|---|
| Claude | `.codegraph/**` | `.kirograph/**`, `.kimigraph/**` |
| Kimi | `.kimigraph/**` | `.codegraph/**`, `.kirograph/**` |
| Kiro | `.kirograph/**` | `.codegraph/**`, `.kimigraph/**` |

Update each CLI's `pretool-write-edit.sh` (or equivalent) to block cross-CLI graph dir writes.

### 6. Framework test suite updates

Add 2 tests per CLI suite:
- Allow write to own graph dir
- Block write to other CLIs' graph dirs

Total: +6 tests. SSOT drift-check unaffected.

### 7. Kimi CLI — no longer asymmetric

Kimi gets KimiGraph (`rwn34/kimigraph`). Install: `npm install -g rwn-kimigraph`.

This resolves the v1 plan's biggest open question.

### 8. Install sequence

**Parallel, all three at once:**

1. All CLIs update their hook tests (+2 tests each)
2. Claude amends ADR-0001 + `.gitignore`
3. Each CLI installs its own tool independently:
   - Claude: `npx @colbymchenry/codegraph` → migrate MCP config to `.mcp.json`
   - Kimi: `npm install -g rwn-kimigraph` → `kimigraph install`
   - Kiro: `npm install -g kirograph` → `kirograph install`
4. Each CLI commits its initial `config.json` (structural-only)
5. Each CLI adds graph-aware steering instructions
6. Verify test suites green across all three

### 9. Semantic embeddings decision

**Start structural-only for all three.** Rationale:
- Structural indexing alone delivers the benchmarked 90%+ tool-call reduction
- Embeddings add 130MB+ model download per CLI per machine
- Easier to turn ON later than to turn OFF
- Keeps initial adoption lightweight

Document in each `config.json` that embeddings are available as opt-in.

---

## Risks / blockers

1. **Kiro subagent hook inheritance (upstream #7671)** — KiroGraph auto-sync misses subagent writes. Known limitation, document in `.ai/known-limitations.md`.
2. **CodeGraph global config default** — requires manual migration to `.mcp.json`. Document in README.
3. **Three 3rd-party dependencies** — all MIT, all local, but external surface area. Mitigation: KimiGraph is owner-controlled.
4. **Index staleness** — silent failure mode when auto-sync doesn't fire. Mitigation: all three tools support manual `sync` command; document in steering.
5. **Disk footprint** — 3 SQLite DBs if all three index the same project. Acceptable: each is 1–5 MB per 100 files. If problematic, users can exclude the other CLIs' framework dirs from indexing.
6. **KimiGraph Windows OOM** — loading many tree-sitter WASM grammars can exhaust V8 zone memory on Windows. Workaround: `NODE_OPTIONS="--max-old-space-size=4096"`. Documented in KimiGraph README.

---

## What "better" looks like

After adoption, the multi-CLI framework has:

- **Instant codebase understanding** for all three CLIs — no more 10+ file reads to answer "how does auth work?"
- **Consistent integration patterns** — same ADR treatment, same gitignore strategy, same test coverage
- **3-CLI parity** — no CLI is second-class
- **Owner-controlled Kimi toolchain** — KimiGraph can be extended to match KiroGraph's features over time
- **Shared learnings across tools** — improvements in one can be ported to the others (all TypeScript/SQLite/tree-sitter)

---

## Execution checklist

- [ ] ADR-0001 amended (Claude)
- [ ] `.gitignore` updated (Claude)
- [ ] `.mcp.json.example` updated with graph servers (Kimi)
- [ ] `.claude/hooks/test_hooks.sh` +2 tests (Claude)
- [ ] `.kimi/hooks/test_hooks.sh` +2 tests (Kimi)
- [ ] `.kiro/hooks/test_hooks.sh` +2 tests (Kiro)
- [ ] CodeGraph steering added to `CLAUDE.md` + `.claude/agents/orchestrator.md` (Claude)
- [ ] KimiGraph steering added to `.kimi/steering/` (Kimi)
- [ ] KiroGraph steering added to `.kiro/steering/` (Kiro)
- [ ] `.ai/known-limitations.md` updated with staleness + Kiro hook bug (orchestrator)
- [ ] Initial `config.json` committed per CLI (each CLI)
- [ ] All test suites pass (CI)
- [ ] README updated with graph quick-start (doc-writer)
