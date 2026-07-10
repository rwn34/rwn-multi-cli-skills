#!/bin/bash
# dispatch-own-queue.sh — auto-dispatch Claude's own to-claude queue (gap B3/B4).
#
# Invoked from Claude's SessionStart hook (.claude/settings.json references this
# script by path). Lives under .ai/tools/ (framework territory, not a gated
# .claude/ sensitive file) so the wiring only needs one gated one-line reference.
#
# Turns the advisory stop-reminder ("Run: dispatch-handoffs.sh") into an actual
# dispatch for Auto:yes Risk-A/B handoffs addressed to claude-code. Risk C stays
# human-gated (the dispatcher enforces this). Complements stop-reminder.sh — it
# does NOT replace the human-visible open-queue counts, it just closes the loop
# so noticed handoffs get acted on without a live runner pane.
#
# Guardrails (in order, all fail-open / non-blocking — exit 0):
#   1. Recursion guard: a session spawned BY the dispatcher inherits
#      AI_HANDOFF_DISPATCH=1 — no-op so a dispatched session never re-dispatches.
#   2. Fast-exit on empty queue: never spawn the dispatcher when there is no
#      Auto:yes + OPEN + Risk-A/B to-claude handoff to act on.
#   3. Debounce: a 5-min stamp at .ai/handoffs/.claims/.claude-auto-dispatch.stamp
#      (gitignored) skips repeat dispatch on rapid session restarts.

set -u

# --- Guardrail 1: recursion guard ---
[ -n "${AI_HANDOFF_DISPATCH:-}" ] && exit 0

# Must run from repo root (where .ai/ lives).
[ -d .ai/handoffs ] || exit 0

# --- Guardrail 2: fast-exit when no auto-dispatchable to-claude handoff exists ---
# A candidate is an OPEN to-claude handoff with Auto: yes AND Risk: A or B.
candidate=""
for f in .ai/handoffs/to-claude/open/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
        README.md|template.md) continue ;;
    esac
    grep -qiE '^Auto:[[:space:]]*yes' "$f" || continue
    grep -qiE '^Risk:[[:space:]]*[AB]([[:space:]]|$)' "$f" || continue
    # Skip if already marked DONE/BLOCKED in the status block.
    grep -qiE '^Status:[[:space:]]*(DONE|BLOCKED)' "$f" && continue
    candidate="$f"
    break
done
[ -z "$candidate" ] && exit 0

# --- Guardrail 3: 5-min debounce ---
stamp=".ai/handoffs/.claims/.claude-auto-dispatch.stamp"
mkdir -p .ai/handoffs/.claims 2>/dev/null
if [ -f "$stamp" ] && [ -n "$(find "$stamp" -mmin -5 2>/dev/null)" ]; then
    echo "[dispatch-own-queue] debounced (ran <5min ago); skipping auto-dispatch."
    exit 0
fi
: > "$stamp"

echo "[dispatch-own-queue] auto-dispatchable to-claude handoff found: $candidate"
echo "[dispatch-own-queue] running: dispatch-handoffs.sh --exec --only claude"
bash .ai/tools/dispatch-handoffs.sh --exec --only claude

exit 0
