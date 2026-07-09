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

# Like run_test, but executes the hook with cwd set to $dir (simulates a
# session rooted elsewhere, e.g. an executor worktree — ADR-0004).
run_test_cd() {
  local name="$1" dir="$2" hook="$3" payload="$4" expected="$5"
  local hook_abs="$PWD/$hook" actual
  actual=$(cd "$dir" && printf '%s' "$payload" | bash "$hook_abs" >/dev/null 2>&1; echo $?)
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
run_test "t27-fw-blocks-kimigraph" ".kimi/hooks/framework-guard.sh" '{"tool_input":{"file_path":".kimigraph/config.json"}}' 2
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

# --- real tool-name payload regression (Write/Edit use 'path', not 'file_path') ---
run_test "t39-root-blocks-evil-path"     ".kimi/hooks/root-guard.sh"      '{"tool_input":{"path":"evil.txt"}}'                2
run_test "t40-root-allows-src-path"      ".kimi/hooks/root-guard.sh"      '{"tool_input":{"path":"src/main.rs"}}'             0
run_test "t41-fw-blocks-claude-path"     ".kimi/hooks/framework-guard.sh" '{"tool_input":{"path":".claude/agents/test.md"}}'  2
run_test "t42-fw-blocks-kiro-path"       ".kimi/hooks/framework-guard.sh" '{"tool_input":{"path":".kiro/agents/test.json"}}'  2
run_test "t43-sens-blocks-env-path"      ".kimi/hooks/sensitive-guard.sh" '{"tool_input":{"path":".env"}}'                    2

# --- matcher regression: canonical snippet must use real tool names ---
if grep -qE 'matcher[[:space:]]*=[[:space:]]*"WriteFile\|StrReplaceFile"' .ai/config-snippets/kimi-hooks.toml; then
    fail=$((fail+1))
    fails+=("t44-snippet-uses-real-tool-names (expected Write|Edit matcher, found WriteFile|StrReplaceFile)")
else
    pass=$((pass+1))
fi

# --- matcher regression: active global config must use real tool names (if present) ---
for cfg in ~/.kimi-code/config.toml ~/.kimi/config.toml; do
    if [ -f "$cfg" ]; then
        if grep -qE 'matcher[[:space:]]*=[[:space:]]*"WriteFile\|StrReplaceFile"' "$cfg"; then
            fail=$((fail+1))
            fails+=("t45-active-config-uses-real-tool-names (file $cfg expected Write|Edit matcher, found WriteFile|StrReplaceFile)")
        else
            pass=$((pass+1))
        fi
    fi
done

# --- matcher regression: shell tool name must be "Bash", not "Shell" ---
if grep -qE 'matcher[[:space:]]*=[[:space:]]*"Shell"' .ai/config-snippets/kimi-hooks.toml; then
    fail=$((fail+1))
    fails+=("t46-snippet-uses-bash-tool-name (expected Bash matcher, found Shell)")
else
    pass=$((pass+1))
fi

for cfg in ~/.kimi-code/config.toml ~/.kimi/config.toml; do
    if [ -f "$cfg" ]; then
        if grep -qE 'matcher[[:space:]]*=[[:space:]]*"Shell"' "$cfg"; then
            fail=$((fail+1))
            fails+=("t47-active-config-uses-bash-tool-name (file $cfg expected Bash matcher, found Shell)")
        else
            pass=$((pass+1))
        fi
    fi
done

# --- config path regression: snippet must point to ~/.kimi-code/config.toml ---
if grep -qE '~/.kimi/config.toml(?!-code)' .ai/config-snippets/kimi-hooks.toml; then
    fail=$((fail+1))
    fails+=("t48-snippet-points-to-active-config (expected ~/.kimi-code/config.toml, found ~/.kimi/config.toml)")
else
    pass=$((pass+1))
fi

# --- worktree-fleet-guard: ADR-0004 worktree confinement + fleet whitelist ---
T=$(mktemp -d)
PROJ_NAME=$(basename "$PWD")
# fleet fixture 1: registry whitelists this project -> proj-b only
mkdir -p "$T/f1/.fleet/handoffs/to-proj-b/open" "$T/f1/.fleet/handoffs/to-proj-c/open" "$T/f1/.fleet/activity"
printf '{"projects":{"%s":{"path":"x","talks_to":["proj-b"]}}}' "$PROJ_NAME" > "$T/f1/.fleet/registry.json"
# fleet fixture 2: no registry at all
mkdir -p "$T/f2/.fleet/handoffs/to-proj-b/open"
# worktree fixture: simulated executor worktree at .wt/projA/kimi
mkdir -p "$T/.wt/projA/kimi/src"

run_test "t32-fleet-whitelisted-allowed"  ".kimi/hooks/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-b/open/x.md\"}}" 0
run_test "t33-fleet-nonwhitelisted-blocked" ".kimi/hooks/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-c/open/x.md\"}}" 2
run_test "t34-fleet-noregistry-blocked"   ".kimi/hooks/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f2/.fleet/handoffs/to-proj-b/open/x.md\"}}" 2
run_test "t35-fleet-activity-allowed"     ".kimi/hooks/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/activity/log.md\"}}" 0
run_test_cd "t36-worktree-absolute-escape-blocked" "$T/.wt/projA/kimi" ".kimi/hooks/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/projA/src/x.ts\"}}" 2
run_test_cd "t37-worktree-dotdot-escape-blocked"   "$T/.wt/projA/kimi" ".kimi/hooks/worktree-fleet-guard.sh" '{"tool_input":{"file_path":"../kimi/src/x.ts"}}' 2
run_test_cd "t38-worktree-in-tree-allowed"         "$T/.wt/projA/kimi" ".kimi/hooks/worktree-fleet-guard.sh" '{"tool_input":{"file_path":"src/x.ts"}}' 0

rm -rf "$T"

total=$((pass+fail))
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
