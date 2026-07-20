#!/bin/bash
# Hook: stop — remind about activity log + open handoff queues + unpushed changes.
# Non-blocking (exit 0). Queue-count block mirrors Claude's stop-reminder.sh so
# Kiro gets the same end-of-session handoff awareness (gap B4).
#
# Dual-mode (ADR-0010): predicate on the FREEZE, not on entries/ emptiness and
# not on log.md's mere presence on disk — see activity-log-inject.sh for the
# full rationale. Post-freeze, log.md is a generated, gitignored VIEW that can
# be present-but-untracked (a stale render); the freeze signal is "is log.md
# git-tracked", not "does it exist" (same test as
# .ai/tools/render-activity-log.sh:29).

# --- Reminder 1: activity log ---
if git ls-files --error-unmatch .ai/activity/log.md >/dev/null 2>&1; then
  if [ -z "$(find .ai/activity/log.md -mmin -60 2>/dev/null)" ]; then
    echo 'REMINDER: .ai/activity/log.md was not updated in this session. If you made substantive changes (file edits, tests run, decisions), prepend an entry before ending.'
  fi
else
  ENTRIES_DIR=.ai/activity/entries
  if [ -z "$(find "$ENTRIES_DIR" -name '*.md' -mmin -60 2>/dev/null)" ]; then
    echo 'REMINDER: no new file in .ai/activity/entries/ in this session. If you made substantive changes (file edits, tests run, decisions), write an entry file before ending.'
  fi
fi

# --- Reminder 1b: open handoff queues (per-queue counts, glob-driven — never a
# hardcoded CLI list). Parity with .claude/hooks/stop-reminder.sh. ---
queue_summary=""
for q in .ai/handoffs/to-*/open; do
  [ -d "$q" ] || continue
  n=$(ls "$q"/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && queue_summary="${queue_summary}  $(basename "$(dirname "$q")"): $n open"$'\n'
done
if [ -n "$queue_summary" ]; then
  echo ""
  echo "REMINDER: open handoffs by queue:"
  printf '%s' "$queue_summary"
  auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' .ai/handoffs/to-*/open/*.md 2>/dev/null)
  if [ -n "$auto_pending" ]; then
    echo "Auto-dispatchable (Risk A/B will launch, Risk C will HOLD):"
    echo "$auto_pending" | head -5
    echo "Run: bash .ai/tools/dispatch-handoffs.sh --exec (or ask the user to)."
  fi
fi

# --- Reminder 2: uncommitted changes beyond the activity log ---
DIRTY=$(git status --short 2>/dev/null | grep -v '.ai/activity/log.md' | grep -v '.ai/activity/entries/')
if [ -n "$DIRTY" ]; then
  echo ""
  echo 'REMINDER: Unpushed changes detected. Delegate to infra-engineer to commit and push.'
fi

exit 0