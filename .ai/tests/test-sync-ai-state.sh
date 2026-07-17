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
    echo 'log entry' > "$CANON/.ai/activity/log.md"
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

# 3. sync-back updates a modified file.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'modified log' > "$WT/.ai/activity/log.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back modified file exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back overwrites modified file" "$(grep -q 'modified log' "$CANON/.ai/activity/log.md" && echo 0 || echo 1)"

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

echo ""
echo "==== sync-ai-state suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
