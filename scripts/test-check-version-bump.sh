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
INSTALL_TEMPLATE="$HERE/install-template.sh"
SYNC_ASSETS="$HERE/../tools/multi-cli-install/scripts/sync-assets.ts"
COPY_FRAMEWORK="$HERE/../tools/multi-cli-install/src/installer/copy-framework.ts"
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
# unresolvable base, e.g. the all-zero SHA a main push carries on a
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

# --- is_placeholder_line: what does NOT count as a real changelog note --------
# Placeholders (bullet marker already stripped by the caller):
assert_true  "placeholder empty"          is_placeholder_line ""
assert_true  "placeholder whitespace"     is_placeholder_line "   "
assert_true  "placeholder ellipsis"       is_placeholder_line "..."
assert_true  "placeholder bare dash"      is_placeholder_line "-"
assert_true  "placeholder TODO"           is_placeholder_line "TODO: write this"
assert_true  "placeholder [TODO: ...]"    is_placeholder_line "[TODO: new features]"
assert_true  "placeholder TBD"            is_placeholder_line "TBD"
assert_true  "placeholder WIP"            is_placeholder_line "wip — still drafting"
assert_true  "placeholder **TODO**"       is_placeholder_line "**TODO**"
# Real notes — including one that merely MENTIONS a keyword mid-sentence. The
# patterns are start-anchored precisely so this is not a false positive:
assert_false "real note"                  is_placeholder_line "Fixed the drift checker"
assert_false "real note naming TODO"      is_placeholder_line "Dropped the TODO scaffolding from the template"
assert_false "real note starting Todos"   is_placeholder_line "Todos list rendering fixed"

# -----------------------------------------------------------------------------
echo "== Part 2: gate end-to-end in real git repos =="

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# setup_repo <old-ver> <new-ver> <changelog:yes|no> <change:versioned|docs|none>
# Builds a two-commit repo in $R: base commit at <old-ver>, head commit that
# rewrites package.json to <new-ver>, optionally adds the '## [<new-ver>]'
# CHANGELOG heading, and changes either versioned content (.ai/tools/*),
# denylisted content (docs/*), or nothing (empty commit).
#
# When changelog=yes, the version heading gets a '- release' bullet; the BASE
# Unreleased section also contains '- release' so the promoted-bullets check
# (Hole 2) sees a valid promotion.
setup_repo() {
    old="$1"; new="$2"; changelog="$3"; change="$4"
    R="$WORK/repo-$old-$new-$changelog-$change"
    mkdir -p "$R/tools/multi-cli-install" "$R/.ai/tools" "$R/docs"
    git -C "$R" -c init.defaultBranch=main init -q
    git -C "$R" config user.email test@test
    git -C "$R" config user.name test
    git -C "$R" config core.autocrlf false   # keep temp-repo output quiet on Windows

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$old" > "$R/tools/multi-cli-install/package.json"
    printf '# Changelog\n\n## [Unreleased]\n\n- release\n\n## [%s] - 2026-01-01\n\n### Fixed\n\n- base\n' "$old" > "$R/CHANGELOG.md"
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
echo "== Part 3: main-push detective mode (ADR-0012) =="
# Under ADR-0012 the gate no longer runs on PRs — it runs on `push: main`,
# comparing the PREVIOUS main tip to the NEW one. Mechanically the script is
# ref-agnostic (it diffs <base-ref>...HEAD), so a main-push run is the same
# invocation with base = the previous main tip. These cases model the two
# main commits as $BASE_SHA (old main) -> HEAD (new main).

# A main push that bumped correctly PASSES.
setup_repo 0.0.28 0.0.30 yes versioned
assert_gate "main-push: content + correct bump PASS" 0

# A main push that changed versioned content WITHOUT bumping FAILS (the whole
# point of the detective check — a merge that forgot the bump turns main red).
setup_repo 0.0.28 0.0.28 no versioned
assert_gate "main-push: content, no bump FAIL" 1

# A downgrade landing on main FAILS (merge-order downgrade guard).
setup_repo 0.0.30 0.0.28 yes versioned
assert_gate "main-push: downgrade FAIL" 1

# The lexicographic-trap bump is still correct on the main-push path.
setup_repo 0.0.9 0.0.10 yes versioned
assert_gate "main-push: 0.0.9 -> 0.0.10 lex-trap PASS" 0

# Fail CLOSED on an unresolvable base ref — the all-zero SHA github.event.before
# carries on a branch-create/force-push edge is an env error, never a wave-through.
setup_repo 0.0.28 0.0.30 yes versioned
assert_gate_ref "main-push: unresolvable base ref FAIL CLOSED" 2 \
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
    # The step must pass the previous-main tip (github.event.before) as base.
    if grep -Eq "check-version-bump\.sh \"\\\$\{\{ github\.event\.before \}\}\"" "$GATES"; then
        pass=$((pass + 1)); printf 'PASS  gates.yml: base ref is github.event.before (previous main tip)\n'
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

# -----------------------------------------------------------------------------
echo
echo "== Part 5: CHANGELOG section substance (the gap ADR-0012 opened) =="
# ADR-0012 made the release-engineer MANUALLY promote the accumulated
# '## [Unreleased]' bullets into a '## [x.y.z]' heading at merge. Asserting only
# that the heading EXISTS let an EMPTY or PLACEHOLDER-ONLY section ship a version
# documented by nothing. These cases pin the substance check.
#
# Because the gate now also proves bullets came from Unreleased (Part 6), the
# PASS cases below supply BASE Unreleased bullets that match the promoted
# bullets. FAIL cases fail on substance before the Unreleased check is reached.

# setup_repo_cl <old-ver> <new-ver> <tag> <head-changelog-content> [base-unreleased-bullets]
# Like setup_repo, but HEAD's CHANGELOG.md is supplied verbatim. Always changes
# versioned content and always bumps, so the version ordering is satisfied and
# ONLY the section's substance decides the verdict.
setup_repo_cl() {
    old="$1"; new="$2"; tag="$3"; content="$4"; base_unreleased="${5:-}"
    R="$WORK/repo-cl-$tag"
    mkdir -p "$R/tools/multi-cli-install" "$R/.ai/tools"
    git -C "$R" -c init.defaultBranch=main init -q
    git -C "$R" config user.email test@test
    git -C "$R" config user.name test
    git -C "$R" config core.autocrlf false

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$old" > "$R/tools/multi-cli-install/package.json"
    printf '# Changelog\n\n## [Unreleased]\n\n%s\n\n## [%s] - 2026-01-01\n\n### Fixed\n\n- base\n' "$base_unreleased" "$old" > "$R/CHANGELOG.md"
    echo "base tool" > "$R/.ai/tools/tool.sh"
    git -C "$R" add -A && git -C "$R" commit -qm base
    BASE_SHA="$(git -C "$R" rev-parse HEAD)"

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$new" > "$R/tools/multi-cli-install/package.json"
    echo "changed" >> "$R/.ai/tools/tool.sh"
    printf '%s' "$content" > "$R/CHANGELOG.md"
    git -C "$R" add -A && git -C "$R" commit -qm head
}

# The happy path: promotion actually happened, real bullets under the heading.
setup_repo_cl 0.0.30 0.0.31 real '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

### Added

- The substantive-section check on the version gate.

## [0.0.30] - 2026-01-01

### Fixed

- base
' '- The substantive-section check on the version gate.'
assert_gate "substance: real bullets PASS" 0

# EMPTY section — heading promoted, bullets forgotten. This is the hole.
setup_repo_cl 0.0.30 0.0.31 empty '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

## [0.0.30] - 2026-01-01

### Fixed

- base
'
assert_gate "substance: EMPTY section FAIL" 1
out="$(cd "$R" && bash "$GATE" "$BASE_SHA" 2>&1)"
case "$out" in
    *"no substantive content"*) pass=$((pass + 1)); printf 'PASS  empty-section message says "no substantive content"\n' ;;
    *) fail=$((fail + 1)); printf 'FAIL  empty-section message unclear; got: %s\n' "$out" ;;
esac

# PLACEHOLDER-ONLY — the Keep-a-Changelog scaffold copied down verbatim. This is
# the shape the real CHANGELOG's '## [Unreleased]' block actually has, so it is
# the single most likely way a botched promotion looks.
setup_repo_cl 0.0.30 0.0.31 todo '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

### Added

- [TODO: new features]

### Fixed

- [TODO: bug fixes]

## [0.0.30] - 2026-01-01

### Fixed

- base
'
assert_gate "substance: TODO-scaffold-only section FAIL" 1

# An empty bullet is not a note.
setup_repo_cl 0.0.30 0.0.31 emptybullet '# Changelog

## [0.0.31] - 2026-01-02

### Fixed

-

## [0.0.30] - 2026-01-01

### Fixed

- base
'
assert_gate "substance: empty dash-bullet only FAIL" 1

# '...' is not a note.
setup_repo_cl 0.0.30 0.0.31 ellipsis '# Changelog

## [0.0.31] - 2026-01-02

### Changed

- ...

## [0.0.30] - 2026-01-01

### Fixed

- base
'
assert_gate "substance: ellipsis-only section FAIL" 1

# An HTML comment carries no release information.
setup_repo_cl 0.0.30 0.0.31 commentonly '# Changelog

## [0.0.31] - 2026-01-02

<!--
  promote the Unreleased bullets here before merging
-->

## [0.0.30] - 2026-01-01

### Fixed

- base
'
assert_gate "substance: comment-only section FAIL" 1

# NO FALSE POSITIVES: real bullets alongside blank lines, a comment, a wrapped
# continuation line, and a trailing blank must still PASS.
setup_repo_cl 0.0.30 0.0.31 noise '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

<!-- promoted from Unreleased at merge -->

### Added

- Substantive-section check on the version gate — an empty or placeholder
  section no longer passes as a documented release.

### Fixed

- [TODO: bug fixes]


## [0.0.30] - 2026-01-01

### Fixed

- base
' '- Substantive-section check on the version gate — an empty or placeholder
- [TODO: bug fixes]'
assert_gate "substance: bullets + comment + wrap + trailing blank PASS" 0

# A bullet that MENTIONS a keyword mid-sentence is a real note, not a placeholder.
setup_repo_cl 0.0.30 0.0.31 mentions '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

### Removed

- Dropped the TODO scaffolding from the onboarding template.

## [0.0.30] - 2026-01-01

### Fixed

- base
' '- Dropped the TODO scaffolding from the onboarding template.'
assert_gate "substance: bullet mentioning TODO mid-sentence PASS" 0

# The section is the LAST in the file: EOF terminates it, not a '## ' heading.
setup_repo_cl 0.0.30 0.0.31 eof '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

### Added

- Real note, last section in the file.
' '- Real note, last section in the file.'
assert_gate "substance: section terminated by EOF PASS" 0

# THE UNRELEASED EXEMPTION: '## [Unreleased]' is empty (the normal steady state
# right after a promotion) while the versioned section is real. The gate only
# ever inspects the section named by the new SEMVER version, so Unreleased is
# never examined and cannot fail the build.
setup_repo_cl 0.0.30 0.0.31 unreleased_empty '# Changelog

## [Unreleased]

## [0.0.31] - 2026-01-02

### Added

- Real note; Unreleased above is intentionally empty post-promotion.

## [0.0.30] - 2026-01-01

### Fixed

- base
' '- Real note; Unreleased above is intentionally empty post-promotion.'
assert_gate "substance: EMPTY [Unreleased] does not fail (exempt by construction)" 0

# Same, with Unreleased holding only the TODO scaffold — also never examined.
setup_repo_cl 0.0.30 0.0.31 unreleased_todo '# Changelog

## [Unreleased]

### Added

- [TODO: new features]

## [0.0.31] - 2026-01-02

### Added

- Real note; the TODO scaffold in Unreleased above is not this gate'"'"'s business.

## [0.0.30] - 2026-01-01

### Fixed

- base
' '- Real note; the TODO scaffold in Unreleased above is not this gate'"'"'s business.'
assert_gate "substance: TODO-scaffolded [Unreleased] does not fail (exempt)" 0

# Fail CLOSED on a section that cannot be parsed: the heading-exists grep is the
# first line of defence, and section_is_substantive independently returns 1 for
# a heading it cannot find, so a bump whose section vanished never waves through.
assert_false "section_is_substantive: missing heading fails closed" \
    section_is_substantive "9.9.9" "$R/CHANGELOG.md"
assert_true  "section_is_substantive: real section is substantive" \
    section_is_substantive "0.0.31" "$R/CHANGELOG.md"

# -----------------------------------------------------------------------------
echo
echo "== Part 6: promoted bullets came from Unreleased (closes wrong-content hole) =="
# Under ADR-0012 the release-engineer promotes '## [Unreleased]' bullets into
# '## [x.y.z]' at merge. The gate has both master tips, so it diffs Unreleased
# across BASE...HEAD and asserts the new versioned bullets came from the
# bullets that disappeared. These cases pin that mechanical check.

# setup_repo_promotion <old> <new> <tag> <base-unreleased-bullets> <version-bullets> [head-unreleased-bullets]
setup_repo_promotion() {
    old="$1"; new="$2"; tag="$3"; base_bullets="$4"; version_bullets="$5"; head_bullets="${6:-}"
    R="$WORK/repo-promo-$tag"
    mkdir -p "$R/tools/multi-cli-install" "$R/.ai/tools"
    git -C "$R" -c init.defaultBranch=master init -q
    git -C "$R" config user.email test@test
    git -C "$R" config user.name test
    git -C "$R" config core.autocrlf false

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$old" > "$R/tools/multi-cli-install/package.json"
    printf '# Changelog\n\n## [Unreleased]\n\n%s\n\n## [%s] - 2026-01-01\n\n### Fixed\n\n- base\n' "$base_bullets" "$old" > "$R/CHANGELOG.md"
    echo "base tool" > "$R/.ai/tools/tool.sh"
    git -C "$R" add -A && git -C "$R" commit -qm base
    BASE_SHA="$(git -C "$R" rev-parse HEAD)"

    printf '{\n  "name": "t",\n  "version": "%s"\n}\n' "$new" > "$R/tools/multi-cli-install/package.json"
    echo "changed" >> "$R/.ai/tools/tool.sh"
    printf '# Changelog\n\n## [Unreleased]\n\n%s\n\n## [%s] - 2026-01-02\n\n### Added\n\n%s\n\n## [%s] - 2026-01-01\n\n### Fixed\n\n- base\n' "$head_bullets" "$new" "$version_bullets" "$old" > "$R/CHANGELOG.md"
    git -C "$R" add -A && git -C "$R" commit -qm head
}

# Bullets promoted unchanged from Unreleased -> PASS.
setup_repo_promotion 0.0.30 0.0.31 promoted_good \
    "- Real note from Unreleased." \
    "- Real note from Unreleased." \
    ""
assert_gate "promotion: bullets promoted from Unreleased PASS" 0

# Bullets invented under the version heading -> FAIL.
setup_repo_promotion 0.0.30 0.0.31 promoted_wrong \
    "- Real note from Unreleased." \
    "- Different note not from Unreleased." \
    ""
assert_gate "promotion: bullets NOT from Unreleased FAIL" 1
out="$(cd "$R" && bash "$GATE" "$BASE_SHA" 2>&1)"
case "$out" in
    *"bullets that were NOT"*) pass=$((pass + 1)); printf 'PASS  wrong-content message names promoted-from-Unreleased failure\n' ;;
    *) fail=$((fail + 1)); printf 'FAIL  wrong-content message unclear; got: %s\n' "$out" ;;
esac

# PR that never added Unreleased bullets in the first place -> FAIL (honest limit).
setup_repo_promotion 0.0.30 0.0.31 promoted_no_unreleased \
    "" \
    "- Some note." \
    ""
assert_gate "promotion: no Unreleased bullets to promote FAIL" 1

# Release-engineer hand-edits during promotion -> FAIL (mechanical check).
setup_repo_promotion 0.0.30 0.0.31 promoted_edited \
    "- Real note from Unreleased." \
    "- Edited real note from Unreleased." \
    ""
assert_gate "promotion: hand-edited bullets FAIL (honest limit)" 1

# -----------------------------------------------------------------------------
echo
echo "== Part 7: versioned-path allowlist vs installer manifest (closes restatement hole) =="
# This check runs against the live installer source files. The current tree
# must be in sync.
assert_true "manifest sync: live allowlist matches installer ship manifests" \
    assert_versioned_manifest_sync "$INSTALL_TEMPLATE" "$SYNC_ASSETS" "$COPY_FRAMEWORK"

echo
echo "=============================================="
echo "RESULT: $pass passed, $fail failed"
echo "=============================================="
[ "$fail" -eq 0 ]
