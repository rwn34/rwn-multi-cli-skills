#!/usr/bin/env bash
# =============================================================================
# Unit tests for scripts/git-hooks/pre-commit decision logic (ADR-0005).
# Standalone — no vitest. Sources the hook as a library (PRECOMMIT_LIB=1) and
# exercises the pure decision functions directly. Run: bash test-pre-commit.sh
# =============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# Point the SSOT-replica lookup at the repo's real registry (HERE = scripts/git-hooks).
SYNC_MD="$(cd "$HERE/../.." && pwd)/.ai/sync.md"
export SYNC_MD
# shellcheck source=/dev/null
PRECOMMIT_LIB=1 . "$HERE/pre-commit"

pass=0
fail=0

# assert_block <desc> <fn> [args...]  — expects the function to return 0 (block).
assert_block() {
    desc="$1"; shift
    if "$@"; then
        pass=$((pass + 1)); printf 'PASS  block  %s\n' "$desc"
    else
        fail=$((fail + 1)); printf 'FAIL  block  %s (expected block, got allow)\n' "$desc"
    fi
}

# assert_allow <desc> <fn> [args...] — expects the function to return non-0 (allow).
assert_allow() {
    desc="$1"; shift
    if "$@"; then
        fail=$((fail + 1)); printf 'FAIL  allow  %s (expected allow, got block)\n' "$desc"
    else
        pass=$((pass + 1)); printf 'PASS  allow  %s\n' "$desc"
    fi
}

echo "== sensitive files =="
assert_block "root .env"                 _is_sensitive ".env"
assert_block ".env.production"           _is_sensitive ".env.production"
assert_block "nested config/db.key"      _is_sensitive "config/db.key"
assert_block "server.pem"                _is_sensitive "certs/server.pem"
assert_block "id_rsa"                    _is_sensitive "deploy/id_rsa"
assert_block "id_ed25519.pub"            _is_sensitive "id_ed25519.pub"
assert_block ".aws/credentials"          _is_sensitive ".aws/credentials"
assert_block "secrets.json"              _is_sensitive "secrets.json"
assert_block "credentials file"          _is_sensitive "app/credentials"
assert_allow "normal source not secret"  _is_sensitive "src/main.ts"
assert_allow "keyboard.ts not a key"     _is_sensitive "src/keyboard.ts"

echo "== removed-graph tombstones =="
assert_block ".kirograph db"             _is_tombstone ".kirograph/graph.db"
assert_block ".kimigraph db"             _is_tombstone ".kimigraph/index.sqlite"
assert_allow ".codegraph is live"        _is_tombstone ".codegraph/config.json"

echo "== root-file policy (new files) =="
assert_block "new random root file"      _root_new_violation "random.txt"
assert_block "new root notes.md"         _root_new_violation "notes.md"
assert_allow "README.md allowlisted"     _root_new_violation "README.md"
assert_allow "opencode.json allowlisted" _root_new_violation "opencode.json"
assert_allow "nested docs not root"      _root_new_violation "docs/notes.md"
assert_allow "LICENSE.txt allowlisted"   _root_new_violation "LICENSE.txt"

echo "== cross-CLI territory =="
assert_block "opencode commits source"   _territory_violation opencode "src/main.ts"
assert_block "opencode commits .claude"  _territory_violation opencode ".claude/x.md"
assert_allow "opencode -> .ai/reports"   _territory_violation opencode ".ai/reports/r.md"
assert_allow "opencode -> activity log"  _territory_violation opencode ".ai/activity/log.md"
assert_block "kimi commits .claude"      _territory_violation kimi-cli ".claude/agents/x.md"
assert_block "kimi commits .opencode"    _territory_violation kimi-cli ".opencode/agent.md"
assert_block "kiro commits .kimi"        _territory_violation kiro-cli ".kimi/steering/x.md"
assert_block "claude commits .kimi"      _territory_violation claude-code ".kimi/hooks/x.sh"
assert_block "claude commits .kiro"      _territory_violation claude-code ".kiro/steering/x.md"
assert_allow "claude -> .ai"             _territory_violation claude-code ".ai/activity/log.md"
assert_allow "claude -> source"          _territory_violation claude-code "src/main.ts"
assert_allow "claude -> .claude"         _territory_violation claude-code ".claude/agents/coder.md"
assert_allow "kimi -> .kimi"             _territory_violation kimi-cli ".kimi/steering/x.md"
assert_allow "kimi -> source"            _territory_violation kimi-cli "backend/main.rs"

echo "== OpenCode lane: activity-log entry spool (ADR-0010 blocker, 2026-07-12) =="
# The commit-time half of the guard's WRITABLE_LANE. If these two disagree, OpenCode
# can write an entry and then have the commit rejected — silently, with no error a
# human sees. Keep in lockstep with .opencode/plugin/framework-guard.js.
#
# ALLOW: the spool.
assert_allow "opencode -> spool entry"     _territory_violation opencode ".ai/activity/entries/20260712T101500Z-opencode-x-a1b2.md"
assert_allow "opencode -> spool nested"    _territory_violation opencode ".ai/activity/entries/2026-07/x.md"
# NO REGRESSION: the old path is still the live log and must still commit.
assert_allow "opencode -> log.md (no regression)" _territory_violation opencode ".ai/activity/log.md"
# ALLOW: .github/* — the commit-time half of the repo-ops lane the guard granted
# in PR #45. The contract assigns OpenCode "CI config/workflow fixes" and "opening
# PRs"; without this it could WRITE the workflow fix and then be REJECTED at commit.
assert_allow "opencode -> .github workflow" _territory_violation opencode ".github/workflows/gates.yml"
assert_allow "opencode -> .github nested"   _territory_violation opencode ".github/actions/setup/action.yml"
#
# DENY: the widening is ONE subtree, not `.ai/activity`, and not `.ai/`.
assert_block "opencode -> activity sibling"  _territory_violation opencode ".ai/activity/other.md"
assert_block "opencode -> activity archive"  _territory_violation opencode ".ai/activity/archive/2026-04.md"
assert_block "opencode -> near-miss entriesfoo" _territory_violation opencode ".ai/activity/entriesfoo/x.md"
assert_block "opencode -> bare 'entries'"    _territory_violation opencode ".ai/activity/entries"
assert_block "opencode -> .ai/instructions"  _territory_violation opencode ".ai/instructions/operating-prompt/principles.md"
assert_block "opencode -> .ai/sync.md"       _territory_violation opencode ".ai/sync.md"
assert_block "opencode -> .ai root file"     _territory_violation opencode ".ai/known-limitations.md"
# DENY: the widening must not leak into source or any other CLI's territory.
assert_block "opencode -> src (post-widen)"  _territory_violation opencode "src/index.js"
assert_block "opencode -> scripts/"          _territory_violation opencode "scripts/git-hooks/pre-commit"
assert_block "opencode -> .claude (post-widen)" _territory_violation opencode ".claude/hooks/stop-reminder.sh"
assert_block "opencode -> .kimi"             _territory_violation opencode ".kimi/steering/00-ai-contract.md"
assert_block "opencode -> .kiro"             _territory_violation opencode ".kiro/agents/coder.json"
assert_block "opencode -> .opencode (own)"   _territory_violation opencode ".opencode/plugin/framework-guard.js"
assert_block "opencode -> docs/architecture" _territory_violation opencode "docs/architecture/0010-x.md"
assert_block "opencode -> CLAUDE.md"         _territory_violation opencode "CLAUDE.md"
# Secrets are caught by _is_sensitive (pass 1 runs it BEFORE the territory rule), so
# the lane never licenses one even inside the spool. Assert the composition, not just
# the parts — a lane entry that allowed a key would be the worst kind of leak.
assert_block "secret inside the spool"       _is_sensitive ".ai/activity/entries/id_rsa"
assert_block ".env inside the spool"         _is_sensitive ".ai/activity/entries/.env.prod"
assert_block "key inside .github/"           _is_sensitive ".github/deploy.key"
# Absolute / MSYS forms FAIL-CLOSED (blocked). git diff --cached only ever emits
# repo-relative POSIX paths, so the hook body never sees these — asserted so that a
# future refactor cannot turn an absolute path into a lane bypass.
assert_block "opencode -> absolute spool (fail-closed)" _territory_violation opencode "/c/proj/.ai/activity/entries/x.md"
assert_block "opencode -> C:\\ spool (fail-closed)"     _territory_violation opencode "c:/proj/.ai/activity/entries/x.md"

# KNOWN ASYMMETRY, documented not fixed (2026-07-12). _territory_violation matches on
# the LOWERCASED path (_lc). That is correct-and-fail-CLOSED for the four DENYLIST
# branches (claude/kimi/kiro/unknown), but it makes OpenCode's WHITELIST branch
# case-INSENSITIVE, i.e. fail-OPEN: on a case-sensitive filesystem `.AI/Activity/
# Entries/x.md` is a DIFFERENT file yet still matches the lane. The guard
# (framework-guard.js) is case-SENSITIVE and blocks the same path — the two layers
# disagree.
#
# Not "fixed" here, deliberately: the leak CANNOT ESCALATE (asserted below — no case
# variant reaches another CLI's territory, source, or a secret; the worst case is
# OpenCode committing junk at a case-variant path inside its own lane). Tightening it
# risks FALSE-BLOCKING a legitimate entry, which is the precise failure this change
# exists to prevent — OpenCode going silent with no error a human sees. If someone
# tightens it later, these assertions are the contract to preserve.
assert_allow "KNOWN: hook lane is case-insensitive (fails open, in-lane only)" \
    _territory_violation opencode ".AI/Activity/Entries/x.md"
# ...but it must NEVER escalate out of the lane. These are the load-bearing ones.
assert_block "case variant cannot reach .claude/" _territory_violation opencode ".CLAUDE/agents/x.md"
assert_block "case variant cannot reach .kimi/"   _territory_violation opencode ".Kimi/steering/x.md"
assert_block "case variant cannot reach .kiro/"   _territory_violation opencode ".KIRO/agents/x.json"
assert_block "case variant cannot reach source"   _territory_violation opencode "SRC/index.js"
assert_block "case variant cannot reach SSOT"     _territory_violation opencode ".AI/Instructions/x.md"
assert_block "case variant cannot reach a secret" _is_sensitive ".AI/Activity/Entries/ID_RSA"

echo "== SSOT replica exception (claude-code only, ADR-0005 2026-07-10, WIDENED 2026-07-12) =="
# sync.md steering replicas -> claude-code may fleet-commit them (original exception).
assert_allow "claude -> .kimi replica"   _territory_violation claude-code ".kimi/steering/operating-prompt.md"
assert_allow "claude -> .kiro replica"   _territory_violation claude-code ".kiro/steering/agent-catalog.md"
assert_allow "claude -> .kimi replica 2" _territory_violation claude-code ".kimi/steering/karpathy-guidelines.md"
# WIDENING (2026-07-12): the exception now covers the full sync.md replica set, not
# just steering. The two non-steering replicas must land in the same atomic commit.
assert_allow "claude -> .kimi resource replica" \
    _territory_violation claude-code ".kimi/resource/karpathy-guidelines-examples.md"
# DELIBERATE INVERSION (was assert_block pre-2026-07-12): .kiro/skills/karpathy-
# guidelines/SKILL.md is a REGISTERED replica in .ai/sync.md, so widening the
# exception from steering-only to the whole replica set now ALLOWS claude-code to
# fleet-commit it. This is the point of the change — it lets the Kiro skill replica
# land atomically with its SSOT source instead of drifting until Kiro syncs.
assert_allow "claude -> .kiro skill replica (INVERTED: now a registered replica)" \
    _territory_violation claude-code ".kiro/skills/karpathy-guidelines/SKILL.md"
# Hand-authored, NOT a sync.md replica -> stays blocked.
assert_block "claude -> .kimi 00-contract" _territory_violation claude-code ".kimi/steering/00-ai-contract.md"
assert_block "claude -> .kiro 00-contract" _territory_violation claude-code ".kiro/steering/00-ai-contract.md"
# Non-replica paths under another CLI's dir -> exception does NOT apply, blocked.
# The widening is REPLICA-ONLY and fail-closed: an unregistered .kiro/skills path is
# still blocked even though its parent dir now participates in the exception.
assert_block "claude -> .kimi hooks (non-replica)"  _territory_violation claude-code ".kimi/hooks/foo.sh"
assert_block "claude -> .kiro unregistered skill"   _territory_violation claude-code ".kiro/skills/x/SKILL.md"
assert_block "claude -> .kimi unregistered resource" _territory_violation claude-code ".kimi/resource/not-a-replica.md"
# Exception is claude-code ONLY: other committers still blocked on the same replica path.
assert_block "kiro -> .kimi replica"     _territory_violation kiro-cli ".kimi/steering/operating-prompt.md"
assert_block "kimi -> .kiro replica"     _territory_violation kimi-cli ".kiro/steering/agent-catalog.md"
assert_block "kiro -> .kimi resource replica" _territory_violation kiro-cli ".kimi/resource/karpathy-guidelines-examples.md"
# Fail-closed: if the registry is unreadable, even a real replica path is blocked.
assert_block "claude replica, no registry" bash -c 'SYNC_MD=/nonexistent/sync.md; PRECOMMIT_LIB=1 . "'"$HERE"'/pre-commit"; _territory_violation claude-code ".kimi/steering/operating-prompt.md"'
assert_block "claude skill replica, no registry" bash -c 'SYNC_MD=/nonexistent/sync.md; PRECOMMIT_LIB=1 . "'"$HERE"'/pre-commit"; _territory_violation claude-code ".kiro/skills/karpathy-guidelines/SKILL.md"'

echo "== PowerShell .ps1 syntax gate =="
# The gate is enforced only where a PowerShell host exists. On Linux CI there is
# none, so the check must SKIP (allow) rather than fail — assert that contract
# unconditionally, then assert real parse behaviour only where PS is available.
assert_allow "no PS host -> parse check skips" \
    bash -c 'PATH=/nonexistent; PRECOMMIT_LIB=1 . "'"$HERE"'/pre-commit"; _ps1_parse_error /nonexistent.ps1'

if [ -z "$(_ps_host)" ]; then
    echo "SKIP  no powershell/pwsh on PATH — parse cases not run (gate is a no-op here)"
else
    ps_tmp="$(mktemp -d)"
    printf 'param([string]$Name)\nif ($Name) { Write-Host "hi $Name" }\n' > "$ps_tmp/good.ps1"
    printf 'function Broken {\n  if ($x -eq ) { }\n' > "$ps_tmp/bad.ps1"

    assert_allow "valid .ps1 parses clean"   _ps1_parse_error "$ps_tmp/good.ps1"
    assert_block "broken .ps1 is caught"     _ps1_parse_error "$ps_tmp/bad.ps1"

    # The error summary must name the line and the reason — that is what makes the
    # rejection actionable.
    _ps1_parse_error "$ps_tmp/bad.ps1"
    case "$PS1_ERR" in
        line\ 2:*eq*) pass=$((pass + 1)); printf 'PASS  msg    error names line 2 + reason: %s\n' "$PS1_ERR" ;;
        *)            fail=$((fail + 1)); printf 'FAIL  msg    expected "line 2: ...-eq...", got: %s\n' "$PS1_ERR" ;;
    esac

    rm -rf "$ps_tmp"
fi

echo "== unknown committer (strictest) =="
assert_block "unknown -> .claude"        _territory_violation unknown ".claude/x.md"
assert_block "unknown -> .kimi"          _territory_violation unknown ".kimi/x.md"
assert_block "unknown -> .kiro"          _territory_violation unknown ".kiro/x.md"
assert_block "unknown -> .opencode"      _territory_violation unknown ".opencode/x.md"
assert_allow "unknown -> source ok"      _territory_violation unknown "src/main.ts"
assert_allow "unknown -> .ai ok"         _territory_violation unknown ".ai/activity/log.md"

# =============================================================================
# Integration tests — the generator, the checker, and the live pre-commit hook
# (ADR-0005 second amendment, 2026-07-12). These spin up throwaway git repos, so
# they exercise the WHOLE path (regenerate → stage/refuse → commit), not just the
# pure decision functions above. Skipped only if git/cp are unavailable.
# =============================================================================
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

# pf <desc> <rc> — PASS iff rc==0 (a scenario computes rc: 0 good, non-0 bad).
pf() {
    if [ "$2" -eq 0 ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
    else fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; fi
}

# mkrepo — materialize a throwaway repo from the current worktree's framework
# files, wired to the hook, with a synced initial commit. Echoes the repo path.
mkrepo() {
    d="$(mktemp -d)"
    cp -R "$REPO_ROOT/.ai" "$REPO_ROOT/.claude" "$REPO_ROOT/.kimi" \
          "$REPO_ROOT/.kiro" "$REPO_ROOT/scripts" "$d/" 2>/dev/null
    cp "$REPO_ROOT/.gitattributes" "$d/" 2>/dev/null
    git -C "$d" init -q 2>/dev/null
    git -C "$d" config core.hooksPath scripts/git-hooks
    git -C "$d" config user.email test@example.com
    git -C "$d" config user.name claude-code
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" commit -q -m init --no-verify >/dev/null 2>&1
    printf '%s' "$d"
}

if ! command -v git >/dev/null 2>&1 || ! command -v cp >/dev/null 2>&1; then
    echo "== integration tests =="
    echo "SKIP  no git/cp available — generator/checker/hook integration not run"
else
    echo "== generator: byte-identical + idempotent on a synced tree =="
    d="$(mkrepo)"
    gout="$(mktemp -d)"
    gman="$(mktemp)"
    ( cd "$d" && bash .ai/tools/sync-replicas.sh --dest-root "$gout" 2>/dev/null ) > "$gman"
    # Every generated replica must equal the committed one (0 drift).
    gdiffs=0
    while IFS="$(printf '\t')" read -r _s dd; do
        [ -n "$dd" ] || continue
        diff -q "$d/$dd" "$gout/$dd" >/dev/null 2>&1 || gdiffs=$((gdiffs + 1))
    done < "$gman"
    pf "generator output byte-identical to committed replicas" "$gdiffs"
    rm -f "$gman"
    # Idempotent: running in place on a synced tree changes nothing.
    ( cd "$d" && bash .ai/tools/sync-replicas.sh >/dev/null 2>&1 )
    idem="$(cd "$d" && git status --porcelain)"
    pf "generator in place produces no changes (idempotent)" "$([ -z "$idem" ] && echo 0 || echo 1)"
    rm -rf "$d" "$gout"

    echo "== generator: fails closed on unreadable registry =="
    d="$(mkrepo)"
    ( cd "$d" && SYNC_MD=/nonexistent/sync.md bash .ai/tools/sync-replicas.sh >/dev/null 2>&1 )
    pf "unreadable sync.md -> non-zero exit" "$([ $? -ne 0 ] && echo 0 || echo 1)"
    rm -rf "$d"

    echo "== generator: regenerates + preserves SKILL.md frontmatter after SSOT edit =="
    d="$(mkrepo)"
    printf '\n<!-- integration drift marker -->\n' >> "$d/.ai/instructions/karpathy-guidelines/examples.md"
    ( cd "$d" && bash .ai/tools/sync-replicas.sh >/dev/null 2>&1 )
    # The examples-derived replicas must now carry the marker...
    grep -q "integration drift marker" "$d/.kiro/skills/karpathy-guidelines/SKILL.md"
    pf "regenerated .kiro skill picked up the SSOT edit" "$?"
    grep -q "integration drift marker" "$d/.kimi/resource/karpathy-guidelines-examples.md"
    pf "regenerated .kimi resource picked up the SSOT edit" "$?"
    # ...while the SKILL.md preamble (frontmatter + SSOT marker) survives intact.
    fm=0
    grep -q "^name: karpathy-guidelines-examples" "$d/.kiro/skills/karpathy-guidelines/SKILL.md" || fm=1
    grep -q "^<!-- SSOT:" "$d/.kiro/skills/karpathy-guidelines/SKILL.md" || fm=1
    pf "regenerated .kiro SKILL.md preserved its frontmatter + SSOT marker" "$fm"
    rm -rf "$d"

    echo "== checker == generator: red after SSOT edit, green after regenerate =="
    d="$(mkrepo)"
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "checker green on synced tree" "$?"
    printf '\n<!-- drift -->\n' >> "$d/.ai/instructions/operating-prompt/principles.md"
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "checker RED after SSOT edit with no replica update" "$([ $? -ne 0 ] && echo 0 || echo 1)"
    ( cd "$d" && bash .ai/tools/sync-replicas.sh >/dev/null 2>&1 )
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "checker green again after running the generator" "$?"
    rm -rf "$d"

    echo "== checker == generator: a deliberate generator change flips the verdict =="
    # If the checker had its OWN copy of the transform, mutating the generator would
    # NOT change its verdict. It does -> proof the checker consumes generator output.
    d="$(mkrepo)"
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "checker green before generator mutation" "$?"
    # Make normalize_lf prepend a sentinel line to every replica it emits.
    sed -i 's/normalize_lf() { tr -d/normalize_lf() { echo ZZDRIFT; tr -d/' \
        "$d/.ai/tools/sync-replicas.sh"
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "checker RED after a deliberate generator change (checker uses generator)" \
        "$([ $? -ne 0 ] && echo 0 || echo 1)"
    rm -rf "$d"

    echo "== pre-commit: claude-code auto-stages replicas atomically =="
    d="$(mkrepo)"
    git -C "$d" config user.name claude-code
    printf '\n<!-- atomic marker -->\n' >> "$d/.ai/instructions/karpathy-guidelines/examples.md"
    ( cd "$d" && git add .ai/instructions/karpathy-guidelines/examples.md >/dev/null 2>&1 )
    ( cd "$d" && git commit -q -m "ssot: edit examples" >/dev/null 2>&1 )
    pf "claude-code commit of SSOT-only change SUCCEEDS" "$?"
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "committed tree is synced (0 drift) after auto-stage" "$?"
    # The WIDENED exception must have let the two non-steering replicas into the commit.
    names="$(git -C "$d" show --name-only --format= HEAD)"
    printf '%s' "$names" | grep -q ".kiro/skills/karpathy-guidelines/SKILL.md"
    pf "widened exception: .kiro/skills replica landed in the commit" "$?"
    printf '%s' "$names" | grep -q ".kimi/resource/karpathy-guidelines-examples.md"
    pf "widened exception: .kimi/resource replica landed in the commit" "$?"
    rm -rf "$d"

    echo "== pre-commit: human/other identity is REFUSED with the hint =="
    d="$(mkrepo)"
    git -C "$d" config user.name "Some Human"
    printf '\n<!-- human marker -->\n' >> "$d/.ai/instructions/karpathy-guidelines/examples.md"
    ( cd "$d" && git add .ai/instructions/karpathy-guidelines/examples.md >/dev/null 2>&1 )
    hout="$(cd "$d" && git commit -m "ssot: edit examples" 2>&1)"; hrc=$?
    pf "human commit of SSOT-only change is REFUSED" "$([ $hrc -ne 0 ] && echo 0 || echo 1)"
    printf '%s' "$hout" | grep -q "sync-replicas.sh"
    pf "refusal names the fix (run sync-replicas.sh / commit as claude-code)" "$?"
    rm -rf "$d"

    echo "== pre-commit: widening does NOT leak beyond registered replicas =="
    d="$(mkrepo)"
    git -C "$d" config user.name claude-code
    mkdir -p "$d/.kimi/hooks"
    printf '#!/bin/sh\necho x\n' > "$d/.kimi/hooks/x.sh"
    ( cd "$d" && git add .kimi/hooks/x.sh >/dev/null 2>&1 )
    ( cd "$d" && git commit -q -m "peer write" >/dev/null 2>&1 )
    pf "claude-code commit of NON-replica peer write (.kimi/hooks) is BLOCKED" \
        "$([ $? -ne 0 ] && echo 0 || echo 1)"
    rm -rf "$d"

    echo "== degradation: --no-verify commits stale, but check-ssot-drift still catches it =="
    d="$(mkrepo)"
    git -C "$d" config user.name claude-code
    printf '\n<!-- bypass marker -->\n' >> "$d/.ai/instructions/karpathy-guidelines/examples.md"
    ( cd "$d" && git add .ai/instructions/karpathy-guidelines/examples.md >/dev/null 2>&1 )
    ( cd "$d" && git commit -q -m "ssot bypass" --no-verify >/dev/null 2>&1 )
    pf "--no-verify lets the SSOT-only (stale) commit through" "$?"
    ( cd "$d" && bash .ai/tools/check-ssot-drift.sh >/dev/null 2>&1 )
    pf "CI net (check-ssot-drift) goes RED on the bypassed stale tree" \
        "$([ $? -ne 0 ] && echo 0 || echo 1)"
    rm -rf "$d"
fi

echo
echo "=============================================="
echo "RESULT: $pass passed, $fail failed"
echo "=============================================="
[ "$fail" -eq 0 ]
