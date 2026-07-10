# Kiro handoff awareness for bare `chat` + auto-dispatch own queue (gaps B2/B3/B4)
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-11 (UTC filename 202607101901)
Auto: yes
Risk: B

## Why
See `.ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md` gaps B2/B3/B4:
- Kiro surfaces `to-kiro/open/` only under NAMED agents (`activity-log-inject.sh`
  wired at `agentSpawn` in each agent JSON + `SessionStart` in `guards.json`). A
  bare `kiro-cli chat` runs the built-in DEFAULT agent, which carries none of
  these hooks — so a hand-started Kiro misses handoffs entirely. The dispatcher's
  own comments confirm this gap.
- Nothing auto-runs `dispatch-handoffs.sh`, so Auto:yes Risk-A/B `to-kiro`
  handoffs sit unprocessed unless a runner pane is live.

## Task
1. Make interactive Kiro handoff-aware even without an explicitly pinned agent:
   either (a) document + enforce that the fleet always launches
   `kiro-cli chat --agent orchestrator` (Selector already pins it — make it the
   only supported interactive entry, and say so), and/or (b) add a
   default-agent-safe SessionStart surfacing of `to-kiro/open/` if Kiro's runtime
   allows a non-agent-scoped session hook.
2. Add a SessionStart step (in `.kiro/`) that not only LISTS `to-kiro/open/` but
   runs `bash .ai/tools/dispatch-handoffs.sh --exec` scoped to Kiro's own queue
   (Auto:yes Risk-A/B), so handoffs get processed without a running pane. The
   per-handoff claim-lock already prevents double-processing.
3. Add a queue-count reminder (Stop or SessionStart) for Kiro, parity with
   Claude's `stop-reminder.sh` (gap B4).

## Rules
- Your territory: `.kiro/**`. Do NOT edit `tools/4ai-panes/Selector.ps1` (Claude's)
  beyond noting what it should launch — if the launch command needs changing, put
  the exact requested command in your report and Claude will adjust Selector.
- Prepend an activity entry via `bash .ai/tools/activity-append.sh`. Self-retire
  (Status DONE + move to `.ai/handoffs/to-kiro/done/`) per protocol v3. Blocked →
  leave OPEN as BLOCKED with a verbatim `## Blocker`.

## Report
What you changed, whether a bare `kiro-cli chat` now notices handoffs (or why it
can't and the enforced-agent decision), and the dispatch/reminder behavior.
