#!/bin/bash
# test-dispatch-encoding.sh — verify dispatch-handoffs.sh warns when shared
# .ai/ files have bad encoding, but stays fail-open (S3-1 integration).
#
# Run: bash .ai/tests/test-dispatch-encoding.sh
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

# Build a minimal fake project with a bad activity log.
mkdir -p "$WORK/.ai/handoffs/to-kimi/open"
mkdir -p "$WORK/.ai/activity"
mkdir -p "$WORK/.ai/tools"
# Copy the tools the dispatcher calls into the fake project so it can run there.
cp "$REPO_ROOT/.ai/tools/check-encoding.sh" "$WORK/.ai/tools/check-encoding.sh"
cp "$REPO_ROOT/.ai/tools/notify.sh" "$WORK/.ai/tools/notify.sh"
cp "$REPO_ROOT/.ai/tools/reconcile-done-handoffs.sh" "$WORK/.ai/tools/reconcile-done-handoffs.sh"
# UTF-16LE activity log (simulates PowerShell corruption).
printf '\xff\xfe##\x00\x20\x00' > "$WORK/.ai/activity/log.md"
# A valid handoff so dispatch has something to scan.
cat > "$WORK/.ai/handoffs/to-kimi/open/202607170000-test.md" <<'EOF'
# Test
Status: OPEN
Sender: claude-cockpit
Recipient: kimi-auto
Created: 2026-07-17 12:00 (UTC+7)
Auto: yes
Risk: A

## Goal
No-op handoff for encoding test.
EOF

out="$(cd "$WORK" && bash "$DISPATCH" --only kimi 2>&1)"
rc=$?

check "dispatch exits 0 despite bad encoding (fail-open)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "dispatch warns about UTF-16LE log" "$(echo "$out" | grep -qi 'UTF-16LE' && echo 0 || echo 1)"
check "dispatch names the bad file" "$(echo "$out" | grep -q '.ai/activity/log.md' && echo 0 || echo 1)"

echo ""
echo "==== dispatch-encoding suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
