# Handoff: regenerate SSOT replicas (role lanes + write-scope caveat), fix stale NNN ref, scope down release-engineer

- Status: OPEN
- Created: 2026-07-07 11:16 (claude-code local)
- From: claude-code
- To: kiro-cli

## Context

Two SSOTs were updated by Claude (commit on branch `claude/project-overview-pn5l4e`):

1. `.ai/instructions/agent-catalog/principles.md` — added (a) a **per-CLI
   nuance** paragraph under "Framework directories" (orchestrator write scope
   is own dir + `.ai/` only; cross-CLI via handoffs, hook-enforced), and
   (b) a new **"CLI role lanes (ADR-0002)"** section.
2. `.ai/instructions/orchestrator-pattern/principles.md` — added a new
   **"CLI role lanes (ADR-0002)"** section (before "Failure handling").

New ADR: `docs/architecture/0002-cli-role-topology.md` — read it first. Key
points affecting Kiro: Kiro = premium-reasoning executor, peer-reviews Kimi's
work; **Kiro has NO deploy lane** (deploy actions out of scope for Kiro's
`release-engineer`).

## Steps

1. Regenerate your steering replicas from the updated SSOTs (per `.ai/sync.md`):
   ```
   cp .ai/instructions/agent-catalog/principles.md      .kiro/steering/agent-catalog.md
   cp .ai/instructions/orchestrator-pattern/principles.md .kiro/steering/orchestrator-pattern.md
   ```
1b. ALSO regenerate your `code-graphs` replica — the drift checker found it
   stale (still says "all three CLIs"; SSOT now says four incl. Crush):
   ```
   cp .ai/instructions/code-graphs/principles.md .kiro/steering/code-graphs.md
   ```
2. Fix the stale handoff-filename reference in `.kiro/steering/00-ai-contract.md`
   (~line 39): `NNN-slug.md` → `YYYYMMDDHHMM-slug.md` (canonical per
   `.ai/handoffs/README.md`).
3. Per ADR-0002: scope down `.kiro/agents/release-engineer.json` so deploy
   actions are excluded. Keep version bumps / CHANGELOG / tag *preparation*;
   remove/deny production deploy + publish execution — prefer your hard
   `toolsSettings.execute_bash.allowedCommands` mechanism. Add a comment/note
   referencing ADR-0002. You own the how, ADR-0002 owns the what.

## Report back with

- Grep evidence (Tier 1): the "CLI role lanes" heading present in both
  `.kiro/steering/` replicas; the timestamp-format line in `00-ai-contract.md`;
  the ADR-0002 reference in `release-engineer.json`.
- `bash .ai/tools/check-ssot-drift.sh` output (expect 0 drift).
- Activity log entry prepended.
