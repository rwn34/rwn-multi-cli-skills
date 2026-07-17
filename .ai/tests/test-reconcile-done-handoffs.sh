#!/bin/bash
# test-reconcile-done-handoffs.sh -- regression suite for reconcile-done-handoffs.sh
#
# reconcile-done-handoffs.sh is fail-open by contract: it always exits 0.
# This suite verifies that it:
#   1. moves a DONE handoff from open/ to done/ when there is no collision
#   2. moves a DONE handoff from review/ to done/ when there is no collision
#   3. does NOT silently overwrite an existing done/ file on collision
#      (it renames the incoming file to <basename>-superseded-<UTC>.md and warns)
#   4. leaves non-DONE handoffs untouched
#
# Run: bash .ai/tests/test-reconcile-done-handoffs.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RECONCILE="$REPO_ROOT/.ai/tools/reconcile-done-handoffs.sh"
[ -f "$RECONCILE" ] || { echo "FAIL: cannot find reconcile-done-handoffs.sh at $RECONCILE"; exit 1; }

pass=0
fail=0
check() { # desc, exit-code-of-condition (0 = pass)
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
HANDOFFS="$WORK/.ai/handoffs"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$HANDOFFS/to-kimi/open" "$HANDOFFS/to-kimi/done"
mkdir -p "$HANDOFFS/to-kiro/review"

mk_open() {
    local name="$1" goal="$2" status="${3:-DONE}"
    cat > "$HANDOFFS/to-kimi/open/$name" <<EOF
# Test handoff
Status: $status
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: A

## Goal
$goal
EOF
}

mk_review() {
    local name="$1" goal="$2"
    cat > "$HANDOFFS/to-kiro/review/$name" <<EOF
# Test handoff
Status: DONE
Sender: claude-code
Recipient: kiro
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: A

## Goal
$goal
EOF
}

mk_done() {
    local cli="$1" name="$2" goal="$3"
    cat > "$HANDOFFS/to-$cli/done/$name" <<EOF
# Test handoff
Status: DONE
Sender: claude-code
Recipient: $cli
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: A

## Goal
$goal
EOF
}

run_reconcile() {
    HANDOFFS_DIR="$HANDOFFS" bash "$RECONCILE"
}

# ==============================================================================
# 1. Normal case: a DONE handoff in open/ moves to done/ when there is no collision.
# ==============================================================================
mk_open "202607170001-normal.md" "normal move from open"
out1="$(run_reconcile 2>&1)"
rc1=$?
check "test1: reconcile exits 0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"
check "test1: DONE handoff moved out of open/" "$([ ! -f "$HANDOFFS/to-kimi/open/202607170001-normal.md" ] && echo 0 || echo 1)"
check "test1: DONE handoff now in done/" "$([ -f "$HANDOFFS/to-kimi/done/202607170001-normal.md" ] && echo 0 || echo 1)"
check "test1: reports the move" "$(echo "$out1" | grep -q 'moved .* -> done/' && echo 0 || echo 1)"

# ==============================================================================
# 2. Normal case: a DONE handoff in review/ moves to done/ when there is no collision.
# ==============================================================================
mk_review "202607170002-review.md" "normal move from review"
out2="$(run_reconcile 2>&1)"
rc2=$?
check "test2: reconcile exits 0" "$([ "$rc2" -eq 0 ] && echo 0 || echo 1)"
check "test2: DONE handoff moved out of review/" "$([ ! -f "$HANDOFFS/to-kiro/review/202607170002-review.md" ] && echo 0 || echo 1)"
check "test2: DONE handoff now in done/" "$([ -f "$HANDOFFS/to-kiro/done/202607170002-review.md" ] && echo 0 || echo 1)"
check "test2: reports the move from review" "$(echo "$out2" | grep -q 'review/' && echo 0 || echo 1)"

# ==============================================================================
# 3. Collision: an existing done/ file with the same name must be preserved.
#    The incoming file should be renamed to <basename>-superseded-<UTC>.md and
#    a warning must be printed. reconcile must still exit 0 (fail-open).
# ==============================================================================
mk_open "202607170003-collision.md" "incoming open handoff"
mk_done "kimi" "202607170003-collision.md" "existing done handoff"
cp "$HANDOFFS/to-kimi/done/202607170003-collision.md" "$WORK/original-done.snapshot"
out3="$(run_reconcile 2>&1)"
rc3=$?
check "test3: reconcile exits 0 on collision" "$([ "$rc3" -eq 0 ] && echo 0 || echo 1)"
check "test3: incoming handoff moved out of open/" "$([ ! -f "$HANDOFFS/to-kimi/open/202607170003-collision.md" ] && echo 0 || echo 1)"
check "test3: original done/ file still exists" "$([ -f "$HANDOFFS/to-kimi/done/202607170003-collision.md" ] && echo 0 || echo 1)"
# Superseded file name must be exactly one file matching the pattern.
superseded_count="$(ls "$HANDOFFS/to-kimi/done"/202607170003-collision-superseded-*.md 2>/dev/null | wc -l)"
check "test3: exactly one superseded file created" "$([ "$superseded_count" -eq 1 ] && echo 0 || echo 1)"
# Ensure the existing done file was NOT overwritten.
check "test3: existing done/ file content unchanged" "$(cmp -s "$WORK/original-done.snapshot" "$HANDOFFS/to-kimi/done/202607170003-collision.md" && echo 0 || echo 1)"
# Ensure the superseded file contains the incoming content.
superseded_file="$(ls "$HANDOFFS/to-kimi/done"/202607170003-collision-superseded-*.md 2>/dev/null | head -n1)"
check "test3: superseded file contains incoming handoff" "$(grep -q 'incoming open handoff' "$superseded_file" 2>/dev/null && echo 0 || echo 1)"
check "test3: prints a WARNING on collision" "$(echo "$out3" | grep -qi 'WARNING' && echo 0 || echo 1)"

# ==============================================================================
# 4. Non-DONE handoffs are left untouched.
# ==============================================================================
mk_open "202607170004-open.md" "still open" "OPEN"
out4="$(run_reconcile 2>&1)"
rc4=$?
check "test4: reconcile exits 0 with OPEN handoff" "$([ "$rc4" -eq 0 ] && echo 0 || echo 1)"
check "test4: OPEN handoff stays in open/" "$([ -f "$HANDOFFS/to-kimi/open/202607170004-open.md" ] && echo 0 || echo 1)"
check "test4: no output for OPEN handoff" "$([ -z "$out4" ] && echo 0 || echo 1)"

# ==============================================================================
# 5. Idempotency: re-running with no stray DONE handoffs is silent and exits 0.
# ==============================================================================
out5="$(run_reconcile 2>&1)"
rc5=$?
check "test5: second run exits 0" "$([ "$rc5" -eq 0 ] && echo 0 || echo 1)"
check "test5: second run is silent" "$([ -z "$out5" ] && echo 0 || echo 1)"

echo ""
echo "==== reconcile-done-handoffs suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
