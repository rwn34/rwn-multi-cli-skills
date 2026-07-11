#!/bin/bash
# dispatch-own-queue.sh — auto-dispatch Kimi's own to-kimi queue (e2e-test gap).
#
# Invoked from Kimi's SessionStart hook. Both `.kimi/config.toml` and the installer
# snippet `.ai/config-snippets/kimi-hooks.toml` reference this script by path.
#
# Turns the advisory handoffs-remind ("Process with: dispatch-handoffs.sh ...") into
# an actual dispatch for Auto:yes Risk-A/B handoffs addressed to kimi-cli. Risk C
# stays human-gated (the dispatcher enforces this). Complements handoffs-remind.sh
# (the human-visible listing) — it does NOT replace it; it closes the loop so noticed
# handoffs get acted on without a live runner pane. Mirrors
# .ai/tools/dispatch-own-queue.sh (claude) and .kiro/hooks/dispatch-own-queue.sh (kiro).
#
# Guardrails (in order, all fail-open / non-blocking — exit 0):
#   1. Recursion guard: a session spawned BY the dispatcher inherits
#      AI_HANDOFF_DISPATCH=1 — no-op so a dispatched session never re-dispatches.
#   2. Fast-exit on empty queue: never spawn the dispatcher when there is no
#      Auto:yes + not-DONE/BLOCKED + Risk-A/B to-kimi handoff to act on.
#   3. Debounce: a 5-min stamp at .ai/handoffs/.claims/.kimi-auto-dispatch.stamp
#      (gitignored) skips repeat dispatch on rapid session restarts.
#
# Testability overrides (defaults = live behavior):
#   HANDOFFS_DIR   candidate queue dir      (default .ai/handoffs/to-kimi/open)
#   DISPATCH_STAMP debounce stamp path      (default .ai/handoffs/.claims/.kimi-auto-dispatch.stamp)
#   DISPATCH_ONLY  --only scope             (default kimi)
#   DRY_RUN=1      print selection + command, do NOT invoke the dispatcher (offline tests)

set -u

# --- Guardrail 1: recursion guard ---
[ -n "${AI_HANDOFF_DISPATCH:-}" ] && exit 0

HANDOFFS_DIR="${HANDOFFS_DIR:-.ai/handoffs/to-kimi/open}"
DISPATCH_STAMP="${DISPATCH_STAMP:-.ai/handoffs/.claims/.kimi-auto-dispatch.stamp}"
DISPATCH_ONLY="${DISPATCH_ONLY:-kimi}"

# Must run from repo root (where .ai/ lives).
[ -d .ai/handoffs ] || exit 0

# --- Guardrail 2: fast-exit when no auto-dispatchable to-kimi handoff exists ---
# A candidate is a to-kimi handoff with Auto: yes AND Risk: A|B AND not DONE/BLOCKED.
candidate=""
for f in "$HANDOFFS_DIR"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
        README.md|template.md) continue ;;
    esac
    grep -qiE '^Auto:[[:space:]]*yes' "$f" || continue
    grep -qiE '^Risk:[[:space:]]*[AB]([[:space:]]|$)' "$f" || continue
    grep -qiE '^Status:[[:space:]]*(DONE|BLOCKED)' "$f" && continue
    candidate="$f"
    break
done
[ -z "$candidate" ] && exit 0

# --- Guardrail 3: 5-min debounce ---
mkdir -p "$(dirname "$DISPATCH_STAMP")" 2>/dev/null
if [ -f "$DISPATCH_STAMP" ] && [ -n "$(find "$DISPATCH_STAMP" -mmin -5 2>/dev/null)" ]; then
    echo "[dispatch-own-queue/kimi] debounced (ran <5min ago); skipping auto-dispatch."
    exit 0
fi
: > "$DISPATCH_STAMP"

echo "[dispatch-own-queue/kimi] auto-dispatchable to-kimi handoff found: $candidate"
echo "[dispatch-own-queue/kimi] running: dispatch-handoffs.sh --exec --only $DISPATCH_ONLY"
if [ "${DRY_RUN:-0}" = "1" ]; then
    exit 0
fi
bash .ai/tools/dispatch-handoffs.sh --exec --only "$DISPATCH_ONLY"

exit 0
