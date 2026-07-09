# Regenerate Kiro steering replicas + release-engineer wording — OpenCode replaces Crush (ADR-0002 amendment 2026-07-09)
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 09:16
Auto: yes
Risk: B
Completed: 2026-07-09 09:13 by kiro-cli

## Goal
Clear the 4 Kiro-side drift lines and the deploy-lane wording in your agent
config: your steering replicas still describe Crush as the 4th CLI / deploy
operator. The SSOTs in `.ai/instructions/` were updated in commit `8d615de`
(task 8 of the swap workstream).

## Current state
- ADR-0002 + ADR-0001 amended (owner-approved): OpenCode replaces Crush —
  same lane (general helper + Stage-2 deploy operator), identity
  `crush` → `opencode`, inbox `to-crush/` → `to-opencode/` (already
  renamed on disk).
- `bash .ai/tools/check-ssot-drift.sh` currently reports Drift: 8 — ALL
  eight lines are `.kimi/` + `.kiro/` replicas (Claude's are clean).
- Your four stale replicas:
  `.kiro/steering/{operating-prompt,orchestrator-pattern,agent-catalog,code-graphs}.md`
- Additionally: `.kiro/agents/release-engineer.json` says Crush is the
  primary DevOps deployment operator (fallback-lane wording) — must say
  OpenCode (parity with `.claude/agents/release-engineer.md`, already
  updated in `8d615de`).
- `.kiro/steering/operating-prompt.md:4` also names Crush in its intro line
  (`**Kiro CLI**, or **Crush** — working inside a shared project
  workspace.`) — regeneration from SSOT should cure this; verify it did.

## Target state
- All four replicas regenerated from their SSOTs
  (`.ai/instructions/<name>/principles.md`) per the replica procedure in
  `.ai/sync.md` (keep your replica preamble convention, replace the body).
- `.kiro/agents/release-engineer.json` deploy-lane wording → OpenCode.
- `bash .ai/tools/check-ssot-drift.sh` → zero `.kiro/` drift lines.
- Grep your OWN files (`.kiro/steering/*.md`, `.kiro/hooks/*`,
  `.kiro/agents/*.json`) for any other operative `crush` reference and
  update; historical references may stay.

## Steps
1. Regenerate the 4 replicas from SSOT per `.ai/sync.md`.
2. Update `.kiro/agents/release-engineer.json` wording.
3. `grep -rin crush .kiro/` — fix operative hits, list what you left as
   historical.
4. Run `bash .ai/tools/check-ssot-drift.sh` — paste the summary line
   (expect: no .kiro lines; .kimi lines may remain if Kimi hasn't run yet).
5. Run `bash .kiro/hooks/test_hooks.sh` — paste PASS count (expect 32/32
   unchanged unless step 3 found hook references).
6. Prepend an activity-log entry (identity `kiro-cli`), set this handoff
   Status: DONE with a closure note, move it to
   `.ai/handoffs/to-kiro/done/`. Commit your files + the handoff move on
   the current branch and push if your session has git access; otherwise
   leave committed-state note for claude-code.

## Verification
Drift-check summary line + grep evidence per self-grep-verify (Tier 1).

## Report back with
(a) drift-check output, (b) hook-suite PASS count, (c) release-engineer.json
wording evidence line, (d) commit hash or "left uncommitted".
