#!/bin/bash
# test-checkpoint-ai.sh — regression tests for checkpoint-ai.sh
#
# Run: bash .ai/tests/test-checkpoint-ai.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKPOINT="$REPO_ROOT/.ai/tools/checkpoint-ai.sh"
[ -f "$CHECKPOINT" ] || { echo "FAIL: cannot find checkpoint-ai.sh at $CHECKPOINT"; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

init_project() {
    local dir="$1"
    mkdir -p "$dir"
    cd "$dir"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name  "test"
    mkdir -p "$dir/.ai/handoffs/to-kimi/open"
    echo "keep" > "$dir/.ai/.gitkeep"
    echo "seed" > "$dir/seed.txt"
    git add -A
    git commit --quiet -m "seed"
}

init_project "$WORK/project"
PROJECT="$WORK/project"

# ==============================================================================
# 1. No .ai/ changes -> no commit, exit 0.
# ==============================================================================
out1="$(bash "$CHECKPOINT" "$PROJECT" 2>&1)"
rc1=$?
check "test1: exit 0 when no changes" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"
check "test1: reports no changes" "$(echo "$out1" | grep -q 'no .ai/ changes' && echo 0 || echo 1)"
commit_count_before="$(git -C "$PROJECT" rev-list --count HEAD)"

# ==============================================================================
# 2. .ai/ change -> checkpoint commit created.
# ==============================================================================
echo "new handoff" > "$PROJECT/.ai/handoffs/to-kimi/open/202607170001-test.md"
out2="$(bash "$CHECKPOINT" "$PROJECT" 2>&1)"
rc2=$?
commit_count_after="$(git -C "$PROJECT" rev-list --count HEAD)"
check "test2: exit 0 on .ai/ change" "$([ "$rc2" -eq 0 ] && echo 0 || echo 1)"
check "test2: commit count increased by 1" "$([ "$commit_count_after" -eq $((commit_count_before + 1)) ] && echo 0 || echo 1)"
check "test2: reports committed" "$(echo "$out2" | grep -q 'checkpoint committed' && echo 0 || echo 1)"
check "test2: only .ai/ file committed" "$(git -C "$PROJECT" show --stat HEAD | grep -q '.ai/handoffs/to-kimi/open/202607170001-test.md' && echo 0 || echo 1)"

# ==============================================================================
# 3. Non-.ai/ uncommitted change blocks checkpoint.
# ==============================================================================
echo "dirty" > "$PROJECT/seed.txt"
out3="$(bash "$CHECKPOINT" "$PROJECT" 2>&1)"
rc3=$?
check "test3: exit non-zero when non-.ai/ changes present" "$([ "$rc3" -ne 0 ] && echo 0 || echo 1)"
check "test3: mentions non-.ai/ changes" "$(echo "$out3" | grep -q 'non-.ai/ changes' && echo 0 || echo 1)"
# Revert the dirty change.
git -C "$PROJECT" checkout -- seed.txt

# ==============================================================================
# 4. --dry-run previews without committing.
# ==============================================================================
echo "another" > "$PROJECT/.ai/handoffs/to-kimi/open/202607170002-dry.md"
commit_count_before_dry="$(git -C "$PROJECT" rev-list --count HEAD)"
out4="$(bash "$CHECKPOINT" --dry-run "$PROJECT" 2>&1)"
rc4=$?
commit_count_after_dry="$(git -C "$PROJECT" rev-list --count HEAD)"
check "test4: dry-run exit 0" "$([ "$rc4" -eq 0 ] && echo 0 || echo 1)"
check "test4: dry-run does not create commit" "$([ "$commit_count_after_dry" -eq "$commit_count_before_dry" ] && echo 0 || echo 1)"
check "test4: dry-run previews changes" "$(echo "$out4" | grep -q 'would checkpoint' && echo 0 || echo 1)"

# ==============================================================================
# 5. Refuses to run inside a linked worktree.
# ==============================================================================
git -C "$PROJECT" worktree add "$PROJECT/../wt" -b test/worktree >/dev/null 2>&1
out5="$(bash "$CHECKPOINT" "$PROJECT/../wt" 2>&1)"
rc5=$?
check "test5: exit non-zero inside linked worktree" "$([ "$rc5" -ne 0 ] && echo 0 || echo 1)"
check "test5: mentions linked worktree" "$(echo "$out5" | grep -q 'linked worktree' && echo 0 || echo 1)"
git -C "$PROJECT" worktree remove --force "$PROJECT/../wt" >/dev/null 2>&1 || true

echo ""
echo "==== checkpoint-ai suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
