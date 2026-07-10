#!/bin/bash
# dispatch-own-queue.sh — SessionStart / agentSpawn hook for Kiro.
#
# Auto-processes to-kiro `Auto: yes` Risk-A/B handoffs so they don't sit
# unprocessed when no 4AI-panes runner pane is live. This is the per-CLI
# always-on delivery path recommended in
# .ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md (gap B3):
# "a per-CLI SessionStart hook that (a) lists that CLI's open inbox and
# (b) runs dispatch-handoffs.sh for its own queue."
#
# Recursion guard: dispatch-handoffs.sh exports AI_HANDOFF_DISPATCH=1 into each
# spawned child (see that script's header). When the var is set, this hook
# no-ops, so a dispatched headless Kiro never re-dispatches — no fork-bomb.
#
# Non-blocking: always exits 0. The dispatcher's per-handoff claim-lock
# (.ai/handoffs/.claims/) prevents double-processing when a live pane-runner
# and this hook race the same handoff.
#
# NOTE: this hook only has effect under a launched agent (orchestrator
# agentSpawn) or a SessionStart that the runtime honors. A bare `kiro-cli chat`
# runs the built-in default agent, which carries none of these hooks — the
# supported interactive entry is `kiro-cli chat --agent orchestrator`.

set -u

# Recursion guard — a dispatched child must not re-dispatch.
[ -n "${AI_HANDOFF_DISPATCH:-}" ] && exit 0

open_dir=".ai/handoffs/to-kiro/open"
[ -d "$open_dir" ] || exit 0

# List the inbox first (cheap, always useful context at session start).
handoffs=$(ls "$open_dir"/*.md 2>/dev/null)
if [ -n "$handoffs" ]; then
  echo '--- Open handoffs for kiro-cli ---'
  echo "$handoffs"
  echo '--- end ---'
fi

# Only spawn a dispatcher when there is at least one Auto:yes OPEN handoff.
# (The dispatcher itself re-checks Risk A/B + Status: OPEN before launching.)
auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' "$open_dir"/*.md 2>/dev/null)
[ -n "$auto_pending" ] || exit 0

if command -v kiro-cli >/dev/null 2>&1 && [ -f .ai/tools/dispatch-handoffs.sh ]; then
  echo '--- Auto-dispatching to-kiro handoffs (Auto: yes, Risk A/B) ---'
  bash .ai/tools/dispatch-handoffs.sh --exec --only kiro
  echo '--- end auto-dispatch ---'
fi

exit 0
