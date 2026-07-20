#!/bin/bash
# test-dispatch-owner-for.sh — unit tests for dispatch-handoffs.sh owner_for().
# Verifies the six-actor auto identity mapping used in claim sidecars and
# fleet notifications. Run from repo root.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCHER="$REPO_ROOT/.ai/tools/dispatch-handoffs.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$DISPATCHER" ] || { echo "FAIL: cannot find dispatch-handoffs.sh"; exit 1; }

# Source the dispatcher in library mode to expose owner_for()/bin_for().
DISPATCH_LIB=1 . "$DISPATCHER"

# owner_for() must map every dispatchable queue name to a six-actor identity.
# Auto panes use the bare name; cockpit queues keep the -cockpit suffix.
check "owner_for claude -> claude"                 "$([ "$(owner_for claude)" = "claude" ] && echo 0 || echo 1)"
check "owner_for claude-auto -> claude"            "$([ "$(owner_for claude-auto)" = "claude" ] && echo 0 || echo 1)"
check "owner_for claude-cockpit -> claude-cockpit" "$([ "$(owner_for claude-cockpit)" = "claude-cockpit" ] && echo 0 || echo 1)"
check "owner_for kimi -> kimi"                     "$([ "$(owner_for kimi)" = "kimi" ] && echo 0 || echo 1)"
check "owner_for kimi-auto -> kimi"                "$([ "$(owner_for kimi-auto)" = "kimi" ] && echo 0 || echo 1)"
check "owner_for kimi-cockpit -> kimi-cockpit"     "$([ "$(owner_for kimi-cockpit)" = "kimi-cockpit" ] && echo 0 || echo 1)"
check "owner_for kimai-auto -> kimi"                 "$([ "$(owner_for kimai-auto)" = "kimi" ] && echo 0 || echo 1)"
check "owner_for kimai-cockpit -> kimi-cockpit"      "$([ "$(owner_for kimai-cockpit)" = "kimi-cockpit" ] && echo 0 || echo 1)"
check "owner_for kiro -> kiro"                     "$([ "$(owner_for kiro)" = "kiro" ] && echo 0 || echo 1)"
check "owner_for kiro-auto -> kiro"                "$([ "$(owner_for kiro-auto)" = "kiro" ] && echo 0 || echo 1)"
check "owner_for opencode -> opencode"             "$([ "$(owner_for opencode)" = "opencode" ] && echo 0 || echo 1)"
check "owner_for opencode-auto -> opencode"        "$([ "$(owner_for opencode-auto)" = "opencode" ] && echo 0 || echo 1)"

# bin_for() still maps queue names to the actual executable on PATH.
check "bin_for claude -> claude"                   "$([ "$(bin_for claude)" = "claude" ] && echo 0 || echo 1)"
check "bin_for kimi -> kimi"                       "$([ "$(bin_for kimi)" = "kimi" ] && echo 0 || echo 1)"
check "bin_for kiro -> kiro-cli"                   "$([ "$(bin_for kiro)" = "kiro-cli" ] && echo 0 || echo 1)"
check "bin_for opencode -> opencode"               "$([ "$(bin_for opencode)" = "opencode" ] && echo 0 || echo 1)"

echo ""
echo "==== owner-for suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
