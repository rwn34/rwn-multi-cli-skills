#!/bin/bash
# Hook: open handoff queue-counts at Stop (kiro-cli) — gap B4-Kiro.
# Mirrors Kimi's handoff-queue-count.sh and Claude's stop-reminder.sh
# "Reminder 1b": print per-queue open counts across every to-*/open queue so
# each turn end is a poll point. Non-blocking (exit 0); stdout is injected into
# the agent's context. Coexists with activity-log-remind.sh as a second Stop hook.
#
# Recursion guard: no-op when AI_HANDOFF_DISPATCH is set (a dispatched session
# must not re-dispatch its own queue). Matches .kiro/hooks/dispatch-own-queue.sh.
#
# Testability: HANDOFFS_ROOT overrides the handoffs root (defaults to .ai/handoffs).

[ -n "${AI_HANDOFF_DISPATCH:-}" ] && exit 0

HANDOFFS_ROOT="${HANDOFFS_ROOT:-.ai/handoffs}"
[ -d "$HANDOFFS_ROOT" ] || exit 0

queue_summary=""
for q in "$HANDOFFS_ROOT"/to-*/open; do
    [ -d "$q" ] || continue
    n=$(ls "$q"/*.md 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && queue_summary="${queue_summary}  $(basename "$(dirname "$q")"): $n open"$'\n'
done

if [ -n "$queue_summary" ]; then
    echo "REMINDER: open handoffs by queue:"
    printf '%s' "$queue_summary"
    auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' "$HANDOFFS_ROOT"/to-*/open/*.md 2>/dev/null)
    if [ -n "$auto_pending" ]; then
        echo "Auto-dispatchable (Risk A/B launch, Risk C HOLD): run"
        echo "  bash .ai/tools/dispatch-handoffs.sh --exec   # or --only kiro"
    fi
fi

exit 0
