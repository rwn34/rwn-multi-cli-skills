# Claude: auto-dispatch own queue on session start/stop (gap B3/B4)
Status: OPEN
Sender: claude-code
Recipient: claude-code
Created: 2026-07-11 (UTC filename 202607101902)
Auto: yes
Risk: B

## Why
See `.ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md` gaps B3/B4.
Claude already has `.claude/hooks/stop-reminder.sh` (wired at `Stop` in
`.claude/settings.json`) that lists per-queue open counts + the auto-dispatchable
list — but it only SUGGESTS running `dispatch-handoffs.sh`; nothing runs it. So
Auto:yes Risk-A/B `to-claude` handoffs are noticed but not acted on unless a human
manually runs the dispatcher or a runner pane is live. Claude is the reference
implementation the Kimi (B1) and Kiro (B2/B3) handoffs are mirroring — close the
loop here too.

## Task
1. Add a step (SessionStart and/or Stop, in `.claude/`) that runs
   `bash .ai/tools/dispatch-handoffs.sh --exec` scoped to Claude's own `to-claude`
   queue for Auto:yes Risk-A/B items — turning the current advisory reminder into
   an actual dispatch. Keep Risk-C human-gated (the dispatcher already enforces
   this). The per-handoff claim-lock prevents double-processing with a live pane.
2. Consider guardrails: don't recurse/loop (a dispatched handoff that itself ends
   a session shouldn't re-trigger endlessly); cap or debounce if needed.
3. Keep the human-visible reminder output (counts) — augment, don't replace.

## Rules
- `.claude/**` is claude-code's own territory — process directly (edit + test),
  no cross-CLI handoff needed for the files. This handoff exists to track the work
  and mirror the Kimi/Kiro pair.
- Prepend an activity entry via `bash .ai/tools/activity-append.sh`. Self-retire
  (Status DONE + move to `.ai/handoffs/to-claude/done/`) per protocol v3.

## Report
What you wired, and confirmation a session start/stop now dispatches an Auto:yes
Risk-B `to-claude` handoff (test with a throwaway one) without looping.
