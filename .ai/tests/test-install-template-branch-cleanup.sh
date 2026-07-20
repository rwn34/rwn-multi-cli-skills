#!/bin/bash
# test-install-template-branch-cleanup.sh — verify install-template.sh recovers
# the original branch and deletes the install branch even when the target is
# already on ai-template-install (e.g. a previous install/update left it there).
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

# Set up a minimal repo with a main branch.
git init -q --initial-branch=main "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo 'initial' > "$REPO/readme.md"
git -C "$REPO" add readme.md
git -C "$REPO" commit -q -m "initial"
MAIN_SHA="$(git -C "$REPO" rev-parse HEAD)"

# Source the installer in library mode to expose recover_original_branch().
INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$REPO"

reset_to_main() {
    git -C "$REPO" checkout -q main
    git -C "$REPO" branch -D ai-template-install 2>/dev/null || true
    rm -f "$REPO/.ai-install-rollback-point.txt"
}

# --- Test 1: recover from rollback-point SHA ---
reset_to_main
git -C "$REPO" checkout -q -b ai-template-install
printf '%s\n' "$MAIN_SHA" > "$REPO/.ai-install-rollback-point.txt"
recovered="$(recover_original_branch 2>/dev/null || true)"
check "recover original branch from rollback SHA" "$([ "$recovered" = "main" ] && echo 0 || echo 1)"

# --- Test 2: recover from reflog when rollback file is missing ---
reset_to_main
# Create and switch to install branch, then switch back to main and back to
# install branch so the reflog records the original branch.
git -C "$REPO" checkout -q -b ai-template-install
git -C "$REPO" checkout -q main
git -C "$REPO" checkout -q ai-template-install
recovered="$(recover_original_branch 2>/dev/null || true)"
check "recover original branch from reflog" "$([ "$recovered" = "main" ] && echo 0 || echo 1)"

# --- Test 3: fall back to main when no other source works ---
reset_to_main
git -C "$REPO" checkout -q -b ai-template-install
# Wipe reflog so neither rollback nor reflog helps.
rm -f "$REPO/.git/logs/HEAD"
recovered="$(recover_original_branch 2>/dev/null || true)"
check "fall back to main when unrecoverable" "$([ "$recovered" = "main" ] && echo 0 || echo 1)"

# Clean up.
rm -rf "$TMP_BASE"

echo ""
echo "==== install-template-branch-cleanup suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
