#!/bin/bash
# test-check-encoding.sh — verify .ai/tools/check-encoding.sh catches non-UTF-8
# shared-state files (S3-1).
#
# Run: bash .ai/tests/test-check-encoding.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$REPO_ROOT/.ai/tools/check-encoding.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$CHECK" ] || { echo "FAIL: cannot find check-encoding.sh at $CHECK"; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# UTF-8 file should pass.
printf '%s\n' '## 2026-07-17 12:00 (UTC+7) — kimi' '- Action: test' > "$WORK/utf8.md"
out="$(bash "$CHECK" "$WORK/utf8.md" 2>&1)"
rc=$?
check "UTF-8 file passes" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# UTF-16LE file should fail (simulates PowerShell Out-File corruption).
printf '\xff\xfe##\x00\x20\x00' > "$WORK/utf16le.md"
out="$(bash "$CHECK" "$WORK/utf16le.md" 2>&1)"
rc=$?
check "UTF-16LE file fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "UTF-16LE failure names the file" "$(echo "$out" | grep -q "$WORK/utf16le.md" && echo 0 || echo 1)"

# UTF-8 BOM should fail (framework wants no BOM).
printf '\xef\xbb\xbf## header\n' > "$WORK/utf8bom.md"
out="$(bash "$CHECK" "$WORK/utf8bom.md" 2>&1)"
rc=$?
check "UTF-8 BOM file fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "UTF-8 BOM failure names the file" "$(echo "$out" | grep -q "$WORK/utf8bom.md" && echo 0 || echo 1)"

# Invalid UTF-8 byte should fail.
printf '## header\n\xff\n' > "$WORK/invalid-utf8.md"
out="$(bash "$CHECK" "$WORK/invalid-utf8.md" 2>&1)"
rc=$?
check "Invalid UTF-8 file fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "Invalid UTF-8 failure names the file" "$(echo "$out" | grep -q "$WORK/invalid-utf8.md" && echo 0 || echo 1)"

# Multiple files with one bad should fail and report the bad one.
out="$(bash "$CHECK" "$WORK/utf8.md" "$WORK/utf16le.md" 2>&1)"
rc=$?
check "Mixed files fail" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "Mixed failure still names UTF-16LE file" "$(echo "$out" | grep -q "$WORK/utf16le.md" && echo 0 || echo 1)"
check "Mixed failure does not name good file" "$(echo "$out" | grep -q "$WORK/utf8.md" && echo 1 || echo 0)"

echo ""
echo "==== check-encoding suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
