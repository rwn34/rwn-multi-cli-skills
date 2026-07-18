#!/bin/bash
# test_hooks.sh — regression suite for .claude/hooks/pretool-*.sh
# Exit 0 if all pass, 1 otherwise.
# Run from repo root: bash .claude/hooks/test_hooks.sh
#
# This is the #50 Write/Edit regression suite, UNCHANGED except:
#   * t87 retargeted from .claude/hooks/x.sh -> .claude/agents/x.sh, because the
#     bash-guard fix adds Rule 1.5 (enforcement-layer self-protection): the guard
#     scripts under .claude/hooks/ are now owner-apply-ONLY on BOTH surfaces. t87's
#     job (prove an absolute .claude path relativizes + allows) is preserved by the
#     .claude/agents/ target; the hooks subdir is exercised by t96-t99 below.
#   * t96-t99 added for Rule 1.5.
#   * the tail delegates to test-bash-guard.sh so one entry point runs everything.

WE=".claude/hooks/pretool-write-edit.sh"
BH=".claude/hooks/pretool-bash.sh"

pass=0; fail=0; skip=0; fails=(); skips=()

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
# The fleet tests must run from a NON-worktree cwd: Rule 2.6 (worktree confinement)
# is evaluated BEFORE Rule 2.7, so if the suite itself happens to be run from inside
# an executor worktree (.wt/<project>/<cli>/ — the normal case for a dispatched CLI),
# the absolute fleet-fixture paths are legitimately blocked as worktree escapes and
# t32/t35 fail for environmental reasons. Pinning cwd to a scratch primary-shaped
# root makes the suite hermetic wherever it is run from.
PROJ_NAME=proj
mkdir -p "$T/proj"
# fleet fixture 1: registry whitelists this project -> proj-b only
mkdir -p "$T/f1/.fleet/handoffs/to-proj-b/open" "$T/f1/.fleet/handoffs/to-proj-c/open" "$T/f1/.fleet/activity"
printf '{"projects":{"%s":{"path":"x","talks_to":["proj-b"]}}}' "$PROJ_NAME" > "$T/f1/.fleet/registry.json"
# fleet fixture 2: no registry at all
mkdir -p "$T/f2/.fleet/handoffs/to-proj-b/open"
# worktree fixture: simulated executor worktree at .wt/projA/kiro
mkdir -p "$T/.wt/projA/kiro/src" "$T/.wt/projA/kiro/.kimi" "$T/.wt/projA/kiro/.ai"

run_test_cd "t32 fleet whitelisted target allowed"  "$T/proj" "$WE" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-b/open/x.md\"}}" 0
run_test_cd "t33 fleet non-whitelisted blocked"     "$T/proj" "$WE" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-c/open/x.md\"}}" 2
run_test_cd "t34 fleet missing registry blocked"    "$T/proj" "$WE" "{\"tool_input\":{\"file_path\":\"$T/f2/.fleet/handoffs/to-proj-b/open/x.md\"}}" 2
run_test_cd "t35 fleet activity log allowed"        "$T/proj" "$WE" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/activity/log.md\"}}" 0
run_test_cd "t36 worktree absolute escape blocked" "$T/.wt/projA/kiro" "$WE" "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$T/projA/src/x.ts\"}}" 2
run_test_cd "t37 worktree ../ escape blocked"      "$T/.wt/projA/kiro" "$WE" '{"agent_type":"coder","tool_input":{"file_path":"../kimi/src/x.ts"}}' 2
run_test_cd "t38 worktree in-tree subagent write allowed" "$T/.wt/projA/kiro" "$WE" '{"agent_type":"coder","tool_input":{"file_path":"src/x.ts"}}' 0

# --- write-edit: python-less environment must NOT fail open (validation campaign 2026-07-09) ---
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
run_test_nopy "t45 no-python rm -rf / blocked (fail-closed)"  "$BH" '{"tool_input":{"command":"rm -rf /"}}'        2
run_test_nopy "t46 no-python git push --force blocked"        "$BH" '{"tool_input":{"command":"git push --force origin main"}}' 2
run_test_nopy "t47 no-python benign ls allowed"               "$BH" '{"tool_input":{"command":"ls -la"}}'          0
run_test_nopy "t48 no-python DROP DATABASE blocked"           "$BH" '{"tool_input":{"command":"DROP DATABASE foo"}}' 2
run_test_nopy "t49 no-python empty stdin allowed"             "$BH" ''                                             0
# fail-CLOSED: non-empty stdin with no parseable command must block (not fail open)
run_test      "t50 bash non-empty unparseable stdin blocked"  "$BH" '{"tool_input":{"garbage":true}}'              2
run_test_nopy "t51 no-python unparseable stdin blocked"       "$BH" '{"tool_input":{"garbage":true}}'              2

# ===========================================================================
# ABSOLUTE-PATH CANONICALIZATION (regression: subagent abs-path territorial bypass)
# ===========================================================================
# Root cause (2026-07-12): the hook did `project_root=$(pwd)` — Git Bash yields the
# MSYS form (/c/Users/...) — and prefix-compared it against file_path, which the
# Write/Edit tools emit as a WINDOWS absolute path (C:\Users\...). The compare never
# matched, `rel` stayed absolute, and every territorial `case "$rel" in .kimi|.kimi/*)`
# arm silently missed. All of these run with cwd = a scratch project root NOT under
# .wt/, because Rule 2.6 blocks absolute paths outright and would mask the bug.

P="$T/proj"                                   # scratch primary-shaped root (from fixture block above)
mkdir -p "$P/.kimi" "$P/.kiro" "$P/.claude/hooks" "$P/.claude/agents" "$P/.ai" "$P/src" "$P/docs"

bs()  { printf '%s' "$1" | tr '/' '\\'; }                       # /a/b -> \a\b
jbs() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }                 # escape backslashes for JSON
root_win() {
  case "$1" in
    /[A-Za-z]/*) printf '%s:/%s' "$(printf '%s' "${1:1:1}" | tr 'a-z' 'A-Z')" "${1:3}" ; return ;;
  esac
  command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" 2>/dev/null
}
PBS=$(bs "$P")                 # \tmp\...\proj   (on Windows: the true backslash form)
PWIN=$(root_win "$P")          # C:/tmp/.../proj  or empty off-Windows
PUP=$(printf '%s' "$P" | tr 'a-z' 'A-Z')   # case-variant of the root

# w <name> <expected> <json-payload>  — always run from the scratch root $P
w() { run_test_cd "$1" "$P" "$WE" "$3" "$2"; }

# --- SUBAGENT -> .kimi/ : every path shape must BLOCK (this is the bypass itself) ---
w "t52 abs native .kimi (subagent)"        2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.kimi/evil.md\"}}"
w "t53 abs backslash .kimi (subagent)"     2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$PBS\\.kimi\\evil.md")\"}}"
w "t54 abs mixed separators .kimi"         2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$PBS")/.kimi\\\\evil.md\"}}"
w "t55 abs doubled slashes .kimi"          2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P//.kimi//evil.md\"}}"
w "t56 dot-segment .kimi"                  2 '{"agent_type":"coder","tool_input":{"file_path":"./.kimi/./evil.md"}}'
w "t57 dotdot laundering via .claude"      2 '{"agent_type":"coder","tool_input":{"file_path":".claude/../.kimi/evil.md"}}'
w "t58 case-variant root .kimi"            2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$PUP/.kimi/evil.md\"}}"
w "t59 win drive abs .kimi (C:\\)"         2 '{"agent_type":"coder","tool_input":{"file_path":"C:\\Users\\x\\proj\\.kimi\\evil.md"}}'
w "t60 win drive abs .kimi (c:/ lower)"    2 '{"agent_type":"coder","tool_input":{"file_path":"c:/Users/x/proj/.kimi/evil.md"}}'
w "t61 msys drive abs .kimi (/C/ upper)"   2 '{"agent_type":"coder","tool_input":{"file_path":"/C/Users/x/proj/.kimi/evil.md"}}'

# --- SUBAGENT -> the other territorial dirs, absolute forms ---
w "t62 abs .kiro (subagent)"               2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.kiro/agents/x.json\"}}"
w "t63 abs backslash .kiro (subagent)"     2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$PBS\\.kiro\\agents\\x.json")\"}}"
w "t64 abs .kimigraph (subagent)"          2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.kimigraph/x.db\"}}"
w "t65 abs .kirograph (subagent)"          2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.kirograph/x.db\"}}"
w "t66 win drive abs .kiro"                2 '{"agent_type":"coder","tool_input":{"file_path":"C:\\Users\\x\\proj\\.kiro\\x.json"}}'
w "t67 dotdot laundering to .kiro"         2 '{"agent_type":"coder","tool_input":{"file_path":".ai/../.kiro/evil.md"}}'

# --- MAIN THREAD -> same targets (Rule 2.5 must not be the only thing saving us) ---
w "t68 main-thread abs .kimi"              2 "{\"tool_input\":{\"file_path\":\"$P/.kimi/evil.md\"}}"
w "t69 main-thread abs backslash .kimi"    2 "{\"tool_input\":{\"file_path\":\"$(jbs "$PBS\\.kimi\\evil.md")\"}}"
w "t70 main-thread dotdot via .claude"     2 '{"tool_input":{"file_path":".claude/../.kimi/evil.md"}}'
w "t71 main-thread dotdot via .ai"         2 '{"tool_input":{"file_path":".ai/../.kiro/evil.md"}}'
w "t72 main-thread abs src (delegate)"     2 "{\"tool_input\":{\"file_path\":\"$P/src/main.rs\"}}"
w "t73 main-thread abs docs (delegate)"    2 "{\"tool_input\":{\"file_path\":\"$P/docs/x.md\"}}"

# --- sensitive-file rule, absolute forms (Rule 2) ---
w "t74 abs .env (subagent)"                2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.env\"}}"
w "t75 abs backslash server.key"           2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$PBS\\server.key")\"}}"
w "t76 abs id_rsa (subagent)"              2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/id_rsa\"}}"
w "t77 abs .KIMI uppercase (subagent)"     2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.KIMI/evil.md\"}}"

# --- root-file policy, absolute forms (Rule 3) ---
w "t78 abs root non-allowlisted"           2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/evil.txt\"}}"
w "t79 abs backslash root non-allowlisted" 2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$PBS\\evil.txt")\"}}"

# --- root-prefix BOUNDARY ---
w "t80 root-prefix boundary not under root" 2 "{\"tool_input\":{\"file_path\":\"$P.ai/evil.txt\"}}"

# --- fail-CLOSED on path shapes the canonicalizer cannot understand ---
w "t81 drive-relative C:foo blocked"       2 '{"agent_type":"coder","tool_input":{"file_path":"C:foo\\bar.txt"}}'
w "t82 bare drive C: blocked"              2 '{"agent_type":"coder","tool_input":{"file_path":"C:"}}'
w "t83 path == project root blocked"       2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P\"}}"

# --- must STILL be allowed: absolute paths that are genuinely legal (no over-blocking) ---
w "t84 abs src (subagent) allowed"         0 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/src/main.rs\"}}"
w "t85 abs backslash src (subagent)"       0 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$PBS\\src\\main.rs")\"}}"
w "t86 main-thread abs .ai allowed"        0 "{\"tool_input\":{\"file_path\":\"$P/.ai/research/x.md\"}}"
# t87 RETARGETED: .claude/hooks/ is now Rule-1.5 protected (see header). Use
# .claude/agents/ to preserve t87's original purpose (abs .claude relativize+allow).
w "t87 main-thread abs .claude/agents allowed" 0 "{\"tool_input\":{\"file_path\":\"$P/.claude/agents/x.md\"}}"
w "t88 main-thread abs .ai dot-segments"   0 "{\"tool_input\":{\"file_path\":\"$P/./.ai/./research/../research/x.md\"}}"

# --- drive-letter form UNDER the root: only constructible on a Windows-ish shell ---
if [ -n "$PWIN" ]; then
  w "t89 win drive abs src under root allowed" 0 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$PWIN/src/main.rs\"}}"
  w "t90 win drive abs .kimi under root blocked" 2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$PWIN/.kimi/evil.md\"}}"
else
  skip=$((skip+2))
  skips+=("t89/t90 drive-letter-form-under-root: cwd '$P' has no /<drive>/ prefix (non-Windows shell) — the Windows form of the project root cannot be constructed here. Their BLOCK-direction twins (t59/t60/t61/t66) run on every platform.")
fi

# --- Rule 2.6 worktree confinement must survive canonicalization (ADR-0004) ---
WT="$T/.wt/projA/kiro"
run_test_cd "t91 worktree abs in-tree write allowed"   "$WT" "$WE" "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$WT/src/x.ts\"}}" 0
run_test_cd "t92 worktree abs .kimi in-tree blocked"   "$WT" "$WE" "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$WT/.kimi/x.md\"}}" 2
run_test_cd "t93 worktree abs backslash escape blocked" "$WT" "$WE" "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$(jbs "$(bs "$T")\\projA\\src\\x.ts")\"}}" 2
run_test_cd "t94 worktree dotdot escape blocked"        "$WT" "$WE" '{"agent_type":"coder","tool_input":{"file_path":"../../../projA/src/x.ts"}}' 2
run_test_cd "t95 worktree junctioned .ai write allowed" "$WT" "$WE" '{"tool_input":{"file_path":".ai/handoffs/to-claude/open/x.md"}}' 0

# --- Rule 1.5 — enforcement-layer self-protection (NEW: bash-guard fix) ---
# .claude/hooks/ guard scripts are owner-apply-ONLY on the Write/Edit surface too
# (defense-in-depth with the harness; and covers any subagent Write/Edit the
# harness may not gate). The Bash surface's twin cases live in test-bash-guard.sh.
w "t96 subagent .claude/hooks blocked (rel)"   2 '{"agent_type":"coder","tool_input":{"file_path":".claude/hooks/evil.sh"}}'
w "t97 main-thread .claude/hooks blocked"      2 '{"tool_input":{"file_path":".claude/hooks/pretool-bash.sh"}}'
w "t98 subagent .claude/agents STILL allowed (only hooks blocked)" 0 '{"agent_type":"coder","tool_input":{"file_path":".claude/agents/x.md"}}'
w "t99 abs .claude/hooks blocked"              2 "{\"agent_type\":\"coder\",\"tool_input\":{\"file_path\":\"$P/.claude/hooks/x.sh\"}}"

rm -rf "$T"

we_total=$((pass+fail))
if [ "$skip" -gt 0 ]; then
  echo "SKIPPED: $skip"
  for s in "${skips[@]}"; do echo "  - $s"; done
fi
if [ $fail -eq 0 ]; then
  echo "write-edit suite: PASS $pass/$we_total"
else
  echo "write-edit suite: FAIL $fail/$we_total"
  for f in "${fails[@]}"; do echo "  - $f"; done
fi

# --- Delegate to the Bash side-door suite (shares the same classify_path). ---
echo "--- running test-bash-guard.sh ---"
if bash "$(dirname "$0")/test-bash-guard.sh"; then bg=0; else bg=1; fi

if [ $fail -eq 0 ] && [ $bg -eq 0 ]; then
  echo "ALL SUITES PASS"
  exit 0
else
  echo "SUITE FAILURES — see above"
  exit 1
fi
