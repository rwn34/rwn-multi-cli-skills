#!/bin/bash
# test-check-changelog-unreleased.sh — TDD verification for the PR-time
# CHANGELOG Unreleased bullet gate.
#
# Run: bash .ai/tests/test-check-changelog-unreleased.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$REPO_ROOT/.ai/tools/check-changelog-unreleased.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$CHECK" ] || { echo "FAIL: cannot find $CHECK"; exit 1; }

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Create a minimal git repo with the framework scripts so is_versioned() works.
setup_repo() {
    local dir="$1"
    git init -q --initial-branch=main "$dir"
    cd "$dir"
    mkdir -p scripts .ai/tools .ai/handoffs .github/workflows
    # Copy the real predicate sources so sourcing works.
    cp "$REPO_ROOT/scripts/check-version-bump.sh" scripts/check-version-bump.sh
    cp "$REPO_ROOT/.ai/tools/check-changelog-unreleased.sh" .ai/tools/check-changelog-unreleased.sh
    # Seed a CHANGELOG with an Unreleased section.
    cat > CHANGELOG.md <<'EOF'
# Changelog

## [Unreleased]

## [0.0.1] - 2026-07-01
- Initial release
EOF
    # Seed a versioned file so the repo is not empty.
    echo "# Framework" > .ai/README.md
    git add .
    git commit -q -m "base"
}

make_base() {
    local dir="$WORK/base"
    setup_repo "$dir"
    echo "$dir"
}

make_head_with_bullet() {
    local base="$1"
    local dir="$WORK/head-pass"
    git clone -q --local "$base" "$dir"
    cd "$dir"
    # Simulate a versioned change.
    echo "# Framework\n\nnew line" > .ai/README.md
    # Add an Unreleased bullet.
    sed -i 's/## \[Unreleased\]/## [Unreleased]\n- Added new framework feature/' CHANGELOG.md
    git add .
    git commit -q -m "change with bullet"
    echo "$dir"
}

make_head_without_bullet() {
    local base="$1"
    local dir="$WORK/head-fail"
    git clone -q --local "$base" "$dir"
    cd "$dir"
    echo "# Framework\n\nnew line" > .ai/README.md
    git add .
    git commit -q -m "change without bullet"
    echo "$dir"
}

make_head_nonversioned() {
    local base="$1"
    local dir="$WORK/head-nonversioned"
    git clone -q --local "$base" "$dir"
    cd "$dir"
    echo "readme" > README.md
    git add .
    git commit -q -m "non-versioned change"
    echo "$dir"
}

BASE_DIR=$(make_base)
PASS_DIR=$(make_head_with_bullet "$BASE_DIR")
FAIL_DIR=$(make_head_without_bullet "$BASE_DIR")
NONVERSIONED_DIR=$(make_head_nonversioned "$BASE_DIR")

# Helper to run the check in a cloned repo.
run_check() {
    local dir="$1"
    local base_dir="$2"
    local base_sha
    base_sha=$(git -C "$base_dir" rev-parse HEAD)
    cd "$dir"
    bash .ai/tools/check-changelog-unreleased.sh "$base_sha" HEAD 2>&1
    echo "exit:$?"
}

out=$(run_check "$PASS_DIR" "$BASE_DIR")
rc=$(echo "$out" | tail -1 | sed 's/exit://')
check "versioned change + Unreleased bullet passes" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

out=$(run_check "$FAIL_DIR" "$BASE_DIR")
rc=$(echo "$out" | tail -1 | sed 's/exit://')
check "versioned change + no bullet fails" "$([ "$rc" -eq 1 ] && echo 0 || echo 1)"
check "failure message names Unreleased" "$(echo "$out" | grep -q "## \[Unreleased\]" && echo 0 || echo 1)"

out=$(run_check "$NONVERSIONED_DIR" "$BASE_DIR")
rc=$(echo "$out" | tail -1 | sed 's/exit://')
check "non-versioned change passes" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

echo ""
echo "==== check-changelog-unreleased suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
