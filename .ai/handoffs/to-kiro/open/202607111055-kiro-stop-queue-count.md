# Add a Stop queue-count hook for Kiro (gap B4-Kiro)
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-11 15:05
Auto: yes
Risk: A

<!-- Protocol v3. Reversible routine (new non-blocking Stop hook + a script
     mirroring an existing one). Auto-dispatchable. -->

## Goal
Give Kiro the same turn-end handoff awareness Kimi and Claude already have. Right
now Kiro's only Stop hook is `activity-log-remind.sh` (an activity-log nag) — it
never prints how many open handoffs are waiting. Add a per-queue open-handoff
count at Stop so every turn end is a poll point across all `to-*/open` queues.

## Current state
- Kimi has `.kimi/hooks/handoff-queue-count.sh` wired as a Stop hook (gap B4 for
  Kimi, done). Claude has the equivalent in `stop-reminder.sh` ("Reminder 1b").
- Kiro has NO queue-count hook. Its Stop hook in `.kiro/guards.json` is only
  `activity-log-remind.sh`. Kiro surfaces handoffs at SessionStart
  (`activity-log-inject` / `dispatch-own-queue`) but not at Stop.

## Target state
- A new `.kiro/hooks/handoff-queue-count.sh` that mirrors Kimi's, wired as an
  ADDITIONAL Stop hook in `.kiro/guards.json` (keep `activity-log-remind.sh` too —
  both Stop hooks coexist).

## Context (reference only — adapt to Kiro's conventions)
Kimi's script (`.kimi/hooks/handoff-queue-count.sh`) is the model. It: recursion-
guards on `AI_HANDOFF_DISPATCH`, defaults `HANDOFFS_ROOT=.ai/handoffs`, loops
`to-*/open`, prints per-queue open counts, and if any `Auto: yes` handoffs exist
prints the dispatch hint. For Kiro, change the dispatch hint to Kiro's scope:
`bash .ai/tools/dispatch-handoffs.sh --exec   # or --only kiro`. Keep it
non-blocking (exit 0); stdout is injected into context.

## Steps
1. Create `.kiro/hooks/handoff-queue-count.sh` mirroring `.kimi/hooks/handoff-queue-count.sh`
   (read that file). Keep the recursion guard, the `HANDOFFS_ROOT` override, the
   per-queue count loop, and the auto-dispatchable hint — but make the hint say
   `--only kiro`. Match whatever header/style your other `.kiro/hooks/*.sh` use.
2. Wire it as a Stop hook in `.kiro/guards.json` alongside the existing
   `activity-log-remind.sh` Stop entry (do not replace it — add to it), following
   the exact JSON shape Kiro uses for Stop hooks.
3. Keep it non-blocking (exit 0 always).

## Verification
- (a) EXECUTE the script from the repo root with a populated queue and paste the
      output — it should print "REMINDER: open handoffs by queue:" with counts
      (there are currently open handoffs in `.ai/handoffs/to-*/open/`, including
      this one, so you'll see a non-empty count).
- (b) EXECUTE it with `AI_HANDOFF_DISPATCH=1 bash .kiro/hooks/handoff-queue-count.sh`
      and confirm it no-ops (recursion guard) — empty output, exit 0.
- (c) Validate `.kiro/guards.json` is still valid JSON after the edit (parse it)
      and show the Stop hooks array now lists BOTH scripts.

## Next step / future note
If a Kiro Stop hook ever needs to block, note this one must stay non-blocking
(exit 0) — it is informational only. First thing that breaks: if the handoffs
root moves, the `HANDOFFS_ROOT` default must track it (same as Kimi's).

## Activity log template
    ## 2026-07-11 HH:MM — kiro-cli
    - Action: per handoff 202607111055-kiro-stop-queue-count — added .kiro/hooks/handoff-queue-count.sh + wired Stop hook in guards.json
    - Files: .kiro/hooks/handoff-queue-count.sh; .kiro/guards.json
    - Decisions: <any Kiro-specific adaptation>

## Report back with
- (a) path of the new script + the guards.json Stop array (pasted).
- (b) pasted output of the populated-queue run and the recursion-guard no-op run.
- (c) JSON-validity confirmation for guards.json.

## When complete (protocol v3)
Set Status to `DONE` and move this file to `.ai/handoffs/to-kiro/done/` yourself
once the hook is wired and the runs are pasted. If blocked, leave it in `open/`,
set Status `BLOCKED`, and append a `## Blocker` with verbatim errors.
