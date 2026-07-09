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

# Like run_test, but executes the hook with cwd set to $dir (simulates a
# session rooted elsewhere, e.g. an executor worktree — ADR-0004 Rule 2.6).
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

# --- write-edit: root-file policy ---
run_test "t1 root non-allowlisted"       "$WE" '{"tool_input":{"file_path":"evil.txt"}}'                 2
run_test "t2 subagent .gitignore allowed" "$WE" '{"agent_type":"coder","tool_input":{"file_path":".gitignore"}}' 0
run_test "t2b main-thread .gitignore blocked (delegate it)" "$WE" '{"tool_input":{"file_path":".gitignore"}}' 2
run_test "t3 subagent src path allowed"  "$WE" '{"agent_type":"coder","tool_input":{"file_path":"src/main.rs"}}' 0
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

# --- write-edit: Crush retirement (task-10 deletion 2026-07-09 — CRUSH.md/.crush.json removed from ADR-0001 + allowlist) ---
run_test "t25 CRUSH.md blocked"          "$WE" '{"tool_input":{"file_path":"CRUSH.md"}}'                 2
run_test "t26 .crush.json blocked"       "$WE" '{"tool_input":{"file_path":".crush.json"}}'              2

# --- write-edit: OpenCode custodianship (ADR-0001/0002 amendments 2026-07-09 — Claude maintains OpenCode's files) ---
run_test "t26b opencode.json allowed"    "$WE" '{"tool_input":{"file_path":"opencode.json"}}'            0
run_test "t26c .opencode/ allowed"       "$WE" '{"tool_input":{"file_path":".opencode/plugin/framework-guard.js"}}' 0

# --- write-edit: main-thread delegation enforcement (Rule 2.5 — orchestrator pattern) ---
run_test "t27 main-thread src blocked"   "$WE" '{"tool_input":{"file_path":"src/main.rs"}}'              2
run_test "t28 main-thread docs blocked"  "$WE" '{"tool_input":{"file_path":"docs/specs/x.md"}}'          2
run_test "t29 main-thread .ai allowed"   "$WE" '{"tool_input":{"file_path":".ai/research/x.md"}}'        0
run_test "t30 subagent docs allowed"     "$WE" '{"agent_type":"doc-writer","tool_input":{"file_path":"docs/specs/x.md"}}' 0
run_test "t31 subagent .kimi still blocked" "$WE" '{"agent_type":"coder","tool_input":{"file_path":".kimi/agents/x.yaml"}}' 2

# --- write-edit: ADR-0004 worktree confinement (Rule 2.6) + fleet whitelist (Rule 2.7) ---
# Fixtures in a temp dir; cleaned up below regardless of pass/fail.
T=$(mktemp -d)
PROJ_NAME=$(basename "$PWD")
# fleet fixture 1: registry whitelists this project -> proj-b only
mkdir -p "$T/f1/.fleet/handoffs/to-proj-b/open" "$T/f1/.fleet/handoffs/to-proj-c/open" "$T/f1/.fleet/activity"
printf '{"projects":{"%s":{"path":"x","talks_to":["proj-b"]}}}' "$PROJ_NAME" > "$T/f1/.fleet/registry.json"
# fleet fixture 2: no registry at all
mkdir -p "$T/f2/.fleet/handoffs/to-proj-b/open"
# worktree fixture: simulated executor worktree at .wt/projA/kiro
mkdir -p "$T/.wt/projA/kiro/src"

run_test "t32 fleet whitelisted target allowed"  "$WE" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-b/open/x.md\"}}" 0
run_test "t33 fleet non-whitelisted blocked"     "$WE" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-c/open/x.md\"}}" 2
run_test "t34 fleet missing registry blocked"    "$WE" "{\"tool_input\":{\"file_path\":\"$T/f2/.fleet/handoffs/to-proj-b/open/x.md\"}}" 2
run_test "t35 fleet activity log allowed"        "$WE" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/activity/log.md\"}}" 0
run_test_cd "t36 worktree absolute escape blocked" "$T/.wt/projA/kiro" "$WE" "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$T/projA/src/x.ts\"}}" 2
run_test_cd "t37 worktree ../ escape blocked"      "$T/.wt/projA/kiro" "$WE" '{"agent_type":"coder","tool_input":{"file_path":"../kimi/src/x.ts"}}' 2
run_test_cd "t38 worktree in-tree subagent write allowed" "$T/.wt/projA/kiro" "$WE" '{"agent_type":"coder","tool_input":{"file_path":"src/x.ts"}}' 0

rm -rf "$T"

# --- write-edit: python-less environment must NOT fail open (validation campaign 2026-07-09) ---
# In the live Claude hook runtime python3 can be a Windows Store alias stub that prints
# nothing + exits 0. These run the hook with python off PATH to prove the pure-bash/sed
# extractor + fail-CLOSED handling work without python. They FAIL against the pre-fix
# hook (which returned 0 for both t39 and t40) and PASS after the fix.
run_test_nopy() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  local hook_abs="$PWD/$hook" actual
  actual=$(printf '%s' "$payload" | PATH="/usr/bin:/bin" bash "$hook_abs" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
  fi
}
run_test_nopy "t39 no-python .kimi blocked (fail-closed)"     "$WE" '{"tool_input":{"file_path":".kimi/evil.txt"}}' 2
run_test_nopy "t40 no-python main-thread src blocked"         "$WE" '{"tool_input":{"file_path":"src/x.ts"}}'       2
run_test_nopy "t41 no-python subagent src allowed"            "$WE" '{"agent_type":"coder","tool_input":{"file_path":"src/x.ts"}}' 0
run_test_nopy "t42 no-python empty stdin allowed"             "$WE" ''                                             0
run_test_nopy "t43 no-python framework .ai allowed"           "$WE" '{"tool_input":{"file_path":".ai/x.md"}}'      0
# fail-CLOSED: non-empty stdin with no parseable file_path must block (not fail open)
run_test      "t44 non-empty unparseable stdin blocked"       "$WE" '{"tool_input":{"garbage":true}}'              2

# --- pretool-bash: python-less environment must NOT fail open (validation campaign 2026-07-09) ---
# Same WindowsApps python-stub fail-open class as t39-t44, but on the higher-severity
# destructive-command guard. These FAIL against the pre-fix bash hook (which returned 0
# for t45/t46 because cmd came back empty) and PASS after the fail-CLOSED + sed-fallback fix.
run_test_nopy "t45 no-python rm -rf / blocked (fail-closed)"  "$BH" '{"tool_input":{"command":"rm -rf /"}}'        2
run_test_nopy "t46 no-python git push --force blocked"        "$BH" '{"tool_input":{"command":"git push --force origin main"}}' 2
run_test_nopy "t47 no-python benign ls allowed"               "$BH" '{"tool_input":{"command":"ls -la"}}'          0
run_test_nopy "t48 no-python DROP DATABASE blocked"           "$BH" '{"tool_input":{"command":"DROP DATABASE foo"}}' 2
run_test_nopy "t49 no-python empty stdin allowed"             "$BH" ''                                             0
# fail-CLOSED: non-empty stdin with no parseable command must block (not fail open)
run_test      "t50 bash non-empty unparseable stdin blocked"  "$BH" '{"tool_input":{"garbage":true}}'              2
run_test_nopy "t51 no-python unparseable stdin blocked"       "$BH" '{"tool_input":{"garbage":true}}'              2

total=$((pass+fail))
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
