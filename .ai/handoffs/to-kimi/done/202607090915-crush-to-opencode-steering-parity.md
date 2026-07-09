# Regenerate Kimi steering replicas — OpenCode replaces Crush (ADR-0002 amendment 2026-07-09)
Status: DONE — 2026-07-09 by kimi-cli: four steering replicas regenerated from SSOT; drift-check shows zero .kimi/ lines (4 .kiro/ lines remain); hook suite 36/36 PASS; no extra operative crush refs found beyond historical SSOT notes.
History note (2026-07-09 08:47 — opencode): first dispatch misfired — the kimi session adopted the OpenCode identity from the then-rewritten AGENTS.md and correctly refused this handoff as out-of-lane (BLOCKED). Root cause fixed: AGENTS.md restored to neutral router; kimi identity re-probed OK. See `.ai/reports/opencode-2026-07-09-misrouted-kimi-handoff.md`.
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 09:15
Auto: yes
Risk: B

## Goal
Clear the 4 Kimi-side drift lines: your steering replicas still describe
Crush as the 4th CLI / deploy operator. The SSOTs in `.ai/instructions/`
were updated in commit `8d615de` (task 8 of the swap workstream); your
replicas must be regenerated from them so a Kimi session stops believing
Crush is the deploy lane.

## Current state
- ADR-0002 + ADR-0001 amended (owner-approved): OpenCode replaces Crush —
  same lane (general helper + Stage-2 deploy operator), identity
  `crush` → `opencode`, inbox `to-crush/` → `to-opencode/` (already
  renamed on disk).
- `bash .ai/tools/check-ssot-drift.sh` currently reports Drift: 8 — ALL
  eight lines are `.kimi/` + `.kiro/` replicas (Claude's are clean).
- Your four stale replicas:
  `.kimi/steering/{operating-prompt,orchestrator-pattern,agent-catalog,code-graphs}.md`

## Target state
- All four replicas regenerated from their SSOTs
  (`.ai/instructions/<name>/principles.md`) per the replica procedure in
  `.ai/sync.md` (keep your replica preamble/frontmatter convention, replace
  the body).
- `bash .ai/tools/check-ssot-drift.sh` → zero `.kimi/` drift lines.
- Also grep your OWN files (`.kimi/steering/*.md`, `.kimi/hooks/*`,
  `.kimi/agents/*`) for any other operative `crush` reference (e.g.
  00-ai-contract.md if it names the 4th CLI) and update those too —
  historical references in comments may stay.

## Steps
1. Regenerate the 4 replicas from SSOT per `.ai/sync.md`.
2. `grep -rin crush .kimi/` — fix operative hits, list what you left as
   historical.
3. Run `bash .ai/tools/check-ssot-drift.sh` — paste the summary line
   (expect: no .kimi lines; .kiro lines may remain if Kiro hasn't run yet).
4. Run your own hook test suite (`bash .kimi/hooks/test_hooks.sh`) — paste
   PASS count (should be unchanged; this is a docs-only change unless step
   2 found hook references).
5. Prepend an activity-log entry (identity `kimi-cli`), set this handoff
   Status: DONE with a closure note, move it to
   `.ai/handoffs/to-kimi/done/`. Commit your files + the handoff move on
   the current branch and push if your session has git access; otherwise
   leave committed-state note for claude-code.

## Verification
Drift-check summary line + grep evidence per self-grep-verify (Tier 1).

## Report back with
(a) drift-check output, (b) hook-suite PASS count, (c) list of operative
crush references fixed beyond the 4 replicas, (d) commit hash or
"left uncommitted".
