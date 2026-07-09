# Remove KimiGraph entirely (owner directive 2026-07-09 — ADR-0003 amendment)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 10:40
Completed: 2026-07-09 10:43
Auto: yes
Risk: B

## Goal
Owner directive: KimiGraph malfunctions more than it works — remove it
entirely rather than keep repairing it. CodeGraph (Claude's) is now the
sole code-knowledge graph (ADR-0003 amendment 2026-07-09, single-graph
topology). Your side of the removal.

## Current state
- KimiGraph MCP registered in your global `~/.kimi/config.toml` (installed
  2026-06-08 per handoff 202606082230).
- `.kimi/steering/kimigraph.md` steering file exists.
- `.kimigraph/` config/index dir exists in the repo.
- The code-graphs SSOT (`.ai/instructions/code-graphs/principles.md`) has
  been reduced to CodeGraph-only (see the `feat(graphs)!` commit on this
  branch); your `.kimi/steering/code-graphs.md` replica is now stale.

## Steps
1. Remove the kimigraph MCP server entry from `~/.kimi/config.toml`
   (BOTH duplicate hook/config blocks if it appears twice — you noted
   duplicate blocks on 2026-07-09). Also remove any project-level kimigraph
   MCP wiring if present.
2. Delete `.kimi/steering/kimigraph.md` (git rm if tracked).
3. Delete `.kimigraph/` (git rm -r for tracked files like config.json;
   plain delete for gitignored db/cache).
4. Regenerate `.kimi/steering/code-graphs.md` from the updated SSOT per
   `.ai/sync.md`.
5. `grep -rin kimigraph .kimi/ ~/.kimi/config.toml` — zero operative hits
   afterward (historical mentions in comments acceptable only if dated).
6. `bash .kimi/hooks/test_hooks.sh` — paste PASS count (update any test
   that references kimigraph paths).
7. `bash .ai/tools/check-ssot-drift.sh` — zero `.kimi/` lines (paste).
8. Activity-log entry (identity `kimi-cli`), handoff Status DONE + move to
   done/, commit + push your files if your session has git access.

## Report back with
(a) config.toml grep evidence (entry gone), (b) drift line, (c) hook PASS
count, (d) commit hash or "left uncommitted".
