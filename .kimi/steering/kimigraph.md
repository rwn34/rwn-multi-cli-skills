# KimiGraph

KimiGraph is a semantic code knowledge graph for Kimi CLI. It parses source code with tree-sitter, stores symbols and relationships in a local SQLite database, and exposes MCP tools for instant codebase exploration.

**Repo:** https://github.com/rwn34/kimigraph  
**Install:** `npm install -g rwn-kimigraph`

---

## When KimiGraph is active

If `.kimigraph/` exists in the project, use `kimigraph_explore` as your PRIMARY exploration tool. It returns full source sections for all relevant symbols in one call, replacing 10+ file reads.

**Rules:**
1. Spawn an Explore agent for broad questions ("how does X work?"). Include: "This project has KimiGraph initialized. Use `kimigraph_explore` as your PRIMARY tool."
2. Do NOT re-read files that `kimigraph_explore` already returned source code for.
3. Only fall back to `grep`/`glob`/`ReadFile` for files listed under "Additional relevant files" or if KimiGraph returns no results.
4. The main session may use lightweight tools directly: `kimigraph_search`, `kimigraph_callers`, `kimigraph_callees`, `kimigraph_impact`, `kimigraph_node`.

## When KimiGraph is NOT active

At the start of a session, ask the user:

> "I notice this project doesn't have KimiGraph initialized. Would you like me to run `kimigraph init` to build a code knowledge graph?"

## Quick reference

| Tool | Use for |
|------|---------|
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

## Limitations

- Dynamic imports, reflection, and runtime-generated calls are invisible to static analysis.
- Semantic embeddings are opt-in (`enableEmbeddings: true` in `.kimigraph/config.json`).
- On Windows, indexing many languages may require `NODE_OPTIONS="--max-old-space-size=4096"`.
- The index auto-syncs via file watcher. If the watcher misses changes, run `kimigraph sync` manually.
