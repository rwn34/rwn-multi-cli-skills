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
cp "$REPO_ROOT/.ai/tools/normalize-encoding.sh" "$WORK/.ai/tools/normalize-encoding.sh"
cp "$REPO_ROOT/.ai/tools/notify.sh" "$WORK/.ai/tools/notify.sh"
cp "$REPO_ROOT/.ai/tools/reconcile-done-handoffs.sh" "$WORK/.ai/tools/reconcile-done-handoffs.sh"
# UTF-16LE activity log (simulates PowerShell corruption). "hi" in UTF-16LE.
printf '\xff\xfeh\x00i\x00' > "$WORK/.ai/activity/log.md"
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
check "dispatch repairs UTF-16LE log to valid UTF-8" "$(bash "$REPO_ROOT/.ai/tools/check-encoding.sh" "$WORK/.ai/activity/log.md" >/dev/null 2>&1 && echo 0 || echo 1)"

# Unrepairable bytes still warn but stay fail-open.
WORK2="$(mktemp -d)"
cleanup2() { rm -rf "$WORK2"; }
trap 'cleanup2; cleanup' EXIT
mkdir -p "$WORK2/.ai/handoffs/to-kimi/open" "$WORK2/.ai/activity" "$WORK2/.ai/tools"
cp "$REPO_ROOT/.ai/tools/check-encoding.sh" "$WORK2/.ai/tools/check-encoding.sh"
cp "$REPO_ROOT/.ai/tools/normalize-encoding.sh" "$WORK2/.ai/tools/normalize-encoding.sh"
cp "$REPO_ROOT/.ai/tools/notify.sh" "$WORK2/.ai/tools/notify.sh"
cp "$REPO_ROOT/.ai/tools/reconcile-done-handoffs.sh" "$WORK2/.ai/tools/reconcile-done-handoffs.sh"
printf '\x80\x81\x82\n' > "$WORK2/.ai/activity/log.md"
cat > "$WORK2/.ai/handoffs/to-kimi/open/202607170001-test.md" <<'EOF'
# Test
Status: OPEN
Sender: claude-cockpit
Recipient: kimi-auto
Created: 2026-07-17 12:00 (UTC+7)
Auto: yes
Risk: A

## Goal
No-op handoff for unrepairable encoding test.
EOF

out2="$(cd "$WORK2" && bash "$DISPATCH" --only kimi 2>&1)"
rc2=$?
check "unrepairable encoding exits 0 (fail-open)" "$([ "$rc2" -eq 0 ] && echo 0 || echo 1)"
check "unrepairable encoding reports repair failed" "$(echo "$out2" | grep -qi 'repair failed' && echo 0 || echo 1)"

echo ""
echo "==== dispatch-encoding suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
