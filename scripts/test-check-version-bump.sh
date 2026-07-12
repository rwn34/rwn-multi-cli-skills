#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/check-version-bump.sh — the CI version gate.
#
# Part 1 unit-tests the pure comparison functions (sourced with
# CHECK_VERSION_BUMP_LIB=1, same pattern as scripts/git-hooks/test-pre-commit.sh).
# Part 2 runs the gate END-TO-END in throwaway git repos: real package.json,
# real CHANGELOG.md, real `git diff BASE...HEAD` — no stubs.
#
# Run: bash scripts/test-check-version-bump.sh
# =============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/check-version-bump.sh"
[ -f "$GATE" ] || { echo "FAIL: cannot find gate at $GATE"; exit 1; }

pass=0
fail=0

# assert_true / assert_false <desc> <fn> [args...]
assert_true() {
    desc="$1"; shift
    if "$@"; then
        pass=$((pass + 1)); printf 'PASS  %s\n' "$desc"
    else
        fail=$((fail + 1)); printf 'FAIL  %s (expected true)\n' "$desc"
    fi
}
assert_false() {
    desc="$1"; shift
    if "$@"; then
        fail=$((fail + 1)); printf 'FAIL  %s (expected false)\n' "$desc"
    else
        pass=$((pass + 1)); printf 'PASS  %s\n' "$desc"
    fi
}

# assert_gate <desc> <expected-exit> — runs the gate in $R against $BASE_SHA.
assert_gate() {
    desc="$1"; want="$2"
    (cd "$R" && bash "$GATE" "$BASE_SHA") >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        pass=$((pass + 1)); printf 'PASS  %s (exit %s)\n' "$desc" "$got"
    else
        fail=$((fail + 1)); printf 'FAIL  %s (expected exit %s, got %s)\n' "$desc" "$want" "$got"
    fi
}

# assert_gate_ref <desc> <expected-exit> <base-ref> — like assert_gate but
# against an explicit base ref (used to exercise the fail-closed guard on an
# unresolvable base, e.g. the all-zero SHA a master push carries on a
# branch-create/force-push edge).
assert_gate_ref() {
    desc="$1"; want="$2"; ref="$3"
    (cd "$R" && bash "$GATE" "$ref") >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        pass=$((pass + 1)); printf 'PASS  %s (exit %s)\n' "$desc" "$got"
    else
        fail=$((fail + 1)); printf 'FAIL  %s (expected exit %s, got %s)\n' "$desc" "$want" "$got"
    fi
}

# -----------------------------------------------------------------------------
echo "== Part 1: version comparison (unit) =="
# shellcheck source=/dev/null
CHECK_VERSION_BUMP_LIB=1 . "$GATE"

assert_true  "is_semver 1.2.3"            is_semver "1.2.3"
assert_true  "is_semver 0.0.10"           is_semver "0.0.10"
assert_false "is_semver empty"            is_semver ""
assert_false "is_semver two-part"         is_semver "1.0"
assert_false "is_semver four-part"        is_semver "1.0.0.1"
assert_false "is_semver v-prefix"         is_semver "v1.0.0"
assert_false "is_semver letters"          is_semver "0.0.x"
assert_false "is_semver prerelease"       is_semver "1.0.0-rc1"

assert_true  "gt 0.0.20 -> 0.0.21"        version_gt "0.0.21" "0.0.20"
assert_false "gt 0.0.21 -> 0.0.21 equal"  version_gt "0.0.21" "0.0.21"
assert_false "gt 0.0.21 -> 0.0.20 downgrade" version_gt "0.0.20" "0.0.21"
# The lexicographic traps — these MUST be true under semver, false under sort:
assert_true  "gt 0.0.9 -> 0.0.10 (lex trap)"  version_gt "0.0.10" "0.0.9"
assert_true  "gt 0.9.0 -> 0.10.0 (lex trap)"  version_gt "0.10.0" "0.9.0"
assert_false "gt 1.0.0 -> 0.9.9 downgrade"    version_gt "0.9.9" "1.0.0"
assert_true  "gt 0.0.08 -> 0.0.9 (leading zero)" version_gt "0.0.9" "0.0.08"
# Unparseable input fails closed (non-0):
assert_false "gt malformed new"           version_gt "0.0.x" "0.0.1"
assert_false "gt malformed old"           version_gt "0.0.2" "1.0"
assert_false "gt empty old"               version_gt "0.0.2" ""

# -----------------------------------------------------------------------------
echo "== Part 2: gate end-to-end in real git repos =="

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# setup_repo <old-ver> <new-ver> <changelog:yes|no> <change:versioned|docs|none>
# Builds a two-commit repo in $R: base commit at <old-ver>, head commit that
# rewrites package.json to <new-ver>, optionally adds the '## [<new-ver>]'
# CHANGELOG heading, and changes either versioned content (.ai/tools/*),
# denylisted content (docs/*), or nothing (empty commit).
setup_repo() {
    old="$1"; new="$2"; changelog="$3"; change="$4"
    R="$WORK/repo-$old-$new-$changelog-$change"
    mkdir -p "$R/tools/multi-cli-install" "$R/.ai/tools" "$R/docs"
    git -C "$R" -c init.defaultBranch=master init -q
    git -C "$R" config user.email test@test
    git -C "$R" config user.name test
    git -C "$R" config core.autocrlf false   # keep temp-repo output quiet on Windows

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$old" > "$R/tools/multi-cli-install/package.json"
    printf '# Changelog\n\n## [Unreleased]\n\n## [%s] - 2026-01-01\n\n### Fixed\n\n- base\n' "$old" > "$R/CHANGELOG.md"
    echo "base tool" > "$R/.ai/tools/tool.sh"
    echo "base doc"  > "$R/docs/doc.md"
    git -C "$R" add -A && git -C "$R" commit -qm base
    BASE_SHA="$(git -C "$R" rev-parse HEAD)"

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$new" > "$R/tools/multi-cli-install/package.json"
    case "$change" in
        versioned) echo "changed" >> "$R/.ai/tools/tool.sh" ;;
        docs)      echo "changed" >> "$R/docs/doc.md" ;;
        none)      : ;;
    esac
    if [ "$changelog" = "yes" ]; then
        printf '# Changelog\n\n## [Unreleased]\n\n## [%s] - 2026-01-02\n\n### Fixed\n\n- release\n\n## [%s] - 2026-01-01\n\n### Fixed\n\n- base\n' "$new" "$old" > "$R/CHANGELOG.md"
    fi
    git -C "$R" add -A
    if [ "$change" = "none" ] && [ "$old" = "$new" ] && [ "$changelog" = "no" ]; then
        git -C "$R" commit -qm head --allow-empty
    else
        git -C "$R" commit -qm head
    fi
}

# Target-state cases 1-6: ordering + downgrade (with a changelog entry, so only
# the version ordering decides the verdict).
setup_repo 0.0.20 0.0.21 yes versioned
assert_gate "e2e 0.0.20 -> 0.0.21 PASS" 0

setup_repo 0.0.21 0.0.21 no versioned
assert_gate "e2e 0.0.21 -> 0.0.21 unchanged FAIL" 1

setup_repo 0.0.21 0.0.20 yes versioned
assert_gate "e2e 0.0.21 -> 0.0.20 DOWNGRADE FAIL" 1

setup_repo 0.0.9 0.0.10 yes versioned
assert_gate "e2e 0.0.9 -> 0.0.10 lex-trap PASS" 0

setup_repo 0.9.0 0.10.0 yes versioned
assert_gate "e2e 0.9.0 -> 0.10.0 lex-trap PASS" 0

setup_repo 1.0.0 0.9.9 yes versioned
assert_gate "e2e 1.0.0 -> 0.9.9 DOWNGRADE FAIL" 1

# Fail closed on unparseable versions, either side.
setup_repo 0.0.20 0.0.x no versioned
assert_gate "e2e malformed HEAD version FAIL CLOSED" 1

setup_repo 1.0 1.0.1 yes versioned
assert_gate "e2e malformed BASE version FAIL CLOSED" 1

# Bump without a CHANGELOG entry must FAIL, and the message must name the
# exact heading expected.
setup_repo 0.0.21 0.0.22 no versioned
assert_gate "e2e bump without CHANGELOG entry FAIL" 1
out="$(cd "$R" && bash "$GATE" "$BASE_SHA" 2>&1)"
case "$out" in
    *"## [0.0.22]"*) pass=$((pass + 1)); printf 'PASS  changelog-fail message names ## [0.0.22]\n' ;;
    *) fail=$((fail + 1)); printf 'FAIL  changelog-fail message missing heading; got: %s\n' "$out" ;;
esac

# Denylisted (docs/*) change needs no bump at all.
setup_repo 0.0.21 0.0.21 no docs
assert_gate "e2e docs-only change PASS (no bump needed)" 0

# Empty diff passes.
setup_repo 0.0.21 0.0.21 no none
assert_gate "e2e no changed files PASS" 0

# -----------------------------------------------------------------------------
echo
echo "== Part 3: master-push detective mode (ADR-0012) =="
# Under ADR-0012 the gate no longer runs on PRs — it runs on `push: master`,
# comparing the PREVIOUS master tip to the NEW one. Mechanically the script is
# ref-agnostic (it diffs <base-ref>...HEAD), so a master-push run is the same
# invocation with base = the previous master tip. These cases model the two
# master commits as $BASE_SHA (old master) -> HEAD (new master).

# A master push that bumped correctly PASSES.
setup_repo 0.0.28 0.0.30 yes versioned
assert_gate "master-push: content + correct bump PASS" 0

# A master push that changed versioned content WITHOUT bumping FAILS (the whole
# point of the detective check — a merge that forgot the bump turns master red).
setup_repo 0.0.28 0.0.28 no versioned
assert_gate "master-push: content, no bump FAIL" 1

# A downgrade landing on master FAILS (merge-order downgrade guard).
setup_repo 0.0.30 0.0.28 yes versioned
assert_gate "master-push: downgrade FAIL" 1

# The lexicographic-trap bump is still correct on the master-push path.
setup_repo 0.0.9 0.0.10 yes versioned
assert_gate "master-push: 0.0.9 -> 0.0.10 lex-trap PASS" 0

# Fail CLOSED on an unresolvable base ref — the all-zero SHA github.event.before
# carries on a branch-create/force-push edge is an env error, never a wave-through.
setup_repo 0.0.28 0.0.30 yes versioned
assert_gate_ref "master-push: unresolvable base ref FAIL CLOSED" 2 \
    "0000000000000000000000000000000000000000"

# -----------------------------------------------------------------------------
echo
echo "== Part 4: workflow wiring (gates.yml) — the PR carve-out lives here =="
# The "a PR that changes content WITHOUT bumping now PASSES" guarantee is NOT a
# property of this ref-agnostic script (it would still FAIL a no-bump versioned
# diff on any ref). It is enforced by gates.yml only running the step on push,
# never on PRs. Encode that as an executable anti-rot check on the workflow file.
GATES="$HERE/../.github/workflows/gates.yml"
if [ -f "$GATES" ]; then
    # The version-bump step must be guarded to push events (so PRs skip it ->
    # a content PR without a bump passes because the check never runs).
    if grep -Eq "check-version-bump\.sh" "$GATES" \
        && grep -Eq "github\.event_name == 'push'" "$GATES"; then
        pass=$((pass + 1)); printf 'PASS  gates.yml: version-bump step guarded to push (PRs skip -> no bump needed)\n'
    else
        fail=$((fail + 1)); printf 'FAIL  gates.yml: version-bump step is not push-guarded\n'
    fi
    # The step must pass the previous-master tip (github.event.before) as base.
    if grep -Eq "check-version-bump\.sh \"\\\$\{\{ github\.event\.before \}\}\"" "$GATES"; then
        pass=$((pass + 1)); printf 'PASS  gates.yml: base ref is github.event.before (previous master tip)\n'
    else
        fail=$((fail + 1)); printf 'FAIL  gates.yml: version-bump step does not use github.event.before as base\n'
    fi
    # The step must NOT still be a pull_request gate (the old, masking placement).
    if grep -Eq "check-version-bump\.sh \"origin/\\\$\{\{ github\.base_ref \}\}\"" "$GATES"; then
        fail=$((fail + 1)); printf 'FAIL  gates.yml: still invokes the check on the PR base_ref (old model)\n'
    else
        pass=$((pass + 1)); printf 'PASS  gates.yml: no residual PR-base invocation of the check\n'
    fi
else
    printf 'SKIP  gates.yml not found at %s (workflow-wiring checks skipped)\n' "$GATES"
fi

echo
echo "=============================================="
echo "RESULT: $pass passed, $fail failed"
echo "=============================================="
[ "$fail" -eq 0 ]
