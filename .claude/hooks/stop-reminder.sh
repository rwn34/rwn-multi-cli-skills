#!/bin/bash
# Stop hook — reminders before Claude ends the turn.
# (1) Activity log not updated in last 60 min → remind to log substantive work.
# (2) Uncommitted changes beyond the activity log → remind to delegate commit.
# Both non-blocking (exit 0).

# --- Reminder 1: activity log ---
if [ -f .ai/activity/log.md ] && [ -z "$(find .ai/activity/log.md -mmin -60 2>/dev/null)" ]; then
    echo "REMINDER: .ai/activity/log.md was not updated in this session. If you made substantive changes (file edits, tests run, decisions), prepend an entry before ending."
fi

# --- Reminder 1b: open + review handoff queues (P4 polling — every session end is a poll point) ---
# Per-queue counts driven by the to-* glob (never a hardcoded CLI list).
queue_summary=""
for to_dir in .ai/handoffs/to-*; do
    [ -d "$to_dir" ] || continue
    open_n=$(ls "$to_dir"/open/*.md 2>/dev/null | wc -l | tr -d ' ')
    review_n=$(ls "$to_dir"/review/*.md 2>/dev/null | wc -l | tr -d ' ')
    parts=""
    [ "$open_n" -gt 0 ] && parts="${parts}open:$open_n "
    [ "$review_n" -gt 0 ] && parts="${parts}review:$review_n "
    [ -n "$parts" ] && queue_summary="${queue_summary}  $(basename "$to_dir"): $parts"$'\n'
done
if [ -n "$queue_summary" ]; then
    echo ""
    echo "REMINDER: handoffs by queue:"
    printf '%s' "$queue_summary"
    auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' .ai/handoffs/to-*/open/*.md .ai/handoffs/to-*/review/*.md 2>/dev/null)
    if [ -n "$auto_pending" ]; then
        echo "Auto-dispatchable (Risk A/B will launch, Risk C will HOLD):"
        echo "$auto_pending" | head -5
        echo "Run: bash .ai/tools/dispatch-handoffs.sh --exec (or ask the user to)."
    fi
fi

# --- Reminder 1c: fleet pane liveness (fleet-health.sh dead-man's switch) ---
# One line per pane whose queue is unwatched. STALL/WEDGED are loud — a human
# must relaunch/unwedge the pane. DOWN (idle) is deliberately NOT surfaced
# here: an idle pane down for days would nag at every turn end and train the
# reader to ignore the hook; it stays visible on demand via fleet-health.sh.
if [ -f .ai/tools/fleet-health.sh ]; then
    health_out=$(bash .ai/tools/fleet-health.sh 2>/dev/null)
    pane_alerts=$(printf '%s\n' "$health_out" | grep -E '\|\s*(STALL|WEDGED)' || true)
    if [ -n "$pane_alerts" ]; then
        echo ""
        echo "ALERT: fleet pane liveness — a handoff queue is unwatched:"
        printf '%s\n' "$pane_alerts"
        echo "Run: bash .ai/tools/fleet-health.sh  (detection only — pane restarts stay with the owner)."
    fi
fi

# --- Reminder 2: uncommitted changes beyond the activity log ---
# Filter out the activity log line from git status; if anything else is uncommitted, remind.
unpushed=$(git status --short 2>/dev/null | grep -vE '\.ai/activity/log\.md$')
if [ -n "$unpushed" ]; then
    echo ""
    echo "REMINDER: Uncommitted changes beyond the activity log:"
    echo "$unpushed" | head -10
    echo ""
    echo "You can't commit directly as orchestrator (no Bash tool). Delegate the commit to infra-engineer with an explicit commit message, or ask the user to commit manually."
fi

exit 0
