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

echo "== SSOT replica-steering exception (claude-code only, ADR-0005 2026-07-10) =="
# sync.md replicas -> claude-code may fleet-commit them.
assert_allow "claude -> .kimi replica"   _territory_violation claude-code ".kimi/steering/operating-prompt.md"
assert_allow "claude -> .kiro replica"   _territory_violation claude-code ".kiro/steering/agent-catalog.md"
assert_allow "claude -> .kimi replica 2" _territory_violation claude-code ".kimi/steering/karpathy-guidelines.md"
# Hand-authored, NOT a sync.md replica -> stays blocked.
assert_block "claude -> .kimi 00-contract" _territory_violation claude-code ".kimi/steering/00-ai-contract.md"
assert_block "claude -> .kiro 00-contract" _territory_violation claude-code ".kiro/steering/00-ai-contract.md"
# Non-steering path under another CLI's dir -> exception does not apply, blocked.
assert_block "claude -> .kimi hooks"     _territory_violation claude-code ".kimi/hooks/foo.sh"
assert_block "claude -> .kiro resource"  _territory_violation claude-code ".kiro/skills/x/SKILL.md"
# Exception is claude-code ONLY: other committers still blocked on the same replica path.
assert_block "kiro -> .kimi replica"     _territory_violation kiro-cli ".kimi/steering/operating-prompt.md"
assert_block "kimi -> .kiro replica"     _territory_violation kimi-cli ".kiro/steering/agent-catalog.md"
# Fail-closed: if the registry is unreadable, even a real replica path is blocked.
assert_block "claude replica, no registry" bash -c 'SYNC_MD=/nonexistent/sync.md; PRECOMMIT_LIB=1 . "'"$HERE"'/pre-commit"; _territory_violation claude-code ".kimi/steering/operating-prompt.md"'

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

echo
echo "=============================================="
echo "RESULT: $pass passed, $fail failed"
echo "=============================================="
[ "$fail" -eq 0 ]
