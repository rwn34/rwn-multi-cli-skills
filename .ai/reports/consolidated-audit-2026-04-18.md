# Consolidated audit findings — 2026-04-18
Produced by: claude-code (orchestrator)
Sources: Kiro audit, Kimi audit, Claude audit, Claude's cross-check of Kiro, Kimi's cross-check of Kiro.

This is a deduplicated severity-sorted view across all three CLIs' findings.
When a finding appears in multiple audits, this doc collapses them into one
row with refs back to each audit.

---

## BLOCKER — live bugs / permission gaps

| # | Finding | Owner(s) | Audits that caught it |
|---|---|---|---|
| **1** | **Kimi hook activity-log paths wrong** — `.kimi/hooks/activity-log-inject.sh`, `activity-log-remind.sh`, and `git-dirty-remind.sh` all reference `.ai/activity-log.md` (hyphen) instead of `.ai/activity/log.md` (slash). Hooks silently no-op — activity-log reminders never fire, injection never happens. | **Kimi** | Kimi flaw #2/#3/#4 |
| **2** | **Dotfile-at-root handling is broken in 2 of 3 CLIs** — Kimi + Kiro root-file hooks BLOCK `.gitignore`/`.gitattributes`/`.editorconfig` (no case arm). Claude's hook BLANKET-ALLOWS all dotfiles (`.*) exit 0`) — too permissive, allows `.foo-secret` or any arbitrary dotfile. | **all 3** | Kiro BUG-1/F-1/I-1, Kimi #2/#3, Claude M5, cross-checks confirm |
| **3** | **`debugger` agent has no framework-dir write restriction** — Kiro's `.kiro/agents/debugger.json` has no `deniedPaths`; Claude's `.claude/agents/debugger.md` has no tool-level path restriction (soft prompt only). Both can write `.ai/**` + own CLI dir. Kimi is prompt-only by design but the debugger prompt doesn't mention framework dirs. | **Claude + Kiro** (Kimi: prompt fix only) | Kiro BUG-2/F-2, Claude crosscheck, Kimi nuance |

---

## WARN — drift, enforcement gaps, misleading docs

| # | Finding | Owner(s) | Audits |
|---|---|---|---|
| **4** | **Kiro `infra-engineer` YAML glob too broad** — `**/*.yml` + `**/*.yaml` match any YAML anywhere (including `.kimi/agents/*.yaml`). Catalog + Claude's narrower scope don't agree with this. | **Kiro** | Kiro F-4/DRIFT-2, Claude H1 |
| **5** | **Destructive-cmd hook coverage divergent across 3 CLIs** — Claude blocks 10 patterns; Kimi blocks 5; Kiro blocks 7. Missing on Kimi+Kiro: `rm -rf .`, `DROP SCHEMA`, `TRUNCATE TABLE`, `--force-with-lease`. | **all 3** | Claude M4 |
| **6** | **SSOT orchestrator write-scope wording vs per-CLI** — SSOT says orchestrator can write to all 4 framework dirs; each CLI's orchestrator.md says own dir + `.ai/` only (not sibling CLI dirs). Needs clarifying note. | **SSOT wording fix** | Kimi inconsistency #1 |
| **7** | **`.ai/sync.md` missing `agent-catalog` mapping** — catalog has been synced to all 3 CLIs' steering dirs but sync.md table+commands don't list it. Future re-sync would skip it. | **SSOT fix** | Kiro I-3/F-6 |
| **8** | **`framework-dir-guard.sh` doesn't protect `.ai/`** (all 3 CLIs' equivalents) — intentional (orchestrator writes there) but leaves subagents unprotected. Mitigated by fixing #3. | **all 3** (architectural) | Kiro BUG-3/F-3, Kimi cross-check confirms |
| **9** | **`.kimi/steering/agent-catalog.md` duplicate rule number 8** — two `8.` entries (infra-engineer rule + "all subagents report back"). Should be `8.` and `9.`. | **Kimi** (check if SSOT has same issue) | Kimi inconsistency #8 |
| **10** | **Unbound Kimi hook scripts** — `handoffs-remind.sh`, `git-dirty-remind.sh`, `git-status.sh` exist in `.kimi/hooks/` but may not be wired in `~/.kimi/config.toml`. Dead code if unwired. | **Kimi** | Kimi flaw #9, bloat #1/#2/#3 |
| **11** | **Kimi `framework-guard.sh` ownership claim wrong** — comment says `.ai/` is owned by kimi-cli. It's shared across all 3 CLIs per the contract. | **Kimi** (comment-only) | Kimi inconsistency #7 |
| **12** | **Kiro `doc-writer.json` scope drift** — includes `LICENSE`/`LICENSE.*`/`SECURITY.md`/`CODE_OF_CONDUCT.md` beyond catalog. Same drift in Claude's doc-writer prose (LICENSE*, README*). Not in Kimi (no path restriction). | **catalog update** (catalog is stale) | Kiro DRIFT-1/F-5/B-3, Claude crosscheck confirms |
| **13** | **Kiro `e2e-tester.json` extra test dirs** — includes `e2e/**`, `cypress/**` beyond catalog. Same extension in Claude's e2e-tester (+ `playwright/**`). Not in Kimi. | **catalog update** | Kiro DRIFT-3, Claude crosscheck confirms |
| **14** | **`.kimi/agents/system/coder-executor.md` missing reports-dir note** — prompt restricts "anywhere EXCEPT framework directories" but doesn't mention `.ai/reports/` restriction. | **Kimi** | Kimi flaw #6 |

---

## INFO — cosmetic, low priority, documented limitations

| # | Finding | Owner | Audits |
|---|---|---|---|
| **15** | **Claude reviewer has Edit+Write tools with no path restriction** — soft prompt enforcement only. Kiro's reviewer has hard `allowedPaths: [".ai/reports/**"]`. Kimi's reviewer.yaml same issue as Claude. | Claude + Kimi | Claude L1, Kimi flaw #8 |
| **16** | **Release-engineer can't enforce field-level writes** (package.json version field etc.) — shared architectural limitation across all 3 CLIs. No fix available at tool layer. | — (known limit) | Kiro DRIFT-4, all crosschecks |
| **17** | **Kiro hooks use `grep+sed` for JSON parsing** — fragile vs. Claude/Kimi which use Python. Could break on multiline JSON / escaped quotes. | Kiro | Kiro I-4b/F-7 |
| **18** | **Handoff numbering collisions in `to-kiro/done/`** — two `004-*` files, two `005-*` files. Convention says NNN is sequential per recipient. | housekeeping | Kiro I-5/B-4 |
| **19** | **`infrastructure/**` vs `infra/**` in Kiro infra-engineer allowlist** — dead duplicate; canonical is `infra/**`. | Kiro (subset of #4) | Claude NIT2 |

---

## BLOAT — cleanup candidates

| # | Finding | Action | Dependency? |
|---|---|---|---|
| **20** | `.ai/activity-log.md` (~5KB, legacy Kimi entries from 2026-04-17) — no CLI reads it | **Delete** | **⚠️ Fix #1 FIRST** — Kimi's hooks wrongly reference this path; deleting before the fix means hooks will still silently no-op after the hook-path fix but against a now-missing file. Actually wait: the hooks reference `.ai/activity-log.md` (same hyphen name). Deleting removes their broken anchor. After fix #1, hooks reference `.ai/activity/log.md`. So order: (a) fix #1, (b) delete this file. |
| **21** | `.ai/research/**` (15 files, ~115 KB, all superseded by landed SSOT) | **Archive** to `.ai/research/archive/<name>-2026-04-18.md` | None — safe whenever |
| **22** | Dead Kimi hook scripts (if unwired) — see #10 | Wire them or delete | Check `~/.kimi/config.toml` first |
| **23** | `.kiro/agents/doc-writer.json` redundant entries (`SECURITY.md`, `CODE_OF_CONDUCT.md` already matched by `*.md`) | Trim | Tied to #12 catalog decision |

---

## CLEAN — validated, no findings across audits

- **SSOT replicas byte-identical** to sources for orchestrator-pattern, karpathy-guidelines, agent-catalog (all 3 CLIs verified).
- **All 13 agent configs exist** in each CLI; tool arrays match catalog.
- **JSON validity** of all `.kiro/agents/*.json` files confirmed.
- **Root-file-policy steering text** is ADR-pointer-only in every CLI's 00-ai-contract.md (handoff 017/006/020 fixes landed).
- **Orchestrator prompts** all have ADR pointer (handoff 009/020 fixes).
- **Activity-log format** consistent across all 3 contracts (identity, timestamp, format rules).
- **Skill provenance** pointer present in `.kiro/skills/karpathy-guidelines/SKILL.md` (and Claude's).
- **Handoff protocol** — README, template, all 3 contracts describe the same lifecycle.
- **Sensitive-file-guard** — all 3 CLIs correctly block `.env*`, `*.key`, `*.pem`, SSH keys, `.aws/`, `.ssh/`.

---

## Owner attribution summary

Fixes needed per CLI:

**Claude (`.claude/**`, `CLAUDE.md`)**:
- Tighten root-file hook dotfile handling (part of #2)
- Add framework-dir denial to debugger (part of #3)
- Add path restriction to reviewer (or accept prompt-only) (#15)
- Expand destructive-cmd hook to canonical block-list (part of #5)

**Kimi (`.kimi/**`)**:
- Fix hook activity-log paths (#1) — **HIGHEST PRIORITY**
- Add dotfile allowlist to root-guard (part of #2)
- Fix duplicate rule number in agent-catalog.md (#9)
- Wire or remove unbound hooks (#10)
- Fix framework-guard.sh ownership comment (#11)
- Add reports-dir note to coder-executor prompt (#14)
- Add path restriction to reviewer (or accept prompt-only) (#15)
- Expand destructive-cmd hook (part of #5)

**Kiro (`.kiro/**`)**:
- Add dotfile allowlist to root-file-guard (part of #2)
- Add deniedPaths to debugger.json (part of #3)
- Tighten infra-engineer YAML glob (#4)
- Migrate hooks to Python JSON parsing (#17)
- Trim doc-writer.json redundant paths (#23)
- Renumber colliding handoffs (#18)
- Expand destructive-cmd hook (part of #5)

**Shared `.ai/` (orchestrator-writable)**:
- SSOT wording for orchestrator write-scope (#6)
- Add agent-catalog to sync.md (#7)
- Update agent-catalog to reflect doc-writer + e2e-tester scope extensions (#12, #13)
- Create destructive-cmd SSOT (optional — if user approves Q6 from earlier)
- Delete `.ai/activity-log.md` after #1 lands (#20)
- Archive `.ai/research/**` (#21)

---

## Suggested fix-order waves

**Wave 1 — highest-safety BLOCKER fixes (one cross-CLI session):**
- #1 Kimi hook paths (Kimi-only, fast)
- #2 Dotfile handling (all 3 CLIs, aligned solution)
- #3 Debugger framework-dir restriction (Claude + Kiro + Kimi prompt)

**Wave 2 — WARN cleanups (shared `.ai/` + per-CLI):**
- #4 Kiro infra-engineer YAML glob
- #5 Destructive-cmd hook alignment
- #6 SSOT wording clarification
- #7 sync.md agent-catalog entry
- #9, #10, #11, #14 Kimi housekeeping
- #12, #13 Catalog updates

**Wave 3 — BLOAT (post-Wave-1):**
- #20 Delete `.ai/activity-log.md`
- #21 Archive `.ai/research/**`

**Wave 4 — INFO / cosmetic (any time):**
- #15 Reviewer path restriction
- #17 Kiro hook JSON parsing
- #18 Handoff number collisions
- #23 Doc-writer redundant paths (tied to #12)

---

## Cross-audit agreement score

All three audits independently converged on: dotfile-at-root bug (#2), debugger framework-dir gap (#3), `.ai/activity-log.md` bloat (#20), `.ai/research/**` archival (#21). Very strong signal — these are the fixes most worth prioritizing.

Three of my findings (#5 destructive-cmd gaps, #15 Claude reviewer, Claude dotfile blanket half of #2) weren't caught by the other CLIs because they required cross-CLI comparison that only orchestrator had visibility for.

Several Kimi findings (#1 hook paths, #9 duplicate rule, #10 unbound hooks, #11 ownership comment) weren't caught by Claude or Kiro because they were deep in Kimi-native territory neither was asked to inspect.

Kiro's finding #7 (sync.md missing agent-catalog) was a good catch — it's a shared-SSOT drift that neither Claude nor Kimi noticed.
