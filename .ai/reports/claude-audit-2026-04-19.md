# Claude Code consistency audit — 2026-04-19

Auditor: claude-code (orchestrator)
Handoff: `.ai/handoffs/to-claude/open/015-cross-cli-consistency-audit.md`
Scope: all 4 tiers from handoff 015 (shared policy, Claude-native, sibling CLIs read-only, handoff queue)

## Context

This audit runs **after** Waves 1–3 of the previous audit cycle (2026-04-18) landed.
Prior audits resolved the major dotfile-allowlist drift, debugger FORBIDDEN-paths gap,
orchestrator-pattern 3-agent staleness, destructive-command pattern expansion, and the
Kimi/Kiro hook activity-log path hyphen bug. That remediation history is visible in the
activity log and accounts for this audit finding far fewer BLOCKER-level items than the
2026-04-18 passes. Remaining findings are narrower — doc drift in one README, sensitive-file
pattern gaps, and handoff-queue hygiene.

---

## Inconsistencies

| # | Rule | File A (says X) | File B (says Y) | Severity |
|---|---|---|---|---|
| I1 | Activity-log path | `.kimi/hooks/README.md:16` says inject `.ai/activity-log.md` (hyphenated, stale) | `.kimi/hooks/activity-log-inject.sh:5` correctly uses `.ai/activity/log.md`; all CLIs' contracts use `.ai/activity/log.md` | **WARN** (doc stale; behavior correct) |
| I2 | Kimi root-allowlist description | `.kimi/hooks/README.md:10` lists only `CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, .mcp.json` | `.kimi/hooks/root-guard.sh:25–42` allows 13 patterns including `.gitignore`, `.gitattributes`, `.editorconfig`, `.dockerignore`, `.gitlab-ci.yml`, `.mcp.json.example` | WARN (doc incomplete) |
| I3 | Sensitive-file pattern `id_ed25519*` | `.kimi/hooks/sensitive-guard.sh:24` blocks `id_ed25519*`; `.claude/hooks/pretool-write-edit.sh:52` blocks it | `.kiro/hooks/sensitive-file-guard.sh:11` blocks only `id_rsa*` — missing `id_ed25519*` | WARN (Kiro coverage gap) |
| I4 | Sensitive-file pattern `*.p12\|*.pfx` | `.kimi/hooks/sensitive-guard.sh:24` + `.kiro/hooks/sensitive-file-guard.sh:11` block `.p12`/`.pfx` | `.claude/hooks/pretool-write-edit.sh` (Rule 2, lines 47–58) does NOT block `*.p12` or `*.pfx` | WARN (Claude coverage gap) |
| I5 | Sensitive-dir basenames | `.claude/hooks/pretool-write-edit.sh:54–57` blocks both `.aws` and `.aws/*` (same for `.ssh`) | Kimi `sensitive-guard.sh:28` and Kiro `sensitive-file-guard.sh:14` block only `.aws/*` and `.ssh/*` — bare-basename write (e.g., accidentally writing a file literally named `.aws`) is NOT blocked | INFO (narrow edge case) |
| I6 | Handoff-number protocol | `.ai/handoffs/README.md:44–47` says numbering is per-recipient and continuous across `open/` + `done/` | `.ai/handoffs/to-kiro/done/` has **two** `004-*` files (`004-validate-claude-agent-configs.md`, `004-validate-kimi-agent-configs.md`) and **two** `005-*` files (`005-validate-kimi-hooks.md`, `005-validate-claude-hooks.md`) | INFO (historical collision, already resolved) |
| I7 | Claude agent tool lists vs catalog | `.ai/instructions/agent-catalog/principles.md` lists abstract tools (`fs_read`, `code`, etc.) | Claude agents use Claude-native tool names (`Read`, `Edit`, `Write`, `Bash`, plus `TaskCreate/Update`, `Skill`, `NotebookEdit`, `WebFetch`) — these are CLI-idiomatic extras, not divergence | INFO (expected; catalog's "abstract-tool" mapping is under-documented though) |

---

## Flaws

| # | Category | File + line | Description | Severity |
|---|---|---|---|---|
| F1 | Queue hygiene | `.ai/handoffs/to-claude/open/015-cross-cli-consistency-audit.md`, `to-kimi/open/022-*.md`, `to-kiro/open/010-*.md` | All three user-dispatched consistency audits remain `Status: OPEN` despite the activity log showing all three were executed (Claude: 11:20, Kimi: 10:35, Kiro: 09:19 on 2026-04-18). Protocol requires sender (user) to validate-and-move. Not a CLI bug — surfaces here for sender awareness. | INFO |
| F2 | Doc staleness | `.kimi/hooks/README.md:16` | References `.ai/activity-log.md` (hyphen, wrong path). Same root cause as the Wave 1 hook bug, but the README was out of scope for Wave 1 ("hook scope only"). Flagged in Kimi's own 2026-04-18 log as deferred. | WARN |
| F3 | Enforcement gap — `.p12`/`.pfx` keys | `.claude/hooks/pretool-write-edit.sh:47–58` | Claude has no sensitive-pattern coverage for PKCS12/PFX certificate archives. A subagent writing `wildcard.pfx` would pass. Kimi and Kiro block these. | WARN |
| F4 | Enforcement gap — `id_ed25519` SSH key | `.kiro/hooks/sensitive-file-guard.sh:11` | Kiro blocks `id_rsa*` only. `id_ed25519*` (the modern Ed25519 default) would pass. Claude and Kimi both block it. | WARN |
| F5 | Missing files / broken links | — | No missing files or broken markdown links found in the Tier 1 / Tier 2 sweep. | — |
| F6 | Settings drift | `.claude/settings.json` | References all 4 hook scripts that actually exist in `.claude/hooks/`; main-agent = `orchestrator` which exists in `.claude/agents/`. Settings clean. | — |

---

## Bloat

| # | Type | Location | Rationale for removal/consolidation | Savings |
|---|---|---|---|---|
| B1 | Accumulated reports | `.ai/reports/*.md` | 9 audit/report files from 2026-04-18 now in the flat dir (`claude-audit`, `claude-code-template-audit`, `consolidated-audit`, two `kiro-audit` variants, two `kimi-audit`/`-crosscheck`, `claude-crosscheck`). Per `.ai/reports/README.md:21–23`, "Archive old reports to `.ai/reports/archive/` when the directory gets noisy." After this audit lands there will be 10 files — probably time to archive once the 015/022/010 handoffs close. | 9 → ~2 active files |
| B2 | Cross-CLI audit handoff triplicate | `.ai/handoffs/to-claude/open/015`, `to-kimi/open/022`, `to-kiro/open/010` | All three files are the same audit brief with only "Claude" / "Kimi" / "Kiro" swapped — ~125 lines each. Acceptable for parallel dispatch (each CLI gets its own inbox entry), but once all three move to `done/`, no long-term reason to keep all three — one canonical + two "see 015" pointers would suffice. | ~250 duplicate lines |
| B3 | Overlapping doc-writer scopes | `.claude/agents/doc-writer.md:13` ("*.md anywhere") vs. catalog's per-file allowlist | Catalog lists `*.md`, `docs/**`, `CHANGELOG*`, `LICENSE*`, `README*`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`. Claude agent says `*.md anywhere` + `docs/**` + `CHANGELOG*` + `LICENSE*` + `README*` — functionally equivalent (the first pattern subsumes the later file-specific ones) but mechanically redundant. | ~3 lines; readability wash |
| B4 | "Skills you rely on" section duplication | `.claude/agents/orchestrator.md:60–64` (in `.claude/agents/`) + `CLAUDE.md` (at project root, which also effectively acts as orchestrator steering) | The orchestrator's skill list lives in two places. CLAUDE.md's "Installed skills" bullet points to the same three skills Claude's agent prompt lists. Mild duplication; intentional for different loading contexts (prompt vs. project memory). INFO only. | ~5 lines each |

---

## Clean — tiers / areas with no findings

- **Tier 1 — `.ai/instructions/orchestrator-pattern/principles.md`** is byte-identical to `.claude/skills/orchestrator-pattern/SKILL.md` body, `.kimi/steering/orchestrator-pattern.md`, and `.kiro/steering/orchestrator-pattern.md`. SSOT-replica drift: zero.
- **Tier 1 — `.ai/instructions/agent-catalog/principles.md`** similarly byte-identical across all three CLI replicas.
- **Tier 1 — Root-file policy pointers.** `CLAUDE.md`, `AGENTS.md`, `.kimi/steering/00-ai-contract.md`, `.kiro/steering/00-ai-contract.md`, `.kiro/agents/orchestrator.json`, `.kimi/agents/system/orchestrator.md`, and `README.md` all reference `docs/architecture/0001-root-file-exceptions.md` by path — none re-list the allowlist inline. Consistent across the contract layer.
- **Tier 1 — Activity-log format.** `CLAUDE.md`, `AGENTS.md`, `.kimi/steering/00-ai-contract.md`, `.kiro/steering/00-ai-contract.md` all declare the same 4-line entry shape (`## YYYY-MM-DD HH:MM — <cli>`, Action / Files / Decisions) and the same timestamp semantics (finish time, prepend-order authoritative).
- **Tier 1 — Sync map.** `.ai/sync.md` covers all three SSOT instruction sets (karpathy-guidelines, orchestrator-pattern, agent-catalog) with source→destination rows for all three CLIs. No instructions in `.ai/instructions/` are unmapped.
- **Tier 1 — Skill provenance.** All three Claude skills include the `<!-- SSOT: .ai/instructions/... -->` comment. Kimi's steering files are SSOT body (no provenance comment needed — they are CLI-loaded replicas named identically). Kiro same.
- **Tier 2 — `.claude/agents/`.** All 13 agent files present; frontmatter complete on each (`name`, `description`, `tools`). Tool lists match catalog's Claude-mapping (with expected Claude-native extras like `TaskCreate/Update`, `Skill`).
- **Tier 2 — `.claude/hooks/`.** 4 scripts wired in `.claude/settings.json`; all use Python-JSON parsing; all use `exit 0/2` semantics. Rule 3 (root-file policy) enumerates all ADR categories A–E explicitly. Rule 1 (framework dirs) blocks `.kimi/`, `.kiro/`. Rule 2 (sensitive) — see I4/F3.
- **Tier 2 — `.claude/settings.json`.** Valid schema; main agent = `orchestrator`; all 4 hook script paths resolve.
- **Tier 3 — Dotfile allowlist byte-alignment.** All three root-guard hooks (`.claude/hooks/pretool-write-edit.sh`, `.kimi/hooks/root-guard.sh`, `.kiro/hooks/root-file-guard.sh`) cover the canonical 7-pattern list. (Prior audit remediation.)
- **Tier 3 — Destructive-command guards.** `.claude/hooks/pretool-bash.sh`, `.kimi/hooks/destructive-guard.sh`, `.kiro/hooks/destructive-cmd-guard.sh` all cover the canonical 11-pattern list: `rm -rf` with 4 broad targets, force-push variants, hard reset, DROP DATABASE/TABLE/SCHEMA, TRUNCATE TABLE. (Prior remediation.)
- **Tier 3 — Framework-dir guards.** Kimi blocks `.claude/*` and `.kiro/*`; Kiro blocks `.kimi/*` and `.claude/*`; Claude blocks `.kimi/*` and `.kiro/*`. Each CLI denies writes to its sibling CLIs' territory, consistent with the "Per-CLI nuance" rule in orchestrator-pattern SSOT.
- **Tier 4 — Handoff inbox.** Only one handoff addressed to claude-code open (this one, 015). `done/` has 001–016 in order (015 missing = OPEN; 014 is final-review, moved 2026-04-18 11:00). No stale claude-addressed handoffs.

---

## Cross-CLI coordination flagged

| Finding | Suggested owner | Why |
|---|---|---|
| I3 / F4 (Kiro missing `id_ed25519*`) | kiro-cli (handoff) | Kiro-only edit; add pattern to `.kiro/hooks/sensitive-file-guard.sh` |
| I4 / F3 (Claude missing `*.p12\|*.pfx`) | claude-code (direct edit to `.claude/hooks/pretool-write-edit.sh`) | Claude's own framework dir |
| I1 / F2 (Kimi README stale path) | kimi-cli (handoff) | Kimi docs; one-line fix |
| I2 (Kimi README allowlist description) | kimi-cli (handoff) | Same README, same pass |
| I5 (bare-basename `.aws`/`.ssh`) | kimi + kiro (handoff) — or leave as INFO | Narrow edge case; arguably not worth the pattern |
| I6 (historical number collision) | — | Already in `done/`, no action |
| F1 (3 user-dispatched audits still OPEN) | user (sender moves) | Protocol action, not a CLI fix |
| B1 (reports dir archival) | any orchestrator | Routine `.ai/reports/` hygiene once this audit + 015/022/010 close |

---

## Scope notes

**Read, not exhaustive.** I read every file explicitly listed in handoff 015's scope (Tiers 1 + 2 + 3 + 4) — that's ~35 files. I spot-checked but did not exhaustively diff every one of the 13 agent configs per CLI against the catalog's tool list; Claude's 13 were full reads, Kimi's orchestrator + hooks + sensitive/destructive were full reads, Kiro's orchestrator.json + hooks + steering were full reads. Non-orchestrator Kimi/Kiro subagent configs were skipped — prior 2026-04-18 audits covered them.

**Dependence on prior work.** This audit sits on top of 2026-04-18's Wave 1–3 remediation. If any of those fixes silently reverted between sessions, I would not have caught it without a full byte-diff — I took the "is byte-identical" check as sufficient for SSOT ⇄ replica pairs but did not verify against git log that they've stayed aligned since the Wave 3 commit (`e9ce8d5`).

**Did not verify.** Hook behavior via pipe-tests (read-only constraint per handoff 015). Kiro agent configs for non-orchestrator agents (12 files). Kimi agent YAMLs for non-orchestrator agents (12 files). `.github/` or any workflow directory (empty-looking in this template).
