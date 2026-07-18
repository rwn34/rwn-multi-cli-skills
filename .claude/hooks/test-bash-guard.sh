#!/bin/bash
# test-bash-guard.sh — focused suite for the Bash side-door closure.
# Installs to .claude/hooks/test-bash-guard.sh. Run from repo root:
#   bash .claude/hooks/test-bash-guard.sh
# Exit 0 if all pass, 1 otherwise.
#
# Covers: write-command target extraction (cp/mv/install/ln/dd/tee/sed -i),
# shell redirections, the fail-CLOSED boundary (eval/sh -c/xargs/$()/backtick/
# unbalanced quotes/ambiguous sed -i), false-positive guards, and the
# CROSS-HOOK DIVERGENCE GUARD (the two hooks must agree via one classify_path).
# The full #50 Write/Edit regression lives in test_hooks.sh; this file is the
# bash-side complement and can be run standalone for fast iteration.

WE=".claude/hooks/pretool-write-edit.sh"
BH=".claude/hooks/pretool-bash.sh"

pass=0; fail=0; fails=()

# run <name> <hook> <payload> <expected>
run() {
  local name="$1" hook="$2" payload="$3" expected="$4" actual
  actual=$(printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then pass=$((pass+1))
  else fail=$((fail+1)); fails+=("$name (expected $expected, got $actual)"); fi
}
# run_cd <name> <dir> <hook> <payload> <expected>  (cwd = $dir; e.g. a worktree)
run_cd() {
  local name="$1" dir="$2" hook="$3" payload="$4" expected="$5"
  local hook_abs="$PWD/$hook" actual
  actual=$(cd "$dir" && printf '%s' "$payload" | bash "$hook_abs" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then pass=$((pass+1))
  else fail=$((fail+1)); fails+=("$name (expected $expected, got $actual)"); fi
}

# Helper to build a subagent (coder) bash payload with an embedded command.
sc() { printf '{"agent_type":"coder","tool_input":{"command":"%s"}}' "$1"; }
mc() { printf '{"tool_input":{"command":"%s"}}' "$1"; }   # main-thread (no agent_type)

# ---------------------------------------------------------------------------
# 1. Write-command target extraction — territorial / sensitive / root blocks
# ---------------------------------------------------------------------------
run "b1 cp into .kimi/ blocked"            "$BH" "$(sc 'cp file.txt .kimi/evil.md')"          2
run "b2 cp into own tree allowed"          "$BH" "$(sc 'cp file.txt src/foo.txt')"            0
run "b3 mv into .kiro/ blocked"            "$BH" "$(sc 'mv a.txt .kiro/agents/evil.json')"    2
run "b4 install into .env blocked"         "$BH" "$(sc 'install -m 644 x .env')"              2
run "b5 ln into .claude/hooks/ blocked"    "$BH" "$(sc 'ln -s /tmp/x .claude/hooks/evil.sh')" 2
run "b6 dd of= into .ssh/ blocked"         "$BH" "$(sc 'dd if=/dev/zero of=.ssh/evil')"       2
run "b7 tee multi-target one bad blocked"  "$BH" "$(sc 'echo x | tee src/ok.txt .kimi/evil.md')" 2
run "b8 tee both-good allowed"             "$BH" "$(sc 'echo x | tee src/a.txt src/b.txt')"   0
run "b9 sed -i.bak (GNU attached) into src allowed" "$BH" "$(sc 'sed -i.bak s/x/y/ src/foo.txt')" 0
run "b10 cp into .claude/hooks/ blocked (side-door)" "$BH" "$(sc 'cp x .claude/hooks/pretool-bash.sh')" 2

# ---------------------------------------------------------------------------
# 2. Shell redirections (apply to ANY command head)
# ---------------------------------------------------------------------------
run "b11 redirect > into root non-allowlisted blocked" "$BH" "$(sc 'echo x > evil.txt')"      2
run "b12 redirect >> into .env blocked"    "$BH" "$(sc 'echo x >> .env')"                     2
run "b13 redirect > into allowlisted root allowed" "$BH" "$(sc 'echo x > CHANGELOG.md')"      0
run "b14 redirect > into .kimi/ blocked"   "$BH" "$(sc 'echo x > .kimi/evil')"                2
run "b15 redirect >| (noclobber) into .kiro blocked" "$BH" "$(sc 'echo x >| .kiro/evil')"     2
run "b16 redirect into own tree allowed"   "$BH" "$(sc 'echo x > src/note.txt')"              0
run "b17 fd-dup 2>&1 not a file (allowed)" "$BH" "$(sc 'ls foo 2>&1')"                         0

# ---------------------------------------------------------------------------
# 3. rm — territorial (narrow) via shared classifier; broad via Part A
# ---------------------------------------------------------------------------
run "b18 rm narrow inside .kimi/ blocked"  "$BH" "$(sc 'rm -f .kimi/agents/evil.json')"       2
run "b19 rm broad / still caught (Part A)" "$BH" "$(sc 'rm -rf /')"                            2
run "b20 rm inside own tree allowed"       "$BH" "$(sc 'rm -f src/tmp.txt')"                  0

# ---------------------------------------------------------------------------
# 4. sed -i GNU/BSD ambiguity — fail closed
# ---------------------------------------------------------------------------
run "b21 sed -i bare detached-suffix blocked" "$BH" "$(sc 'sed -i .bak src/foo.txt')"          2
run "b22 sed -i (bare, GNU no-backup) ambiguous blocked" "$BH" "$(sc 'sed -i s/x/y/ src/f.txt')" 2
run "b23 sed WITHOUT -i writes stdout (allowed)" "$BH" "$(sc 'sed s/x/y/ src/foo.txt')"        0
run "b24 sed -i into .env blocked"         "$BH" "$(sc 'sed -i.bak s/x/y/ .env')"             2

# ---------------------------------------------------------------------------
# 5. Fail-CLOSED boundary (§2.3) — the load-bearing set
# ---------------------------------------------------------------------------
run "b25 command substitution in target blocked" "$BH" "$(sc 'cp file.txt \"$(echo .kimi)/x\"')" 2
run "b26 backtick substitution in target blocked" "$BH" "$(sc 'cp file.txt \`echo .kimi\`/x')"   2
run "b27 bare var target blocked"          "$BH" "$(sc 'cp file.txt \"$DEST\"')"              2
run "b28 eval wrapper blocked outright"    "$BH" "$(sc 'eval \"cp file.txt .kimi/evil.md\"')" 2
run "b29 sh -c wrapper blocked outright"   "$BH" "$(sc 'sh -c \"cp file.txt .kimi/evil.md\"')" 2
run "b30 bash -c wrapper blocked outright" "$BH" "$(sc 'bash -c \"cp file.txt .kimi/evil.md\"')" 2
run "b31 xargs write-capable blocked"      "$BH" "$(sc 'echo .kimi/evil.md | xargs cp file.txt')" 2
run "b32 unbalanced quote blocked"         "$BH" "$(sc 'cp file.txt \".kimi/evil')"           2
run "b33 compound &&: 2nd stmt violation"  "$BH" "$(sc 'cd /tmp && cp file.txt .kimi/evil.md')" 2
run "b34 compound pipe: tee violation"     "$BH" "$(sc 'cat file.txt | tee .kimi/evil.md')"   2
run "b35 tee with no file operand blocked" "$BH" "$(sc 'echo x | tee')"                       2
run "b36 cp -t target-directory blocked"   "$BH" "$(sc 'cp -t .kimi src/a.txt')"              2
# newline-separated compound (2nd statement is the violation)
run "b37 compound newline: 2nd stmt violation" "$BH" '{"agent_type":"coder","tool_input":{"command":"cd /tmp\ncp file.txt .kimi/evil.md"}}' 2

# ---------------------------------------------------------------------------
# 6. Explicitly-documented ALLOW: sensitive SOURCE, safe dest (§2.4 read-gap)
# ---------------------------------------------------------------------------
run "b38 cp sensitive SOURCE non-sensitive dest ALLOWED (documented gap)" "$BH" "$(sc 'cp .env src/x')" 0

# ---------------------------------------------------------------------------
# 7. False-positive guards (§3.4) — must NOT over-block
# ---------------------------------------------------------------------------
run "b39 cpanm untouched (not cp)"         "$BH" "$(sc 'cpanm Some::Module')"                 0
run "b40 movement.sh untouched (not mv)"   "$BH" "$(sc 'bash movement.sh')"                   0
run "b41 install-template.sh untouched"    "$BH" "$(sc 'bash scripts/install-template.sh .')" 0
run "b42 sedgwick untouched (not sed)"     "$BH" "$(sc 'echo sedgwick')"                      0
run "b43 grep -i untouched (not sed -i)"   "$BH" "$(sc 'grep -i pattern src/file.txt')"       0
run "b44 git status untouched"             "$BH" "$(sc 'git status')"                         0
run "b45 sudo cp still classified (prefix stripped)" "$BH" "$(sc 'sudo cp x .kimi/e')"        2
run "b46 env VAR=val cp still classified"  "$BH" "$(sc 'FOO=bar cp x .kimi/e')"               2
run "b46a echo \$VAR into own tree allowed (redirect target static)" "$BH" "$(sc 'echo \"$VAR\" > src/out.txt')" 0
run "b46b redirect into a \$-var target blocked (dynamic target)"    "$BH" "$(sc 'echo x > $DEST')"  2

# ---------------------------------------------------------------------------
# 8. Redirect / cp ESCAPE from an executor worktree (ADR-0004 Rule 2.6)
# ---------------------------------------------------------------------------
T=$(mktemp -d); WT="$T/.wt/projA/kiro"; mkdir -p "$WT/src"
run_cd "b47 redirect escape ../other-cli/ blocked (worktree)" "$WT" "$BH" "$(sc 'echo x > ../other-cli/z')" 2
run_cd "b48 redirect in-tree allowed (worktree)"              "$WT" "$BH" "$(sc 'echo x > src/z.txt')"       0
run_cd "b49 cp escape ../ blocked (worktree)"                 "$WT" "$BH" "$(sc 'cp a ../evil/z')"           2
rm -rf "$T"

# ---------------------------------------------------------------------------
# 9. CROSS-HOOK DIVERGENCE GUARD (requirement #4)
# ---------------------------------------------------------------------------
# For a shared fixture set, the Write/Edit surface (file_path=P) and the Bash
# surface (cp SRC P -> target=P) MUST return the SAME verdict, because both route
# through the ONE classify_path. If a future edit re-implements policy in either
# hook, these diverge and the suite fails LOUDLY — that is the whole point.
div=0; divfail=0
check_parity() {
  local label="$1" agent="$2" path="$3" wpay bpay we bh
  if [ "$agent" = "main" ]; then
    wpay=$(printf '{"tool_input":{"file_path":"%s"}}' "$path")
    bpay=$(printf '{"tool_input":{"command":"cp SRC %s"}}' "$path")
  else
    wpay=$(printf '{"agent_type":"coder","tool_input":{"file_path":"%s"}}' "$path")
    bpay=$(printf '{"agent_type":"coder","tool_input":{"command":"cp SRC %s"}}' "$path")
  fi
  we=$(printf '%s' "$wpay" | bash "$WE" >/dev/null 2>&1; echo $?)
  bh=$(printf '%s' "$bpay" | bash "$BH" >/dev/null 2>&1; echo $?)
  div=$((div+1))
  if [ "$we" = "$bh" ]; then pass=$((pass+1))
  else fail=$((fail+1)); divfail=$((divfail+1)); fails+=("DIVERGENCE $label [$agent $path]: write-edit=$we bash=$bh — the two surfaces disagree on policy!"); fi
}
# subagent context (isolates territorial/sensitive/root from Rule 2.5)
check_parity "kimi"          coder ".kimi/x"
check_parity "kiro"          coder ".kiro/x"
check_parity "claude-hooks"  coder ".claude/hooks/x"
check_parity "env"           coder ".env"
check_parity "serverkey"     coder "server.key"
check_parity "ssh"           coder ".ssh/x"
check_parity "src"           coder "src/x.ts"
check_parity "docs"          coder "docs/x.md"
check_parity "changelog"     coder "CHANGELOG.md"
check_parity "root-evil"     coder "evil.txt"
check_parity "ai"            coder ".ai/x.md"
check_parity "claude-agents" coder ".claude/agents/x.md"
# main-thread context (Rule 2.5 delegation must match on both surfaces too)
check_parity "main-src"      main  "src/x.ts"
check_parity "main-ai"       main  ".ai/x.md"
check_parity "main-docs"     main  "docs/x.md"

total=$((pass+fail))
echo "divergence-guard parity checks: $div (mismatches: $divfail)"
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
