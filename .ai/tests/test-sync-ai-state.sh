#!/bin/bash
# test-sync-ai-state.sh — verify .ai/tools/sync-ai-state.sh snapshot/sync-back behavior.
#
# Run: bash .ai/tests/test-sync-ai-state.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYNC="$REPO_ROOT/.ai/tools/sync-ai-state.sh"
CHECK="$REPO_ROOT/.ai/tools/check-encoding.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$SYNC" ] || { echo "FAIL: cannot find sync-ai-state.sh at $SYNC"; exit 1; }
[ -f "$CHECK" ] || { echo "FAIL: cannot find check-encoding.sh at $CHECK"; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CANON="$WORK/canonical"
WT="$WORK/worktree"
mkdir -p "$CANON/.ai" "$WT"

# Helper: create canonical .ai/ state.
setup_canon() {
    rm -rf "$CANON/.ai"
    mkdir -p "$CANON/.ai/activity" "$CANON/.ai/handoffs/to-kimi/open" "$CANON/.ai/handoffs/to-kimi/done" "$CANON/.ai/reports"
    cat > "$CANON/.ai/activity/log.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) - test
- Action: canonical log entry

EOF
    echo 'handoff open' > "$CANON/.ai/handoffs/to-kimi/open/h1.md"
    echo 'report' > "$CANON/.ai/reports/r1.md"
}

# 1. snapshot copies canonical .ai/ into worktree.
setup_canon
out="$(bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" 2>&1)"; rc=$?
check "snapshot exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "snapshot copies log.md" "$([ -f "$WT/.ai/activity/log.md" ] && echo 0 || echo 1)"
check "snapshot copies handoff" "$([ -f "$WT/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "snapshot writes manifest" "$([ -f "$WT/.ai/.snapshot-manifest" ] && echo 0 || echo 1)"

# 2. sync-back copies a new file from worktree to canonical.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'new report' > "$WT/.ai/reports/r2.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back new file exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back copies new report to canonical" "$([ -f "$CANON/.ai/reports/r2.md" ] && echo 0 || echo 1)"

# 3. sync-back merges a modified activity/log.md entry.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
cat > "$WT/.ai/activity/log.md" <<'EOF'
## 2026-07-19 11:00 (UTC+7) - test
- Action: modified log entry

EOF
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back modified file exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back merges new log entry" "$(grep -q 'modified log entry' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"
check "sync-back keeps old log entry" "$(grep -q 'canonical log entry' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"

# 4. sync-back replays a handoff move (open -> done).
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
mkdir -p "$WT/.ai/handoffs/to-kimi/done"
mv "$WT/.ai/handoffs/to-kimi/open/h1.md" "$WT/.ai/handoffs/to-kimi/done/h1.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back handoff move exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back removes open handoff from canonical" "$([ ! -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back creates done handoff in canonical" "$([ -f "$CANON/.ai/handoffs/to-kimi/done/h1.md" ] && echo 0 || echo 1)"

# 5. sync-back does NOT delete canonical files that were never in the snapshot.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Simulate a concurrent canonical addition while executor runs.
echo 'concurrent' > "$CANON/.ai/handoffs/to-kimi/open/h2.md"
# Executor changes nothing in worktree.
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back preserves concurrent canonical addition" "$([ -f "$CANON/.ai/handoffs/to-kimi/open/h2.md" ] && echo 0 || echo 1)"

# 6. sync-back removes worktree .ai/ after completion.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back removes worktree .ai" "$([ ! -e "$WT/.ai" ] && echo 0 || echo 1)"

# 7. snapshot is idempotent: re-running on existing worktree .ai/ refreshes it.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'stale' > "$WT/.ai/stale.md"
setup_canon  # change canonical
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
check "snapshot refresh removes stale file" "$([ ! -f "$WT/.ai/stale.md" ] && echo 0 || echo 1)"
check "snapshot refresh copies new canonical state" "$([ -f "$WT/.ai/activity/log.md" ] && echo 0 || echo 1)"

# 8. canonical .ai/ passes encoding check after sync-back.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'new' > "$WT/.ai/reports/r2.md"
bash "$SYNC" sync-back "$WT" "$CANON" >/dev/null 2>&1
out="$(bash "$CHECK" "$CANON/.ai/activity/log.md" 2>&1)"; rc=$?
check "canonical log passes encoding check after sync-back" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# 9. sync-back does NOT delete a canonical open/review handoff that changed
#    since the snapshot (prevents one executor from wiping another actor's
#    in-flight handoff during its own sync-back).
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Another actor changes the open handoff while this executor runs.
echo 'changed by another actor' > "$CANON/.ai/handoffs/to-kimi/open/h1.md"
# This executor retires its own copy.
mkdir -p "$WT/.ai/handoffs/to-kimi/done"
mv "$WT/.ai/handoffs/to-kimi/open/h1.md" "$WT/.ai/handoffs/to-kimi/done/h1.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back skip-delete changed open handoff exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back preserves changed canonical open handoff" "$([ -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back still creates done handoff in canonical" "$([ -f "$CANON/.ai/handoffs/to-kimi/done/h1.md" ] && echo 0 || echo 1)"

# 10. sync-back does NOT delete open/review handoffs addressed to other
#     recipients that are still present in the worktree snapshot.
setup_canon
# Add cross-recipient open handoffs in canonical.
mkdir -p "$CANON/.ai/handoffs/to-kiro/open" "$CANON/.ai/handoffs/to-opencode/open"
echo 'kiro handoff' > "$CANON/.ai/handoffs/to-kiro/open/h2.md"
echo 'opencode handoff' > "$CANON/.ai/handoffs/to-opencode/open/h3.md"
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# This executor (kimi) retires only its own handoff; leaves kiro/opencode untouched.
mkdir -p "$WT/.ai/handoffs/to-kimi/done"
mv "$WT/.ai/handoffs/to-kimi/open/h1.md" "$WT/.ai/handoffs/to-kimi/done/h1.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back cross-recipient exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back removes own retired open handoff" "$([ ! -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back preserves kiro open handoff" "$([ -f "$CANON/.ai/handoffs/to-kiro/open/h2.md" ] && echo 0 || echo 1)"
check "sync-back preserves opencode open handoff" "$([ -f "$CANON/.ai/handoffs/to-opencode/open/h3.md" ] && echo 0 || echo 1)"

# 11. sync-back merges activity/log.md instead of overwriting it when the
#     worktree version dropped canonical history (executor bug / encoding issue).
setup_canon
cat > "$CANON/.ai/activity/log.md" <<'EOF'
## 2026-07-18 09:00 (UTC+7) - kimi-cli
- Action: canonical history entry

EOF
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
cat > "$WT/.ai/activity/log.md" <<'EOF'
## 2026-07-19 08:00 (UTC+7) - opencode-auto
- Action: executor overwrote the log with only its own entry

EOF
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back log merge exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back preserves canonical log history" "$(grep -qF 'canonical history entry' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"
check "sync-back prepends executor log entry" "$(grep -qF 'executor overwrote the log' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"
check "sync-back log has no duplicate headers" "$( [ "$(grep -c '^## ' "$CANON/.ai/activity/log.md")" -eq 2 ] && echo 0 || echo 1)"

# 12. log merge also works via the pure-awk fallback when python is not on PATH.
setup_canon
cat > "$CANON/.ai/activity/log.md" <<'EOF'
## 2026-07-18 09:00 (UTC+7) - kimi-cli
- Action: canonical history entry

EOF
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
cat > "$WT/.ai/activity/log.md" <<'EOF'
## 2026-07-19 08:00 (UTC+7) - opencode-auto
- Action: executor overwrote the log with only its own entry

EOF
out="$(env PATH=/usr/bin:/bin bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back awk fallback exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "awk fallback preserves canonical history" "$(grep -qF 'canonical history entry' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"
check "awk fallback prepends executor entry" "$(grep -qF 'executor overwrote the log' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"

echo ""
echo "==== sync-ai-state suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
