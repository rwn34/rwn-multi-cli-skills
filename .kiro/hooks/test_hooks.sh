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
