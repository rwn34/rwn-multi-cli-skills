#!/bin/bash
# test-ensure-queue-dirs.sh — verify dispatch-handoffs.sh auto-creates missing
# recipient queue subdirectories (S3-3).
#
# Run: bash .ai/tests/test-ensure-queue-dirs.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCH="$REPO_ROOT/.ai/tools/dispatch-handoffs.sh"
[ -f "$DISPATCH" ] || { echo "FAIL: cannot find dispatch-handoffs.sh at $DISPATCH"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/.ai/handoffs/to-kimi"
# Intentionally do NOT create open/review/done subdirs.

# Run dispatch in dry-run mode; it should create the missing dirs.
out="$(cd "$WORK" && bash "$DISPATCH" 2>&1)"
rc=$?

check "dispatch exits 0 on missing queue dirs" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "dispatch creates open/" "$([ -d "$WORK/.ai/handoffs/to-kimi/open" ] && echo 0 || echo 1)"
check "dispatch creates review/" "$([ -d "$WORK/.ai/handoffs/to-kimi/review" ] && echo 0 || echo 1)"
check "dispatch creates done/" "$([ -d "$WORK/.ai/handoffs/to-kimi/done" ] && echo 0 || echo 1)"

echo ""
echo "==== ensure-queue-dirs suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
