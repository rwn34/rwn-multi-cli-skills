# Wave 2 + Wave 3 bundle — Kimi
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-18 12:40

## Goal
Post–Wave-1 cleanup. Six items bundled. All trace back to the consolidated
audit at `.ai/reports/consolidated-audit-2026-04-18.md`.

I've landed all Claude-side equivalents and the shared `.ai/` SSOT updates
already (see this session's activity log entries). Your side:

1. Re-sync two Kimi steering replicas from updated SSOTs
2. Fix duplicate rule number in Kimi agent-catalog replica (resolves via #1)
3. Expand destructive-cmd hook coverage
4. Add FORBIDDEN-paths section to Kimi reviewer prompt (matches Claude's)
5. Add reports-dir note to coder-executor prompt
6. Check + document unbound Kimi hooks
7. Fix `framework-guard.sh` ownership comment

## Fixes

### Fix A — Re-sync `.kimi/steering/orchestrator-pattern.md` from updated SSOT (#6)
The SSOT at `.ai/instructions/orchestrator-pattern/principles.md` was updated
with a "Per-CLI nuance" paragraph after the orchestrator write-path section
(inserted between lines 15 and 17). Re-sync via:

    cp .ai/instructions/orchestrator-pattern/principles.md .kimi/steering/orchestrator-pattern.md

Verify with `diff` — should be identical.

### Fix B — Re-sync `.kimi/steering/agent-catalog.md` from updated SSOT (#9, #12, #13)
Agent-catalog SSOT was updated with 3 changes:
- **doc-writer row** — added `LICENSE*`, `README*`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md` to write scope column
- **e2e-tester row** — changed "Test files" to "E2E test files"
- **Write scope details section** — split "Test files" into separate `tester`
  and `e2e-tester` subsections; rewrote "IaC/CI dirs" → "IaC/CI paths" with
  ADR-aware scoping (rejects root-level `Dockerfile`, `docker-compose.yml`,
  `**/*.yml`)

Re-sync via:

    cp .ai/instructions/agent-catalog/principles.md .kimi/steering/agent-catalog.md

**Side-benefit:** this also fixes consolidated audit item #9 — your replica
currently has two `8.` entries under "Agent behavior rules" (your finding
from the audit). The SSOT is correct (1–9 enumerated). A byte-identical copy
removes the drift.

Verify the replica no longer has `8. All subagents report back` — it should
be `9. All subagents report back`.

### Fix C — Expand destructive-cmd hook coverage (#5)
`.kimi/hooks/destructive-guard.sh` currently covers 5 patterns. Add
coverage for: `rm -rf .`, `DROP SCHEMA`, `TRUNCATE TABLE`,
`--force-with-lease`. Canonical pattern set (aligned across all 3 CLIs
per Claude's existing hook):

| Pattern | Block? |
|---|---|
| `rm -rf /` | ✓ (existing) |
| `rm -rf *` | add |
| `rm -rf ~` | add |
| `rm -rf .` | add |
| `git push --force` / `-f` | ✓ (existing) |
| `git push --force-with-lease` | add |
| `git reset --hard` | ✓ (existing) |
| `DROP DATABASE` | ✓ (existing) |
| `DROP TABLE` | ✓ (existing) |
| `DROP SCHEMA` | add |
| `TRUNCATE TABLE` | add |

Keep fail-open on unparseable input. Python JSON parsing already in place.

### Fix D — Add FORBIDDEN-paths section to reviewer prompt (#15)
`.kimi/agents/system/reviewer.md` restricts writes to `.ai/reports/` via
prompt but doesn't explicitly list forbidden paths. Add the same kind of
section Claude just landed in `.claude/agents/reviewer.md`:

```markdown
**FORBIDDEN paths — never write under these** (enforcement is prompt-only):
- Any file under `src/**`, `tests/**`, `docs/**`, `infra/**`, `migrations/**`,
  `scripts/**`, `tools/**`, `config/**`, `assets/**`, or the repo root
- `.ai/**` except `.ai/reports/reviewer-<YYYY-MM-DD>-<slug>.md`
- `.kimi/**`, `.kiro/**`, `.claude/**` — framework territory
- `CLAUDE.md`, `AGENTS.md`, `README.md`, any other root contract

If a reviewer insight requires changing a file, STOP and hand back — the
orchestrator routes the change to the appropriate executor (coder,
refactorer, doc-writer, etc.).
```

### Fix E — Add reports-dir note to coder-executor prompt (#14)
`.kimi/agents/system/coder-executor.md` says "write anywhere EXCEPT framework
directories" but doesn't mention that `.ai/reports/` is off-limits for coder
(it's a diagnoser-only zone per the catalog). Add a line under the Scope
section:

> Note: `.ai/reports/` is for diagnosers (reviewer, security-auditor,
> e2e-tester). The coder-executor should not write there — if you have
> findings to document, the orchestrator will route them via a diagnoser.

### Fix F — Audit unbound Kimi hooks (#10, bloat #22)
Three hook scripts may exist in `.kimi/hooks/` but not be wired in
`~/.kimi/config.toml`: `handoffs-remind.sh`, `git-dirty-remind.sh`,
`git-status.sh`. Check config.toml to verify. If unbound, either:
- Wire them (add to config.toml), OR
- Remove them from `.kimi/hooks/` to avoid dead-code confusion

Either way, document which you chose in the activity log.

### Fix G — Fix `framework-guard.sh` ownership comment (#11)
`.kimi/hooks/framework-guard.sh` has a comment claiming ".ai/ and .kimi/ are
allowed (kimi-cli owns these)". `.ai/` is SHARED across all 3 CLIs, not
owned by Kimi. Fix the comment to read something like:

```bash
# .kimi/ is Kimi's own territory. .ai/ is shared with other CLIs
# (allowed for orchestrator; subagent writes restricted per agent config).
# Block other CLIs' framework dirs (.kiro/, .claude/).
```

## Verification
- (a) `diff .ai/instructions/orchestrator-pattern/principles.md .kimi/steering/orchestrator-pattern.md` → empty
- (b) `diff .ai/instructions/agent-catalog/principles.md .kimi/steering/agent-catalog.md` → empty (resolves the duplicate `8.`)
- (c) `.kimi/hooks/destructive-guard.sh` blocks the 11 canonical patterns (pipe-test a few)
- (d) `.kimi/agents/system/reviewer.md` has FORBIDDEN-paths section
- (e) `.kimi/agents/system/coder-executor.md` has reports-dir note
- (f) `.kimi/hooks/framework-guard.sh` ownership comment updated
- (g) Decision on unbound hooks documented (wired or removed)

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Wave 2+3 bundle (per handoff 025) — re-synced 2 SSOT replicas
      (orchestrator-pattern, agent-catalog); expanded destructive-guard.sh;
      added FORBIDDEN-paths to reviewer; reports-dir note to coder-executor;
      audited unbound hooks; fixed framework-guard.sh ownership comment.
    - Files: .kimi/steering/orchestrator-pattern.md, .kimi/steering/agent-catalog.md,
      .kimi/hooks/destructive-guard.sh, .kimi/agents/system/reviewer.md,
      .kimi/agents/system/coder-executor.md, .kimi/hooks/framework-guard.sh,
      (+ unbound-hook resolution files)
    - Decisions: <unbound hooks — wired or removed; any deviations>

## Report back with
- (a) Diff output confirming both re-syncs byte-identical
- (b) Pipe-test output for destructive-guard (one new pattern)
- (c) Unbound-hook decision (wired or removed; which ones)
- (d) Any scope deviations

## When complete
Sender (claude-code) validates by reading touched files + diff output.
Self-review acceptable — mechanical pattern-match plus well-documented
design choices. On success, move to `to-kimi/done/`.
