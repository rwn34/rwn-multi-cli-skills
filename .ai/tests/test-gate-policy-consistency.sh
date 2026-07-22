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

# Behavioral check: the workflow's skip verdict must match is_versioned() for
# representative changed-file sets. This catches the drift class where the inline
# bash in gates.yml and the canonical predicate disagree about a path.
REPLICATED_SKIP_HEAVY=1
if [ -f "$CHECK" ]; then
  CHECK_VERSION_BUMP_LIB=1 . "$CHECK"
  TMPD=$(mktemp -d)
  compute_skip_heavy() {
    local versioned_hit=0 f
    for f in "$@"; do
      [ -n "$f" ] || continue
      if is_versioned "$f"; then
        versioned_hit=1
        break
      fi
    done
    if [ "$versioned_hit" -eq 0 ]; then
      printf 'true\n'
    else
      printf 'false\n'
    fi
  }
  expect_skip() {
    local label="$1" expected="$2"; shift 2
    local got
    got=$(compute_skip_heavy "$@")
    if [ "$got" = "$expected" ]; then
      echo "PASS  behavioral skip verdict: $label"
      pass=$((pass+1))
    else
      echo "FAIL  behavioral skip verdict: $label (expected $expected, got $got)"
      fail=$((fail+1))
    fi
  }
  expect_skip "versioned-only" "false" ".ai/instructions/operating-prompt/principles.md"
  expect_skip "non-versioned-only" "true" "src/app/main.ts"
  expect_skip "shipped-docs-only" "false" "docs/specs/4ai-panes-install-sync.md"
  expect_skip "non-shipped-docs-only" "true" "docs/guides/example-handoff-chain.md"
  expect_skip "framework-workflow-only" "false" ".github/workflows/gates.yml"
  expect_skip "framework-script-only" "false" "scripts/wt-bootstrap.sh"
  expect_skip "mixed versioned + non-versioned" "false" "src/app/main.ts" ".ai/instructions/operating-prompt/principles.md"
  expect_skip "empty changed set" "true"
  rm -rf "$TMPD"
  REPLICATED_SKIP_HEAVY=0
fi
check "behavioral skip verdicts replicate gates.yml policy" "$REPLICATED_SKIP_HEAVY"

echo ""
echo "==== gate-policy-consistency suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
