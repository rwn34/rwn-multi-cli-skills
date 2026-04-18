# Wave 2 + Wave 3 bundle — Kiro
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-18 12:40

## Goal
Post–Wave-1 cleanup. Five items bundled. All trace back to the consolidated
audit at `.ai/reports/consolidated-audit-2026-04-18.md`.

I've landed all Claude-side equivalents and the shared `.ai/` SSOT updates
already. Your side:

1. Re-sync two Kiro steering replicas from updated SSOTs
2. Tighten `.kiro/agents/infra-engineer.json` YAML glob (your own DRIFT-2)
3. Trim `.kiro/agents/doc-writer.json` redundant/extra paths
4. Expand destructive-cmd hook coverage
5. Migrate `.kiro/hooks/` JSON parsing to Python (your own I-4b/F-7)

## Handoff numbering note
Using **012** because **010** is still open (user's audit dispatch) and
**011** is now in done/ (Wave 1 fix I sent you). Next available per recipient.

## Fixes

### Fix A — Re-sync `.kiro/steering/orchestrator-pattern.md` from updated SSOT (#6)
SSOT got a "Per-CLI nuance" paragraph. Re-sync:

    cp .ai/instructions/orchestrator-pattern/principles.md .kiro/steering/orchestrator-pattern.md

Verify with `diff` — should be identical.

### Fix B — Re-sync `.kiro/steering/agent-catalog.md` from updated SSOT (#12, #13)
Agent-catalog SSOT updated: doc-writer extra paths, e2e-tester renamed to
"E2E test files", "IaC/CI paths" section rewritten to be ADR-aware
(Dockerfile at root NOT permitted; scope is `infra/**` + root-level
category-D exceptions).

Re-sync:

    cp .ai/instructions/agent-catalog/principles.md .kiro/steering/agent-catalog.md

Verify with `diff` — should be identical.

### Fix C — Tighten `.kiro/agents/infra-engineer.json` allowedPaths (#4)
Current config has `**/*.yml`, `**/*.yaml`, `Dockerfile*`, `docker-compose*`
at top level — matches any YAML anywhere, permits root-level Dockerfile
(not ADR-permitted).

New allowlist aligned with updated agent-catalog SSOT:

```json
"fs_write": {
  "allowedPaths": [
    "infra/**",
    "scripts/**",
    "tools/**",
    ".github/workflows/**",
    ".circleci/**",
    ".buildkite/**",
    ".gitlab-ci.yml",
    ".dockerignore"
  ]
}
```

Drop: `Dockerfile*` (use `infra/docker/Dockerfile*` — covered by `infra/**`),
`docker-compose*` at root (same), `**/*.yml`/`**/*.yaml` (too broad),
`infrastructure/**` (dead duplicate of `infra/**`), bare `terraform/**`/`k8s/**`/`helm/**`
(now covered under `infra/**` subdirs).

### Fix D — Trim `.kiro/agents/doc-writer.json` (#12 / #23)
Current config allows `LICENSE`, `LICENSE.*`, `SECURITY.md`, `CODE_OF_CONDUCT.md`
in addition to `**/*.md`. `*.md` already covers `SECURITY.md` and
`CODE_OF_CONDUCT.md` — those are redundant.

Updated agent-catalog SSOT now lists `LICENSE*`, `README*`, `SECURITY.md`,
`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md` explicitly for doc-writer. Align
Kiro's `allowedPaths`:

```json
"allowedPaths": [
  "**/*.md",
  "docs/**",
  "CHANGELOG*",
  "LICENSE*",
  "README*",
  ".ai/reports/**"
]
```

Drop the redundant `SECURITY.md` and `CODE_OF_CONDUCT.md` since `*.md` + the
root-file hook already cover them.

### Fix E — Expand destructive-cmd hook coverage (#5)
`.kiro/hooks/destructive-cmd-guard.sh` currently covers 7 patterns. Align
to the canonical 11-pattern set (same list I gave Kimi in handoff 025):

| Pattern | Block? |
|---|---|
| `rm -rf /` | ✓ (existing) |
| `rm -rf ~` | ✓ (existing) |
| `rm -rf *` | ✓ (existing) |
| `rm -rf .` | add |
| `git push --force` / `-f` | ✓ (existing) |
| `git push --force-with-lease` | add |
| `git reset --hard` | ✓ (existing) |
| `DROP DATABASE` | ✓ (existing) |
| `DROP TABLE` | ✓ (existing) |
| `DROP SCHEMA` | add |
| `TRUNCATE TABLE` | add |

### Fix F — Migrate `.kiro/hooks/` JSON parsing to Python (#17)
Your own audit flagged this: Kiro's hooks use `grep -o` + `sed` for JSON
extraction, which breaks on multiline JSON, escaped quotes, or reordered
keys. Claude and Kimi both use Python (with fallback) — more robust.

Migrate at least `root-file-guard.sh`, `framework-dir-guard.sh`,
`sensitive-file-guard.sh`, `destructive-cmd-guard.sh` — the 4 preToolUse hooks
that extract tool-input fields. Reference pattern from Kimi's `.kimi/hooks/root-guard.sh`:

```bash
FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python -c  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
```

Fail-open if both `python3` and `python` fail (already the Kimi pattern).

## Verification
- (a) `diff .ai/instructions/orchestrator-pattern/principles.md .kiro/steering/orchestrator-pattern.md` → empty
- (b) `diff .ai/instructions/agent-catalog/principles.md .kiro/steering/agent-catalog.md` → empty
- (c) `.kiro/agents/infra-engineer.json` allowlist no longer contains `**/*.yml`, `**/*.yaml`, `Dockerfile*`, `docker-compose*`, `terraform/**`, `k8s/**`, `helm/**`, `infrastructure/**` at top level. JSON still valid.
- (d) `.kiro/agents/doc-writer.json` no longer lists `SECURITY.md` or `CODE_OF_CONDUCT.md`; adds `README*`, `CONTRIBUTING.md`. JSON still valid.
- (e) `.kiro/hooks/destructive-cmd-guard.sh` blocks all 11 canonical patterns (pipe-test a few new ones).
- (f) `.kiro/hooks/{root-file-guard,framework-dir-guard,sensitive-file-guard,destructive-cmd-guard}.sh` all use Python JSON parsing. Pipe-test at least root-file-guard.sh with `.gitignore` input (should still exit 0).

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Wave 2+3 bundle (per handoff 012) — re-synced 2 SSOT replicas;
      tightened infra-engineer + doc-writer allowedPaths; expanded
      destructive-cmd-guard; migrated 4 hooks to Python JSON parsing.
    - Files: .kiro/steering/orchestrator-pattern.md, .kiro/steering/agent-catalog.md,
      .kiro/agents/infra-engineer.json, .kiro/agents/doc-writer.json,
      .kiro/hooks/destructive-cmd-guard.sh, .kiro/hooks/root-file-guard.sh,
      .kiro/hooks/framework-dir-guard.sh, .kiro/hooks/sensitive-file-guard.sh
    - Decisions: <JSON schema choices, pipe-test results, any deviations>

## Report back with
- (a) Diff confirming both re-syncs byte-identical
- (b) Before/after diff of `infra-engineer.json` and `doc-writer.json` allowedPaths
- (c) JSON validity confirmation for both agent configs
- (d) Pipe-test output for at least one new destructive pattern + one root-file-guard case
- (e) Any scope deviations

## When complete
Sender (claude-code) validates by reading touched files + diff output.
Self-review acceptable — mechanical pattern-match + straightforward config
tightening. On success, move to `to-kiro/done/`.
