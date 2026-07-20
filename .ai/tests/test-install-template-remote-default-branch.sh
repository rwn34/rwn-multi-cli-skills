#!/bin/bash
# test-install-template-remote-default-branch.sh — verify install-template.sh
# normalizes the GitHub remote default branch to `main` when it is still `master`.
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
GH_LOG="$TMP_BASE/gh.log"
export GH_LOG

# Set up a minimal repo with a fake GitHub remote.
git init -q --initial-branch=main "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo 'initial' > "$REPO/readme.md"
git -C "$REPO" add readme.md
git -C "$REPO" commit -q -m "initial"

# Stub gh CLI that simulates a remote whose default branch is `master`.
mkdir -p "$TMP_BASE/bin"
cat > "$TMP_BASE/bin/gh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$GH_LOG"
# arg parsing: detect GET vs PATCH and return the plain branch name.
if [ "\$1" = "api" ] && [ "\$2" = "repos/testowner/testrepo" ]; then
    if echo "\$*" | grep -q -- '-X PATCH'; then
        echo 'main'
    else
        echo 'master'
    fi
fi
exit 0
EOF
chmod +x "$TMP_BASE/bin/gh"
export PATH="$TMP_BASE/bin:$PATH"

# Source the installer in library mode to expose the helper functions.
INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$REPO"

# --- Test 1: github_owner_repo extracts owner/repo from HTTPS URL ---
git -C "$REPO" remote add origin "https://github.com/testowner/testrepo.git"
owner_repo="$(github_owner_repo origin 2>/dev/null || true)"
check "HTTPS URL parsed to owner/repo" "$([ "$owner_repo" = "testowner/testrepo" ] && echo 0 || echo 1)"

# --- Test 2: github_owner_repo extracts owner/repo from SSH URL ---
git -C "$REPO" remote set-url origin "git@github.com:testowner/testrepo.git"
owner_repo="$(github_owner_repo origin 2>/dev/null || true)"
check "SSH URL parsed to owner/repo" "$([ "$owner_repo" = "testowner/testrepo" ] && echo 0 || echo 1)"

# --- Test 3: normalize_remote_default_branch_to_main calls gh to flip default ---
rm -f "$GH_LOG"
git -C "$REPO" remote set-url origin "https://github.com/testowner/testrepo.git"
normalize_remote_default_branch_to_main 2>/dev/null
check "gh was invoked" "$([ -s "$GH_LOG" ] && echo 0 || echo 1)"
check "gh GET checked current default branch" "$(grep -q 'api repos/testowner/testrepo' "$GH_LOG" && echo 0 || echo 1)"
check "gh PATCH set default branch to main" "$(grep -q -- '-X PATCH.*repos/testowner/testrepo' "$GH_LOG" && echo 0 || echo 1)"

# --- Test 4: no remote -> function is a no-op ---
rm -f "$GH_LOG"
REPO2="$TMP_BASE/no-remote"
git init -q --initial-branch=main "$REPO2"
INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$REPO2"
normalize_remote_default_branch_to_main 2>/dev/null
check "no remote -> no gh invocations" "$([ ! -s "$GH_LOG" ] && echo 0 || echo 1)"

# --- Test 5: non-GitHub remote -> function is a no-op ---
rm -f "$GH_LOG"
REPO3="$TMP_BASE/other-remote"
git init -q --initial-branch=main "$REPO3"
git -C "$REPO3" remote add origin "https://gitlab.com/foo/bar.git"
INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$REPO3"
normalize_remote_default_branch_to_main 2>/dev/null
check "non-GitHub remote -> no gh invocations" "$([ ! -s "$GH_LOG" ] && echo 0 || echo 1)"

# Clean up.
rm -rf "$TMP_BASE"

echo ""
echo "==== install-template-remote-default-branch suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
