# Remove KiroGraph entirely (owner directive 2026-07-09 — ADR-0003 amendment)
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 10:41
Auto: yes
Risk: B

## Goal
Owner directive: KiroGraph malfunctions more than it works — your dispatched
session on 2026-07-09 logged "One or more mcp server did not load correctly"
(kirograph). Remove it entirely rather than keep repairing it. CodeGraph
(Claude's) is now the sole code-knowledge graph (ADR-0003 amendment
2026-07-09, single-graph topology). Your side of the removal.

## Current state
- KiroGraph MCP registered in `.kiro/settings/mcp.json`
  (`"command": "kirograph", "args": ["serve", "--mcp"]`, global install
  2026-06-08 per handoff 202606082231) — this is the source of your MCP
  load warning (the global binary is being uninstalled by claude-code's
  batch, so the entry is now dangling).
- `.kiro/steering/kirograph.md` steering file exists.
- `.kirograph/` config/index dir exists (config.json tracked).
- The code-graphs SSOT (`.ai/instructions/code-graphs/principles.md`) has
  been reduced to CodeGraph-only (see the `feat(graphs)!` commit on this
  branch); your `.kiro/steering/code-graphs.md` replica is now stale.

## Steps
1. Remove the kirograph server entry from `.kiro/settings/mcp.json`.
2. Delete `.kiro/steering/kirograph.md` (git rm if tracked).
3. Delete `.kirograph/` (git rm -r for tracked config.json; plain delete
   for gitignored db/cache).
4. Regenerate `.kiro/steering/code-graphs.md` from the updated SSOT per
   `.ai/sync.md`.
5. `grep -rin kirograph .kiro/` — zero operative hits afterward.
6. `bash .kiro/hooks/test_hooks.sh` — paste PASS count (update any test
   referencing kirograph paths).
7. `bash .ai/tools/check-ssot-drift.sh` — zero `.kiro/` lines (paste).
8. Activity-log entry (identity `kiro-cli`), handoff Status DONE + move to
   done/. Leave commits to claude-code if your lane has no git.

## Report back with
(a) mcp.json grep evidence (entry gone), (b) drift line, (c) hook PASS
count, (d) confirmation the next kiro session starts without the MCP
warning if verifiable headless.

---

## Completion report (kiro-cli, 2026-07-09 10:41)

Done. All 8 steps executed. Handoff under-enumerated the artifacts — grep
surfaced 4 auto-sync hook JSONs and the t5a allow-test beyond the 3 listed;
all removed/updated.

**What was removed**
- `.kirograph/` dir: `git rm` config.json (tracked) + plain-removed gitignored
  `kirograph.db`, `token-savings.jsonl`, `.session-id`. Dir gone (`Test-Path .kirograph` → False).
- 4 auto-sync hooks (`git rm`): `kirograph-mark-dirty-on-create.json`,
  `kirograph-mark-dirty-on-save.json`, `kirograph-sync-if-dirty.json`,
  `kirograph-sync-on-delete.json`.
- `.kiro/steering/code-graphs.md` regenerated from SSOT (CodeGraph-only).
- No-ops: mcp.json already had empty `mcpServers`; `.kiro/steering/kirograph.md`
  never existed.

**Tombstone (per SSOT "hook rules blocking writes retained against recreation")**
- framework-dir-guard.sh now BLOCKs `.kirograph/*` (exit 2); test t5a flipped allow→block.

**Report-back answers**
- (a) mcp.json entry gone: `.kiro/settings/mcp.json` → `{ "mcpServers": {} }` — no `kirograph` key.
- (b) drift: `bash .ai/tools/check-ssot-drift.sh` → `Checked: 24 replicas, Drift: 0`.
- (c) hooks: `bash .kiro/hooks/test_hooks.sh` → `PASS: 32/32` (incl. `t5a block .kirograph (removed)`).
- (d) MCP warning: mcpServers is empty so no server is launched → no load warning
  is possible on the next session. Not separately headless-verified (no dispatched
  kiro session run this turn); the empty registry is the mechanical guarantee.

**Lane note:** deletions/edits staged via `git rm`; per handoff, commits left to
claude-code. Remaining `kirograph` string hits under `.kiro/` are non-operative:
the code-graphs.md removal notice (SSOT replica) + the guard tombstone + its test.
