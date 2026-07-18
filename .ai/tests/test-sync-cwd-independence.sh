#!/bin/bash
# test-sync-cwd-independence.sh -- prove sync-replicas.sh measures the script's
# own repo, not the caller's current working directory.
#
# Regression test for the false-pass fixed in PR #72 and re-ported to the
# current sync-replicas.sh design: when invoked by absolute path from a
# different directory, --check must diff against the tree containing the script,
# not against the caller's CWD.
#
# Run: bash .ai/tests/test-sync-cwd-independence.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYNC_REPLICAS="$REPO_ROOT/.ai/tools/sync-replicas.sh"
CHECK_SHIM="$REPO_ROOT/.ai/tools/check-ssot-drift.sh"
[ -f "$SYNC_REPLICAS" ] || { echo "FAIL: cannot find sync-replicas.sh at $SYNC_REPLICAS"; exit 1; }
[ -f "$CHECK_SHIM" ]   || { echo "FAIL: cannot find check-ssot-drift.sh at $CHECK_SHIM"; exit 1; }

pass=0
fail=0
check() { # desc, exit-code-of-condition (0 = pass)
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SANDBOX="$WORK/repo"
DECOY="$WORK/decoy"

# ---- build sandbox repo (the script's own repo) ----
mkdir -p "$SANDBOX/.ai/instructions" "$SANDBOX/.ai/tools"
cat > "$SANDBOX/.ai/sync.md" <<'EOF'
# Sync registry

| Source | Destination |
|---|---|
| `.ai/instructions/source.md` | `replica.md` |
EOF
printf 'SSOT content\n' > "$SANDBOX/.ai/instructions/source.md"
printf 'SSOT content\n' > "$SANDBOX/replica.md"

# Copy the scripts under test so $0 resolves to the sandbox tree.
cp "$SYNC_REPLICAS" "$SANDBOX/.ai/tools/sync-replicas.sh"
cp "$CHECK_SHIM"   "$SANDBOX/.ai/tools/check-ssot-drift.sh"

# sync-replicas.sh probes git for skip-worktree, so the sandbox must be a repo.
git init --quiet "$SANDBOX"
git -C "$SANDBOX" config user.email "test@example.com"
git -C "$SANDBOX" config user.name  "test"
git -C "$SANDBOX" add -A
git -C "$SANDBOX" commit --quiet -m "seed"

# ---- build decoy CWD repo with different content ----
mkdir -p "$DECOY/.ai/instructions"
printf 'decoy SSOT\n' > "$DECOY/.ai/instructions/source.md"
printf 'decoy replica\n' > "$DECOY/replica.md"

# ---- test helpers ----
run_from_decoy() { ( cd "$DECOY" && "$@" ); }

# ======================================================================
# 1. --check from decoy CWD exits 0 when the SANDBOX is clean.
#    If the script measured CWD, it would see the decoy drift and fail.
# ======================================================================
out1="$(run_from_decoy bash "$SANDBOX/.ai/tools/sync-replicas.sh" --check 2>&1)"
rc1=$?
check "test1: --check from decoy CWD exits 0 when sandbox is clean" "$rc1"
check "test1: drift summary reports 0" "$(echo "$out1" | grep -q 'Checked: 1 replicas, Drift: 0' && echo 0 || echo 1)"
check "test1: decoy content was not measured" "$(echo "$out1" | grep -qi 'decoy' && echo 1 || echo 0)"

# ======================================================================
# 2. --check from decoy CWD reports drift when the SANDBOX replica drifts.
# ======================================================================
printf 'drifted content\n' > "$SANDBOX/replica.md"
out2="$(run_from_decoy bash "$SANDBOX/.ai/tools/sync-replicas.sh" --check 2>&1)"
rc2=$?
check "test2: --check exits non-zero when sandbox replica drifts" "$([ "$rc2" -ne 0 ] && echo 0 || echo 1)"
check "test2: drift summary reports 1" "$(echo "$out2" | grep -q 'Checked: 1 replicas, Drift: 1' && echo 0 || echo 1)"
check "test2: drift mentions the sandbox replica" "$(echo "$out2" | grep -q 'DRIFT:.*replica.md' && echo 0 || echo 1)"

# ======================================================================
# 3. Default regenerate from decoy CWD writes to the sandbox, not the decoy.
# ======================================================================
# Restore clean state, then change the sandbox source.
printf 'SSOT content\n' > "$SANDBOX/replica.md"
printf 'new SSOT content\n' > "$SANDBOX/.ai/instructions/source.md"
run_from_decoy bash "$SANDBOX/.ai/tools/sync-replicas.sh" >/dev/null 2>&1
rc3=$?
check "test3: default regenerate exits 0" "$rc3"
check "test3: sandbox replica received the new SSOT" "$(grep -q 'new SSOT content' "$SANDBOX/replica.md" && echo 0 || echo 1)"
check "test3: decoy replica was untouched" "$(grep -q 'decoy replica' "$DECOY/replica.md" && echo 0 || echo 1)"

# ======================================================================
# 4. check-ssot-drift.sh shim, invoked by absolute path from decoy CWD,
#    still checks the sandbox tree (its own repo).
# ======================================================================
printf 'new SSOT content\n' > "$SANDBOX/replica.md"
out4="$(run_from_decoy bash "$SANDBOX/.ai/tools/check-ssot-drift.sh" 2>&1)"
rc4=$?
check "test4: check-ssot-drift.sh shim from decoy CWD exits 0 when clean" "$rc4"
check "test4: shim drift summary reports 0" "$(echo "$out4" | grep -q 'Checked: 1 replicas, Drift: 0' && echo 0 || echo 1)"

# ======================================================================
# 5. --dest-root remains caller-relative (writes to decoy, not sandbox).
# ======================================================================
mkdir -p "$WORK/dest"
printf 'dest SSOT\n' > "$SANDBOX/.ai/instructions/source.md"
run_from_decoy bash "$SANDBOX/.ai/tools/sync-replicas.sh" --dest-root "$WORK/dest" >/dev/null 2>&1
rc5=$?
check "test5: --dest-root exits 0" "$rc5"
check "test5: --dest-root wrote replica under caller-supplied dir" "$(grep -q 'dest SSOT' "$WORK/dest/replica.md" && echo 0 || echo 1)"
check "test5: sandbox replica unchanged by --dest-root" "$(grep -q 'new SSOT content' "$SANDBOX/replica.md" && echo 0 || echo 1)"

# ======================================================================
# 6. Running from the sandbox root itself still works (relative-path $0).
# ======================================================================
# Restore matching source/replica so the check is a true no-drift case.
printf 'new SSOT content\n' > "$SANDBOX/.ai/instructions/source.md"
out6="$(cd "$SANDBOX" && bash .ai/tools/sync-replicas.sh --check 2>&1)"
rc6=$?
check "test6: --check from sandbox root exits 0" "$rc6"
check "test6: relative-path invocation drift summary reports 0" "$(echo "$out6" | grep -q 'Checked: 1 replicas, Drift: 0' && echo 0 || echo 1)"

echo ""
echo "==== sync-cwd-independence suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
