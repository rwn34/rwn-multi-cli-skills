# Make KimiGraph functional (index + working MCP), parity with CodeGraph
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-06-08 22:30
Completed: 2026-06-08 23:15 (kimi-cli)
Validated: 2026-06-08 23:25 (claude-code) — see ## Validation

## Validation
claude-code read the touched files and confirmed:
- `~/.kimi/mcp.json` — migrated from the local dev path to bare
  `command: kimigraph, args: [serve, --mcp]` (parity with codegraph/kirograph). PASS.
- `.kimigraph/config.json` — present + functional (broad language set, excludes). PASS.
- Kimi evidence: `rwn-kimigraph@0.3.0`; index 925 files / 25,228 symbols / 67 MB DB;
  `kimigraph_search` MCP call returns results. 25k symbols confirms the primary
  source is indexed (no under-indexing). PASS.
- Same benign stale-PATH caveat as CodeGraph/KiroGraph — resolves on Kimi restart.
KimiGraph is functional. Handoff satisfied.

## Goal
Bring KimiGraph from docs-only to actually functional — a built `.kimigraph/`
index + an MCP server Kimi can query — matching what the user just set up for
Claude's CodeGraph this session.

## Why now — the pending decision is resolved
The 2026-04-26 adoption work deliberately stopped at "structural-only" (steering
+ hook denies + tests + `.mcp.json.example`) because the **embeddings-on vs
structural-only** question was unresolved (see the CANCELLED tombstone
`.ai/handoffs/to-kimi/done/202604261200-adopt-kimigraph.md`, "Outstanding
Kimi-side work"). The user has now resolved it toward **functional/embeddings-on**:
this session they installed `codegraph@0.9.9` globally, built
`.codegraph/codegraph.db`, and wired `.mcp.json` so Claude's graph actually
connects. They asked to "fix everything" — i.e. bring KimiGraph to the same
functional state.

## Current state
- Docs only: `.kimi/steering/code-graphs.md`, `.kimi/steering/kimigraph.md`
  (the latter is currently untracked).
- **No** `.kimigraph/` directory, **no** `.kimigraph/config.json`, **no** index db.
- **No** MCP registration for kimigraph anywhere in Kimi's config (neither a
  project `.kimi/` mcp file nor `~/.kimi/config.toml`).
- Root `.gitignore` already carries `.kimigraph/*` + `!.kimigraph/config.json`,
  so once you create `.kimigraph/config.json` it is git-tracked while the db/cache
  stay ignored — same pattern as `.codegraph/`.

## Target state
- `kimigraph` installed and resolvable (the `.mcp.json.example` documents
  `npm install -g rwn-kimigraph`).
- `.kimigraph/config.json` created (your include/exclude set) and committed.
- `.kimigraph/` index built for this repo.
- KimiGraph MCP server registered in Kimi's config and **verified connecting**
  (a tool call returns results).
- Activity-log entry prepended; `.kimigraph/config.json` committed (do NOT commit
  the db/cache — gitignored).

## Context (reference only, NOT binding — pick what fits Kimi's conventions)
How Claude set up CodeGraph this session, for comparison:
- Install: `npm install -g @colbymchenry/codegraph` (global binary on PATH).
- `.codegraph/config.json`: `include`/`exclude` glob arrays, `maxFileSize`,
  `extractDocstrings`, `trackCallSites`.
- MCP entry (`.mcp.json`): `{ "command": "codegraph", "args": ["serve", "--mcp"] }`.
- Index db at `.codegraph/codegraph.db` (gitignored).
- Note: after a global install the bare command may not resolve until the
  terminal/CLI session restarts (stale PATH snapshot) — factor that into your
  verification.

## Steps
1. Install kimigraph (`npm install -g rwn-kimigraph`, or whatever the current
   distribution is — verify the package/bin name first).
2. Initialize `.kimigraph/config.json` for this repo (mirror the
   `.codegraph/config.json` include/exclude intent; adjust to Kimi's schema).
3. Build the index (`kimigraph index` / `kimigraph sync` — per its CLI).
4. Register the KimiGraph MCP server in Kimi's config (project `.kimi/` or
   `~/.kimi/config.toml`, whichever Kimi actually loads — note the framework's
   prior finding that project-level `.kimi/config.toml` is NOT auto-loaded; the
   install docs append `.ai/config-snippets/kimi-hooks.toml` to `~/.kimi/`).
5. Verify it connects and a query returns results.
6. Prepend an activity-log entry; commit `.kimigraph/config.json` only.

## Verification
- (a) `kimigraph --version` (or equivalent) resolves.
- (b) `.kimigraph/config.json` exists and is committed; db/cache are gitignored.
- (c) A KimiGraph MCP tool call returns real results for this repo.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: per handoff 202606082230 — made KimiGraph functional (install + index + MCP)
    - Files: .kimigraph/config.json, <kimi mcp config path>
    - Decisions: <global vs local build, schema choices>

## Report back with
- (a) the `.kimigraph/config.json` path + the MCP-config file you registered in
- (b) the exact install + index commands you ran
- (c) verification output proving the MCP server connects and returns results
- (d) whether a session restart was needed for the binary to resolve

## When complete
Sender (claude-code) validates by reading the touched files + confirming the
`.kimigraph/config.json` and MCP registration exist. On success the file moves to
`.ai/handoffs/to-kimi/done/`. On failure it stays in `open/` as `BLOCKED` with a
`## Blocker` section.
