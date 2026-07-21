#!/bin/bash
# test-render-activity-log.sh — verify the ADR-0010 spool renderer.
#
# Run: bash .ai/tests/test-render-activity-log.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RENDER="$REPO_ROOT/.ai/tools/render-activity-log.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$RENDER" ] || { echo "FAIL: cannot find $RENDER"; exit 1; }

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/.ai/activity/entries" "$WORK/.ai/activity/archive"

# Create entries out of order to prove sorting.
printf '## 2026-07-21 12:00 (UTC+7) - kimi-cli\n- Action: first\n' > "$WORK/.ai/activity/entries/20260721T110000Z-kimi-cli-first-a3f9.md"
printf '## 2026-07-21 13:00 (UTC+7) - kiro-cli\n- Action: second\n' > "$WORK/.ai/activity/entries/20260721T120000Z-kiro-cli-second-b2e5.md"
printf '## 2026-07-21 14:00 (UTC+7) - claude-code\n- Action: third\n' > "$WORK/.ai/activity/entries/20260721T130000Z-claude-code-third-c8d1.md"

bash "$RENDER" "$WORK" >/dev/null

[ -f "$WORK/.ai/activity/log.md" ] || { echo "FAIL: output file missing"; exit 1; }

out=$(cat "$WORK/.ai/activity/log.md")

# Newest entry (by UTC filename) must appear first.
check "newest entry appears first" "$(printf '%s' "$out" | head -1 | grep -q '14:00' && echo 0 || echo 1)"
check "entries are reverse-sorted" "$(printf '%s' "$out" | grep -n '## 2026-07-21' | awk 'NR==1{first=$0} NR==3{third=$0} END{exit(first ~ /14:00/ && third ~ /12:00/ ? 0 : 1)}' && echo 0 || echo 1)"

# Pre-spool pointer appears when archive file exists.
printf '# Pre-spool\n' > "$WORK/.ai/activity/archive/log-pre-spool.md"
bash "$RENDER" "$WORK" >/dev/null
out=$(cat "$WORK/.ai/activity/log.md")
check "pre-spool pointer is appended" "$(printf '%s' "$out" | grep -q 'log-pre-spool.md' && echo 0 || echo 1)"

echo ""
echo "==== render-activity-log suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
