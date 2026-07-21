#!/bin/bash
# test_hooks.sh — standing regression suite for .kiro/hooks/*
# Run: bash .kiro/hooks/test_hooks.sh
# Exits 0 if all pass, 1 if any fail.

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
# Windows-form repo root (C:/…) for absolute-path regression payloads; matches
# the `pwd -W` the guards use so root-relative normalization can be exercised.
ROOT_W=$(pwd -W 2>/dev/null || pwd); ROOT_W="${ROOT_W%/}"
pass=0
fail=0
fails=()

run_test() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  actual=$(printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
    echo "  PASS  $name"
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
    echo "  FAIL  $name (expected $expected, got $actual)"
  fi
}

echo "=== Kiro hooks regression suite ==="
echo ""

# --- root-file-guard ---
echo "root-file-guard:"
run_test "t1  block evil.txt at root"       "$HOOKS_DIR/root-file-guard.sh" '{"tool_input":{"file_path":"evil.txt"}}'    2
run_test "t2  allow .gitignore (ADR cat B)" "$HOOKS_DIR/root-file-guard.sh" '{"tool_input":{"file_path":".gitignore"}}'  0
run_test "t3  allow src/main.rs (not root)" "$HOOKS_DIR/root-file-guard.sh" '{"tool_input":{"file_path":"src/main.rs"}}' 0
run_test "t3a block ABSOLUTE root evil.txt"  "$HOOKS_DIR/root-file-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_W/evil.txt\"}}" 2
run_test "t3b allow ABSOLUTE src/main.rs"    "$HOOKS_DIR/root-file-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_W/src/main.rs\"}}" 0

# --- framework-dir-guard ---
echo "framework-dir-guard:"
run_test "t4  allow .ai/handoffs/test.md"       "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".ai/handoffs/test.md"}}'    0
run_test "t5  block .claude/agents/test.md"     "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".claude/agents/test.md"}}'  2
run_test "t5a block .kirograph (removed)"       "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".kirograph/config.json"}}'  2
run_test "t5b block .codegraph/codegraph.db"    "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".codegraph/codegraph.db"}}' 2
run_test "t5c block .kimigraph/kimigraph.db"    "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".kimigraph/kimigraph.db"}}' 2
run_test "t5d block ABSOLUTE .claude (fwd)"     "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":"C:/proj/.claude/agents/test.md"}}' 2
run_test "t5e block ABSOLUTE .claude (backslash)" "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":"C:\\proj\\.claude\\agents\\x.json"}}' 2
run_test "t5f block ABSOLUTE .kimi (real root)" "$HOOKS_DIR/framework-dir-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_W/.kimi/steering/x.md\"}}" 2

# --- sensitive-file-guard ---
echo "sensitive-file-guard:"
run_test "t6  block .env"        "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":".env"}}'        2
run_test "t7  block id_ed25519"  "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":"id_ed25519"}}'  2
run_test "t8  block id_rsa"      "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":"id_rsa"}}'      2
run_test "t9  block server.key"       "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":"server.key"}}'       2
run_test "t10 block secrets.yaml"     "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":"secrets.yaml"}}'     2
run_test "t11 block credentials.json" "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":"credentials.json"}}' 2
run_test "t11a block ABSOLUTE .env"       "$HOOKS_DIR/sensitive-file-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_W/.env\"}}"        2
run_test "t11b block ABSOLUTE .aws/config" "$HOOKS_DIR/sensitive-file-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_W/.aws/config\"}}" 2

# --- ADR-0010: activity-log-inject.sh / activity-log-remind.sh dual-mode
# predicate (B1, review handoff 202607201755) ---
# The dual-mode predicate is `git ls-files --error-unmatch .ai/activity/log.md`
# — is log.md GIT-TRACKED, not merely present on disk. This must be exercised
# in three states: TRACKED+present (pre-freeze, reads log.md), UNTRACKED+present
# (post-freeze stale render, must read entries/), and ABSENT (post-freeze clean
# clone, must read entries/). A fixture that only ever has one state (as the
# suite lacked before this) would stay green even if the predicate were
# inverted or deleted — see the handoff's own point.
echo "activity-log-inject.sh / activity-log-remind.sh dual-mode predicate:"

DLM=$(mktemp -d)
git -C "$DLM" init -q
git -C "$DLM" config user.email "test@example.com"
git -C "$DLM" config user.name "test"
mkdir -p "$DLM/.ai/activity/entries" "$DLM/.ai/handoffs/to-kiro/open"

# TRACKED+present state: log.md committed -> both hooks must read log.md.
printf '## 2026-01-01 00:00 (UTC+7) - test\n- Action: tracked fixture entry\n' > "$DLM/.ai/activity/log.md"
git -C "$DLM" add .ai/activity/log.md
git -C "$DLM" commit -q -m "tracked log.md fixture"

INJECT_OUT=$(cd "$DLM" && bash "$HOOKS_DIR/activity-log-inject.sh" 2>&1)
if echo "$INJECT_OUT" | grep -q "top of .ai/activity/log.md" && echo "$INJECT_OUT" | grep -q "tracked fixture entry"; then
  pass=$((pass+1)); echo "  PASS  t51 inject: log.md TRACKED+present -> reads log.md"
else
  fail=$((fail+1)); fails+=("t51 inject: log.md TRACKED+present -> reads log.md"); echo "  FAIL  t51 inject: log.md TRACKED+present -> reads log.md"
fi

REMIND_OUT=$(cd "$DLM" && bash "$HOOKS_DIR/activity-log-remind.sh" 2>&1)
if ! echo "$REMIND_OUT" | grep -q "no new file in .ai/activity/entries"; then
  pass=$((pass+1)); echo "  PASS  t52 remind: log.md TRACKED+present -> checks log.md mtime, not entries/"
else
  fail=$((fail+1)); fails+=("t52 remind: log.md TRACKED+present -> checks log.md mtime, not entries/"); echo "  FAIL  t52 remind: log.md TRACKED+present -> checks log.md mtime, not entries/"
fi

# UNTRACKED+present state: log.md exists on disk but is NOT git-tracked (the
# post-freeze stale-render case) -> both hooks must ignore it and read entries/.
git -C "$DLM" rm --cached -q .ai/activity/log.md
git -C "$DLM" commit -q -m "untrack log.md (simulate freeze)"
printf '## 2026-01-02 00:00Z - kiro - untracked-render-abcd\n- Action: entries fixture (untracked-state)\n' > "$DLM/.ai/activity/entries/20260102T000000Z-kiro-untracked-render-abcd.md"
# log.md remains present on disk (stale render) but untracked.
if git -C "$DLM" ls-files --error-unmatch .ai/activity/log.md >/dev/null 2>&1; then
  fail=$((fail+1)); fails+=("t53 fixture sanity: log.md must be untracked here"); echo "  FAIL  t53 fixture sanity: log.md must be untracked here"
else
  pass=$((pass+1)); echo "  PASS  t53 fixture sanity: log.md is present-but-untracked"
fi

INJECT_OUT=$(cd "$DLM" && bash "$HOOKS_DIR/activity-log-inject.sh" 2>&1)
if echo "$INJECT_OUT" | grep -q "entries/" && echo "$INJECT_OUT" | grep -q "entries fixture (untracked-state)"; then
  pass=$((pass+1)); echo "  PASS  t54 inject: log.md UNTRACKED+present -> reads entries/, ignores stale log.md"
else
  fail=$((fail+1)); fails+=("t54 inject: log.md UNTRACKED+present -> reads entries/, ignores stale log.md"); echo "  FAIL  t54 inject: log.md UNTRACKED+present -> reads entries/, ignores stale log.md"
fi

# ABSENT state: log.md removed entirely (post-freeze clean clone) -> reads entries/.
rm -f "$DLM/.ai/activity/log.md"
INJECT_OUT=$(cd "$DLM" && bash "$HOOKS_DIR/activity-log-inject.sh" 2>&1)
if echo "$INJECT_OUT" | grep -q "entries/" && echo "$INJECT_OUT" | grep -q "entries fixture (untracked-state)"; then
  pass=$((pass+1)); echo "  PASS  t55 inject: log.md ABSENT -> reads entries/"
else
  fail=$((fail+1)); fails+=("t55 inject: log.md ABSENT -> reads entries/"); echo "  FAIL  t55 inject: log.md ABSENT -> reads entries/"
fi

# B2 regression: outside any git repo, the predicate's stderr (e.g.
# "fatal: not a git repository") must NOT leak into the injected output —
# i.e. the `git ls-files` call must redirect stderr, not just stdout.
NOTGIT=$(mktemp -d)
mkdir -p "$NOTGIT/.ai/activity/entries" "$NOTGIT/.ai/handoffs/to-kiro/open"
printf '## 2026-01-03 00:00Z - kiro - notgit-abcd\n- Action: entries fixture (not-a-repo state)\n' > "$NOTGIT/.ai/activity/entries/20260103T000000Z-kiro-notgit-abcd.md"
INJECT_OUT=$(cd "$NOTGIT" && bash "$HOOKS_DIR/activity-log-inject.sh" 2>&1)
if ! echo "$INJECT_OUT" | grep -qi "fatal: not a git repository"; then
  pass=$((pass+1)); echo "  PASS  t56 inject: not-a-repo does not leak git stderr into output"
else
  fail=$((fail+1)); fails+=("t56 inject: not-a-repo does not leak git stderr into output"); echo "  FAIL  t56 inject: not-a-repo does not leak git stderr into output"
fi
if echo "$INJECT_OUT" | grep -q "entries fixture (not-a-repo state)"; then
  pass=$((pass+1)); echo "  PASS  t57 inject: not-a-repo falls through to entries/ (fail-direction correct)"
else
  fail=$((fail+1)); fails+=("t57 inject: not-a-repo falls through to entries/ (fail-direction correct)"); echo "  FAIL  t57 inject: not-a-repo falls through to entries/ (fail-direction correct)"
fi
REMIND_OUT=$(cd "$NOTGIT" && bash "$HOOKS_DIR/activity-log-remind.sh" 2>&1)
if ! echo "$REMIND_OUT" | grep -qi "fatal: not a git repository"; then
  pass=$((pass+1)); echo "  PASS  t58 remind: not-a-repo does not leak git stderr into output"
else
  fail=$((fail+1)); fails+=("t58 remind: not-a-repo does not leak git stderr into output"); echo "  FAIL  t58 remind: not-a-repo does not leak git stderr into output"
fi

rm -rf "$DLM" "$NOTGIT"

# --- destructive-cmd-guard ---
echo "destructive-cmd-guard:"
run_test "t12 block rm -rf /"              "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'              2
run_test "t13 allow rm -rf /tmp/foo"       "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf /tmp/foo"}}'       0
run_test "t14 block rm -rf / (trailing sp)" "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf / "}}'            2
run_test "t15 block rm -rf /;echo ok"      "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf /;echo ok"}}'      2
run_test "t16 allow rm -rf /usr"           "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf /usr"}}'           0
run_test "t17 allow rm -rf ~/foo"          "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf ~/foo"}}'          0
run_test "t18 allow rm -rf *.log"          "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf *.log"}}'          0
run_test "t19 allow rm -rf ./build"        "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf ./build"}}'        0
run_test "t20 block DROP DATABASE (upper)" "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"DROP DATABASE foo"}}'     2
run_test "t21 block Drop Database (mixed)" "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"Drop Database foo"}}'     2
run_test "t22 allow git status"            "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"git status"}}'            0

# --- ADR-0004: worktree confinement + fleet whitelist ---
echo "worktree-confinement-guard + fleet-whitelist-guard:"

# Helper: run_test_cd — executes hook with cwd set to $dir
run_test_cd() {
  local name="$1" dir="$2" hook="$3" payload="$4" expected="$5"
  local hook_abs
  hook_abs="$(cd "$(dirname "$hook")" && pwd)/$(basename "$hook")"
  actual=$(cd "$dir" && printf '%s' "$payload" | bash "$hook_abs" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
    echo "  PASS  $name"
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
    echo "  FAIL  $name (expected $expected, got $actual)"
  fi
}

# Temp fixtures
T=$(mktemp -d)
PROJ_NAME=$(basename "$PWD")

# Fleet fixture 1: registry whitelists this project -> proj-b only
mkdir -p "$T/f1/.fleet/handoffs/to-proj-b/open" "$T/f1/.fleet/handoffs/to-proj-c/open" "$T/f1/.fleet/activity"
printf '{"projects":{"%s":{"path":"x","talks_to":["proj-b"]}}}' "$PROJ_NAME" > "$T/f1/.fleet/registry.json"

# Fleet fixture 2: no registry at all
mkdir -p "$T/f2/.fleet/handoffs/to-proj-b/open"

# Worktree fixture: simulated executor worktree at .wt/projA/kiro
mkdir -p "$T/.wt/projA/kiro/src"

WC="$HOOKS_DIR/worktree-confinement-guard.sh"
FW="$HOOKS_DIR/fleet-whitelist-guard.sh"

run_test    "t23 fleet whitelisted target allowed"   "$FW" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-b/open/x.md\"}}" 0
run_test    "t24 fleet non-whitelisted blocked"      "$FW" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-c/open/x.md\"}}" 2
run_test    "t25 fleet missing registry blocked"     "$FW" "{\"tool_input\":{\"file_path\":\"$T/f2/.fleet/handoffs/to-proj-b/open/x.md\"}}" 2
run_test    "t26 fleet activity log allowed"         "$FW" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/activity/log.md\"}}" 0
run_test_cd "t27 worktree absolute escape blocked"   "$T/.wt/projA/kiro" "$WC" "{\"tool_input\":{\"file_path\":\"$T/projA/src/x.ts\"}}" 2
run_test_cd "t28 worktree ../ escape blocked"        "$T/.wt/projA/kiro" "$WC" '{"tool_input":{"file_path":"../kimi/src/x.ts"}}' 2
run_test_cd "t29 worktree in-tree write allowed"     "$T/.wt/projA/kiro" "$WC" '{"tool_input":{"file_path":"src/x.ts"}}' 0
run_test_cd "t29a worktree absolute in-tree .ai allowed (snapshot-copy)" "$T/.wt/projA/kiro" "$WC" "{\"tool_input\":{\"file_path\":\"$T/.wt/projA/kiro/.ai/activity/log.md\"}}" 0
run_test_cd "t29b worktree relative .ai allowed"    "$T/.wt/projA/kiro" "$WC" '{"tool_input":{"file_path":".ai/handoffs/x.md"}}' 0

rm -rf "$T"

# --- python-less fail-open regression (2026-07-09) ---
# On this host python3 resolves to a Windows Store alias stub (empty stdout,
# exit 0). Before the fix the `|| python` chain keyed on exit status, so the
# guards silently no-op'd (fail-OPEN) whenever python was unavailable. These
# tests run each guard with PATH restricted to /usr/bin:/bin (no python on
# PATH) to force the pure-sed fallback, and assert both directions: a
# forbidden write still BLOCKS (exit 2) and a benign write is ALLOWED (exit 0).
echo "python-less fail-open regression (PATH=/usr/bin:/bin):"

run_test_pyless() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  actual=$(printf '%s' "$payload" | PATH="/usr/bin:/bin" bash "$hook" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
    echo "  PASS  $name"
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
    echo "  FAIL  $name (expected $expected, got $actual)"
  fi
}

run_test_pyless "t30 pyless framework .claude blocked" "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".claude/agents/x.md"}}' 2
run_test_pyless "t31 pyless framework .ai allowed"     "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"file_path":".ai/handoffs/x.md"}}'   0
run_test_pyless "t32 pyless root evil.txt blocked"     "$HOOKS_DIR/root-file-guard.sh"     '{"tool_input":{"file_path":"evil.txt"}}'          2
run_test_pyless "t33 pyless root src/main.rs allowed"  "$HOOKS_DIR/root-file-guard.sh"     '{"tool_input":{"file_path":"src/main.rs"}}'       0
run_test_pyless "t34 pyless sensitive .env blocked"    "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"file_path":".env"}}'             2
run_test_pyless "t35 pyless destructive rm -rf / blocked" "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'       2
run_test_pyless "t36 pyless destructive git status allowed" "$HOOKS_DIR/destructive-cmd-guard.sh" '{"tool_input":{"command":"git status"}}'   0

# --- fail-CLOSED regression: non-empty stdin, no parseable field → block ---
echo "fail-closed on unparseable input:"
run_test "t37 framework unparseable → block" "$HOOKS_DIR/framework-dir-guard.sh"  '{"garbage":true}' 2
run_test "t38 root unparseable → block"      "$HOOKS_DIR/root-file-guard.sh"      '{"garbage":true}' 2
run_test "t39 sensitive unparseable → block" "$HOOKS_DIR/sensitive-file-guard.sh" '{"garbage":true}' 2
run_test "t40 destructive unparseable → block" "$HOOKS_DIR/destructive-cmd-guard.sh" '{"garbage":true}' 2
# empty stdin → allow (nothing to evaluate)
run_test "t41 framework empty stdin → allow"  "$HOOKS_DIR/framework-dir-guard.sh"  '' 0
run_test "t42 destructive empty stdin → allow" "$HOOKS_DIR/destructive-cmd-guard.sh" '' 0

# --- str_replace "path"-key extraction regression (2026-07-10) ---
# Kiro's fs_write/str_replace tool_input carries the target under "path", not
# "file_path". The guards' matcher (fs_write|str_replace|write) caught these
# edits but the extraction only read file_path → every str_replace edit hit the
# fail-CLOSED exit-2 and was blanket-blocked as noise. These assert the guards
# now path-evaluate the "path" key: forbidden → BLOCK, legit → ALLOW, and a
# genuine no-target input → still BLOCK (fail-closed preserved).
echo "str_replace \"path\"-key extraction:"
run_test "t43 path .claude blocked (framework)"  "$HOOKS_DIR/framework-dir-guard.sh"  '{"tool_input":{"path":".claude/agents/x.md"}}'  2
run_test "t44 path .ai allowed (framework)"      "$HOOKS_DIR/framework-dir-guard.sh"  '{"tool_input":{"path":".ai/activity/log.md"}}'  0
run_test "t45 path no-target block (framework)"  "$HOOKS_DIR/framework-dir-guard.sh"  '{"tool_input":{"command":"str_replace"}}'       2
run_test "t46 path evil.txt blocked (root)"      "$HOOKS_DIR/root-file-guard.sh"      '{"tool_input":{"path":"evil.txt"}}'             2
run_test "t47 path src/main.rs allowed (root)"   "$HOOKS_DIR/root-file-guard.sh"      '{"tool_input":{"path":"src/main.rs"}}'          0
run_test "t48 path .env blocked (sensitive)"     "$HOOKS_DIR/sensitive-file-guard.sh" '{"tool_input":{"path":".env"}}'                 2
# pyless: force the pure-sed "path" fallback (python is a Windows Store stub) —
# the sed path pattern must extract without any python present.
run_test_pyless "t49 pyless path .claude blocked" "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"path":".claude/agents/x.md"}}' 2
run_test_pyless "t50 pyless path .ai allowed"      "$HOOKS_DIR/framework-dir-guard.sh" '{"tool_input":{"path":".ai/handoffs/x.md"}}'   0

# --- Summary ---
echo ""
total=$((pass+fail))
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
