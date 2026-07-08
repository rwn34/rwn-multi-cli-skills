# P4 — Automation layer: polling + scheduled dispatch
Status: OPEN
Sender: claude-code
Recipient: claude-code
Created: 2026-07-08 22:51
Auto: yes
Risk: B

## Goal
Make handoff flow self-driving: queues get polled and Risk-A/B work dispatches
without a human relaying, per the 2026-07-08 autonomy-tier rebuild ("the human
is a gate, not a relay").

## Current state
- `.ai/tools/dispatch-handoffs.sh` — protocol v2 with Risk gate (functional
  test passed 2026-07-08). Runs only when someone invokes it.
- Claude Code now has `/loop` (in-session interval runner) and `schedule`
  (cron cloud routines) — neither wired to the dispatcher.
- `.claude/hooks/stop-reminder.sh` — nudges about uncommitted changes; does
  not mention open handoff queues.

## Target state
1. `stop-reminder.sh` also surfaces counts of open handoffs per queue (cheap
   `ls` — non-blocking reminder), so every session end is a poll point.
2. A documented polling recipe in `.ai/handoffs/README.md`: `/loop 15m bash
   .ai/tools/dispatch-handoffs.sh --exec` for active sessions; a `schedule`
   routine for out-of-session dispatch (define cadence with the owner —
   suggest hourly during work hours).
3. Dispatcher failure alerting: when a headless dispatch exits non-zero, the
   dispatcher writes a `.ai/reports/dispatch-failure-<timestamp>.md` stub
   with the exit code + tail of output (act-then-notify, Tier B).
4. Decision recorded (research note or ADR section): what polls where —
   in-pane /loop vs schedule vs 4ai-panes selector badge (see P5) — so the
   three mechanisms don't fight.

## Steps
1. Edit stop-reminder.sh + test_hooks.sh cases (orchestrator .claude/ scope).
2. Edit dispatcher for failure reports (.ai/tools — orchestrator scope).
3. Update handoffs README polling section.
4. Functional test: fixture handoff + forced-failure dispatch, paste outputs.
5. Ask owner to approve the schedule cadence before creating the routine
   (routines run in cloud = Tier C spend gate).

## Verification
- (a) hook suite all-pass, pasted.
- (b) forced-failure dispatch produces a report file — paste its path + body.

## Next step / future note
P5 integrates the queue badge into 4ai-panes' selector. Breaks first: if a
future CLI rename changes queue dir names, the stop-reminder `ls` globs go
stale — keep them driven by `to-*` glob, not a hardcoded list.

## Report back with
- (a) diffs summary, (b) functional-test outputs, (c) README section text
