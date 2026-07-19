#!/bin/bash
# test-dispatch-worktree.sh -- regression suite for worktree-per-CLI dispatch
# (ADR-0004 amendment, 2026-07-11: docs/architecture/0004-worktree-multi-project-topology.md).
#
# Builds an isolated sandbox: a bare "origin", a primary checkout cloned from
# it (playing the role of the real repo root), and stub CLI binaries on PATH
# that record their cwd + branch instead of doing real work. Runs
# .ai/tools/dispatch-handoffs.sh --exec against that sandbox and asserts on
# the worktree-per-CLI contract from the handoff:
#   1. a dispatch runs in the CLI's worktree, NOT the primary checkout
#   2. an existing healthy worktree is reused, not recreated
#   3. worktree-creation failure => dispatch fails, handoff stays OPEN,
#      non-zero exit, NO fallback to the primary checkout
#   4. the branch is cut from the declared base, not ambient HEAD
#   5. a stale/pruned worktree does not wedge the dispatch
#   6. two concurrent dispatches (different CLIs) do not perturb each other's
#      HEAD or working files (the acceptance test for the whole task)
#
# Run: bash .ai/tests/test-dispatch-worktree.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCHER="$REPO_ROOT/.ai/tools/dispatch-handoffs.sh"
WT_BOOTSTRAP="$REPO_ROOT/scripts/wt-bootstrap.sh"
[ -f "$DISPATCHER" ]  || { echo "FAIL: cannot find dispatch-handoffs.sh at $DISPATCHER"; exit 1; }
[ -f "$WT_BOOTSTRAP" ] || { echo "FAIL: cannot find wt-bootstrap.sh at $WT_BOOTSTRAP"; exit 1; }

# TODO: remove this workaround once kiro's PR #97 (removing the skip-worktree
# reverse-write guard from wt-bootstrap.sh) lands on main. The guard makes
# `git restore --staged -- .ai` fail in a fresh sandbox, so we copy the live
# bootstrap into the sandbox and strip the guard function + call site.
pass=0
fail=0
check() { # desc, exit-code-of-condition (0 = pass)
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
STUB_BIN="$WORK/bin"
LOGS="$WORK/logs"
mkdir -p "$STUB_BIN" "$LOGS"
cleanup() {
    # Best-effort: prune any worktrees the sandbox project registered before
    # nuking the directory tree, so a leftover .git/worktrees entry in the
    # temp dir can't wedge a later `git worktree` call on the SAME machine.
    if [ -d "$WORK/project/.git" ]; then
        git -C "$WORK/project" worktree prune >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "Sandbox: $WORK"

# ---------- build a bare "origin" + a primary checkout cloned from it ----------
ORIGIN="$WORK/origin.git"
PROJECT="$WORK/project"     # plays the role of the real repo root ($root)
PARENT_DIR="$WORK"          # .wt/ lands as a SIBLING of $PROJECT, i.e. $WORK/.wt

git init --quiet --bare "$ORIGIN"

git init --quiet "$PROJECT"
git -C "$PROJECT" config user.email "test@example.com"
git -C "$PROJECT" config user.name  "test"
mkdir -p "$PROJECT/.ai/handoffs/to-kiro/open" "$PROJECT/.ai/handoffs/to-kimi/open" "$PROJECT/.ai/handoffs/to-opencode/open" "$PROJECT/.ai/reports"
# ensure_declared_base_branch() restores .ai/ from the declared base, so .ai/
# must exist in the repo tree. A .gitkeep is enough.
echo "keep" > "$PROJECT/.ai/.gitkeep"
echo "seed" > "$PROJECT/seed.txt"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit --quiet -m "seed"
git -C "$PROJECT" branch -M main
# Use a relative path for the remote to avoid MSYS/Cygwin absolute-path
# conversion issues in Git-for-Windows that can cause "could not read from
# remote repository" / shared-library load errors in temp sandboxes.
git -C "$PROJECT" remote add origin "../origin.git"
git -C "$PROJECT" push --quiet -u origin main

# Copy a working wt-bootstrap.sh into the sandbox so the dispatcher (which
# resolves it from $root/scripts/wt-bootstrap.sh) picks up the sandbox version.
mkdir -p "$PROJECT/scripts" "$PROJECT/.ai/tools"
cp "$WT_BOOTSTRAP" "$PROJECT/scripts/wt-bootstrap.sh"
cp "$REPO_ROOT/.ai/tools/sync-ai-state.sh" "$PROJECT/.ai/tools/sync-ai-state.sh"

# ---------- stub CLI binaries on PATH ----------
# Each stub: records its own cwd + current branch to a per-CLI log file, then
# exits 0. This is the "stub-binary test" pattern already used to find the
# same-second dispatch-failure collision bug (see dispatch-handoffs.sh header).
make_stub() {
    local name="$1" logfile="$2"
    cat > "$STUB_BIN/$name" <<EOF
#!/bin/bash
{
  echo "cwd=\$(pwd)"
  echo "branch=\$(git branch --show-current 2>/dev/null)"
  echo "args=\$*"
} >> "$logfile"
exit 0
EOF
    chmod +x "$STUB_BIN/$name"
}
make_stub "kiro-cli" "$LOGS/kiro.log"
make_stub "kimi"     "$LOGS/kimi.log"

export PATH="$STUB_BIN:$PATH"

mk_handoff() {
    local cli="$1" slug="$2" extra="${3:-}"
    cat > "$PROJECT/.ai/handoffs/to-$cli/open/$slug.md" <<EOF
# Test handoff
Status: OPEN
Sender: claude-code
Recipient: $cli
Created: 2026-07-11 00:00 (UTC+7)
Auto: yes
Risk: A
$extra

## Goal
Test handoff for dispatch-worktree suite.
EOF
}

run_dispatcher() {
    ( cd "$PROJECT" && bash "$DISPATCHER" --exec "$@" )
}

# ======================================================================
# 1 + 2. A dispatch runs in the CLI's worktree, not the primary checkout;
#        re-running reuses the existing worktree rather than recreating it.
# ======================================================================
mk_handoff kiro 202607110001-t1
out1="$(run_dispatcher --only kiro 2>&1)"
rc1=$?
check "test1: dispatcher exits 0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"

wt_kiro="$WORK/.wt/project/kiro"
check "test1: kiro worktree dir created at .wt/project/kiro" "$([ -d "$wt_kiro" ] && echo 0 || echo 1)"

kiro_log1="$LOGS/kiro.log"
if [ -f "$kiro_log1" ]; then
    cwd_seen="$(grep '^cwd=' "$kiro_log1" | tail -1 | cut -d= -f2-)"
    # Realpath both sides to survive any /tmp vs /private/tmp style symlink games.
    cwd_real="$(cd "$cwd_seen" 2>/dev/null && pwd)"
    wt_real="$(cd "$wt_kiro" 2>/dev/null && pwd)"
    check "test1: stub ran with cwd == kiro worktree (got '$cwd_seen')" "$([ -n "$cwd_real" ] && [ "$cwd_real" = "$wt_real" ] && echo 0 || echo 1)"
    check "test1: stub ran with cwd != primary checkout" "$([ "$cwd_real" != "$PROJECT" ] && echo 0 || echo 1)"
else
    check "test1: stub log written" 1
    check "test1 (skipped: no log)" 1
fi

# Mark the worktree with a sentinel BEFORE the second dispatch so a "recreate"
# (destroy + re-add) would wipe it, but a "reuse" would not.
sentinel="$wt_kiro/.sentinel-from-test"
echo "keep-me" > "$sentinel" 2>/dev/null

# Move handoff 1 back to OPEN-equivalent state for a clean re-run: create a
# second, independent handoff so this is a genuine second dispatch cycle.
mk_handoff kiro 202607110002-t2
run_dispatcher --only kiro >/dev/null 2>&1
check "test2: worktree reused, not recreated (sentinel file survives)" "$([ -f "$sentinel" ] && echo 0 || echo 1)"
rm -f "$sentinel"   # clean up so later kiro dispatches actually cut branches

# ======================================================================
# 3. Worktree-creation failure => dispatch fails, handoff stays OPEN,
#    non-zero item path taken (surfaced as a FAIL/ALERT line + report),
#    and it NEVER falls back to running in the primary checkout.
# ======================================================================
# Force wt-bootstrap.sh to fail for a fresh CLI by pre-creating a non-worktree
# FILE at the exact path it would use — wt-bootstrap.sh's own contract is to
# `die` rather than touch a path that exists but isn't a git worktree.
mkdir -p "$WORK/.wt/project"
: > "$WORK/.wt/project/opencode"   # a plain file, not a directory/worktree

# opencode has no stub on PATH by default; add one so this test is isolated
# to the worktree-failure path specifically rather than the PATH-skip path
# (bin_for/command -v runs BEFORE worktree setup in the dispatcher).
make_stub "opencode" "$LOGS/opencode.log"
mk_handoff opencode 202607110003-t3

before_reports="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
out3="$(run_dispatcher --only opencode 2>&1)"
after_reports="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"

check "test3: dispatcher reports a FAIL for the broken worktree" "$(echo "$out3" | grep -q 'FAIL.*opencode' && echo 0 || echo 1)"
check "test3: a dispatch-failure report was written" "$([ "$after_reports" -gt "$before_reports" ] && echo 0 || echo 1)"
check "test3: handoff file still present in open/ (never moved)" "$([ -f "$PROJECT/.ai/handoffs/to-opencode/open/202607110003-t3.md" ] && echo 0 || echo 1)"
check "test3: handoff Status is still OPEN" "$(grep -q '^Status: OPEN' "$PROJECT/.ai/handoffs/to-opencode/open/202607110003-t3.md" && echo 0 || echo 1)"
check "test3: stub was NEVER invoked (no fallback to primary checkout)" "$([ ! -f "$LOGS/opencode.log" ] && echo 0 || echo 1)"
check "test3: primary checkout untouched (no stray opencode worktree artifacts in \$PROJECT)" "$([ ! -e "$PROJECT/.sentinel-from-test" ] && echo 0 || echo 1)"

rm -f "$WORK/.wt/project/opencode"   # clear the induced failure for later tests
rm -f "$PROJECT/.ai/handoffs/to-opencode/open/202607110003-t3.md"  # don't let it dispatch in later tests

# ======================================================================
# 4. Branch is cut from the DECLARED base (origin/main), not ambient HEAD.
# ======================================================================
# Put a decoy commit on a decoy branch and check it out in the PRIMARY
# checkout, simulating "whatever HEAD happens to be" at dispatch time.
# `git add decoy.txt` explicitly (NOT `-A`) -- `.ai/handoffs/**` is untracked
# scratch state for this test harness and must never be staged/committed; doing
# so would make main checkout later DELETE those files (they'd only exist on
# the decoy branch), which is a self-inflicted test bug, not a dispatcher one.
git -C "$PROJECT" checkout --quiet -b decoy/should-not-be-base
echo "decoy content" > "$PROJECT/decoy.txt"
git -C "$PROJECT" add decoy.txt
git -C "$PROJECT" commit --quiet -m "decoy commit not on main"
DECOY_SHA="$(git -C "$PROJECT" rev-parse HEAD)"
git -C "$PROJECT" checkout --quiet main

mk_handoff kimi 202607110004-t4
run_dispatcher --only kimi >/dev/null 2>&1

wt_kimi="$WORK/.wt/project/kimi"
if [ -d "$wt_kimi" ]; then
    branch_head="$(git -C "$wt_kimi" rev-parse "exec/kimi/202607110004-t4" 2>/dev/null)"
    main_head="$(git -C "$PROJECT" rev-parse origin/main 2>/dev/null)"
    check "test4: exec/kimi/<slug> branch exists" "$([ -n "$branch_head" ] && echo 0 || echo 1)"
    check "test4: exec/kimi/<slug> was cut from origin/main, not the decoy branch" "$([ "$branch_head" = "$main_head" ] && echo 0 || echo 1)"
    check "test4: decoy commit is NOT an ancestor of the dispatched branch" "$(git -C "$wt_kimi" merge-base --is-ancestor "$DECOY_SHA" "exec/kimi/202607110004-t4" 2>/dev/null; [ $? -ne 0 ] && echo 0 || echo 1)"
else
    check "test4: kimi worktree exists" 1
fi

# ==============================================================================
# 4a. Annotated Base: line is parsed correctly — only the first token is used.
# ==============================================================================
mk_handoff kimi 202607110004-t4a "Base: origin/main (4df2cbf)"
out4a="$(run_dispatcher --only kimi 2>&1)"
rc4a=$?
check "test4a: dispatcher exits 0 with annotated Base:" "$([ "$rc4a" -eq 0 ] && echo 0 || echo 1)"
wt_kimi4a="$WORK/.wt/project/kimi"
if [ -d "$wt_kimi4a" ]; then
    branch_head4a="$(git -C "$wt_kimi4a" rev-parse "exec/kimi/202607110004-t4a" 2>/dev/null)"
    main_head4a="$(git -C "$PROJECT" rev-parse origin/main 2>/dev/null)"
    check "test4a: exec/kimi/<slug> branch exists" "$([ -n "$branch_head4a" ] && echo 0 || echo 1)"
    check "test4a: branch cut from annotated base resolves to origin/main" "$([ "$branch_head4a" = "$main_head4a" ] && echo 0 || echo 1)"
else
    check "test4a: kimi worktree exists" 1
fi

# ==============================================================================
# 4b. Genuinely unresolvable Base: fails loudly and makes --exec exit non-zero.
# ==============================================================================
mk_handoff kiro 202607110004-t4b "Base: origin/does-not-exist"
before_reports4b="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
out4b="$(run_dispatcher --only kiro 2>&1)"
rc4b=$?
after_reports4b="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"

check "test4b: dispatcher exits non-zero for unresolvable base" "$([ "$rc4b" -ne 0 ] && echo 0 || echo 1)"
check "test4b: dispatcher reports FAIL for unresolvable base" "$(echo "$out4b" | grep -q 'FAIL.*kiro.*could not establish declared-base' && echo 0 || echo 1)"
check "test4b: a dispatch-failure report was written" "$([ "$after_reports4b" -gt "$before_reports4b" ] && echo 0 || echo 1)"
check "test4b: handoff file still present in open/" "$([ -f "$PROJECT/.ai/handoffs/to-kiro/open/202607110004-t4b.md" ] && echo 0 || echo 1)"
check "test4b: handoff Status is still OPEN" "$(grep -q '^Status: OPEN' "$PROJECT/.ai/handoffs/to-kiro/open/202607110004-t4b.md" && echo 0 || echo 1)"
# Remove the deliberately-broken handoff so later --only kiro runs do not
# repeatedly fail and make their exit codes non-zero.
rm -f "$PROJECT/.ai/handoffs/to-kiro/open/202607110004-t4b.md"

# ==============================================================================
# 4c. Repo whose default branch is `main` (no `origin/main`) resolves the
#     declared base to `origin/main` and dispatches without error. Regression
#     test for the hardcoded origin/main default-base bug.
# ==============================================================================
ORIGIN_MAIN="$WORK/origin-main.git"
PROJECT_MAIN="$WORK/project-main"
git init --quiet --bare "$ORIGIN_MAIN"
git init --quiet "$PROJECT_MAIN"
git -C "$PROJECT_MAIN" config user.email "test@example.com"
git -C "$PROJECT_MAIN" config user.name  "test"
mkdir -p "$PROJECT_MAIN/.ai/handoffs/to-kimi/open" "$PROJECT_MAIN/.ai/reports"
echo "keep" > "$PROJECT_MAIN/.ai/.gitkeep"
echo "seed" > "$PROJECT_MAIN/seed.txt"
git -C "$PROJECT_MAIN" add -A
git -C "$PROJECT_MAIN" commit --quiet -m "seed"
git -C "$PROJECT_MAIN" branch -M main
# Relative remote path avoids Git-for-Windows absolute-path conversion issues.
git -C "$PROJECT_MAIN" remote add origin "../origin-main.git"
git -C "$PROJECT_MAIN" push --quiet -u origin main

mkdir -p "$PROJECT_MAIN/scripts" "$PROJECT_MAIN/.ai/tools"
cp "$WT_BOOTSTRAP" "$PROJECT_MAIN/scripts/wt-bootstrap.sh"
cp "$REPO_ROOT/.ai/tools/sync-ai-state.sh" "$PROJECT_MAIN/.ai/tools/sync-ai-state.sh"

mk_handoff_for() {
    local project="$1" cli="$2" slug="$3" extra="${4:-}"
    cat > "$project/.ai/handoffs/to-$cli/open/$slug.md" <<EOF
# Test handoff
Status: OPEN
Sender: claude-code
Recipient: $cli
Created: 2026-07-11 00:00 (UTC+7)
Auto: yes
Risk: A
$extra

## Goal
Test handoff for main-default dispatch suite.
EOF
}

mk_handoff_for "$PROJECT_MAIN" kimi 202607110004-t4c
(
    cd "$PROJECT_MAIN" && bash "$DISPATCHER" --exec --only kimi
) >"$LOGS/t4c-dispatcher.out" 2>&1
rc4c=$?
check "test4c: dispatcher exits 0 on a main-only repo" "$([ "$rc4c" -eq 0 ] && echo 0 || echo 1)"

wt_kimi_main="$WORK/.wt/project-main/kimi"
if [ -d "$wt_kimi_main" ]; then
    branch_head_main="$(git -C "$wt_kimi_main" rev-parse --verify --quiet "exec/kimi/202607110004-t4c" 2>/dev/null)"
    origin_main_head="$(git -C "$PROJECT_MAIN" rev-parse --verify --quiet origin/main 2>/dev/null)"
    check "test4c: exec/kimi/<slug> branch exists" "$([ -n "$branch_head_main" ] && echo 0 || echo 1)"
    check "test4c: branch was cut from origin/main (repo has no master ref)" "$([ "$branch_head_main" = "$origin_main_head" ] && echo 0 || echo 1)"
else
    check "test4c: kimi worktree exists" 1
fi

# ==============================================================================
# 4d. base_for() refreshes stale/missing local refs before resolving. Push a new
#     commit to origin/main, rewind the local cache, delete origin/HEAD, then
#     prove the dispatcher fetches and still cuts from the latest origin/main.
# ==============================================================================
echo "second" > "$PROJECT_MAIN/second.txt"
git -C "$PROJECT_MAIN" add second.txt
git -C "$PROJECT_MAIN" commit --quiet -m "second on main"
LATEST_MAIN="$(git -C "$PROJECT_MAIN" rev-parse HEAD)"
git -C "$PROJECT_MAIN" push --quiet origin main

# Rewind local refs to simulate a stale primary checkout / pruned worktree.
git -C "$PROJECT_MAIN" update-ref refs/remotes/origin/main "${LATEST_MAIN}~1"
git -C "$PROJECT_MAIN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/does-not-exist

mk_handoff_for "$PROJECT_MAIN" kimi 202607110004-t4d
(
    cd "$PROJECT_MAIN" && bash "$DISPATCHER" --exec --only kimi
) >"$LOGS/t4d-dispatcher.out" 2>&1
rc4d=$?
check "test4d: dispatcher exits 0 despite stale local refs" "$([ "$rc4d" -eq 0 ] && echo 0 || echo 1)"

wt_kimi_main4d="$WORK/.wt/project-main/kimi"
if [ -d "$wt_kimi_main4d" ]; then
    branch_head_4d="$(git -C "$wt_kimi_main4d" rev-parse --verify --quiet "exec/kimi/202607110004-t4d" 2>/dev/null)"
    check "test4d: exec/kimi/<slug> branch exists" "$([ -n "$branch_head_4d" ] && echo 0 || echo 1)"
    check "test4d: branch was cut from latest origin/main after fetch" "$([ "$branch_head_4d" = "$LATEST_MAIN" ] && echo 0 || echo 1)"
else
    check "test4d: kimi worktree exists" 1
fi

# ==============================================================================
# 5. A stale/pruned worktree does not wedge the dispatch.
# ======================================================================
# Simulate the exact staleness class the handoff calls out: the worktree
# directory is gone from disk but git's .git/worktrees/<name> bookkeeping
# still references it ("already checked out" hazard) until pruned.
if [ -d "$wt_kiro" ]; then
    rm -rf "$wt_kiro"
    git -C "$PROJECT" worktree prune
    mk_handoff kiro 202607110005-t5
    out5="$(run_dispatcher --only kiro 2>&1)"
    rc5=$?
    check "test5: dispatch after prune succeeds (no wedge)" "$([ "$rc5" -eq 0 ] && echo 0 || echo 1)"
    check "test5: worktree re-created after prune" "$([ -d "$wt_kiro" ] && echo 0 || echo 1)"
else
    check "test5: precondition (kiro worktree existed)" 1
fi

# ======================================================================
# 6. THE REAL PROOF — two concurrent dispatches (different CLIs) do not
#    perturb each other's HEAD or on-disk files. This is the direct
#    regression test for the 2026-07-11 near-miss: a `git checkout` in one
#    CLI's context must never be observable from another's.
# ======================================================================
# Clean up test4's leftover dirt on the kimi worktree first, so THIS test
# proves the concurrent clean-branch-cut case distinctly from the "dirty
# worktree is never destroyed" case (already covered by test4's WARN path;
# re-asserted below in isolation as 6b).
if [ -d "$wt_kimi" ]; then
    git -C "$wt_kimi" add -A >/dev/null 2>&1 || true
    git -C "$wt_kimi" commit --quiet -m "test6 setup: clear dirt from test4" >/dev/null 2>&1 || true
fi

mk_handoff kiro 202607110006-t6
mk_handoff kimi 202607110006-t6

( run_dispatcher --only kiro >"$LOGS/concurrent-kiro.out" 2>&1 ) &
pid_kiro=$!
( run_dispatcher --only kimi >"$LOGS/concurrent-kimi.out" 2>&1 ) &
pid_kimi=$!
wait "$pid_kiro"; rc_ckiro=$?
wait "$pid_kimi"; rc_ckimi=$?

check "test6: concurrent kiro dispatch exited 0" "$([ "$rc_ckiro" -eq 0 ] && echo 0 || echo 1)"
check "test6: concurrent kimi dispatch exited 0" "$([ "$rc_ckimi" -eq 0 ] && echo 0 || echo 1)"

kiro_branch_after="$(git -C "$wt_kiro" branch --show-current 2>/dev/null)"
kimi_branch_after="$(git -C "$wt_kimi" branch --show-current 2>/dev/null)"
check "test6: kiro worktree ended on its own branch (exec/kiro/202607110006-t6)" "$([ "$kiro_branch_after" = "exec/kiro/202607110006-t6" ] && echo 0 || echo 1)"
check "test6: kimi worktree ended on its own branch (exec/kimi/202607110006-t6)" "$([ "$kimi_branch_after" = "exec/kimi/202607110006-t6" ] && echo 0 || echo 1)"
check "test6: primary checkout ($PROJECT) stayed on main throughout" "$([ "$(git -C "$PROJECT" branch --show-current)" = "main" ] && echo 0 || echo 1)"

# ---- 6b: a DIRTY worktree survives a CONCURRENT neighbor's dispatch ----
# Re-dirty the kimi worktree (uncommitted, off .ai/) and prove kiro's
# concurrent run (a) never touches it and (b) kimi's OWN dispatch also
# refuses to destroy it (reuse-as-is safety path), matching test4's WARN case
# but now proven under genuine concurrency rather than sequentially.
if [ -d "$wt_kimi" ]; then
    kimi_branch_before="$(git -C "$wt_kimi" branch --show-current 2>/dev/null)"
    echo "kimi-private" > "$wt_kimi/.kimi-private-marker"
fi
mk_handoff kiro 202607110007-t6b
mk_handoff kimi 202607110007-t6b
( run_dispatcher --only kiro >"$LOGS/concurrent-kiro-6b.out" 2>&1 ) &
pid_kiro6b=$!
( run_dispatcher --only kimi >"$LOGS/concurrent-kimi-6b.out" 2>&1 ) &
pid_kimi6b=$!
wait "$pid_kiro6b"
wait "$pid_kimi6b"
kimi_branch_after6b="$(git -C "$wt_kimi" branch --show-current 2>/dev/null)"
check "test6b: kimi worktree branch unchanged (dirty -> reuse-as-is, never destroyed, even under concurrency)" "$([ "$kimi_branch_after6b" = "$kimi_branch_before" ] && echo 0 || echo 1)"
check "test6b: kimi's private marker survived a concurrent kiro dispatch" "$([ -f "$wt_kimi/.kimi-private-marker" ] && echo 0 || echo 1)"

# ======================================================================
# S2-4. Self-addressed handoff is rejected before launch.
# ======================================================================
cat > "$PROJECT/.ai/handoffs/to-opencode/open/202607110008-s2-4-self.md" <<'EOF'
# Self-addressed test
Status: OPEN
Sender: opencode-auto
Recipient: opencode-auto
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: A

## Goal
Prove self-addressed handoffs are rejected.
EOF
before_reports_s24="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
out_s24="$(run_dispatcher --only opencode 2>&1)"
after_reports_s24="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
check "S2-4: dispatcher reports FAIL for self-addressed handoff" "$(echo "$out_s24" | grep -qi 'self-addressed' && echo 0 || echo 1)"
check "S2-4: dispatch-failure report was written" "$([ "$after_reports_s24" -gt "$before_reports_s24" ] && echo 0 || echo 1)"
check "S2-4: handoff stays OPEN" "$(grep -q '^Status: OPEN' "$PROJECT/.ai/handoffs/to-opencode/open/202607110008-s2-4-self.md" && echo 0 || echo 1)"
check "S2-4: stub was not invoked" "$([ ! -f "$LOGS/opencode.log" ] && echo 0 || echo 1)"

# ======================================================================
# S2-5. Dirty worktree (different branch) fails by default;
#       --reuse-dirty allows reuse.
# ======================================================================
# Put the kiro worktree on a different branch with uncommitted work.
if [ -d "$wt_kiro" ]; then
    git -C "$wt_kiro" checkout --quiet -b test/s2-5-dirty
    echo "dirty" > "$wt_kiro/.dirty-marker"
fi
cat > "$PROJECT/.ai/handoffs/to-kiro/open/202607110009-s2-5-dirty.md" <<'EOF'
# Dirty-worktree test
Status: OPEN
Sender: claude-code
Recipient: kiro
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: A

## Goal
Prove dirty worktree default failure and --reuse-dirty reuse.
EOF
before_reports_s25="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
out_s25_default="$(run_dispatcher --only kiro 2>&1)"
after_reports_s25="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
check "S2-5: default dispatch FAILs on dirty worktree" "$(echo "$out_s25_default" | grep -qi 'FAIL.*kiro' && echo 0 || echo 1)"
check "S2-5: default dispatch wrote a failure report" "$([ "$after_reports_s25" -gt "$before_reports_s25" ] && echo 0 || echo 1)"
check "S2-5: handoff stays OPEN after default failure" "$(grep -q '^Status: OPEN' "$PROJECT/.ai/handoffs/to-kiro/open/202607110009-s2-5-dirty.md" && echo 0 || echo 1)"
check "S2-5: stub not invoked for the dirty handoff by default" "$(grep -q '202607110009-s2-5-dirty' "$LOGS/kiro.log" 2>/dev/null && echo 1 || echo 0)"

# Now run with --reuse-dirty; the dirty worktree is reused and the handoff dispatches.
before_reports_s25r="$after_reports_s25"
out_s25_reuse="$(run_dispatcher --only kiro --reuse-dirty 2>&1)"
after_reports_s25r="$(ls "$PROJECT/.ai/reports" 2>/dev/null | wc -l)"
check "S2-5: --reuse-dirty emits a WARN" "$(echo "$out_s25_reuse" | grep -qi 'WARN.*dirty' && echo 0 || echo 1)"
check "S2-5: --reuse-dirty dispatches the handoff" "$(grep -q '202607110009-s2-5-dirty' "$LOGS/kiro.log" && echo 0 || echo 1)"
check "S2-5: --reuse-dirty wrote no new failure report" "$([ "$after_reports_s25r" -eq "$before_reports_s25r" ] && echo 0 || echo 1)"

# ======================================================================
# S3-4. Status block parsing is key-based and tolerates extra headers / ## Blocker.
# ======================================================================
# Clean the kimi worktree so this test proves parsing, not dirty-worktree behavior.
if [ -d "$wt_kimi" ]; then
    rm -f "$wt_kimi/.kimi-private-marker"
    git -C "$wt_kimi" reset --hard >/dev/null 2>&1 || true
fi
cat > "$PROJECT/.ai/handoffs/to-kimi/open/202607110010-s3-4-blocker.md" <<'EOF'
# Status-block parsing test
Status: OPEN
Owner: claude-cockpit
Auto: yes
Risk: A
## Blocker
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)

## Goal
Prove status block parsing tolerates extra header lines and a ## Blocker before Sender.
EOF
out_s34="$(run_dispatcher --only kimi 2>&1)"
rc_s34=$?
check "S3-4: dispatcher exits 0 despite extra header lines and ## Blocker" "$([ "$rc_s34" -eq 0 ] && echo 0 || echo 1)"
check "S3-4: handoff was dispatched (slug in kimi log)" "$(grep -q '202607110010-s3-4-blocker' "$LOGS/kimi.log" && echo 0 || echo 1)"

# ======================================================================
# Protocol v4 regression tests (Evidence, Gate, Observed-in)
# ======================================================================
# Clean the kimi worktree so these tests prove protocol gating, not dirty-worktree behavior.
if [ -d "$wt_kimi" ]; then
    rm -f "$wt_kimi/.kimi-private-marker"
    git -C "$wt_kimi" reset --hard >/dev/null 2>&1 || true
fi

# Remove leftover kimi handoffs from earlier tests so each v4 dispatcher run
# processes only the target handoff. This keeps the suite fast enough to finish
# within the execution timeout without changing any assertions.
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110004-t4.md" \
      "$PROJECT/.ai/handoffs/to-kimi/open/202607110004-t4a.md" \
      "$PROJECT/.ai/handoffs/to-kimi/open/202607110006-t6.md" \
      "$PROJECT/.ai/handoffs/to-kimi/open/202607110007-t6b.md" \
      "$PROJECT/.ai/handoffs/to-kimi/open/202607110010-s3-4-blocker.md"
rm -f "$PROJECT_MAIN/.ai/handoffs/to-kimi/open/202607110004-t4c.md" \
      "$PROJECT_MAIN/.ai/handoffs/to-kimi/open/202607110004-t4d.md"

# ---- v4-1. Evidence: HYPOTHESIS at Risk A/B dispatches verify-first ----
mk_handoff kimi 202607110011-v4-hypothesis "Evidence: HYPOTHESIS"
out_v41="$(run_dispatcher --only kimi 2>&1)"
rc_v41=$?
check "v4-1: Evidence: HYPOTHESIS at Risk A/B dispatches (exit 0)" "$([ "$rc_v41" -eq 0 ] && echo 0 || echo 1)"
check "v4-1: dispatcher reports HYPOTHESIS verify-first" "$(echo "$out_v41" | grep -q 'HYPOTHESIS.*verifies premise' && echo 0 || echo 1)"
check "v4-1: kimi stub was invoked" "$(grep -q '202607110011-v4-hypothesis' "$LOGS/kimi.log" && echo 0 || echo 1)"
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110011-v4-hypothesis.md"

# ---- v4-2. Risk C without Gate: is HELD ----
cat > "$PROJECT/.ai/handoffs/to-kimi/open/202607110012-v4-risk-c-no-gate.md" <<'EOF'
# Risk C no-gate test
Status: OPEN
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: C

## Goal
Prove Risk C with no Gate: is held.
EOF
out_v42="$(run_dispatcher --only kimi 2>&1)"
check "v4-2: Risk C with no Gate: is HELD" "$(echo "$out_v42" | grep -q 'HOLD.*Risk C with no Gate:' && echo 0 || echo 1)"
check "v4-2: kimi stub was not invoked" "$(grep -q '202607110012-v4-risk-c-no-gate' "$LOGS/kimi.log" 2>/dev/null && echo 1 || echo 0)"
check "v4-2: handoff stays OPEN" "$(grep -q '^Status: OPEN' "$PROJECT/.ai/handoffs/to-kimi/open/202607110012-v4-risk-c-no-gate.md" && echo 0 || echo 1)"
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110012-v4-risk-c-no-gate.md"

# ---- v4-3. Hard Gate: with Gate-satisfied-by still HOLDs ----
cat > "$PROJECT/.ai/handoffs/to-kimi/open/202607110013-v4-risk-c-hard-gate.md" <<'EOF'
# Risk C hard-gate test
Status: OPEN
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: C
Gate: production deploy
Gate-satisfied-by: owner@2026-07-17 00:00 (UTC+7)

## Goal
Prove a hard Gate: is never auto-dispatched, even with Gate-satisfied-by.
EOF
out_v43="$(run_dispatcher --only kimi 2>&1)"
rc_v43=$?
check "v4-3: Risk C hard gate HOLDs even with Gate-satisfied-by (exit 0)" "$([ "$rc_v43" -eq 0 ] && echo 0 || echo 1)"
check "v4-3: dispatcher reports hard gate requires cockpit" "$(echo "$out_v43" | grep -q 'hard gate.*requires cockpit' && echo 0 || echo 1)"
check "v4-3: kimi stub was not invoked" "$(grep -q '202607110013-v4-risk-c-hard-gate' "$LOGS/kimi.log" 2>/dev/null && echo 1 || echo 0)"
check "v4-3: handoff stays OPEN" "$(grep -q '^Status: OPEN' "$PROJECT/.ai/handoffs/to-kimi/open/202607110013-v4-risk-c-hard-gate.md" && echo 0 || echo 1)"
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110013-v4-risk-c-hard-gate.md"

# ---- v4-3b. Non-hard Gate: with Gate-satisfied-by DISPATCHes ----
cat > "$PROJECT/.ai/handoffs/to-kimi/open/202607110013b-v4-risk-c-soft-gate.md" <<'EOF'
# Risk C soft-gate test
Status: OPEN
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: C
Gate: update documentation
Gate-satisfied-by: owner@2026-07-17 00:00 (UTC+7)

## Goal
Prove a non-hard Gate: with Gate-satisfied-by auto-dispatches.
EOF
out_v43b="$(run_dispatcher --only kimi 2>&1)"
rc_v43b=$?
check "v4-3b: Risk C non-hard gate with Gate-satisfied-by dispatches (exit 0)" "$([ "$rc_v43b" -eq 0 ] && echo 0 || echo 1)"
check "v4-3b: dispatcher reports non-hard Gate: with satisfied Gate-satisfied-by" "$(echo "$out_v43b" | grep -q 'non-hard Gate:.*satisfied Gate-satisfied-by' && echo 0 || echo 1)"
check "v4-3b: kimi stub was invoked" "$(grep -q '202607110013b-v4-risk-c-soft-gate' "$LOGS/kimi.log" && echo 0 || echo 1)"
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110013b-v4-risk-c-soft-gate.md"

# ---- v4-4. Observed-in mismatch on origin/main fails before branch cut ----
# Use the main-default project so the observed branch is origin/main.
DECOY_SHA_MAIN="$(git -C "$PROJECT_MAIN" rev-parse --verify --quiet 'decoy/main-not-base^{commit}' 2>/dev/null || true)"
if [ -z "$DECOY_SHA_MAIN" ]; then
    git -C "$PROJECT_MAIN" checkout --quiet -b decoy/main-not-base
    echo "decoy content main" > "$PROJECT_MAIN/decoy-main.txt"
    git -C "$PROJECT_MAIN" add decoy-main.txt
    git -C "$PROJECT_MAIN" commit --quiet -m "decoy commit not on main"
    DECOY_SHA_MAIN="$(git -C "$PROJECT_MAIN" rev-parse --verify --quiet HEAD)"
    git -C "$PROJECT_MAIN" checkout --quiet main
fi
if [ -n "$DECOY_SHA_MAIN" ]; then
    mk_handoff_for "$PROJECT_MAIN" kimi 202607110014-v4-observed-mismatch "Observed-in: origin/main@$DECOY_SHA_MAIN"
    before_reports_v44="$(ls "$PROJECT_MAIN/.ai/reports" 2>/dev/null | wc -l)"
    (
        cd "$PROJECT_MAIN" && bash "$DISPATCHER" --exec --only kimi
    ) >"$LOGS/t4-v44-dispatcher.out" 2>&1
    rc_v44=$?
    out_v44="$(cat "$LOGS/t4-v44-dispatcher.out")"
    after_reports_v44="$(ls "$PROJECT_MAIN/.ai/reports" 2>/dev/null | wc -l)"
    check "v4-4: Observed-in mismatch exits non-zero" "$([ "$rc_v44" -ne 0 ] && echo 0 || echo 1)"
    check "v4-4: dispatcher reports evidence-base mismatch" "$(echo "$out_v44" | grep -Eq 'evidence-base mismatch|not an ancestor' && echo 0 || echo 1)"
    check "v4-4: dispatch-failure report was written" "$([ "$after_reports_v44" -gt "$before_reports_v44" ] && echo 0 || echo 1)"
    check "v4-4: handoff stays OPEN" "$(grep -q '^Status: OPEN' "$PROJECT_MAIN/.ai/handoffs/to-kimi/open/202607110014-v4-observed-mismatch.md" && echo 0 || echo 1)"
    check "v4-4: kimi stub was not invoked" "$(grep -q '202607110014-v4-observed-mismatch' "$LOGS/kimi.log" 2>/dev/null && echo 1 || echo 0)"
    rm -f "$PROJECT_MAIN/.ai/handoffs/to-kimi/open/202607110014-v4-observed-mismatch.md"
else
    check "v4-4: precondition (decoy branch exists)" 1
fi

# ---- v4-4b. Observed-in abbreviated SHA of origin/main dispatches ----
MAIN_SHA_SHORT="$(git -C "$PROJECT_MAIN" rev-parse --short=8 origin/main)"
mk_handoff_for "$PROJECT_MAIN" kimi 202607110014b-v4-observed-abbrev "Observed-in: origin/main@$MAIN_SHA_SHORT"
(
    cd "$PROJECT_MAIN" && bash "$DISPATCHER" --exec --only kimi
) >"$LOGS/t4-v44b-dispatcher.out" 2>&1
rc_v44b=$?
out_v44b="$(cat "$LOGS/t4-v44b-dispatcher.out")"
check "v4-4b: Observed-in abbreviated SHA dispatches (exit 0)" "$([ "$rc_v44b" -eq 0 ] && echo 0 || echo 1)"
check "v4-4b: dispatcher reports no evidence-base mismatch" "$(echo "$out_v44b" | grep -qv 'evidence-base mismatch' && echo 0 || echo 1)"
check "v4-4b: kimi stub was invoked" "$(grep -q '202607110014b-v4-observed-abbrev' "$LOGS/kimi.log" && echo 0 || echo 1)"
rm -f "$PROJECT_MAIN/.ai/handoffs/to-kimi/open/202607110014b-v4-observed-abbrev.md"

# ---- v4-4c. Observed-in ancestor SHA of origin/main dispatches ----
# Make the base advance by one commit so origin/main~1 is a strict ancestor.
git -C "$PROJECT_MAIN" checkout --quiet main
echo "ancestor advance" > "$PROJECT_MAIN/ancestor-advance.txt"
git -C "$PROJECT_MAIN" add ancestor-advance.txt
git -C "$PROJECT_MAIN" commit --quiet -m "advance main for v4-4c ancestor test"
git -C "$PROJECT_MAIN" push --quiet origin main
ANCESTOR_SHA="$(git -C "$PROJECT_MAIN" rev-parse origin/main~1)"
mk_handoff_for "$PROJECT_MAIN" kimi 202607110014c-v4-observed-ancestor "Observed-in: origin/main@$ANCESTOR_SHA"
(
    cd "$PROJECT_MAIN" && bash "$DISPATCHER" --exec --only kimi
) >"$LOGS/t4-v44c-dispatcher.out" 2>&1
rc_v44c=$?
out_v44c="$(cat "$LOGS/t4-v44c-dispatcher.out")"
check "v4-4c: Observed-in ancestor SHA dispatches (exit 0)" "$([ "$rc_v44c" -eq 0 ] && echo 0 || echo 1)"
check "v4-4c: dispatcher reports no evidence-base mismatch" "$(echo "$out_v44c" | grep -qv 'evidence-base mismatch' && echo 0 || echo 1)"
check "v4-4c: kimi stub was invoked" "$(grep -q '202607110014c-v4-observed-ancestor' "$LOGS/kimi.log" && echo 0 || echo 1)"
rm -f "$PROJECT_MAIN/.ai/handoffs/to-kimi/open/202607110014c-v4-observed-ancestor.md"

# ---- v4-5. Evidence: HYPOTHESIS + Risk: C is a lint error ----
cat > "$PROJECT/.ai/handoffs/to-kimi/open/202607110016-v4-hypothesis-risk-c.md" <<'EOF'
# HYPOTHESIS + Risk C lint test
Status: OPEN
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 00:00 (UTC+7)
Auto: yes
Risk: C
Evidence: HYPOTHESIS

## Goal
Prove HYPOTHESIS with Risk C is rejected by lint-handoff.sh.
EOF
(
    cd "$PROJECT" && bash "$REPO_ROOT/.ai/tools/lint-handoff.sh"
) >"$LOGS/t4-v45-lint.out" 2>&1
rc_v45=$?
out_v45="$(cat "$LOGS/t4-v45-lint.out")"
check "v4-5: lint exits non-zero for HYPOTHESIS + Risk C" "$([ "$rc_v45" -ne 0 ] && echo 0 || echo 1)"
check "v4-5: lint reports HYPOTHESIS not allowed with Risk C" "$(echo "$out_v45" | grep -q 'HYPOTHESIS is not allowed with Risk: C' && echo 0 || echo 1)"
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110016-v4-hypothesis-risk-c.md"

# ==============================================================================
# ADR-0016 snapshot-copy regression test.
# ==============================================================================
# The dispatcher must copy canonical .ai/ into the worktree as ordinary files
# (not a junction) and sync changes back after the CLI exits.
sync_stub_log="$LOGS/kimi-sync.log"
# Temporarily replace the kimi stub with one that writes a report inside the
# worktree's .ai/ and asserts .ai/ is a real directory, not a junction/symlink.
cat > "$STUB_BIN/kimi" <<EOF
#!/bin/bash
{
  echo "cwd=\$(pwd)"
  echo "branch=\$(git branch --show-current 2>/dev/null)"
  echo "args=\$*"
} >> "$sync_stub_log"
# Write into the worktree's snapshot .ai/; this should propagate to canonical.
mkdir -p "\$(pwd)/.ai/reports"
echo 'synced from worktree' > "\$(pwd)/.ai/reports/sync-test.md"
exit 0
EOF
chmod +x "$STUB_BIN/kimi"
rm -f "$sync_stub_log"
mk_handoff kimi 202607110020-adr0016-sync
run_dispatcher --only kimi >/dev/null 2>&1
sync_test_canon="$PROJECT/.ai/reports/sync-test.md"
check "ADR-0016: worktree .ai/ removed after sync-back" "$([ ! -e "$wt_kimi/.ai" ] && echo 0 || echo 1)"
check "ADR-0016: new report created in worktree .ai/ synced back to canonical" "$([ -f "$sync_test_canon" ] && grep -q 'synced from worktree' "$sync_test_canon" && echo 0 || echo 1)"
# Restore the original kimi stub.
make_stub "kimi" "$LOGS/kimi.log"

# ==============================================================================
# --one mode: dispatch exactly one handoff even when multiple are open.
# ==============================================================================
# Remove the ADR-0016 handoff so it is not picked up before the --one targets.
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110020-adr0016-sync.md"
rm -f "$LOGS/kimi.log"
mk_handoff kimi 202607110021-one-a
mk_handoff kimi 202607110021-one-b
out_one="$(run_dispatcher --only kimi --one 2>&1)"
rc_one=$?
check "--one: dispatcher exits 0" "$([ "$rc_one" -eq 0 ] && echo 0 || echo 1)"
# Exactly one of the two slugs should appear in the log.
# Count via the args= line so we don't also match branch=.
if [ -f "$LOGS/kimi.log" ]; then
    one_count="$(grep -cE '^args=.*202607110021-one-[ab]' "$LOGS/kimi.log")"
else
    one_count=0
fi
check "--one: exactly one handoff dispatched (count=$one_count)" "$([ "$one_count" -eq 1 ] && echo 0 || echo 1)"
# The undispatched handoff must remain in open/.
# (The dispatched handoff also stays open unless the recipient moves it; we
# only require that one-b was not consumed.)
check "--one: second handoff stays OPEN" "$([ -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110021-one-b.md" ] && echo 0 || echo 1)"
# Clean up.
rm -f "$PROJECT/.ai/handoffs/to-kimi/open/202607110021-one-a.md" \
      "$PROJECT/.ai/handoffs/to-kimi/open/202607110021-one-b.md"

# ======================================================================
# grep proof (mirrors handoff verification item (c)): the old shared-checkout
# invocation `cd "$root"` must be GONE from the dispatch execution path.
# ======================================================================
old_form_hits="$(grep -n 'cd "\$root" &&' "$DISPATCHER" || true)"
check "grep: old 'cd \"\$root\" &&' shared-checkout invocation is gone from dispatch-handoffs.sh" "$([ -z "$old_form_hits" ] && echo 0 || echo 1)"

echo ""
echo "==== dispatch-worktree suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
