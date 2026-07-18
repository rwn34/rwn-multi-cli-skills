#!/bin/bash
# test-fleet-health.sh — framework health watchdog tests.
#
# Exercises queue-dir checks, heartbeat STALL/WEDGED detection, worktree layout
# hygiene, ADR-0016 junction detection, stale-base detection, and shared-state
# encoding checks. Run from repo root.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLEET_HEALTH="$REPO_ROOT/.ai/tools/fleet-health.sh"

[ -f "$FLEET_HEALTH" ] || { echo "FAIL: cannot find fleet-health.sh"; exit 1; }

pass=0
fail=0
check() {
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

# Helpers
mk_project() {
  local sandbox
  sandbox="$(mktemp -d)"
  git init -q "$sandbox/project"
  git -C "$sandbox/project" config user.email "test@test"
  git -C "$sandbox/project" config user.name "test"
  for actor in kimi kiro; do
    for sub in open review done; do
      mkdir -p "$sandbox/project/.ai/handoffs/to-$actor/$sub"
    done
  done
  mkdir -p "$sandbox/project/.ai/activity"
  echo "init" > "$sandbox/project/seed.txt"
  git -C "$sandbox/project" add -A
  git -C "$sandbox/project" commit -q -m "init"
  echo "$sandbox"
}

# Create a fake heartbeat sidecar.
heartbeat() {
  local root="$1" cli="$2" age_min="$3" pid="$4"
  local ts
  ts="$(date -u -d "${age_min} minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${age_min}M +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$root/.ai"
  cat > "$root/.ai/.heartbeat-${cli}.json" <<EOF
{"ts":"$ts","pid":$pid,"host":"$(hostname)"}
EOF
}

# Create a qualifying handoff.
handoff() {
  local root="$1" cli="$2" slug="$3" age_min="$4"
  local ts
  ts="$(date -u -d "${age_min} minutes ago" '+%Y-%m-%d %H:%M' 2>/dev/null || date -u -v-${age_min}M '+%Y-%m-%d %H:%M')"
  cat > "$root/.ai/handoffs/to-$cli/open/${slug}.md" <<EOF
# $slug
Status: OPEN
Sender: claude-cockpit
Recipient: $cli-auto
Created: $ts (UTC+7)
Auto: yes
Risk: B
EOF
}

# ======================================================================
# 1. Clean project with no qualifying handoffs -> OK/down-idle, exit 0
# ======================================================================
SANDBOX1="$(mk_project)"
heartbeat "$SANDBOX1/project" kimi 5 $$
out1="$(bash "$FLEET_HEALTH" "$SANDBOX1/project" 2>&1)"
rc1=$?
check "test1: clean project exits 0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"
check "test1: reports down-idle for kimi" "$(printf '%s' "$out1" | grep -q 'DOWN (idle)' && echo 0 || echo 1)"

# ======================================================================
# 2. STALL: stale heartbeat + qualifying open handoff -> exit 1
# ======================================================================
SANDBOX2="$(mk_project)"
heartbeat "$SANDBOX2/project" kimi 20 $$
handoff "$SANDBOX2/project" kimi 202607110001-t2 20
out2="$(bash "$FLEET_HEALTH" "$SANDBOX2/project" 2>&1)"
rc2=$?
check "test2: stale heartbeat with open handoff exits non-zero" "$([ "$rc2" -ne 0 ] && echo 0 || echo 1)"
check "test2: reports STALL" "$(printf '%s' "$out2" | grep -q 'STALL' && echo 0 || echo 1)"

# ======================================================================
# 3. WEDGED: fresh heartbeat + unclaimed aged handoff -> exit 1
# ======================================================================
SANDBOX3="$(mk_project)"
heartbeat "$SANDBOX3/project" kimi 5 $$
handoff "$SANDBOX3/project" kimi 202607110001-t3 20
out3="$(bash "$FLEET_HEALTH" "$SANDBOX3/project" 2>&1)"
rc3=$?
check "test3: fresh heartbeat with aged unclaimed handoff exits non-zero" "$([ "$rc3" -ne 0 ] && echo 0 || echo 1)"
check "test3: reports WEDGED" "$(printf '%s' "$out3" | grep -q 'WEDGED' && echo 0 || echo 1)"

# ======================================================================
# 4. Missing queue dir -> exit 1, names the fix command
# ======================================================================
SANDBOX4="$(mk_project)"
heartbeat "$SANDBOX4/project" kimi 5 $$
rmdir "$SANDBOX4/project/.ai/handoffs/to-kimi/open"
out4="$(bash "$FLEET_HEALTH" "$SANDBOX4/project" 2>&1)"
rc4=$?
check "test4: missing queue dir exits non-zero" "$([ "$rc4" -ne 0 ] && echo 0 || echo 1)"
check "test4: reports missing queue dir" "$(printf '%s' "$out4" | grep -q 'missing queue dir' && echo 0 || echo 1)"

# ======================================================================
# 5. Junctioned .ai/ -> exit 1, names the worktree
# ======================================================================
SANDBOX5="$(mk_project)"
PROJECT5="$SANDBOX5/project"
  # Create a fake worktree dir with .ai/ as the same inode as canonical.
  # Use a Windows junction on this host; POSIX symlinks created by Git Bash's
  # `ln -s` report different inodes, so mklink /J is preferred when available.
  WT_KIMI5="$SANDBOX5/.wt/project/kimi"
  mkdir -p "$WT_KIMI5"
  rmdir "$WT_KIMI5" 2>/dev/null || true
  if command -v cygpath >/dev/null 2>&1 && command -v cmd >/dev/null 2>&1; then
    cmd //c mklink //J "$(cygpath -w "$WT_KIMI5")" "$(cygpath -w "$PROJECT5")" >/dev/null 2>&1
  else
    ln -s "$PROJECT5" "$WT_KIMI5" 2>/dev/null || true
  fi
  [ -d "$WT_KIMI5/.ai" ] || mkdir -p "$WT_KIMI5/.ai"
heartbeat "$PROJECT5" kimi 5 $$
out5="$(bash "$FLEET_HEALTH" "$PROJECT5" 2>&1)"
rc5=$?
check "test5: junctioned .ai/ detected" "$([ "$rc5" -ne 0 ] && echo 0 || echo 1)"
check "test5: reports junction/symlink" "$(printf '%s' "$out5" | grep -qE 'junction|symlink' && echo 0 || echo 1)"

# ======================================================================
# 6. Stale worktree (HEAD behind origin/main) -> exit 1
# ======================================================================
SANDBOX6="$(mk_project)"
PROJECT6="$SANDBOX6/project"
WT_KIMI6="$SANDBOX6/.wt/project/kimi"
mkdir -p "$WT_KIMI6"
git -C "$PROJECT6" worktree add -q "$WT_KIMI6" HEAD 2>/dev/null || true
# Make a new commit on main so the worktree HEAD is behind.
echo "advance" >> "$PROJECT6/seed.txt"
git -C "$PROJECT6" add -A
git -C "$PROJECT6" commit -q -m "advance"
git -C "$PROJECT6" remote add origin "$PROJECT6" 2>/dev/null || true
git -C "$PROJECT6" fetch origin 2>/dev/null || true
git -C "$PROJECT6" update-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || true
git -C "$PROJECT6" update-ref refs/remotes/origin/main "$(git -C "$PROJECT6" rev-parse HEAD)" 2>/dev/null || true
heartbeat "$PROJECT6" kimi 5 $$
out6="$(bash "$FLEET_HEALTH" "$PROJECT6" 2>&1)"
rc6=$?
check "test6: stale worktree detected" "$([ "$rc6" -ne 0 ] && echo 0 || echo 1)"
check "test6: reports stale worktree" "$(printf '%s' "$out6" | grep -q 'stale worktree' && echo 0 || echo 1)"

# ======================================================================
# 7. Encoding problem -> exit 1, names the file
# ======================================================================
SANDBOX7="$(mk_project)"
PROJECT7="$SANDBOX7/project"
printf '\xff\xfe' > "$PROJECT7/.ai/activity/log.md"
heartbeat "$PROJECT7" kimi 5 $$
out7="$(bash "$FLEET_HEALTH" "$PROJECT7" 2>&1)"
rc7=$?
check "test7: encoding problem detected" "$([ "$rc7" -ne 0 ] && echo 0 || echo 1)"
check "test7: reports encoding problem" "$(printf '%s' "$out7" | grep -q 'encoding problem' && echo 0 || echo 1)"

echo ""
echo "==== fleet-health suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
