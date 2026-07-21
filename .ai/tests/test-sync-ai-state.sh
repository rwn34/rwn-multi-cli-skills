#!/bin/bash
# test-sync-ai-state.sh — verify .ai/tools/sync-ai-state.sh snapshot/sync-back behavior.
#
# Run: bash .ai/tests/test-sync-ai-state.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYNC="$REPO_ROOT/.ai/tools/sync-ai-state.sh"
CHECK="$REPO_ROOT/.ai/tools/check-encoding.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$SYNC" ] || { echo "FAIL: cannot find sync-ai-state.sh at $SYNC"; exit 1; }
[ -f "$CHECK" ] || { echo "FAIL: cannot find check-encoding.sh at $CHECK"; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CANON="$WORK/canonical"
WT="$WORK/worktree"
mkdir -p "$CANON/.ai" "$WT"

# Helper: create canonical .ai/ state.
setup_canon() {
    rm -rf "$CANON/.ai"
    mkdir -p "$CANON/.ai/activity/entries" "$CANON/.ai/handoffs/to-kimi/open" "$CANON/.ai/handoffs/to-kimi/done" "$CANON/.ai/reports"
    cat > "$CANON/.ai/activity/entries/20260717T100000Z-test-canonical-a1b2.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) - test
- Action: canonical log entry

EOF
    cat > "$CANON/.ai/activity/log.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) - test
- Action: generated view

EOF
    echo 'handoff open' > "$CANON/.ai/handoffs/to-kimi/open/h1.md"
    echo 'report' > "$CANON/.ai/reports/r1.md"
}

# 1. snapshot copies canonical .ai/ into worktree.
setup_canon
out="$(bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" 2>&1)"; rc=$?
check "snapshot exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "snapshot copies spool entry" "$([ -f "$WT/.ai/activity/entries/20260717T100000Z-test-canonical-a1b2.md" ] && echo 0 || echo 1)"
check "snapshot manifest omits generated log.md" "$(grep -q 'activity/log\.md' "$WT/.ai/.snapshot-manifest" && echo 1 || echo 0)"
check "snapshot copies handoff" "$([ -f "$WT/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "snapshot writes manifest" "$([ -f "$WT/.ai/.snapshot-manifest" ] && echo 0 || echo 1)"

# 1b. snapshot copies .gitkeep files so git does not treat queue dirs as deleted.
setup_canon
mkdir -p "$CANON/.ai/handoffs/to-kimi/open"
touch "$CANON/.ai/handoffs/to-kimi/open/.gitkeep"
out1b="$(bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" 2>&1)"; rc1b=$?
check "snapshot copies .gitkeep" "$([ "$rc1b" -eq 0 ] && [ -f "$WT/.ai/handoffs/to-kimi/open/.gitkeep" ] && echo 0 || echo 1)"
check "snapshot manifest records .gitkeep" "$(grep -q 'handoffs/to-kimi/open/\.gitkeep' "$WT/.ai/.snapshot-manifest" && echo 0 || echo 1)"

# 2. sync-back copies a new file from worktree to canonical.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'new report' > "$WT/.ai/reports/r2.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back new file exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back copies new report to canonical" "$([ -f "$CANON/.ai/reports/r2.md" ] && echo 0 || echo 1)"

# 3. sync-back copies a new entry file and leaves canonical's old entry alone.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
cat > "$WT/.ai/activity/entries/20260719T110000Z-test-new-entry-b3c4.md" <<'EOF'
## 2026-07-19 11:00 (UTC+7) - test
- Action: new entry from worktree

EOF
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back new entry exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back copies new entry file" "$([ -f "$CANON/.ai/activity/entries/20260719T110000Z-test-new-entry-b3c4.md" ] && echo 0 || echo 1)"
check "sync-back preserves canonical entry" "$([ -f "$CANON/.ai/activity/entries/20260717T100000Z-test-canonical-a1b2.md" ] && echo 0 || echo 1)"

# 4. sync-back replays a handoff move (open -> done).
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
mkdir -p "$WT/.ai/handoffs/to-kimi/done"
mv "$WT/.ai/handoffs/to-kimi/open/h1.md" "$WT/.ai/handoffs/to-kimi/done/h1.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back handoff move exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back removes open handoff from canonical" "$([ ! -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back creates done handoff in canonical" "$([ -f "$CANON/.ai/handoffs/to-kimi/done/h1.md" ] && echo 0 || echo 1)"

# 5. sync-back does NOT delete canonical files that were never in the snapshot.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Simulate a concurrent canonical addition while executor runs.
echo 'concurrent' > "$CANON/.ai/handoffs/to-kimi/open/h2.md"
# Executor changes nothing in worktree.
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back preserves concurrent canonical addition" "$([ -f "$CANON/.ai/handoffs/to-kimi/open/h2.md" ] && echo 0 || echo 1)"

# 6. sync-back removes worktree .ai/ after completion.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back removes worktree .ai" "$([ ! -e "$WT/.ai" ] && echo 0 || echo 1)"

# 7. snapshot is idempotent: re-running on existing worktree .ai/ refreshes it.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'stale' > "$WT/.ai/stale.md"
setup_canon  # change canonical
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
check "snapshot refresh removes stale file" "$([ ! -f "$WT/.ai/stale.md" ] && echo 0 || echo 1)"
check "snapshot refresh copies new canonical state" "$([ -f "$WT/.ai/activity/log.md" ] && echo 0 || echo 1)"

# 8. canonical .ai/ passes encoding check after sync-back.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo 'new' > "$WT/.ai/reports/r2.md"
bash "$SYNC" sync-back "$WT" "$CANON" >/dev/null 2>&1
out="$(bash "$CHECK" "$CANON/.ai/activity/log.md" 2>&1)"; rc=$?
check "canonical log passes encoding check after sync-back" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# 9. sync-back does NOT delete a canonical open/review handoff that changed
#    since the snapshot (prevents one executor from wiping another actor's
#    in-flight handoff during its own sync-back).
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Another actor changes the open handoff while this executor runs.
echo 'changed by another actor' > "$CANON/.ai/handoffs/to-kimi/open/h1.md"
# This executor retires its own copy.
mkdir -p "$WT/.ai/handoffs/to-kimi/done"
mv "$WT/.ai/handoffs/to-kimi/open/h1.md" "$WT/.ai/handoffs/to-kimi/done/h1.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back skip-delete changed open handoff exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back preserves changed canonical open handoff" "$([ -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back still creates done handoff in canonical" "$([ -f "$CANON/.ai/handoffs/to-kimi/done/h1.md" ] && echo 0 || echo 1)"

# 10. sync-back does NOT delete open/review handoffs addressed to other
#     recipients that are still present in the worktree snapshot.
setup_canon
# Add cross-recipient open handoffs in canonical.
mkdir -p "$CANON/.ai/handoffs/to-kiro/open" "$CANON/.ai/handoffs/to-opencode/open"
echo 'kiro handoff' > "$CANON/.ai/handoffs/to-kiro/open/h2.md"
echo 'opencode handoff' > "$CANON/.ai/handoffs/to-opencode/open/h3.md"
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# This executor (kimi) retires only its own handoff; leaves kiro/opencode untouched.
mkdir -p "$WT/.ai/handoffs/to-kimi/done"
mv "$WT/.ai/handoffs/to-kimi/open/h1.md" "$WT/.ai/handoffs/to-kimi/done/h1.md"
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back cross-recipient exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back removes own retired open handoff" "$([ ! -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back preserves kiro open handoff" "$([ -f "$CANON/.ai/handoffs/to-kiro/open/h2.md" ] && echo 0 || echo 1)"
check "sync-back preserves opencode open handoff" "$([ -f "$CANON/.ai/handoffs/to-opencode/open/h3.md" ] && echo 0 || echo 1)"

# 11. sync-back copies new entry files from the worktree spool and does NOT
#     sync the generated .ai/activity/log.md view.
setup_canon
mkdir -p "$CANON/.ai/activity/entries"
cat > "$CANON/.ai/activity/entries/20260718T090000Z-kimi-cli-canonical-a1b2.md" <<'EOF'
## 2026-07-18 09:00 (UTC+7) - kimi-cli
- Action: canonical history entry

EOF
cat > "$CANON/.ai/activity/log.md" <<'EOF'
## 2026-07-18 09:00 (UTC+7) - kimi-cli
- Action: generated view before sync

EOF
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
cat > "$WT/.ai/activity/entries/20260719T080000Z-opencode-executor-b3c4.md" <<'EOF'
## 2026-07-19 08:00 (UTC+7) - opencode
- Action: executor entry from worktree

EOF
cat > "$WT/.ai/activity/log.md" <<'EOF'
## 2026-07-19 08:00 (UTC+7) - opencode
- Action: worktree overwrote generated view

EOF
out="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc=$?
check "sync-back entry-spool exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "sync-back preserves canonical entry" "$([ -f "$CANON/.ai/activity/entries/20260718T090000Z-kimi-cli-canonical-a1b2.md" ] && echo 0 || echo 1)"
check "sync-back copies new entry file" "$([ -f "$CANON/.ai/activity/entries/20260719T080000Z-opencode-executor-b3c4.md" ] && echo 0 || echo 1)"
check "sync-back ignores generated log.md" "$(grep -qF 'worktree overwrote generated view' "$CANON/.ai/activity/log.md" && echo 1 || echo 0)"

# 12. snapshot tolerates concurrent canonical modifications of entry files
#     (tar: file changed as we read it).
setup_canon
mkdir -p "$CANON/.ai/activity/entries"
# Start a background writer that creates entry files every 50ms while the
# snapshot runs, to trigger tar's "file changed as we read it".
writer_pid=""
(
    for i in $(seq 1 100); do
        printf '## 2026-07-19 12:%02d (UTC+7) - concurrent-writer\n- Action: line %d\n\n' "$i" "$i" > "$CANON/.ai/activity/entries/20260719T1200$(printf '%02d' "$i")Z-concurrent-writer-c${i}.md"
        sleep 0.05 2>/dev/null || sleep 1
    done
) &
writer_pid=$!
out14="$(bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" 2>&1)"; rc14=$?
kill "$writer_pid" 2>/dev/null || true
wait "$writer_pid" 2>/dev/null || true
check "snapshot concurrent-write exits 0" "$([ "$rc14" -eq 0 ] && echo 0 || echo 1)"
check "snapshot concurrent-write produces non-empty manifest" "$([ -s "$WT/.ai/.snapshot-manifest" ] && echo 0 || echo 1)"
check "snapshot concurrent-write copies spool" "$([ -d "$WT/.ai/activity/entries" ] && echo 0 || echo 1)"

# 15. safe_rm_rf renames a busy .ai/ directory instead of hanging forever.
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Hold the directory open with a subshell whose cwd is inside .ai/.
(
    cd "$WT/.ai" && sleep 5
) &
busy_pid=$!
sleep 0.2
out15="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc15=$?
kill "$busy_pid" 2>/dev/null || true
wait "$busy_pid" 2>/dev/null || true
check "sync-back busy dir exits 0" "$([ "$rc15" -eq 0 ] && echo 0 || echo 1)"
check "sync-back busy dir removes or renames worktree .ai" "$( ([ ! -e "$WT/.ai" ] || [ -e "$WT/.ai.stale"* ]) && echo 0 || echo 1)"

# 16. sync-back REFUSES to propagate a bare deletion of an open/review handoff
#     that has no matching done/ entry. This is the ADR-0016 deletion-policy bug:
#     if the snapshot fails to copy the handoff into the worktree, the canonical
#     hash still matches the old manifest hash, so the old code deleted the open
#     handoff from history. A handoff must only be removed from open/review when
#     it is explicitly retired to done/ (or blocked).
setup_canon
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Simulate the failure mode: the handoff is missing from the worktree snapshot
# (snapshot did not copy it, or the executor deleted it without retiring it).
rm -f "$WT/.ai/handoffs/to-kimi/open/h1.md"
out16="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc16=$?
check "sync-back refuses bare open-handoff deletion (non-zero exit)" "$([ "$rc16" -ne 0 ] && echo 0 || echo 1)"
check "sync-back preserves canonical open handoff" "$([ -f "$CANON/.ai/handoffs/to-kimi/open/h1.md" ] && echo 0 || echo 1)"
check "sync-back error names the refused deletion" "$(echo "$out16" | grep -qi 'refuse.*delete.*open.*handoff\|handoff.*h1\.md.*no.*done' && echo 0 || echo 1)"

# 17. sync-back copies a NEW activity/entries/*.md file from worktree to
#     canonical (ADR-0010 spool). This is the common case: no filename
#     collision, entry syncs like any other new file.
setup_canon
mkdir -p "$CANON/.ai/activity/entries"
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo '## entry from worktree' > "$WT/.ai/activity/entries/20260720T120000Z-kiro-test-aaaa.md"
out17="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc17=$?
check "sync-back new entry file exits 0" "$([ "$rc17" -eq 0 ] && echo 0 || echo 1)"
check "sync-back copies new entry file to canonical" "$([ -f "$CANON/.ai/activity/entries/20260720T120000Z-kiro-test-aaaa.md" ] && echo 0 || echo 1)"

# 18. sync-back is a no-op for an entry file whose content is byte-identical
#     in canonical already (idempotent re-sync, e.g. a retried dispatch).
#
#     B5 (review handoff 202607201755): the entry must be ABSENT from the
#     snapshot and appear in canonical only AFTER the snapshot is taken, then
#     independently written into the worktree with the SAME body. Writing it
#     into canonical before snapshot (the prior form of this test) makes the
#     snapshot tar it into the worktree too, so old_hash == new_hash for that
#     path and the outer diff loop in sync-ai-state.sh never evaluates the
#     entries/* case at all -- the elif cmp -s branch this test claims to
#     cover never executes. This form forces manifest_old to have NO entry
#     for the filename, so the file is picked up as new-or-changed and the
#     cmp -s identical-content branch is actually reached.
setup_canon
mkdir -p "$CANON/.ai/activity/entries"
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
echo '## identical entry' > "$CANON/.ai/activity/entries/20260720T130000Z-kiro-idem-bbbb.md"
mkdir -p "$WT/.ai/activity/entries"
echo '## identical entry' > "$WT/.ai/activity/entries/20260720T130000Z-kiro-idem-bbbb.md"
out18="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc18=$?
check "sync-back idempotent entry re-sync exits 0" "$([ "$rc18" -eq 0 ] && echo 0 || echo 1)"
check "sync-back idempotent entry unchanged" "$(grep -qF 'identical entry' "$CANON/.ai/activity/entries/20260720T130000Z-kiro-idem-bbbb.md" && echo 0 || echo 1)"
check "sync-back idempotent entry: cmp -s branch actually reached (no conflict artifacts written)" "$([ ! -f "$CANON/.ai/activity/entries/20260720T130000Z-kiro-idem-bbbb.conflict"*.md ] 2>/dev/null && ! ls "$CANON"/.ai/.sync-conflict-*.marker >/dev/null 2>&1 && echo 0 || echo 1)"

# 19. sync-back preserves BOTH sides when canonical and worktree disagree on
#     content under the same entry filename (the ADR-0010 invariant: no
#     writer ever rewrites another writer's entry). This models a
#     filename-collision bug, not a normal outcome.
#
#     B3 (review handoff 202607201755): the original fix only warned and left
#     canonical untouched, but the worktree's .ai/ is unconditionally removed
#     at the end of cmd_sync_back (safe_rm_rf), which meant the worktree body
#     was destroyed the moment this function returned -- the exact data loss
#     this test's own comment says must never happen. The fix now copies the
#     worktree body aside into canonical as a distinctly-named
#     "*.conflict-<hash>.md" file (so BOTH bodies survive for a human to
#     reconcile) and writes a durable ".sync-conflict-*.marker" file, in
#     addition to the warn(). B4: the collision is no longer signaled by exit
#     0 alone (a non-fatal warn buried in dark-gray pane text is not a guard)
#     -- cmd_sync_back now returns 2 (distinct from the deletion-guard's 1)
#     when a collision was preserved this run.
setup_canon
mkdir -p "$CANON/.ai/activity/entries"
bash "$SYNC" snapshot "$CANON/.ai" "$WT/.ai" >/dev/null 2>&1
# Canonical gains an entry at this filename from another actor while this
# executor's worktree independently produces a *different* body at the same
# filename (simulated collision).
echo '## canonical writer body' > "$CANON/.ai/activity/entries/20260720T140000Z-kiro-collide-cccc.md"
mkdir -p "$WT/.ai/activity/entries"
echo '## worktree writer body (different)' > "$WT/.ai/activity/entries/20260720T140000Z-kiro-collide-cccc.md"
out19="$(bash "$SYNC" sync-back "$WT" "$CANON" 2>&1)"; rc19=$?
check "sync-back collision returns distinct exit code 2" "$([ "$rc19" -eq 2 ] && echo 0 || echo 1)"
check "sync-back collision preserves canonical body" "$(grep -qF 'canonical writer body' "$CANON/.ai/activity/entries/20260720T140000Z-kiro-collide-cccc.md" && echo 0 || echo 1)"
check "sync-back collision does not overwrite canonical with worktree body" "$(grep -qF 'worktree writer body' "$CANON/.ai/activity/entries/20260720T140000Z-kiro-collide-cccc.md" && echo 1 || echo 0)"
check "sync-back collision warns" "$(echo "$out19" | grep -qi 'ENTRY FILENAME COLLISION' && echo 0 || echo 1)"
conflict_file="$(ls "$CANON"/.ai/activity/entries/20260720T140000Z-kiro-collide-cccc.conflict-*.md 2>/dev/null | head -1)"
check "sync-back collision preserves worktree body as a conflict file" "$([ -n "$conflict_file" ] && grep -qF 'worktree writer body' "$conflict_file" && echo 0 || echo 1)"
check "sync-back collision writes a durable marker file in canonical" "$(ls "$CANON"/.ai/.sync-conflict-*.marker >/dev/null 2>&1 && echo 0 || echo 1)"

# 20. cmd_snapshot must refuse when src and dst resolve to the SAME directory
#     (or one contains the other). Root-cause of the 2026-07-21 canonical .ai/
#     deletion incident (handoff 202607211105-diagnose-canonical-ai-deletion.md):
#     cmd_snapshot's first action is safe_rm_rf "$dst" -- unconditional, with no
#     realpath comparison against $src. If a caller ever computes a worktree
#     path that collapses onto the canonical .ai/ itself (a bad dirname/basename
#     substitution, a mis-anchored $root, etc.), this deletes the ONLY copy of
#     canonical .ai/ before tar ever reads from $src -- and because $src is now
#     also gone (same path), the subsequent tar read fails too, but by then the
#     data is already gone. This must be refused BEFORE any deletion happens.
setup_canon
before_count="$(find "$CANON/.ai" -type f | wc -l)"
out20="$(bash "$SYNC" snapshot "$CANON/.ai" "$CANON/.ai" 2>&1)"; rc20=$?
after_count="$(find "$CANON/.ai" -type f 2>/dev/null | wc -l)"
check "snapshot src==dst exits non-zero (refuses)" "$([ "$rc20" -ne 0 ] && echo 0 || echo 1)"
check "snapshot src==dst does not delete canonical files" "$([ "$after_count" -eq "$before_count" ] && echo 0 || echo 1)"
check "snapshot src==dst names the refusal" "$(echo "$out20" | grep -qi 'same\|identical\|refus' && echo 0 || echo 1)"

# 20b. cmd_snapshot must also refuse when dst is an ANCESTOR of src (deleting dst
#     would delete src too, since src lives inside it) -- the same hazard, one
#     path-arithmetic step removed.
setup_canon
before_count_b="$(find "$CANON/.ai" -type f | wc -l)"
out20b="$(bash "$SYNC" snapshot "$CANON/.ai/handoffs" "$CANON/.ai" 2>&1)"; rc20b=$?
after_count_b="$(find "$CANON/.ai" -type f 2>/dev/null | wc -l)"
check "snapshot dst-ancestor-of-src exits non-zero (refuses)" "$([ "$rc20b" -ne 0 ] && echo 0 || echo 1)"
check "snapshot dst-ancestor-of-src does not delete canonical files" "$([ "$after_count_b" -eq "$before_count_b" ] && echo 0 || echo 1)"

echo ""
echo "==== sync-ai-state suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
