#!/bin/bash
# test-gate-policy-consistency.sh — verify that the gates.yml skip policy and
# the versioned-path predicate in scripts/check-version-bump.sh stay in sync.
#
# The old implementation used a hand-maintained paths-ignore list in gates.yml
# that silently drifted from is_versioned(). This test enforces the new design:
# gates.yml must source check-version-bump.sh and call is_versioned(), and must
# NOT contain a paths-ignore block.
#
# Run: bash .ai/tests/test-gate-policy-consistency.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATES="$REPO_ROOT/.github/workflows/gates.yml"
CHECK="$REPO_ROOT/scripts/check-version-bump.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$GATES" ] || { echo "FAIL: cannot find $GATES"; exit 1; }
[ -f "$CHECK" ] || { echo "FAIL: cannot find $CHECK"; exit 1; }

# gates.yml must not contain the old hand-maintained paths-ignore block.
out=$(grep -n "paths-ignore:" "$GATES" 2>/dev/null || true)
check "gates.yml has no paths-ignore" "$([ -z "$out" ] && echo 0 || echo 1)"

# gates.yml must source the canonical predicate.
check "gates.yml sources check-version-bump.sh" "$(grep -q 'CHECK_VERSION_BUMP_LIB=1' "$GATES" && echo 0 || echo 1)"
check "gates.yml calls is_versioned" "$(grep -q 'is_versioned' "$GATES" && echo 0 || echo 1)"

# The skip-detection step must have an id and outputs.skip_heavy.
check "gates.yml skip step has id=skip" "$(grep -q 'id: skip' "$GATES" && echo 0 || echo 1)"
check "gates.yml skip step outputs skip_heavy" "$(grep -q 'skip_heavy' "$GATES" && echo 0 || echo 1)"

# Heavy steps must be guarded by the skip output.
check "heavy steps guard on skip_heavy" "$(grep -q 'steps.skip.outputs.skip_heavy' "$GATES" && echo 0 || echo 1)"

echo ""
echo "==== gate-policy-consistency suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
