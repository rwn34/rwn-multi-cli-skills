# Re-index KiroGraph to include the installer source (drop tools/** exclude)
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-06-08 22:46
Completed: 2026-06-08 22:49 (kiro-cli)
Validated: 2026-06-08 23:20 (claude-code) — see ## Validation

## Validation
claude-code read `.kirograph/config.json` and confirmed:
- `exclude` no longer contains `tools/multi-cli-install/**`; keeps `tools/kirograph/**`. PASS.
- Kiro evidence: index grew 15→90 files, 13→701 symbols, 0→645 relationships;
  `kirograph_search wireMcp` → `tools/multi-cli-install/src/installer/wire-mcp.ts:11`. PASS.
KiroGraph now indexes the primary source. Handoff satisfied.

## Goal
Make KiroGraph's index actually cover this repo's code. Right now it excludes the
primary TypeScript source, so the graph is nearly empty (15 files / 13 symbols)
and can't answer code questions about the installer.

## Current state
Per your completed handoff 202606082231, `.kirograph/config.json` `exclude`
currently contains BOTH:
- `tools/kirograph/**` — fine to exclude (that's the graph tool's own source)
- `tools/multi-cli-install/**` — **this is the repo's main TypeScript codebase**
  (the framework installer: `src/installer/*`, `bin/`, `src/upgrade/*`, tests).
  Excluding it is why `kirograph status` reports only 15 files / 13 symbols.

For comparison, Claude's `.codegraph/config.json` does NOT exclude
`tools/multi-cli-install` — CodeGraph indexes that source, which is the whole
point of having a code graph here.

## Target state
- `.kirograph/config.json` `exclude` keeps `tools/kirograph/**` but **removes**
  `tools/multi-cli-install/**` (keep the other excludes: node_modules, dist,
  build, .git, .kirograph, .codegraph, .kimigraph, .archive).
- Re-index so `kirograph status` reflects the real codebase (should jump well
  above 15 files / 13 symbols once the installer TS is included).
- MCP still connects and returns results.

## Steps
1. Edit `.kirograph/config.json` — delete the `"tools/multi-cli-install/**"`
   entry from `exclude`. Leave `"tools/kirograph/**"` in place.
2. Re-run the index (`kirograph sync` / `kirograph index` — per its CLI).
3. Verify the new counts and that a query over the installer code returns nodes
   (e.g. search for `wireMcp` or `buildManifestFromInstalledTree`, which live in
   `tools/multi-cli-install/src/`).
4. Prepend an activity-log entry; commit the updated `.kirograph/config.json`.

## Verification
- (a) `exclude` no longer contains `tools/multi-cli-install/**`.
- (b) `kirograph status` shows a materially higher file/symbol count.
- (c) A KiroGraph query for a known installer symbol (e.g. `wireMcp`) returns it.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: per handoff 202606082246 — re-indexed KiroGraph to include installer source
    - Files: .kirograph/config.json
    - Decisions: <any>

## Report back with
- (a) the new `exclude` list
- (b) before/after `kirograph status` counts
- (c) a sample query result for an installer symbol (e.g. `wireMcp`)

## When complete
Sender (claude-code) validates by reading `.kirograph/config.json` + confirming
the exclude no longer drops the installer source. On success the file moves to
`.ai/handoffs/to-kiro/done/`.
