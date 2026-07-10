#!/bin/bash
# Hook: Open handoffs reminder at SessionStart (kimi-cli)
# Lists qualifying handoffs in .ai/handoffs/to-kimi/open/ so an interactive Kimi
# session does not silently ignore work addressed to it. Non-blocking (exit 0);
# stdout is injected into the agent's context.
#
# "Qualifying" mirrors the auto-dispatch filter in .ai/tools/dispatch-handoffs.sh
# (lines 147-150):  Status: OPEN  AND  Auto: yes  AND  Risk: A|B.
# Risk C / missing Risk and Auto: no are human-relayed and are NOT listed here.
#
# Recursion guard: when dispatch-handoffs.sh spawns a headless CLI it exports
# AI_HANDOFF_DISPATCH=1; in that case we no-op so a dispatched session never
# re-lists or re-dispatches its own queue (no fork-bomb). Matches
# .ai/tools/dispatch-own-queue.sh.
#
# Testability: HANDOFFS_DIR overrides the queue dir (defaults to the live queue).

[ -n "${AI_HANDOFF_DISPATCH:-}" ] && exit 0

HANDOFFS_DIR="${HANDOFFS_DIR:-.ai/handoffs/to-kimi/open}"
[ -d "$HANDOFFS_DIR" ] || exit 0

qualifying=()
for f in "$HANDOFFS_DIR"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
        README.md|template.md) continue ;;
    esac
    block=$(head -20 "$f")
    printf '%s\n' "$block" | grep -qiE '^Status:[[:space:]]*OPEN'           || continue
    printf '%s\n' "$block" | grep -qiE '^Auto:[[:space:]]*yes'             || continue
    printf '%s\n' "$block" | grep -qiE '^Risk:[[:space:]]*[AB]([[:space:]]|$)' || continue
    qualifying+=("$(basename "$f")")
done

COUNT=${#qualifying[@]}
if [ "$COUNT" -gt 0 ]; then
    echo "--- Pending handoffs for kimi-cli ($COUNT, Auto:yes / Risk A|B) ---"
    for name in "${qualifying[@]}"; do echo "  $name"; done
    echo "Process with: bash .ai/tools/dispatch-handoffs.sh --exec --only kimi"
    echo "--- end ---"
fi

exit 0
