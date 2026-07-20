#!/bin/bash
# test-claude-hook-auto-handoff-claim.sh
# Verifies that .claude/hooks/pretool-write-edit.sh blocks an interactive
# cockpit from editing a to-claude/open Auto: yes handoff that is already
# claimed by another live process, while allowing the auto pane and stale
# claims through.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/pretool-write-edit.sh"
[ -f "$HOOK" ] || { echo "FAIL: hook not found at $HOOK"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1))
    else echo "FAIL  $1"; fail=$((fail+1)); fi
}

TMP_CLAIMS="$REPO_ROOT/.ai/handoffs/.claims"
mkdir -p "$TMP_CLAIMS"
SLUG="test-hook-claim-$$"
CLAIM="$TMP_CLAIMS/claude__${SLUG}.claim.json"

cleanup() { rm -f "$CLAIM"; }
trap cleanup EXIT

h=$(hostname 2>/dev/null || echo "unknown")
t=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Helper: run the hook with a given file_path and env
call_hook() {
    local path="$1" auto="${2:-0}" pid_override="${3:-}"
    local pid=${pid_override:-$$}
    printf '{"tool_input":{"file_path":"%s"}}' "$path" | \
        AI_HANDOFF_AUTO="$auto" bash "$HOOK"
}

# 1. Auto pane (AI_HANDOFF_AUTO=1) may edit the handoff even with a live claim.
cat > "$CLAIM" <<EOF
{"handoff":"$SLUG","recipient":"claude","owner":"claude","pid":12345,"host":"$h","claimed_at":"$t"}
EOF
(call_hook ".ai/handoffs/to-claude/open/${SLUG}.md" 1) >/dev/null 2>&1
check "auto pane edits claimed handoff" "$?"

# 2. Cockpit editing a non-auto queue (e.g., to-kimi) is not blocked by a claude claim.
(call_hook ".ai/handoffs/to-kimi/open/${SLUG}.md" 0) >/dev/null 2>&1
check "cockpit edit in to-kimi queue not blocked by claude claim" "$?"

# 3. Cockpit with a live foreign claim is blocked. Need a real live pid
# for the foreign claim; use a background sleep and kill it after.
sleep_pid=
sleep 300 &
sleep_pid=$!
cat > "$CLAIM" <<EOF
{"handoff":"$SLUG","recipient":"claude","owner":"claude","pid":$sleep_pid,"host":"$h","claimed_at":"$t"}
EOF
(call_hook ".ai/handoffs/to-claude/open/${SLUG}.md" 0 $sleep_pid) >/dev/null 2>&1
rc=$?
kill "$sleep_pid" 2>/dev/null || true
wait "$sleep_pid" 2>/dev/null || true
[ "$rc" -ne 0 ]
check "cockpit blocked when live foreign claim holds handoff" "$?"

# 4. Cockpit with a dead/stale claim is allowed.
(call_hook ".ai/handoffs/to-claude/open/${SLUG}.md" 0 99999) >/dev/null 2>&1
check "cockpit allowed when claim owner pid is dead" "$?"

# 5. Cockpit with an expired (old mtime) claim is allowed.
cat > "$CLAIM" <<EOF
{"handoff":"$SLUG","recipient":"claude","owner":"claude","pid":12345,"host":"$h","claimed_at":"2026-01-01T00:00:00Z"}
EOF
touch -d "2026-01-01 00:00:00" "$CLAIM" 2>/dev/null || touch -t 202601010000 "$CLAIM"
(call_hook ".ai/handoffs/to-claude/open/${SLUG}.md" 0 12345) >/dev/null 2>&1
check "cockpit allowed when claim is older than staleness window" "$?"

echo "==== claude-hook-auto-handoff-claim suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]
