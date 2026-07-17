#!/bin/bash
# test-wt-bootstrap-remove.sh — regression tests for safe worktree removal and
# destructive-op guards after the 2026-07-16 saja-qr .ai/ deletion incident.
#
# Run: bash .ai/tests/test-wt-bootstrap-remove.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WT_BOOTSTRAP="$REPO_ROOT/scripts/wt-bootstrap.sh"
GUARD="$REPO_ROOT/.ai/tools/guard-ai-destructive.sh"
[ -f "$WT_BOOTSTRAP" ] || { echo "FAIL: cannot find wt-bootstrap.sh at $WT_BOOTSTRAP"; exit 1; }
[ -f "$GUARD" ] || { echo "FAIL: cannot find guard-ai-destructive.sh at $GUARD"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
cleanup() {
    if [ -d "$WORK/project/.git" ]; then
        # Safe removal: unmount .ai/ first, then remove worktrees, then delete project.
        bash "$WT_BOOTSTRAP" --remove "$WORK/project" kiro 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init --quiet "$PROJECT"
git config user.email "test@example.com"
git config user.name  "test"

# Seed content so the primary checkout has a canonical .ai/.
mkdir -p "$PROJECT/.ai/handoffs/to-kimi/open"
echo "keep" > "$PROJECT/.ai/.gitkeep"
echo "seed" > "$PROJECT/seed.txt"
git add -A
git commit --quiet -m "seed"

# Bootstrap a kiro worktree.
bash "$WT_BOOTSTRAP" "$PROJECT" kiro >/dev/null 2>&1
WT_KIRO="$WORK/.wt/project/kiro"

# ======================================================================
# 1. Bootstrap creates a junction/symlink .ai/ in the worktree.
# ======================================================================
check "bootstrap: kiro worktree exists" "$([ -d "$WT_KIRO" ] && echo 0 || echo 1)"
check "bootstrap: .ai/ is mounted in worktree" "$([ -L "$WT_KIRO/.ai" ] && echo 0 || echo 1)"

# Add a shared report through the junction; this should land in the primary .ai/.
shared_report="$PROJECT/.ai/reports/coordination-report.md"
mkdir -p "$PROJECT/.ai/reports"
echo "shared findings" > "$shared_report"
check "junction: shared report visible through worktree" "$(grep -q 'shared findings' "$WT_KIRO/.ai/reports/coordination-report.md" 2>/dev/null && echo 0 || echo 1)"

# ======================================================================
# 2. guard-ai-destructive.sh blocks destructive ops while .ai/ is mounted.
# ======================================================================
if ( cd "$WT_KIRO" && bash "$GUARD" git clean -fd ) >/dev/null 2>&1; then
    check "guard: blocks git clean -fd while .ai/ mounted" 1
else
    check "guard: blocks git clean -fd while .ai/ mounted" 0
fi

if bash "$GUARD" --check "$WT_KIRO" >/dev/null 2>&1; then
    check "guard: --check fails while .ai/ mounted" 1
else
    check "guard: --check fails while .ai/ mounted" 0
fi

# ======================================================================
# 3. --remove unmounts .ai/ and removes the worktree without deleting canonical .ai/.
# ======================================================================
bash "$WT_BOOTSTRAP" --remove "$PROJECT" kiro >/dev/null 2>&1
check "remove: worktree directory gone" "$([ ! -e "$WT_KIRO" ] && echo 0 || echo 1)"
check "remove: canonical .ai/ still exists" "$([ -d "$PROJECT/.ai" ] && echo 0 || echo 1)"
check "remove: shared report survived" "$(grep -q 'shared findings' "$shared_report" 2>/dev/null && echo 0 || echo 1)"

# ======================================================================
# 4. guard allows destructive ops once .ai/ is unmounted.
# ======================================================================
# Create a dummy dir with a normal (non-junction) .ai/ subdir and prove the
# guard lets a destructive command through.
SAFE_DIR="$WORK/safe-dir"
mkdir -p "$SAFE_DIR/.ai" "$SAFE_DIR/junk"
echo "x" > "$SAFE_DIR/.ai/keep"
echo "y" > "$SAFE_DIR/junk/delete-me"
if ( cd "$SAFE_DIR" && bash "$GUARD" rm -rf junk ) >/dev/null 2>&1 && [ ! -e "$SAFE_DIR/junk" ]; then
    check "guard: allows rm -rf junk when .ai/ is normal dir" 0
else
    check "guard: allows rm -rf junk when .ai/ is normal dir" 1
fi

# ======================================================================
# 5. Re-creating the worktree after removal works and re-junctions .ai/.
# ======================================================================
bash "$WT_BOOTSTRAP" "$PROJECT" kiro >/dev/null 2>&1
check "re-create: worktree exists after removal" "$([ -d "$WT_KIRO" ] && echo 0 || echo 1)"
check "re-create: .ai/ is mounted again" "$([ -L "$WT_KIRO/.ai" ] && echo 0 || echo 1)"
check "re-create: shared report still visible" "$(grep -q 'shared findings' "$WT_KIRO/.ai/reports/coordination-report.md" 2>/dev/null && echo 0 || echo 1)"

echo ""
echo "==== wt-bootstrap-remove suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
