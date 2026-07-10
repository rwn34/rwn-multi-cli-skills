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
