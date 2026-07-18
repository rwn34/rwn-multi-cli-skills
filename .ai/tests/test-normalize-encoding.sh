#!/bin/bash
# test-normalize-encoding.sh — verify .ai/tools/normalize-encoding.sh repairs
# common encoding corruption in shared-state files (S3-1 follow-up).
#
# Run: bash .ai/tests/test-normalize-encoding.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NORMALIZE="$REPO_ROOT/.ai/tools/normalize-encoding.sh"
CHECK="$REPO_ROOT/.ai/tools/check-encoding.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$NORMALIZE" ] || { echo "FAIL: cannot find normalize-encoding.sh at $NORMALIZE"; exit 1; }
[ -f "$CHECK" ] || { echo "FAIL: cannot find check-encoding.sh at $CHECK"; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Helper: assert file content equals expected string (after repair).
# Writes expected to a temp file so cmp preserves trailing newlines.
assert_content() {
    local label="$1" file="$2" expected="$3"
    local expected_file
    expected_file="$(mktemp -p "$WORK")"
    printf '%b' "$expected" > "$expected_file"
    if cmp -s "$file" "$expected_file"; then
        echo "PASS  $label"
        pass=$((pass+1))
    else
        echo "FAIL  $label"
        echo "  expected: $(xxd -p "$expected_file" | tr -d '\n' | head -c 80)"
        echo "  actual:   $(xxd -p "$file" | tr -d '\n' | head -c 80)"
        fail=$((fail+1))
    fi
    rm -f "$expected_file"
}

# 1. cp1252 em-dash (0x97) is converted to UTF-8 em-dash.
printf 'cost\x97fixed\n' > "$WORK/cp1252.md"
out="$(bash "$NORMALIZE" "$WORK/cp1252.md" 2>&1)"; rc=$?
check "cp1252 em-dash repair exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
assert_content "cp1252 em-dash becomes UTF-8" "$WORK/cp1252.md" "cost—fixed\n"

# 2. NUL byte is removed; if it sits where a hex digit was expected, replace with '0'.
printf 'commit \x004edd7e\n' > "$WORK/nul.md"
out="$(bash "$NORMALIZE" "$WORK/nul.md" 2>&1)"; rc=$?
check "NUL byte repair exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
assert_content "NUL byte becomes '0' in commit context" "$WORK/nul.md" "commit 04edd7e\n"

# 3. UTF-16LE is converted to UTF-8.
printf '\xff\xfe##\x00 \x002026\x00' > "$WORK/utf16le.md"
out="$(bash "$NORMALIZE" "$WORK/utf16le.md" 2>&1)"; rc=$?
check "UTF-16LE repair exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
out_check="$(bash "$CHECK" "$WORK/utf16le.md" 2>&1)"; rc_check=$?
check "UTF-16LE file passes check-encoding after repair" "$([ "$rc_check" -eq 0 ] && echo 0 || echo 1)"

# 4. UTF-8 BOM is stripped.
printf '\xef\xbb\xbf## header\n' > "$WORK/utf8bom.md"
out="$(bash "$NORMALIZE" "$WORK/utf8bom.md" 2>&1)"; rc=$?
check "UTF-8 BOM strip exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
assert_content "UTF-8 BOM is stripped" "$WORK/utf8bom.md" "## header\n"

# 5. Already valid UTF-8 is left unchanged.
printf '## 2026-07-17 12:00 (UTC+7) — kimi-cli\n- Action: test\n' > "$WORK/valid.md"
out="$(bash "$NORMALIZE" "$WORK/valid.md" 2>&1)"; rc=$?
check "valid UTF-8 exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
assert_content "valid UTF-8 unchanged" "$WORK/valid.md" "## 2026-07-17 12:00 (UTC+7) — kimi-cli\n- Action: test\n"

# 6. Mixed corruption is fully repaired.
printf '\xef\xbb\xbf##\x00 \x002026\x00' > "$WORK/mixed.md"
out="$(bash "$NORMALIZE" "$WORK/mixed.md" 2>&1)"; rc=$?
check "mixed corruption repair exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
out_check="$(bash "$CHECK" "$WORK/mixed.md" 2>&1)"; rc_check=$?
check "mixed corruption file passes check-encoding after repair" "$([ "$rc_check" -eq 0 ] && echo 0 || echo 1)"

# 7. Unrepairable invalid bytes still fail.
printf '\x80\x81\x82\n' > "$WORK/unrepairable.md"
out="$(bash "$NORMALIZE" "$WORK/unrepairable.md" 2>&1)"; rc=$?
check "unrepairable bytes exit non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"

echo ""
echo "==== normalize-encoding suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
