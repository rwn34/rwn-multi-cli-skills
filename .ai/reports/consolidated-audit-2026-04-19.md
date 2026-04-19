# Consolidated audit — 2026-04-19

Merges findings from the three parallel 2026-04-18/19 audits for cross-CLI review.
Purpose: deduplicated matrix + proposed severity + ownership, so each CLI can
agree/disagree and vote on fix priority.

## Inputs

| Source | File | Date | Findings |
|---|---|---|---|
| Claude | `.ai/reports/claude-audit-2026-04-19.md` | 2026-04-19 | 7 inconsistencies, 4 flaws, 4 bloat |
| Kiro | `.ai/reports/kiro-audit-2026-04-18.md` | 2026-04-19 (file named 04-18 per handoff 010 spec) | 5 inconsistencies, 6 flaws, 5 bloat |
| Kimi | `.ai/reports/kimi-audit-2026-04-18.md` | 2026-04-18 (no 04-19 re-run; missed its own F-4 in this pass) | 8 inconsistencies, 10 flaws, 4 bloat |

Kimi's input predates Kiro's F-4 discovery. The vote handoff asks Kimi to
specifically revisit F-4 (its own hook bug).

---

## Master finding matrix

Each row: finding, who found it, proposed severity, owner, and vote column
(C = Claude, Kr = Kiro, Km = Kimi). Vote cell reads: `✓` agree, `✗` disagree,
`?` not evaluated, `~` nuance — see notes below.

| # | Finding | Found by | Severity | Owner | C | Kr | Km |
|---|---|---|---|---|---|---|---|
| **CRITICAL** |
| 1 | `.kiro/agents/doc-writer.json` `**/*.md` allowedPaths allows subagent to write any `.md` in repo — bypasses `.claude/**`, `.kimi/**`, `.ai/**` edit boundaries | Kiro F-3 | **BLOCKER** | Kiro | ✓ | ✓ | ? |
| 2 | Kimi's 4 preToolUse hooks use `read JSON` before `python … json.load(sys.stdin)` — `read` consumes stdin, python gets EOF, all hooks fail-open (effectively no-ops) | Kiro F-4 | **BLOCKER** | Kimi | ✓ | ✓ | ? (missed in own audit) |
| **HIGH** |
| 3 | `.kiro/agents/tester.json` allowedPaths missing `*_test.*` and `*_spec.*` from catalog's Test-files scope | Kiro F-1 | WARN | Kiro | ? | ✓ | ? |
| 4 | `.kiro/agents/e2e-tester.json` allowedPaths missing `playwright/**`, `**/*.e2e.*`, `playwright.config.*`, `cypress.config.*` | Kiro F-2 | WARN | Kiro | ? | ✓ | ? |
| 5 | `.kiro/hooks/sensitive-file-guard.sh` blocks only `id_rsa*` — missing `id_ed25519*` (Ed25519 SSH keys bypass). Kimi + Claude block it | Claude I3/F4 | WARN | Kiro | ✓ | ? | ? |
| 6 | `.claude/hooks/pretool-write-edit.sh` missing `*.p12\|*.pfx` sensitive-pattern coverage. Kimi + Kiro block it | Claude I4/F3 | WARN | Claude | ✓ | ? | ? |
| 7 | Kimi's `.kimi/hooks/README.md:16` documents `.ai/activity-log.md` (hyphen, stale). Actual hook is correct; docs out of date | Claude I1/F2 | WARN | Kimi | ✓ | ? | ~ (Kimi found the hook bug, not the README) |
| 8 | Kiro subagent configs (12 files) have no `hooks` section — preToolUse guards only wired on `orchestrator.json`. If Kiro runtime doesn't inherit hooks, subagents run unguarded | Kiro F-5 | WARN | Kiro (verify runtime behavior first) | ? | ✓ | ? |
| 9 | `.kimi/agents/reviewer.yaml` `WriteFile`/`StrReplaceFile` in allowed_tools with no path restriction. Prompt restricts to `.ai/reports/` but tool layer doesn't enforce | Kimi Flaw 8 | WARN | Kimi | ? | ? | ✓ |
| 10 | SSOT orchestrator-pattern says orchestrator writes all 4 framework dirs; per-CLI hook narrows to own+shared. I-1 in Kiro's audit — prompt vs hook gap is misleading | Kiro I-1, Kimi Inc 1 | WARN | SSOT or each CLI's orchestrator prompt | ✓ | ✓ | ✓ |
| **MEDIUM** |
| 11 | `.kimi/hooks/README.md:10` describes root allowlist incompletely — lists only `CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, .mcp.json`, missing `.gitignore`, `.gitattributes`, `.editorconfig`, `.dockerignore`, `.gitlab-ci.yml`, `.mcp.json.example` | Claude I2 | WARN | Kimi | ✓ | ? | ? |
| 12 | `.kiro/agents/infra-engineer.json` prompt text lists stale scope (`Dockerfile*`, `**/*.yml`, `**/*.yaml`, `infrastructure/**`) while `allowedPaths` is correctly tightened — prompt is misleading | Kiro I-2 | WARN | Kiro | ? | ✓ | ? |
| 13 | `.kimi/agents/system/coder-executor.md:7` prompt says "anywhere EXCEPT framework directories" — doesn't mention reports-dir restriction from catalog | Kimi Flaw 6 | WARN | Kimi | ? | ? | ✓ |
| 14 | Kimi destructive-guard lowercases full command before matching; Kiro matches both cases literally. Kimi catches mixed-case like `Drop Database`; Kiro does not (though uppercase + lowercase variants in Kiro's list cover the common cases) | Kiro I-4 | INFO | Kiro (optional tighten) | ? | ✓ | ? |
| **LOW / INFO** |
| 15 | Claude `pretool-write-edit.sh` covers both `.aws` bare + `.aws/*`; Kimi/Kiro only cover `.aws/*`. Narrow edge case | Claude I5 | INFO | Kimi + Kiro (optional) | ✓ | ? | ? |
| 16 | Handoff-number collisions in `.ai/handoffs/to-kiro/done/`: two `004-*` and two `005-*` files | Claude I6, Kiro F-6 | INFO | Historical, no action needed | ✓ | ✓ | ? |
| 17 | 3 user-dispatched audits (`to-claude/open/015`, `to-kimi/open/022`, `to-kiro/open/010`) remain OPEN despite execution. Sender-move pending | Claude F1 | INFO | User (sender) | ✓ | ? | ? |
| 18 | `.kimi/hooks/` has unbound scripts (`handoffs-remind.sh`, `git-dirty-remind.sh`, `git-status.sh`) not wired in `~/.kimi/config.toml` — dead unless bound | Kimi Flaw 9 | INFO | Kimi (wire or remove) | ? | ? | ✓ |
| 19 | `.ai/reports/` has ~10 files from the 2026-04-18 audit cycle — archival protocol not yet exercised. Both Claude B1 and Kiro B-4 flagged | Claude B1, Kiro B-4 | INFO | Any orchestrator (archive) | ✓ | ✓ | ? |
| 20 | `docs/_templates/` could host TEMPLATE.md files (4 files in `docs/*/TEMPLATE.md`) to avoid polluting `file://docs/**/*.md` agent resource loads | Kiro B-2 | INFO | doc-writer (move) | ? | ✓ | ? |
| 21 | Handoff `done/` accumulation: Kimi 24, Claude 16, Kiro 14 = 54 files total. No archival protocol | Kiro B-3 | INFO | Any orchestrator (propose protocol) | ? | ✓ | ? |
| 22 | `.kimi/steering/agent-catalog.md` had duplicate "8." rule — fixed in Wave 2 re-sync | Kimi Inc 8, Kimi Flaw | RESOLVED | — | ~ | ~ | ✓ |

---

## Severity summary

| Severity | Count | Items |
|---|---|---|
| BLOCKER | 2 | #1 (Kiro doc-writer glob), #2 (Kimi hooks stdin) |
| WARN | 11 | #3–#13 |
| INFO | 8 | #14–#21 |
| RESOLVED | 1 | #22 |

## Ownership summary

| Owner | Items | Notes |
|---|---|---|
| Kiro | #1, #3, #4, #5, #8, #12, #14 | 1 BLOCKER, 5 WARN, 1 INFO |
| Kimi | #2, #7, #9, #11, #13, #18 | 1 BLOCKER, 4 WARN, 1 INFO |
| Claude | #6 | 1 WARN |
| Shared / SSOT | #10 | 1 WARN (could be SSOT clarification) |
| User (sender) | #17 | Queue hygiene |
| Any orchestrator | #15, #16, #19, #20, #21 | Mostly INFO / cleanup |

## Proposed fix order (Claude's draft)

Subject to Kimi + Kiro votes — this is my opening proposal.

1. **#2 (Kimi hooks stdin)** — silently disabled guards are worse than no guards. Dispatch today.
2. **#1 (Kiro doc-writer `**/*.md`)** — tighten allowedPaths to `*.md` + `docs/**/*.md` + named root files. Fix same wave.
3. **#6 (Claude `*.p12|*.pfx`)** — one-line hook addition; Claude self-fix.
4. **#5 (Kiro `id_ed25519*`)** — one-line hook addition; Kiro self-fix.
5. **#10 (orchestrator prompt vs hook mismatch)** — SSOT clarification; low risk, high explainability value.
6. **#7, #11 (Kimi README stale)** — doc fix, bundle with #2.
7. **#3, #4 (Kiro tester/e2e allowedPaths)** — bundle with #1.
8. **#8 (Kiro hook-inheritance)** — needs verification of Kiro runtime first.
9. **#12, #13 (prompt-text drift)** — cosmetic.
10. **#9 (Kimi reviewer tool layer)** — Kimi's soft-enforcement limitation; may need hook-level fix.

Everything below remaining as INFO / optional cleanup.

---

## Vote mechanism

Vote handoffs filed at:
- `.ai/handoffs/to-kimi/open/026-audit-consensus-vote.md`
- `.ai/handoffs/to-kiro/open/013-audit-consensus-vote.md`

Each CLI returns:
1. For each of the 21 findings: agree / disagree / nuance + rationale.
2. Additional findings neither audit caught.
3. Top-5 fix-priority ranking (BLOCKER+WARN items only).
4. Any change to proposed severity.

Once both votes are in, Claude writes a "consensus patch" summary and the user
picks which wave to dispatch.
