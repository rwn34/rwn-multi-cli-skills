#!/bin/bash
# test_hooks.sh — regression suite for .kimi/hooks/*
# Exits 0 if all pass, 1 if any fail.

pass=0
fail=0
fails=()

run_test() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  local actual
  actual=$(echo "$payload" | bash "$hook" > /dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
  fi
}

# --- root-guard ---
run_test "t1-root-blocks-evil"     ".kimi/hooks/root-guard.sh"     '{"tool_input":{"file_path":"evil.txt"}}'          2
run_test "t2-root-allows-gitignore" ".kimi/hooks/root-guard.sh"    '{"tool_input":{"file_path":".gitignore"}}'        0
run_test "t3-root-allows-src"      ".kimi/hooks/root-guard.sh"     '{"tool_input":{"file_path":"src/main.rs"}}'       0

# --- framework-guard ---
run_test "t4-fw-allows-ai"         ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".ai/handoffs/test.md"}}'  0
run_test "t5-fw-blocks-claude"     ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".claude/agents/test.md"}}' 2
run_test "t6-fw-blocks-kiro"       ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".kiro/agents/test.json"}}' 2
run_test "t27-fw-allows-kimigraph" ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".kimigraph/config.json"}}' 0
run_test "t28-fw-blocks-codegraph" ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".codegraph/codegraph.db"}}' 2
run_test "t29-fw-blocks-kirograph" ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".kirograph/kirograph.db"}}' 2

# --- sensitive-guard ---
run_test "t7-sens-blocks-env"      ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":".env"}}'              2
run_test "t8-sens-blocks-id_rsa"   ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":"id_rsa"}}'           2
run_test "t9-sens-blocks-id_ed25519" ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":"id_ed25519"}}'     2
run_test "t10-sens-blocks-key"     ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":"server.key"}}'       2
run_test "t11-sens-blocks-pem"     ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":"cert.pem"}}'         2
run_test "t17-sens-blocks-secrets-yaml" ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":"secrets.yaml"}}'     2
run_test "t18-sens-blocks-credentials-json" ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"file_path":"credentials.json"}}' 2

# --- destructive-guard ---
run_test "t12-dest-blocks-rmrf"    ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'          2
run_test "t13-dest-blocks-drop"    ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"DROP DATABASE foo"}}'  2
run_test "t14-dest-blocks-mixed"   ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"Drop Database foo"}}' 2
run_test "t15-dest-allows-gitstatus" ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"git status"}}'     0
run_test "t19-dest-blocks-rmrf-root"    ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'          2
run_test "t20-dest-allows-rmrf-tmp"     ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /tmp/foo"}}'    0
run_test "t21-dest-blocks-rmrf-trailsp" ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf / "}}'         2
run_test "t22-dest-blocks-rmrf-semi"    ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /;echo ok"}}'  2
run_test "t23-dest-allows-rmrf-usr"     ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /usr"}}'       0
run_test "t24-dest-allows-rmrf-homefoo" ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf ~/foo"}}'      0
run_test "t25-dest-allows-rmrf-glob"    ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf *.log"}}'      0
run_test "t26-dest-allows-rmrf-dotbuild" ".kimi/hooks/destructive-guard.sh" '{"tool_input":{"command":"rm -rf ./build"}}'   0

# --- stdin-drain regression (F-4) ---
run_test "t16-empty-stdin"         ".kimi/hooks/root-guard.sh"      ""                                                     0

total=$((pass+fail))
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
