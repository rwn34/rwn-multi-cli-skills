#!/bin/bash
# test_hooks.sh — regression suite for .kimi/hooks/*
# Exits 0 if all pass, 1 if any fail.
#
# Hermeticity (2026-07-12, handoff 202607120059): hook paths are resolved from
# THIS script's location, not from cwd, so the suite tests its own hooks no
# matter where it is invoked from. Fixtures that need a specific session cwd
# (fleet whitelist, worktree confinement) pin it via run_test_cd — under the
# ADR-0004 amendment dispatched CLIs RUN in worktrees, so a suite that only
# passes from the primary checkout is certifying the wrong environment.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass=0
fail=0
fails=()

run_test() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  local actual
  actual=$(printf '%s' "$payload" | bash "$hook" > /dev/null 2>&1; echo $?)
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
  local actual
  actual=$(cd "$dir" && printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
  fi
}

# Windows-absolute shapes (C:\..., C:/...) only exist when the session root
# is an MSYS drive path (/c/...). On Linux CI the runtime never emits them
# and they have no lexical Windows twin, so those fixtures are SKIPPED there
# (counted separately — never faked as passes). WIN_SHAPES is set below,
# right after SESSION_ROOT is derived.
skip=0
run_test_win() {
  if [ "$WIN_SHAPES" = 1 ]; then run_test "$@"; else skip=$((skip+1)); fi
}
run_test_cd_win() {
  if [ "$WIN_SHAPES" = 1 ]; then run_test_cd "$@"; else skip=$((skip+1)); fi
}

# --- path-shape fixtures ---------------------------------------------------
# The runtime emits Windows-ABSOLUTE paths; the suite must feed every
# territorial rule in every shape the runtime can produce (relative,
# Windows-abs backslash, Windows-abs forward-slash, MSYS /c/..., mixed
# separators, case-variant drive, . / .. segments). Fixtures are rooted at
# the SESSION root ($PWD — what the guards compare against), NOT the script's
# location, so the suite passes both from the primary checkout and from an
# executor worktree. $PWD must be a real /c/... path so its Windows forms
# are lexically equivalent (unlike MSYS pseudo-paths such as /tmp, which
# have no lexical Windows twin).
SESSION_ROOT="$(pwd | tr '\\' '/')"
WIN_SHAPES=0
case "$SESSION_ROOT" in /[A-Za-z]/*) WIN_SHAPES=1 ;; esac
ROOT_POSIX="$SESSION_ROOT"                       # /c/Users/.../<repo-or-worktree>
_drive="${ROOT_POSIX:1:1}"
ROOT_WIN_FWD="${_drive^^}:${ROOT_POSIX:2}"       # C:/Users/.../<root>
ROOT_WIN_LOW="${_drive,,}:${ROOT_POSIX:2}"       # c:/Users/.../<root>
ROOT_WIN_BSL=$(printf '%s' "$ROOT_WIN_FWD" | tr '/' '\\')   # C:\Users\...\<root>
json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }

# --- root-guard ---
run_test "t1-root-blocks-evil"     "$HOOK_DIR/root-guard.sh"     '{"tool_input":{"file_path":"evil.txt"}}'          2
run_test "t2-root-allows-gitignore" "$HOOK_DIR/root-guard.sh"    '{"tool_input":{"file_path":".gitignore"}}'        0
run_test "t3-root-allows-src"      "$HOOK_DIR/root-guard.sh"     '{"tool_input":{"file_path":"src/main.rs"}}'       0

# --- framework-guard ---
run_test "t4-fw-allows-ai"         "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".ai/handoffs/test.md"}}'  0
run_test "t5-fw-blocks-claude"     "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".claude/agents/test.md"}}' 2
run_test "t6-fw-blocks-kiro"       "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".kiro/agents/test.json"}}' 2
run_test "t27-fw-blocks-kimigraph" "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".kimigraph/config.json"}}' 2
run_test "t28-fw-blocks-codegraph" "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".codegraph/codegraph.db"}}' 2
run_test "t29-fw-blocks-kirograph" "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".kirograph/kirograph.db"}}' 2

# --- framework-guard: absolute/laundered path shapes (handoff 202607120059) ---
run_test "t60-fw-blocks-abs-msys-claude"   "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_POSIX/.claude/agents/x.md\"}}" 2
run_test_win "t61-fw-blocks-abs-winfwd-claude" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/.claude/agents/x.md\"}}" 2
run_test_win "t62-fw-blocks-abs-winbsl-claude" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$ROOT_WIN_BSL\\.claude\\agents\\x.md")\"}}" 2
run_test_win "t63-fw-blocks-abs-lowdrive-kiro" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_LOW/.kiro/x.json\"}}" 2
run_test_win "t64-fw-blocks-abs-mixedsep-claude" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$ROOT_WIN_FWD\\.claude/agents\\x.md")\"}}" 2
run_test "t65-fw-blocks-dotdot-laundering" "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":".kimi/../.claude/x.md"}}' 2
run_test "t66-fw-blocks-abs-dotdot"        "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_POSIX/x/../.claude/x.md\"}}" 2
run_test "t67-fw-blocks-dot-segments"      "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_POSIX/./.claude/x.md\"}}" 2
run_test_win "t68-fw-blocks-abs-winfwd-codegraph" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/.codegraph/codegraph.db\"}}" 2
run_test_win "t69-fw-blocks-abs-winfwd-kimigraph" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/.kimigraph/config.json\"}}" 2
run_test_win "t70-fw-blocks-abs-winfwd-kirograph" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/.kirograph/kirograph.db\"}}" 2
run_test_win "t71-fw-allows-abs-winbsl-ai"     "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$ROOT_WIN_BSL\\.ai\\handoffs\\x.md")\"}}" 0
run_test_win "t72-fw-allows-abs-winfwd-kimi"   "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/.kimi/hooks/x.sh\"}}" 0
run_test "t73-fw-allows-outside-root-boundary" "$HOOK_DIR/framework-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_POSIX-evil/.claude/x.md\"}}" 0
run_test "t74-fw-failclosed-bare-drive"    "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":"C:"}}' 2
run_test "t75-fw-failclosed-drive-relative" "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"file_path":"C:foo\bar"}}' 2

# --- sensitive-guard ---
run_test "t7-sens-blocks-env"      "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":".env"}}'              2
run_test "t8-sens-blocks-id_rsa"   "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":"id_rsa"}}'           2
run_test "t9-sens-blocks-id_ed25519" "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":"id_ed25519"}}'     2
run_test "t10-sens-blocks-key"     "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":"server.key"}}'       2
run_test "t11-sens-blocks-pem"     "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":"cert.pem"}}'         2
run_test "t17-sens-blocks-secrets-yaml" "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":"secrets.yaml"}}'     2
run_test "t18-sens-blocks-credentials-json" "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"file_path":"credentials.json"}}' 2

# --- destructive-guard ---
run_test "t12-dest-blocks-rmrf"    "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'          2
run_test "t13-dest-blocks-drop"    "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"DROP DATABASE foo"}}'  2
run_test "t14-dest-blocks-mixed"   "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"Drop Database foo"}}' 2
run_test "t15-dest-allows-gitstatus" "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"git status"}}'     0
run_test "t19-dest-blocks-rmrf-root"    "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'          2
run_test "t20-dest-allows-rmrf-tmp"     "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /tmp/foo"}}'    0
run_test "t21-dest-blocks-rmrf-trailsp" "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf / "}}'         2
run_test "t22-dest-blocks-rmrf-semi"    "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /;echo ok"}}'  2
run_test "t23-dest-allows-rmrf-usr"     "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf /usr"}}'       0
run_test "t24-dest-allows-rmrf-homefoo" "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf ~/foo"}}'      0
run_test "t25-dest-allows-rmrf-glob"    "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf *.log"}}'      0
run_test "t26-dest-allows-rmrf-dotbuild" "$HOOK_DIR/destructive-guard.sh" '{"tool_input":{"command":"rm -rf ./build"}}'   0

# --- stdin-drain regression (F-4) ---
run_test "t16-empty-stdin"         "$HOOK_DIR/root-guard.sh"      ""                                                     0

# --- real tool-name payload regression (Write/Edit use 'path', not 'file_path') ---
run_test "t39-root-blocks-evil-path"     "$HOOK_DIR/root-guard.sh"      '{"tool_input":{"path":"evil.txt"}}'                2
run_test "t40-root-allows-src-path"      "$HOOK_DIR/root-guard.sh"      '{"tool_input":{"path":"src/main.rs"}}'             0
run_test "t41-fw-blocks-claude-path"     "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"path":".claude/agents/test.md"}}'  2
run_test "t42-fw-blocks-kiro-path"       "$HOOK_DIR/framework-guard.sh" '{"tool_input":{"path":".kiro/agents/test.json"}}'  2
run_test "t43-sens-blocks-env-path"      "$HOOK_DIR/sensitive-guard.sh" '{"tool_input":{"path":".env"}}'                    2

# --- root-guard: absolute/laundered path shapes (handoff 202607120059) ---
run_test "t80-root-blocks-abs-msys-evil"   "$HOOK_DIR/root-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_POSIX/evil.txt\"}}" 2
run_test_win "t81-root-blocks-abs-winfwd-evil" "$HOOK_DIR/root-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/evil.txt\"}}" 2
run_test_win "t82-root-blocks-abs-winbsl-evil" "$HOOK_DIR/root-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$ROOT_WIN_BSL\\evil.txt")\"}}" 2
run_test_win "t83-root-allows-abs-winfwd-readme" "$HOOK_DIR/root-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/README.md\"}}" 0
run_test_win "t84-root-allows-abs-winbsl-gitignore" "$HOOK_DIR/root-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$ROOT_WIN_BSL\\.gitignore")\"}}" 0
run_test_win "t85-root-allows-abs-winfwd-src"  "$HOOK_DIR/root-guard.sh" "{\"tool_input\":{\"file_path\":\"$ROOT_WIN_FWD/src/main.rs\"}}" 0
run_test "t86-root-blocks-dotdot-laundering" "$HOOK_DIR/root-guard.sh" '{"tool_input":{"file_path":"src/../evil.txt"}}' 2
run_test "t87-root-failclosed-bare-drive"  "$HOOK_DIR/root-guard.sh" '{"tool_input":{"file_path":"C:"}}' 2
run_test "t88-root-failclosed-drive-relative" "$HOOK_DIR/root-guard.sh" '{"tool_input":{"file_path":"C:foo\bar"}}' 2

# --- matcher regression: canonical snippet must use real tool names ---
if grep -qE 'matcher[[:space:]]*=[[:space:]]*"WriteFile\|StrReplaceFile"' "$SESSION_ROOT/.ai/config-snippets/kimi-hooks.toml"; then
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
if grep -qE 'matcher[[:space:]]*=[[:space:]]*"Shell"' "$SESSION_ROOT/.ai/config-snippets/kimi-hooks.toml"; then
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
if grep -qE '~/.kimi/config.toml(?!-code)' "$SESSION_ROOT/.ai/config-snippets/kimi-hooks.toml"; then
    fail=$((fail+1))
    fails+=("t48-snippet-points-to-active-config (expected ~/.kimi-code/config.toml, found ~/.kimi/config.toml)")
else
    pass=$((pass+1))
fi

# --- worktree-fleet-guard: ADR-0004 worktree confinement + fleet whitelist ---
T=$(mktemp -d)
# fleet fixture 1: registry whitelists the PINNED cwd's project -> proj-b only.
# cwd is pinned to the fixture dir (hermeticity fix 2026-07-12): with the
# ADR-0004 amendment the suite itself often runs from a worktree, where
# confinement would legitimately block these absolute fixture paths before
# the fleet rule ever runs (old t32/t35 failure from a worktree cwd).
mkdir -p "$T/f1/.fleet/handoffs/to-proj-b/open" "$T/f1/.fleet/handoffs/to-proj-c/open" "$T/f1/.fleet/activity"
printf '{"projects":{"f1":{"path":"x","talks_to":["proj-b"]}}}' > "$T/f1/.fleet/registry.json"
# fleet fixture 2: no registry at all
mkdir -p "$T/f2/.fleet/handoffs/to-proj-b/open"
# worktree fixture: simulated executor worktree at .wt/projA/kimi
mkdir -p "$T/.wt/projA/kimi/src"

run_test_cd "t32-fleet-whitelisted-allowed"  "$T/f1" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-b/open/x.md\"}}" 0
run_test_cd "t33-fleet-nonwhitelisted-blocked" "$T/f1" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/handoffs/to-proj-c/open/x.md\"}}" 2
run_test_cd "t34-fleet-noregistry-blocked"   "$T/f2" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f2/.fleet/handoffs/to-proj-b/open/x.md\"}}" 2
run_test_cd "t35-fleet-activity-allowed"     "$T/f1" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/f1/.fleet/activity/log.md\"}}" 0
run_test_cd "t36-worktree-absolute-escape-blocked" "$T/.wt/projA/kimi" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$T/projA/src/x.ts\"}}" 2
run_test_cd "t37-worktree-dotdot-escape-blocked"   "$T/.wt/projA/kimi" "$HOOK_DIR/worktree-fleet-guard.sh" '{"tool_input":{"file_path":"../kimi/src/x.ts"}}' 2
run_test_cd "t38-worktree-in-tree-allowed"         "$T/.wt/projA/kimi" "$HOOK_DIR/worktree-fleet-guard.sh" '{"tool_input":{"file_path":"src/x.ts"}}' 0

rm -rf "$T"

# --- worktree-fleet-guard: Windows/absolute path shapes (handoff 202607120059) ---
# A fake executor worktree under the repo (gitignored .scratch/) — a real
# /c/... path so its Windows forms are lexically equivalent and the guard's
# canonicalizer can be exercised end to end.
WT_FIX="$SESSION_ROOT/.scratch/wt-fixture"
rm -rf "$WT_FIX"
mkdir -p "$WT_FIX/.wt/projA/kimi/src" "$WT_FIX/.wt/projA/kimi-evil" "$WT_FIX/projA/src"
WT_POSIX="$WT_FIX/.wt/projA/kimi"
WT_WIN_FWD="${_drive^^}:${WT_POSIX:2}"
WT_WIN_LOW="${_drive,,}:${WT_POSIX:2}"
WT_WIN_BSL=$(printf '%s' "$WT_WIN_FWD" | tr '/' '\\')
ESC_WIN_FWD="${_drive^^}:${WT_FIX:2}/projA/src/x.ts"
ESC_WIN_BSL=$(printf '%s' "$ESC_WIN_FWD" | tr '/' '\\')

run_test_cd "t90-wt-abs-msys-in-tree-allowed"     "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$WT_POSIX/src/x.ts\"}}" 0
run_test_cd_win "t91-wt-abs-winfwd-in-tree-allowed"   "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$WT_WIN_FWD/src/x.ts\"}}" 0
run_test_cd_win "t92-wt-abs-winbsl-in-tree-allowed"   "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$WT_WIN_BSL\\src\\x.ts")\"}}" 0
run_test_cd_win "t93-wt-abs-winfwd-escape-blocked"    "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$ESC_WIN_FWD\"}}" 2
run_test_cd_win "t94-wt-abs-winbsl-escape-blocked"    "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$(json_esc "$ESC_WIN_BSL")\"}}" 2
run_test_cd "t95-wt-sibling-prefix-escape-blocked" "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$WT_POSIX-evil/x.ts\"}}" 2
run_test_cd_win "t96-wt-sibling-prefix-winfwd-blocked" "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$WT_WIN_FWD-evil/x.ts\"}}" 2
run_test_cd_win "t97-wt-abs-lowdrive-in-tree-allowed" "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" "{\"tool_input\":{\"file_path\":\"$WT_WIN_LOW/src/x.ts\"}}" 0
run_test_cd "t98-wt-failclosed-bare-drive"        "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" '{"tool_input":{"file_path":"C:"}}' 2
run_test_cd "t99-wt-failclosed-drive-relative"    "$WT_POSIX" "$HOOK_DIR/worktree-fleet-guard.sh" '{"tool_input":{"file_path":"C:foo\bar"}}' 2

rm -rf "$WT_FIX"

# --- handoffs-remind.sh: lists only qualifying (Auto:yes + Status:OPEN + Risk A|B) ---
T=$(mktemp -d)
mkdir -p "$T/open"
cat > "$T/open/202607101900-qualifying.md" <<'EOF'
# qualifying
Status: OPEN
Auto: yes
Risk: B
EOF
cat > "$T/open/202607101901-riskc.md" <<'EOF'
# risk c
Status: OPEN
Auto: yes
Risk: C
EOF
cat > "$T/open/202607101902-autono.md" <<'EOF'
# auto no
Status: OPEN
Auto: no
Risk: B
EOF
out=$(HANDOFFS_DIR="$T/open" bash "$HOOK_DIR/handoffs-remind.sh" 2>/dev/null)
if echo "$out" | grep -q '202607101900-qualifying.md' \
   && ! echo "$out" | grep -q '202607101901-riskc.md' \
   && ! echo "$out" | grep -q '202607101902-autono.md' \
   && echo "$out" | grep -q -- '--exec --only kimi'; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t49-handoffs-remind-filters-qualifying")
fi

# --- handoffs-remind.sh: recursion guard no-ops under AI_HANDOFF_DISPATCH ---
out_guard=$(AI_HANDOFF_DISPATCH=1 HANDOFFS_DIR="$T/open" bash "$HOOK_DIR/handoffs-remind.sh" 2>/dev/null)
if [ -z "$out_guard" ]; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t50-handoffs-remind-recursion-guard")
fi

# --- handoff-queue-count.sh: per-queue counts across to-*/open ---
mkdir -p "$T/root/to-kimi/open" "$T/root/to-kiro/open" "$T/root/to-claude/open"
: > "$T/root/to-kimi/open/a.md"
: > "$T/root/to-kiro/open/b.md"
: > "$T/root/to-kiro/open/c.md"
out_q=$(HANDOFFS_ROOT="$T/root" bash "$HOOK_DIR/handoff-queue-count.sh" 2>/dev/null)
if echo "$out_q" | grep -q 'to-kimi: 1 open' \
   && echo "$out_q" | grep -q 'to-kiro: 2 open' \
   && ! echo "$out_q" | grep -q 'to-claude'; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t51-queue-count-per-queue")
fi

rm -rf "$T"

# --- dispatch-own-queue.sh: recursion guard no-ops under AI_HANDOFF_DISPATCH ---
T2=$(mktemp -d)
mkdir -p "$T2/open"
cat > "$T2/open/202001010000-qualifying.md" <<'EOF'
# qualifying
Status: OPEN
Auto: yes
Risk: B
EOF
out_recur=$(AI_HANDOFF_DISPATCH=1 HANDOFFS_DIR="$T2/open" DISPATCH_STAMP="$T2/stamp" bash "$HOOK_DIR/dispatch-own-queue.sh" 2>/dev/null)
if [ -z "$out_recur" ]; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t52-dispatch-own-queue-recursion-guard")
fi

# --- dispatch-own-queue.sh: empty queue fast-exits (no output) ---
mkdir -p "$T2/empty"
out_empty=$(HANDOFFS_DIR="$T2/empty" DISPATCH_STAMP="$T2/stamp2" bash "$HOOK_DIR/dispatch-own-queue.sh" 2>/dev/null)
if [ -z "$out_empty" ]; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t53-dispatch-own-queue-empty-fast-exit")
fi

# --- dispatch-own-queue.sh: candidate -> would-dispatch (DRY_RUN, offline) ---
out_cand=$(DRY_RUN=1 HANDOFFS_DIR="$T2/open" DISPATCH_STAMP="$T2/stamp3" bash "$HOOK_DIR/dispatch-own-queue.sh" 2>/dev/null)
if echo "$out_cand" | grep -q 'auto-dispatchable to-kimi handoff found' \
   && echo "$out_cand" | grep -q -- '--exec --only kimi' \
   && echo "$out_cand" | grep -q '202001010000-qualifying.md'; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t54-dispatch-own-queue-candidate-would-dispatch")
fi

# --- dispatch-own-queue.sh: debounce on 2nd run within 5 min ---
DRY_RUN=1 HANDOFFS_DIR="$T2/open" DISPATCH_STAMP="$T2/stamp4" bash "$HOOK_DIR/dispatch-own-queue.sh" >/dev/null 2>&1
out_deb=$(DRY_RUN=1 HANDOFFS_DIR="$T2/open" DISPATCH_STAMP="$T2/stamp4" bash "$HOOK_DIR/dispatch-own-queue.sh" 2>/dev/null)
if echo "$out_deb" | grep -q 'debounced'; then
    pass=$((pass+1))
else
    fail=$((fail+1))
    fails+=("t55-dispatch-own-queue-debounce")
fi

rm -rf "$T2"

total=$((pass+fail))
if [ $fail -eq 0 ]; then
  if [ "$skip" -gt 0 ]; then
    echo "PASS: $pass/$total ($skip Windows-shape fixtures skipped — non-MSYS session root, shapes not emittable by this runtime)"
  else
    echo "PASS: $pass/$total"
  fi
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
