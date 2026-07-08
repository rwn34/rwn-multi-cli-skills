# Fleet-upgrade continuation — context + next steps (session moved to owner's PC)
Status: OPEN
Sender: claude-code (remote cloud session, 2026-07-07)
Recipient: claude-code (owner's PC)
Created: 2026-07-07 13:30
Auto: no

## Why this handoff exists

The owner ended the remote (cloud) Claude session and is continuing on their
PC. This file carries the full closing context so the next Claude session can
continue without re-deriving anything. Read it top to bottom before acting.

## Current state (as of this handoff)

1. **Template repo (this repo):** ALL of today's work lives on branch
   `claude/project-overview-pn5l4e` (HEAD ≈ `47ac12d` + this handoff commit).
   **NOT merged to master yet.** Contents: drift fixes, ADR-0002 (CLI role
   topology), ADR-0003 (code-graph rationalization), Crush onboarding
   (CRUSH.md + custodianship), hook Rule 2.5 (main-thread delegation
   enforcement, live-verified), dispatch-handoffs.sh + `Auto:` field,
   operating-prompt SSOT (6 SSOTs, 21 drift pairs), 32-test Claude hook suite.
2. **rwn-4AI-panes (owner's PC):** upgraded to this branch's state on its
   local branch `framework-upgrade-adr0002`, HEAD `0dcbe73`, reviewed and
   APPROVED by the remote session. All gates green there (drift 21/0, hooks
   37/37 / 35/35 / 31/31, real Rule 2.5 probes on `docs/hook-probe.tmp`).
   Not yet merged to its default branch, not pushed.
3. **Kimi/Kiro:** their in-repo files here were updated directly with owner
   authorization (handoffs 202607071115/1116, now in `done/`). Nothing is
   waiting on them.

## The open problem — stale framework configs across the fleet

4AI-panes is a launcher: its Selector opens ANY project, and each CLI reads
THAT project's framework files. Projects with older installs behave on the
OLD rules when opened:

| Pane | Behavior in an old-framework project |
|---|---|
| Claude | No Rule 2.5 (orchestrator can write source), NNN handoff refs, no operating-prompt, no role lanes |
| Kimi/Kiro | release-engineer still has a deploy lane; no peer-review flow |
| Crush | **Worst**: `crush --yolo` with NO CRUSH.md — no contract, no SAFETY RULES at all |
| All | Old cross-wired graph MCP configs → 3 graph servers attempt startup → the MCP connection errors ADR-0003 was written to end |

Old installs are self-consistent (nothing crashes), but you get per-project
behavioral drift and a real safety regression in the Crush pane. Detection
can't live in old projects' own hooks (they ARE the old install).

## Agreed coverage plan (3 layers)

1. **Selector badge (4AI-panes repo):** Selector.ps1 reads
   `.ai/.framework-version` per project and shows `⚠ outdated / ✔ current /
   – none` (absence of the marker itself means "old").
2. **Upgrade runbook (THIS repo):** turn the battle-tested 4AI-panes upgrade
   prompt into `docs/guides/framework-upgrade-runbook.md` — generic
   sync-template → preserve → copy → adapt → verify procedure, INCLUDING the
   two lessons learned: (a) the Rule 2.5 probe must target a project-source
   path (e.g. `docs/hook-probe.tmp`), NOT `.ai/` (allowed for everyone —
   proves nothing); (b) merge `.ai/known-limitations.md` (Crush entry) — it
   was missing from the original copy list; (c) write `.ai/.framework-version`
   at the end (the 4AI-panes upgrade did NOT do this — small fixup needed
   there).
3. **Installer alignment + --upgrade (durable fix):** `tools/multi-cli-install`
   is out of line with ADR-0003 (its `wire-mcp.ts` wires all 3 graphs to all
   4 CLIs) and its assets predate CRUSH.md / operating-prompt / Rule 2.5
   hooks. Align assets, then implement `--upgrade` per
   `.ai/research/framework-upgrade-mode-plan.md` (Phase A =
   `.ai/.framework-version` marker, already stamped by fresh installs).

## Task queue for the next session (recommended order)

1. Merge `claude/project-overview-pn5l4e` → master here (owner approves).
2. In 4AI-panes: merge `framework-upgrade-adr0002` → default branch; then a
   small fixup: write `.ai/.framework-version` + add the Selector badge
   (layer 1).
3. Here: installer asset alignment + `docs/guides/framework-upgrade-runbook.md`
   (layers 2-3; delegate coder/tester/doc-writer; gates: vitest 83+,
   `tsc --noEmit`, drift 21/0, hooks 32/32).
4. Fleet: upgrade other old projects lazily via the runbook (or installer
   `--upgrade` once it lands).

## Owner's manual items (cannot be done by any session)

- Strip graph entries from `~/.kimi/mcp.json` / `~/.kimi/config.toml`
  (ADR-0003; user-global files).
- Review template-repo stash (`git stash list`) — contains pre-switch master
  work incl. a `0002-worktree-multi-project-topology.md`; if real, it needs
  RENUMBERING (0002/0003 are taken by the pushed ADRs).

## Small known follow-ups (nice-to-have)

- Kiro `release-engineer.json` prompt body still says "Handle versioning,
  tagging, and publishing" after the ADR-0002 no-deploy prefix — reword.
- Kimi/Kiro runtime-level delegation enforcement (Rule 2.5 equivalents) was
  deferred — needs their CLIs present to test.
- `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` could use a
  "superseded in part by ADR-0003" banner.

## When complete

Work through the task queue (each item is its own commit with gates green +
activity-log entry). Move this file to `.ai/handoffs/to-claude/done/` once
items 1-3 are done; items under "Owner's manual items" stay with the owner.
