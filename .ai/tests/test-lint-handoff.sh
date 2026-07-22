#!/bin/bash
# test-lint-handoff.sh — regression tests for lint-handoff.sh protocol v4 checks.
#
# Run: bash .ai/tests/test-lint-handoff.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LINT="$REPO_ROOT/.ai/tools/lint-handoff.sh"
[ -f "$LINT" ] || { echo "FAIL: cannot find lint-handoff.sh at $LINT"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
HANDOFFS="$WORK/.ai/handoffs"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$HANDOFFS/to-kimi/open"

mk_handoff() {
    local name="$1" status="$2"
    shift 2
    cat > "$HANDOFFS/to-kimi/open/$name" <<EOF
# Test handoff
Status: $status
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
$*
## Goal
Test handoff for lint suite.
EOF
}

run_lint() {
    HANDOFFS_DIR="$HANDOFFS" bash "$LINT"
}

# Each test starts with a clean open/ dir so leftover failing files don't cascade.
reset_open() {
    rm -f "$HANDOFFS"/to-kimi/open/*.md
}

# ==============================================================================
# 1. Status: DONE requires evidence section.
# ==============================================================================
reset_open
mk_handoff "202607170001-done-no-evidence.md" "DONE" "Risk: A"
out1="$(run_lint 2>&1)"
rc1=$?
check "test1: lint fails for DONE without evidence" "$([ "$rc1" -ne 0 ] && echo 0 || echo 1)"
check "test1: mentions missing Evidence section" "$(echo "$out1" | grep -q 'missing a non-empty Evidence' && echo 0 || echo 1)"

# ==============================================================================
# 2. Status: DONE with evidence passes.
# ==============================================================================
reset_open
mk_handoff "202607170002-done-with-evidence.md" "DONE" $'Risk: A\n## Evidence\nRan the test and it passed.\n'
out2="$(run_lint 2>&1)"
rc2=$?
check "test2: lint passes for DONE with evidence" "$([ "$rc2" -eq 0 ] && echo 0 || echo 1)"

# ==============================================================================
# 3. Status: IMPOSSIBLE requires Why and Evidence sections.
# ==============================================================================
reset_open
mk_handoff "202607170003-impossible-no-why.md" "IMPOSSIBLE" $'Risk: A\n## Evidence\nOutput shows the premise is false.\n'
out3="$(run_lint 2>&1)"
rc3=$?
check "test3: lint fails for IMPOSSIBLE without Why" "$([ "$rc3" -ne 0 ] && echo 0 || echo 1)"
check "test3: mentions missing Why section" "$(echo "$out3" | grep -q 'requires a non-empty ## Why' && echo 0 || echo 1)"

reset_open
mk_handoff "202607170004-impossible-full.md" "IMPOSSIBLE" $'Risk: A\n## Why\nThe cited file does not exist in the recipient\'s tree.\n## Evidence\nls output is empty.\n'
out4="$(run_lint 2>&1)"
rc4=$?
check "test4: lint passes for IMPOSSIBLE with Why and Evidence" "$([ "$rc4" -eq 0 ] && echo 0 || echo 1)"

# ==============================================================================
# 4. Status: NOT-A-BUG requires Why and Evidence sections.
# ==============================================================================
reset_open
mk_handoff "202607170005-notabug-full.md" "NOT-A-BUG" $'Risk: A\n## Why\nThe reported error does not reproduce.\n## Evidence\nFresh run completed with exit 0.\n'
out5="$(run_lint 2>&1)"
rc5=$?
check "test5: lint passes for NOT-A-BUG with Why and Evidence" "$([ "$rc5" -eq 0 ] && echo 0 || echo 1)"

# ==============================================================================
# 5. HYPOTHESIS must not carry a priority label or Risk C.
# ==============================================================================
reset_open
mk_handoff "202607170006-hypothesis-priority.md" "OPEN" $'Risk: A\nEvidence: HYPOTHESIS\nPriority: P0\n'
out6="$(run_lint 2>&1)"
rc6=$?
check "test6: lint fails for HYPOTHESIS with priority label" "$([ "$rc6" -ne 0 ] && echo 0 || echo 1)"

reset_open
mk_handoff "202607170007-hypothesis-risk-c.md" "OPEN" $'Evidence: HYPOTHESIS\nRisk: C\n'
out7="$(run_lint 2>&1)"
rc7=$?
check "test7: lint fails for HYPOTHESIS with Risk C" "$([ "$rc7" -ne 0 ] && echo 0 || echo 1)"

# ==============================================================================
# 6. HYPOTHESIS without priority label or Risk C passes.
# ==============================================================================
reset_open
mk_handoff "202607170008-hypothesis-ok.md" "OPEN" $'Risk: A\nEvidence: HYPOTHESIS\n'
out8="$(run_lint 2>&1)"
rc8=$?
check "test8: lint passes for HYPOTHESIS without priority/Risk C" "$([ "$rc8" -eq 0 ] && echo 0 || echo 1)"

# ==============================================================================
# 7. Same basename in open/ and done/ under the same recipient queue is a duplicate.
# ==============================================================================
reset_open
mkdir -p "$HANDOFFS/to-kimi/done"
mk_handoff "202607170009-dup-in-both.md" "OPEN" $'Risk: A\n## Evidence\nok\n'
cp "$HANDOFFS/to-kimi/open/202607170009-dup-in-both.md" "$HANDOFFS/to-kimi/done/202607170009-dup-in-both.md"
out9="$(run_lint 2>&1)"
rc9=$?
check "test9: lint fails for same basename in open/ and done/" "$([ "$rc9" -ne 0 ] && echo 0 || echo 1)"
check "test9: mentions duplicate handoff basename" "$(echo "$out9" | grep -q 'duplicate handoff basename' && echo 0 || echo 1)"

# Same basename in done/ of two different recipient queues is allowed (return copies).
reset_open
mkdir -p "$HANDOFFS/to-claude/done"
mk_handoff "202607170010-shared-return.md" "OPEN" $'Risk: A\n## Evidence\nok\n'
cp "$HANDOFFS/to-kimi/open/202607170010-shared-return.md" "$HANDOFFS/to-claude/done/202607170010-shared-return.md"
out10="$(run_lint 2>&1)"
rc10=$?
check "test10: lint passes for same basename across different recipient done/ queues" "$([ "$rc10" -eq 0 ] && echo 0 || echo 1)"

echo ""
echo "==== lint-handoff suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
