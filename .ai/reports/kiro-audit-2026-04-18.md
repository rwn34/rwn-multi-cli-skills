# Kiro CLI consistency audit — 2026-04-18

Auditor: `kiro-cli` (orchestrator)
Handoff: `010-cross-cli-consistency-audit.md`
Scope: ~35 files across 4 tiers (shared policy, Kiro-native, sibling CLIs, handoff queue)

---

## Inconsistencies

| # | Rule | File A (says X) | File B (says Y) | Severity |
|---|---|---|---|---|
| I-1 | Orchestrator write scope | `orchestrator.json` prompt: "You can write to .ai/, .kiro/, .kimi/, .claude/" | `framework-dir-guard.sh`: blocks writes to `.kimi/` and `.claude/` | WARN |
| I-2 | infra-engineer prompt vs config | `infra-engineer.json` prompt: "Write scope: Dockerfile*, .github/**, docker-compose*, *.yml, *.yaml, scripts/**, infrastructure/**, infra/**, terraform/**, k8s/**, helm/**" | `infra-engineer.json` allowedPaths: `["infra/**", "scripts/**", "tools/**", ".github/workflows/**", ".circleci/**", ".buildkite/**", ".gitlab-ci.yml", ".dockerignore"]` — correctly tightened | WARN |
| I-3 | doc-writer allowedPaths vs catalog | `doc-writer.json` allowedPaths: `["**/*.md", "docs/**", "CHANGELOG*", "LICENSE*", "README*", ".ai/reports/**"]` — `**/*.md` matches any `.md` file anywhere | Catalog says: `*.md`, `docs/**`, `CHANGELOG*`, `LICENSE*`, `README*`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `.ai/reports/` — scoped to root-level `.md` files | WARN |
| I-4 | Destructive-cmd case sensitivity | `destructive-cmd-guard.sh` (Kiro): matches literal case with both upper and lower variants (`DROP DATABASE` + `drop database`) | `destructive-guard.sh` (Kimi): lowercases entire command before matching — catches mixed-case like `Drop Database` | INFO |
| I-5 | Kimi `read JSON` stdin handling | `root-guard.sh` (Kimi): uses `read JSON` then pipes to python — consumes stdin before python can read it; python gets empty input | `root-file-guard.sh` (Kiro): reads stdin directly in python — correct pattern | WARN |

**Notes on I-1:** This is by design per the orchestrator-pattern SSOT ("Per-CLI nuance" paragraph). The prompt states the SSOT-level permission; the hook narrows it to own+shared. All 3 CLIs have this same pattern. However, the prompt is misleading — an agent reading it would expect `.kimi/` and `.claude/` writes to succeed. Suggest updating the prompt to say "You can write to .ai/ and .kiro/ (framework dirs). For .kimi/ and .claude/ changes, use handoffs."

**Notes on I-5:** Kimi's `read JSON` on line 6 consumes stdin. The subsequent `python3 -c "... json.load(sys.stdin) ..."` receives empty input. This means the python fallback always gets `""`, and the hook falls through to `exit 0` (fail-open). The hook is effectively a no-op. Kiro's hooks avoid this by piping stdin directly to python. This is a **flaw** in Kimi's hooks, not just an inconsistency — listed here because it's a cross-CLI delta, but also appears in Flaws below.

---

## Flaws

| # | Category | File + line | Description | Severity |
|---|---|---|---|---|
| F-1 | Missing allowedPaths patterns | `.kiro/agents/tester.json` | Missing `*_test.*` and `*_spec.*` patterns from catalog's "Test files" scope. Catalog lists them; Kiro config omits them. | WARN |
| F-2 | Missing allowedPaths patterns | `.kiro/agents/e2e-tester.json` | Missing `playwright/**`, `**/*.e2e.*`, and `playwright.config.*`/`cypress.config.*` patterns from catalog's "E2E test files" scope. | WARN |
| F-3 | Overly broad glob | `.kiro/agents/doc-writer.json` allowedPaths | `**/*.md` allows doc-writer to write to ANY `.md` file in the repo, including `.kimi/steering/*.md`, `.claude/agents/*.md`, etc. This bypasses the framework-dir restriction for `.md` files. The `framework-dir-guard.sh` hook only fires on the orchestrator agent (it's wired in `orchestrator.json` hooks), not on subagents. | BLOCKER |
| F-4 | Kimi stdin consumption bug | `.kimi/hooks/root-guard.sh:6`, `framework-guard.sh:6`, `destructive-guard.sh:6`, `sensitive-guard.sh` | `read JSON` consumes stdin before python can parse it. All 4 Kimi hooks using this pattern are effectively no-ops (fail-open). Kiro's hooks don't have this bug. | BLOCKER |
| F-5 | Hooks not wired to subagents | `.kiro/agents/*.json` (all 12 subagents) | The `preToolUse` hooks (root-file-guard, framework-dir-guard, sensitive-file-guard, destructive-cmd-guard) are only declared in `orchestrator.json`. Subagent configs have no `hooks` section. If Kiro's runtime doesn't inherit hooks from the spawning agent, subagents bypass all hook-based guards. | WARN |
| F-6 | Handoff numbering collisions | `.ai/handoffs/to-kiro/done/` | Number `010` used twice: `010-resync-orchestrator-pattern.md` (done) and `010-cross-cli-consistency-audit.md` (open). Also: two `005-*` files and two `004-*` files in done/. Per `README.md`, numbering should be unique across open+done. | INFO |

**Notes on F-3:** This is the highest-severity finding. The doc-writer agent with `**/*.md` in allowedPaths can write to `.kimi/steering/orchestrator-pattern.md` or `.claude/agents/reviewer.md` — framework files owned by other CLIs. The `framework-dir-guard.sh` hook is only wired in the orchestrator's config, so it doesn't protect against subagent writes. Fix: change `**/*.md` to `*.md` (root-level only) + `docs/**/*.md` + the specific root files (`CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`).

**Notes on F-5:** Needs verification — if Kiro's runtime inherits hooks from the parent agent to spawned subagents, this is a non-issue. If not, all subagents run without hook guards. The `allowedPaths`/`deniedPaths` in `toolsSettings` still provide hard enforcement regardless of hooks, so the impact is limited to: (a) root-file-guard not firing for subagents that write to root (only doc-writer and release-engineer have root-level paths in allowedPaths), (b) sensitive-file-guard not firing for subagents with broad write scope (coder, debugger).

---

## Bloat

| # | Type | Location | Rationale for removal/consolidation | Savings |
|---|---|---|---|---|
| B-1 | Unfilled templates | `docs/security.md` (14 TODOs), `SECURITY.md` (6 TODOs), `CHANGELOG.md` (6 TODOs), `CODE_OF_CONDUCT.md` (2 TODOs), `README.md` (2 TODOs) | Placeholder files with `[TODO: ...]` scaffolds unfilled across multiple sessions. These are intentional templates for a not-yet-started project, but they add noise to any grep/search. | Low — intentional scaffolding |
| B-2 | Template files in docs/ | `docs/api/TEMPLATE.md` (16 TODOs), `docs/specs/TEMPLATE.md` (13 TODOs), `docs/architecture/TEMPLATE.md` (8 TODOs), `docs/standards/TEMPLATE.md` (8 TODOs) | These are copy-paste templates, not content. They're useful but could be moved to a `docs/_templates/` dir to separate them from real docs and avoid polluting `file://docs/**/*.md` resource loads. | Medium — reduces noise in agent resource loading |
| B-3 | Handoff done/ accumulation | `to-kiro/done/` (14 files), `to-claude/done/` (16 files), `to-kimi/done/` (24 files) = 54 total | No archival protocol for done/ handoffs. These are historical records but grow unbounded. The activity log already captures the summary of each handoff's execution. | Medium — 54 files, ~150KB |
| B-4 | Duplicate audit reports | `.ai/reports/` | Multiple overlapping audit reports from this session: `kiro-audit-2026-04-18-rule-consistency.md` (earlier self-initiated), `kiro-audit-2026-04-18.md` (this report, per handoff), `claude-code-template-audit-2026-04-18.md`, `kimi-audit-2026-04-18.md`, `claude-crosscheck-2026-04-18-kiro-audit.md`, `kimi-crosscheck-2026-04-18-kiro-audit.md`, `consolidated-audit-2026-04-18.md`, `claude-audit-2026-04-18.md` (pointer). 8 reports from one audit cycle. | Low — one-time event, but suggests a reports archival protocol is needed |
| B-5 | Kiro hooks README | `.kiro/hooks/README.md` | Documents hook purposes and wiring — useful but duplicates info already in `orchestrator.json` hooks section. Same pattern exists in `.kimi/hooks/README.md`. | Low — documentation, not dead code |

---

## Clean — no findings

The following areas returned zero issues:

- **SSOT sync**: All 3 Kiro steering files (orchestrator-pattern, agent-catalog, karpathy-guidelines) are byte-identical to their SSOT sources in `.ai/instructions/`. Sync is clean.
- **Root-file policy references**: `CLAUDE.md`, `.kiro/steering/00-ai-contract.md`, `.kimi/steering/00-ai-contract.md`, and `AGENTS.md` all point to ADR-0001 without re-listing the allowlist inline. The ADR is the single authority as intended.
- **Activity-log format**: All recent entries in `.ai/activity/log.md` follow the prescribed format (`## YYYY-MM-DD HH:MM — <cli-name>`, `- Action:`, `- Files:`, `- Decisions:`). Consistent across all 3 CLIs.
- **Sync map completeness**: `.ai/sync.md` lists all 3 instruction dirs (karpathy-guidelines, orchestrator-pattern, agent-catalog) with correct source→destination pairs for all 3 CLIs.
- **Skill provenance**: `.kiro/skills/karpathy-guidelines/SKILL.md` contains provenance pointer: `<!-- SSOT: .ai/instructions/karpathy-guidelines/examples.md — regenerate via .ai/sync.md -->`.
- **Hook ADR alignment**: `root-file-guard.sh` allowlist matches ADR-0001 categories A/B/C/D/E exactly. Comments reference the ADR.
- **JSON validity**: All 13 `.kiro/agents/*.json` files are valid JSON (confirmed by successful parsing during read).
- **Agent roster**: All 13 agents present in `.kiro/agents/` matching the catalog. Names match (Kiro uses `coder`, not `coder-executor` like Kimi — known and documented delta).
- **Handoff protocol**: Template and README are consistent. No contradictions between `AGENTS.md` handoff section and `.ai/handoffs/README.md`.

---

## Summary

| Category | BLOCKER | WARN | INFO |
|---|---|---|---|
| Inconsistencies | 0 | 3 | 1 |
| Flaws | 2 | 2 | 1 |
| Bloat | 0 | 0 | 5 |
| **Total** | **2** | **5** | **7** |

### BLOCKERs requiring action

1. **F-3** — doc-writer `**/*.md` glob bypasses framework-dir restriction. Owner: Kiro. Fix: narrow to `*.md` + `docs/**/*.md` + named root files.
2. **F-4** — Kimi hooks `read JSON` stdin bug makes all 4 hooks no-ops. Owner: Kimi (handoff needed). Already partially flagged in earlier audits but the `read JSON` root cause was not identified.

### Cross-CLI coordination needed

- F-4 requires a handoff to Kimi to fix the `read JSON` stdin consumption pattern across 4 hook scripts.
- I-1 (prompt vs hook mismatch) is shared across all 3 CLIs — could be addressed by updating the SSOT orchestrator-pattern to clarify the per-CLI narrowing, or by updating each CLI's orchestrator prompt individually.
