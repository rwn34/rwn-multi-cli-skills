#!/bin/bash
# Stop hook — reminders before Claude ends the turn.
# (1) Activity log not updated in last 60 min → remind to log substantive work.
# (2) Uncommitted changes beyond the activity log → remind to delegate commit.
# Both non-blocking (exit 0).

# --- Reminder 1: activity log ---
if [ -f .ai/activity/log.md ] && [ -z "$(find .ai/activity/log.md -mmin -60 2>/dev/null)" ]; then
    echo "REMINDER: .ai/activity/log.md was not updated in this session. If you made substantive changes (file edits, tests run, decisions), prepend an entry before ending."
fi

# --- Reminder 1b: auto-dispatchable handoffs waiting ---
auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' .ai/handoffs/to-*/open/*.md 2>/dev/null)
if [ -n "$auto_pending" ]; then
    echo ""
    echo "REMINDER: open handoffs marked 'Auto: yes' are waiting for dispatch:"
    echo "$auto_pending" | head -5
    echo "Run: bash .ai/tools/dispatch-handoffs.sh --exec (or ask the user to)."
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
