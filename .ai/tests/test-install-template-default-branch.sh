#!/bin/bash
# test-install-template-default-branch.sh — verify install-template.sh normalizes
# the repo's default branch to `main` when the repo still uses `master`, so the
# framework never dispatches from origin/master later.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-template.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$INSTALLER" ] || { echo "FAIL: cannot find $INSTALLER"; exit 1; }

TMP_BASE="$(mktemp -d)"
REPO="$TMP_BASE/target"

# Set up a minimal repo whose default branch is `master`.
git init -q --initial-branch=master "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo 'initial' > "$REPO/readme.md"
git -C "$REPO" add readme.md
git -C "$REPO" commit -q -m "initial"
MASTER_SHA="$(git -C "$REPO" rev-parse HEAD)"

# Source the installer in library mode to expose normalize_default_branch_to_main().
INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$REPO"

# --- Test 1: normalize_default_branch_to_main creates main and removes master ---
normalize_default_branch_to_main 2>/dev/null
check "local main branch exists after normalization" "$(git -C "$REPO" rev-parse --verify main >/dev/null 2>&1; echo $?)"
check "local master branch removed after normalization" "$([ ! "$(git -C "$REPO" rev-parse --verify master 2>/dev/null)" ] && echo 0 || echo 1)"
check "current branch is main after normalization" "$([ "$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null)" = "main" ] && echo 0 || echo 1)"
check "main points at the same commit master did" "$([ "$(git -C "$REPO" rev-parse main)" = "$MASTER_SHA" ] && echo 0 || echo 1)"

# --- Test 2: ORIGINAL_BRANCH is updated to main when on master ---
git -C "$REPO" checkout -q master 2>/dev/null || true
ORIGINAL_BRANCH="master"
normalize_default_branch_to_main 2>/dev/null
check "ORIGINAL_BRANCH updated to main when it was master" "$([ "$ORIGINAL_BRANCH" = "main" ] && echo 0 || echo 1)"

# --- Test 3: repos already on main are untouched ---
rm -rf "$REPO"
git init -q --initial-branch=main "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo 'initial' > "$REPO/readme.md"
git -C "$REPO" add readme.md
git -C "$REPO" commit -q -m "initial"
MAIN_SHA="$(git -C "$REPO" rev-parse HEAD)"

INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$REPO"
normalize_default_branch_to_main 2>/dev/null
check "main-only repo remains on main" "$([ "$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null)" = "main" ] && echo 0 || echo 1)"
check "main-only repo commit unchanged" "$([ "$(git -C "$REPO" rev-parse main)" = "$MAIN_SHA" ] && echo 0 || echo 1)"

# Clean up.
rm -rf "$TMP_BASE"

echo ""
echo "==== install-template-default-branch suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
