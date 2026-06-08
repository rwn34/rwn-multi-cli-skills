# Fix KiroGraph's dangling MCP config + make it functional, parity with CodeGraph
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-06-08 22:31
Completed: 2026-06-08 22:41 (kiro-cli)
Validated: 2026-06-08 22:45 (claude-code) — see ## Validation

## Validation
claude-code read the two touched files and confirmed:
- `.kiro/settings/mcp.json` — dangling `tools/kirograph/dist/...` path removed;
  now `command: kirograph, args: [serve, --mcp]` (global, resolves after restart). PASS.
- `.kirograph/config.json` — present + reconciled, db/cache gitignored. PASS.
- Kiro evidence: `kirograph@0.20.0`, index 15 files/13 symbols, `kirograph_status`
  MCP call returns results. PASS.

OBSERVATION (not a blocker): the config `exclude` list drops `tools/kirograph/**`
AND `tools/multi-cli-install/**` — the latter is this repo's primary TypeScript
source, which is why the index is only 15 files/13 symbols. CodeGraph does NOT
exclude `tools/multi-cli-install`. If Kiro wants the graph to actually cover the
installer code, re-index without that exclude. Left to Kiro's discretion since
indexing scope is its call.

## Goal
Fix KiroGraph's broken MCP registration (it points at a build that doesn't
exist) and bring KiroGraph to functional parity with Claude's CodeGraph — a
built `.kirograph/` index + an MCP server Kiro can actually query.

## Why now — the pending decision is resolved
KiroGraph adoption stopped at structural-only (steering + tests) pending the
**embeddings-on vs structural-only** decision (see the CANCELLED tombstone
`.ai/handoffs/to-kiro/done/202604261200-adopt-kirograph.md`). The user has now
resolved it toward **functional**: this session they installed `codegraph@0.9.9`
globally, built `.codegraph/codegraph.db`, and wired `.mcp.json` for Claude.
They asked to "fix everything" — bring KiroGraph to the same functional state.

## Current state (what I found — read-only inspection)
- **Dangling MCP registration:** `.kiro/settings/mcp.json` registers kirograph as
  `"command": "node", "args": ["tools/kirograph/dist/bin/kirograph.js", "serve",
  "--mcp"]` — but **`tools/kirograph/` does not exist** in this repo. So Kiro
  cannot launch the server; it would error on startup.
- `.kirograph/config.json` exists but is currently **tracked + modified +
  uncommitted** (release-engineer left it alone this session — it's your
  territory). Needs reconciling/committing.
- `.kiro/steering/kirograph.md` exists (currently untracked, docs).
- **No** `.kirograph/` index db.
- Root `.gitignore` already carries `.kirograph/*` + `!.kirograph/config.json`
  (same tracked-config / ignored-db pattern as `.codegraph/`).

## Target state
- A working KiroGraph: pick ONE install approach and make the MCP config match it:
  - **Global** (matches how Claude's CodeGraph + `.mcp.json.example` are set up):
    `npm install -g kirograph`, then `.kiro/settings/mcp.json` →
    `{ "command": "kirograph", "args": ["serve", "--mcp"] }`; OR
  - **Local build:** actually create/build `tools/kirograph/dist/...` so the
    existing `node tools/kirograph/dist/bin/kirograph.js` path resolves.
- `.kirograph/` index built for this repo.
- `.kirograph/config.json` reconciled and committed.
- MCP server **verified connecting** (a tool call returns results).
- Activity-log entry prepended.

## Context (reference only, NOT binding)
How Claude set up CodeGraph this session, for comparison:
- `npm install -g @colbymchenry/codegraph`; `.mcp.json` entry
  `{ "command": "codegraph", "args": ["serve", "--mcp"] }`; index db at
  `.codegraph/codegraph.db` (gitignored); `.codegraph/config.json` holds
  include/exclude globs.
- Gotcha: after a global install the bare command may not resolve until the
  terminal/Kiro session restarts (stale PATH snapshot).

## Steps
1. Decide global-install vs local-build (recommend global for consistency with
   CodeGraph + `.mcp.json.example`, but your call).
2. Install/build kirograph accordingly.
3. **Fix `.kiro/settings/mcp.json`** so the command actually resolves (remove the
   dangling `tools/kirograph/dist/...` path if going global).
4. Ensure `.kirograph/config.json` is correct; build the `.kirograph/` index.
5. Verify the MCP server connects and a query returns results.
6. Prepend an activity-log entry; commit `.kirograph/config.json` (+ the
   `.kiro/settings/mcp.json` fix). Do NOT commit the db/cache (gitignored).

## Verification
- (a) `.kiro/settings/mcp.json` command resolves (no dangling path).
- (b) `kirograph --version` (or the built entrypoint) runs.
- (c) `.kirograph/config.json` committed; db/cache gitignored.
- (d) A KiroGraph MCP tool call returns real results for this repo.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: per handoff 202606082231 — fixed dangling KiroGraph MCP + made it functional
    - Files: .kiro/settings/mcp.json, .kirograph/config.json
    - Decisions: <global install vs local build, etc.>

## Report back with
- (a) the final `.kiro/settings/mcp.json` kirograph entry (command + args)
- (b) install/build approach + exact commands
- (c) verification output proving the MCP server connects and returns results
- (d) whether a session restart was needed for the binary to resolve

## When complete
Sender (claude-code) validates by reading the touched files + confirming the
MCP registration no longer dangles and `.kirograph/config.json` is committed. On
success the file moves to `.ai/handoffs/to-kiro/done/`. On failure it stays in
`open/` as `BLOCKED` with a `## Blocker` section.
