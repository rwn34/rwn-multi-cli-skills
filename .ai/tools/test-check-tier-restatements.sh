#!/bin/bash
# test-check-tier-restatements.sh — prove check-tier-restatements.sh actually BITES.
# Run from repo root. Exit 0 if all cases pass.
#
# These fixtures are HERMETIC: each case builds a throwaway repo-root in a temp dir
# and runs the checker against it via the checker's root-override argument. Nothing
# here reads or mutates the live tree, so the tests answer "does the CHECKER detect
# this failure mode?" and never "is the repo currently compliant?". Repo compliance
# is a separate concern, enforced by the `gates` workflow running the checker on the
# real tree.
#
# The GREEN fixture synthesizes the orchestrator restatement from the SSOT's own §8
# text. That is deliberate: §8 contains every load-bearing concept by construction,
# so a compliant restatement is guaranteed to exist without this test hard-coding a
# second copy of the tier table (which would just re-create the drift problem the
# checker exists to solve).

set -u

# Optional first arg: repo root the fixtures are seeded from (defaults to CWD, so
# the `gates` invocation stays a bare `bash .ai/tools/test-check-tier-restatements.sh`).
ROOT="${1:-$PWD}"

CHECK="$ROOT/.ai/tools/check-tier-restatements.sh"
SSOT_SRC="$ROOT/.ai/instructions/operating-prompt/principles.md"
CLAUDEMD_SRC="$ROOT/CLAUDE.md"

pass=0
fail=0

[ -r "$CHECK" ]        || { echo "FAIL: checker not found: $CHECK"; exit 1; }
[ -r "$SSOT_SRC" ]     || { echo "FAIL: SSOT not found: $SSOT_SRC"; exit 1; }
[ -r "$CLAUDEMD_SRC" ] || { echo "FAIL: CLAUDE.md not found: $CLAUDEMD_SRC"; exit 1; }

# Build a compliant fixture root and echo its path.
mkfixture() {
  local root
  root="$(mktemp -d)"
  mkdir -p "$root/.ai/instructions/operating-prompt" "$root/.claude/agents"
  cp "$SSOT_SRC" "$root/.ai/instructions/operating-prompt/principles.md"
  cp "$CLAUDEMD_SRC" "$root/CLAUDE.md"
  # Synthesize a compliant orchestrator restatement out of SSOT §8 (see header).
  {
    echo "# Orchestrator (fixture)"
    echo
    echo "## Autonomy tiers (operating-prompt §8)"
    echo
    awk '/^## 8\./ {inside=1} inside && /^## / && !/^## 8\./ {inside=0} inside' \
      "$root/.ai/instructions/operating-prompt/principles.md"
  } > "$root/.claude/agents/orchestrator.md"
  echo "$root"
}

# expect <expected-exit: 0|1> <case-name> <root> [grep-for-in-output]
expect() {
  local want="$1" name="$2" root="$3" needle="${4:-}"
  local out rc
  out="$(bash "$CHECK" "$root" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL: $name — expected exit $want, got $rc"
    echo "$out" | sed 's/^/      /'
    fail=$((fail + 1)); rm -rf "$root"; return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "FAIL: $name — exit $rc as expected, but output lacked: $needle"
    echo "$out" | sed 's/^/      /'
    fail=$((fail + 1)); rm -rf "$root"; return
  fi
  echo "PASS: $name"
  pass=$((pass + 1))
  rm -rf "$root"
}

# --- Case 1: a compliant tree is GREEN (guards against a check that always fails).
R="$(mkfixture)"
expect 0 "compliant tree passes" "$R"

# --- Case 2: restatement drops the owner's only gate -> RED.
# This is the exact PR #54 / PR #57 failure mode: SSOT moves, orchestrator.md doesn't.
R="$(mkfixture)"
sed -i 's/deploy to PRODUCTION/deploy to somewhere/g' "$R/.claude/agents/orchestrator.md"
expect 1 "orchestrator.md missing 'deploy to PRODUCTION' is caught" "$R" \
  "[Tier C: deploy to PRODUCTION] missing from .claude/agents/orchestrator.md"

# --- Case 3: CLAUDE.md drops the staging-deploy authority -> RED.
R="$(mkfixture)"
sed -i 's/deploy to STAGING/deploy to nowhere/g' "$R/CLAUDE.md"
expect 1 "CLAUDE.md missing 'deploy to STAGING' is caught" "$R" \
  "[Tier B: deploy to STAGING] missing from CLAUDE.md"

# --- Case 4: the SSOT itself drops a tier item -> RED on the SSOT anchor.
# Without this arm the concept table could quietly track a tier rule the SSOT had
# already deleted, and the whole check would be theatre.
R="$(mkfixture)"
sed -i 's/ADR authorship or amendment/ADR stuff/g' \
  "$R/.ai/instructions/operating-prompt/principles.md"
expect 1 "SSOT dropping a tier item is caught (SSOT anchor)" "$R" \
  "[Tier B: ADR authorship] not found in"

# --- Case 5: staging deploy silently promoted out of Tier B in the SSOT -> RED.
# Byte-drift checkers cannot see this; tier PLACEMENT is the thing that decides who
# is allowed to deploy, so it gets its own assertion.
R="$(mkfixture)"
sed -i 's/\*\*deploy to STAGING\*\*/**deploy to NOWHERE**/' \
  "$R/.ai/instructions/operating-prompt/principles.md"
expect 1 "staging deploy leaving SSOT Tier B is caught (placement)" "$R" \
  "[placement] 'deploy to STAGING' is not in the SSOT §8 Tier B bullet"

echo "----"
echo "test-check-tier-restatements: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
