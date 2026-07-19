#!/bin/bash
# test-install-template-copy.sh — verify install-template.sh copy_dir never
# propagates nested .git repositories/worktrees as gitlinks into the target.
#
# Root cause: when the installer runs from a worktree whose .claude/.kimi/.kiro
# directories are junctions, a nested git worktree can live under those dirs.
# cp -R copies the nested .git file and `git add -A` stages it as a submodule
# gitlink, corrupting the target repo (git status later fails when the gitlink
# points at a missing worktree). This test guards that copy_dir strips any
# nested .git entries before the manifest is staged.
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
SRC="$TMP_BASE/template"
DST="$TMP_BASE/target"
MANIFEST_FILE="$TMP_BASE/manifest"

# Set up a minimal source tree with a nested git worktree under .claude.
mkdir -p "$SRC/.claude/worktrees/agent"
echo 'nested file' > "$SRC/.claude/worktrees/agent/readme.md"
# A .git file (not directory) is what a git worktree root carries.
cat > "$SRC/.claude/worktrees/agent/.git" <<'EOF'
gitdir: /tmp/nonexistent-worktree-gitdir
EOF

mkdir -p "$DST"
git init -q "$DST"

# Source the installer in library mode to expose copy_dir().
# Pass $DST as a dummy target so argument parsing/validation succeeds; phases
# are skipped and we override the globals copy_dir actually uses.
INSTALL_TEMPLATE_LIB=1 . "$INSTALLER" "$DST"

# Wire the globals copy_dir expects.
TEMPLATE_DIR="$SRC"
TARGET="$DST"
DRY_RUN=0
MANIFEST="$MANIFEST_FILE"
touch "$MANIFEST"

copy_dir ".claude"

# Stage the copied tree in the target repo.
git -C "$DST" add -A

# Before the fix, .claude/worktrees/agent is staged as a gitlink (160000).
# After the fix, it must be a normal file tree with no gitlink entry.
gitlink="$(git -C "$DST" ls-files --stage | grep -E "^160000 .*\.claude/worktrees/agent" || true)"
check "no nested gitlink staged" "$([ -z "$gitlink" ] && echo 0 || echo 1)"
check "nested .git file removed from copied tree" "$([ ! -e "$DST/.claude/worktrees/agent/.git" ] && echo 0 || echo 1)"
check "copied file retained and staged as blob" "$(git -C "$DST" ls-files --stage '.claude/worktrees/agent/readme.md' | grep -q '^100644' && echo 0 || echo 1)"

# Clean up.
rm -rf "$TMP_BASE"

echo ""
echo "==== install-template-copy suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
