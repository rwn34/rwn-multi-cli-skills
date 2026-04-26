#!/bin/bash
# test_hooks.sh — regression suite for .claude/hooks/pretool-*.sh
# Exit 0 if all pass, 1 otherwise.
# Run from repo root: bash .claude/hooks/test_hooks.sh

WE=".claude/hooks/pretool-write-edit.sh"
BH=".claude/hooks/pretool-bash.sh"

pass=0; fail=0; fails=()

run_test() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  local actual
  actual=$(printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
  fi
}

# --- write-edit: root-file policy ---
run_test "t1 root non-allowlisted"       "$WE" '{"tool_input":{"file_path":"evil.txt"}}'                 2
run_test "t2 root .gitignore allowed"    "$WE" '{"tool_input":{"file_path":".gitignore"}}'               0
run_test "t3 non-root src path"          "$WE" '{"tool_input":{"file_path":"src/main.rs"}}'              0
run_test "t4 .ai handoffs path"          "$WE" '{"tool_input":{"file_path":".ai/handoffs/test.md"}}'     0

# --- write-edit: framework-dir rule ---
run_test "t5 .kimi blocked"              "$WE" '{"tool_input":{"file_path":".kimi/agents/test.md"}}'     2
run_test "t6 .kiro blocked"              "$WE" '{"tool_input":{"file_path":".kiro/agents/test.json"}}'   2
run_test "t7 .claude allowed"            "$WE" '{"tool_input":{"file_path":".claude/agents/test.md"}}'   0

# --- write-edit: sensitive files ---
run_test "t8 .env blocked"               "$WE" '{"tool_input":{"file_path":".env"}}'                     2
run_test "t9 id_rsa blocked"             "$WE" '{"tool_input":{"file_path":"id_rsa"}}'                   2
run_test "t10 id_ed25519 blocked"        "$WE" '{"tool_input":{"file_path":"id_ed25519"}}'               2
run_test "t11 server.key blocked"        "$WE" '{"tool_input":{"file_path":"server.key"}}'               2
run_test "t12 cert.p12 blocked"          "$WE" '{"tool_input":{"file_path":"cert.p12"}}'                 2

# --- pretool-bash ---
run_test "t13 rm -rf / blocked"          "$BH" '{"tool_input":{"command":"rm -rf /"}}'                   2
run_test "t14 git push --force blocked"  "$BH" '{"tool_input":{"command":"git push --force origin main"}}' 2
run_test "t15 DROP DATABASE blocked"     "$BH" '{"tool_input":{"command":"DROP DATABASE foo"}}'          2
run_test "t16 git status allowed"        "$BH" '{"tool_input":{"command":"git status"}}'                 0

# --- bonus: fail-open on empty/unparseable stdin ---
run_test "t17 empty stdin fail-open"     "$WE" ''                                                        0

# --- pretool-bash: rm -rf boundary (false-positive regression) ---
run_test "t18 rm -rf /tmp/foo allowed"   "$BH" '{"tool_input":{"command":"rm -rf /tmp/foo"}}'            0
run_test "t19 rm -rf / trailing space"   "$BH" '{"tool_input":{"command":"rm -rf / "}}'                  2
run_test "t20 rm -rf /;echo ok blocked"  "$BH" '{"tool_input":{"command":"rm -rf /;echo ok"}}'           2
run_test "t21 rm -rf /usr allowed"       "$BH" '{"tool_input":{"command":"rm -rf /usr"}}'                0

# --- write-edit: cross-CLI graph-tool dirs (per codegraph+kimigraph+kirograph adoption) ---
run_test "t22 .codegraph allowed"        "$WE" '{"tool_input":{"file_path":".codegraph/codegraph.db"}}'  0
run_test "t23 .kimigraph blocked"        "$WE" '{"tool_input":{"file_path":".kimigraph/kimigraph.db"}}'  2
run_test "t24 .kirograph blocked"        "$WE" '{"tool_input":{"file_path":".kirograph/kirograph.db"}}'  2

total=$((pass+fail))
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
