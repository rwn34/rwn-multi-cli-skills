# Kiro CLI consistency audit — 2026-04-18

Auditor: kiro-cli (per handoff 010)
Scope: All 4 tiers — shared policy, Kiro-native, sibling CLI cross-check, handoff queue hygiene

---

## Inconsistencies

| # | Rule | File A (says X) | File B (says Y) | Severity |
|---|---|---|---|---|
| I-1 | Root-file dotfile handling | `.claude/hooks/pretool-write-edit.sh` line 67: `.*) exit 0 ;;` — allows ALL dot-prefixed root files | `.kiro/hooks/root-file-guard.sh` lines 19–22: comment claims dotfiles are handled but they hit the BLOCKED case | BLOCKER |
| I-2 | Root-file dotfile handling | `.kimi/hooks/root-guard.sh`: dotfiles pass through because the `grep -q '/'` check passes them (no slash = root, but the case block has no dotfile catch-all — they hit `*) BLOCKED`) | `.claude/hooks/pretool-write-edit.sh`: explicit `.*) exit 0` catch-all | WARN |
| I-3 | Sync map completeness | `.ai/sync.md`: maps `karpathy-guidelines` and `orchestrator-pattern` | `.ai/instructions/agent-catalog/principles.md` → `.kiro/steering/agent-catalog.md` exists as a replica but is NOT listed in sync.md | WARN |
| I-4 | JSON parsing in hooks | `.claude/hooks/pretool-write-edit.sh`: uses `python` for JSON parsing | `.kimi/hooks/root-guard.sh`: uses `python3` with `python` fallback | INFO |
| I-4b | JSON parsing in hooks | `.kiro/hooks/root-file-guard.sh`: uses `grep` + `sed` for JSON parsing (fragile — breaks on multiline JSON, escaped quotes, or reordered keys) | `.claude/hooks/pretool-write-edit.sh`: uses `python` (robust) | INFO |
| I-5 | Handoff numbering | `.ai/handoffs/README.md`: "NNN — 3-digit sequence, per recipient" (implies unique) | `.ai/handoffs/to-kiro/done/`: two `004-*` files and two `005-*` files (collision) | INFO |
| I-6 | Agent naming | `.kiro/agents/coder.json`: agent name `coder` | `.kimi/agents/coder-executor.yaml`: agent name `coder-executor` | INFO (known) |

## Flaws

| # | Category | File + line | Description | Severity |
|---|---|---|---|---|
| F-1 | Live bug | `.kiro/hooks/root-file-guard.sh` lines 10–22 | ADR category B/C/D dotfiles (`.gitignore`, `.gitattributes`, `.editorconfig`) are blocked. `dirname "./.gitignore"` = `.` → enters case block → hits `*) BLOCKED`. Any agent writing these at root will be rejected. | BLOCKER |
| F-2 | Missing enforcement | `.kiro/agents/debugger.json` | No `deniedPaths` and no `allowedPaths` in `toolsSettings.fs_write`. Debugger can write to all 4 framework dirs (`.ai/`, `.kiro/`, `.kimi/`, `.claude/`), violating catalog rule "All subagents are denied write access to these paths." | BLOCKER |
| F-3 | Scope gap | `.kiro/hooks/framework-dir-guard.sh` | Only blocks `.kimi/*` and `.claude/*` writes. Does NOT block `.ai/*` or `.kiro/*` from subagents. Combined with F-2, debugger has unrestricted framework-dir access. | WARN |
| F-4 | Over-broad scope | `.kiro/agents/infra-engineer.json` `allowedPaths` | `**/*.yml` and `**/*.yaml` match ANY YAML file in the project, not just IaC/CI dirs. Catalog says "IaC/CI dirs only." Could overwrite `docs/openapi.yaml` or app config YAML. | WARN |
| F-5 | Scope drift | `.kiro/agents/doc-writer.json` `allowedPaths` | Includes `LICENSE`, `LICENSE.*`, `SECURITY.md`, `CODE_OF_CONDUCT.md` — root files outside catalog's doc-writer scope (`*.md`, `docs/**`, `CHANGELOG*`, `.ai/reports/`). Note: `*.md` already covers `SECURITY.md` and `CODE_OF_CONDUCT.md`, so those are redundant. `LICENSE`/`LICENSE.*` are genuinely extra. | WARN |
| F-6 | Missing sync entry | `.ai/sync.md` | `agent-catalog` instruction is replicated to all 3 CLIs' steering dirs but has no entry in the sync map table or copy commands. A future re-sync would miss it. | WARN |
| F-7 | Fragile parsing | `.kiro/hooks/root-file-guard.sh` line 4 | Uses `grep -o` + `sed` to extract JSON `path` field. Breaks on: multiline JSON, escaped quotes in path, keys in different order than expected. Claude and Kimi both use Python for this. | INFO |
| F-8 | Kimi dotfile gap | `.kimi/hooks/root-guard.sh` | Kimi's hook blocks unknown root files via case block but has no `.*) exit 0` catch-all for dotfiles. However, the `grep -q '/'` check may let some dotfile paths through depending on how Kimi formats the path. Needs pipe-testing to confirm. | WARN |

## Bloat

| # | Type | Location | Rationale for removal/consolidation | Savings |
|---|---|---|---|---|
| B-1 | Stale duplicate | `.ai/activity-log.md` (4,698 bytes) | Orphaned copy of activity log entries at `.ai/` root. Real log is `.ai/activity/log.md`. Not referenced by any config, contract, or hook. | 4.7 KB, reduces confusion |
| B-2 | Archival candidates | `.ai/research/` — 12 files, ~115 KB | All research fed into landed decisions (agent catalog, orchestrator pattern, hooks, template completeness). Referenced in ADR-0001. Move to `.ai/research/archive/` per archival protocol. | ~115 KB from active dir |
| B-3 | Redundant allowedPaths | `.kiro/agents/doc-writer.json` | `SECURITY.md` and `CODE_OF_CONDUCT.md` are already matched by `**/*.md`. Redundant entries. | Trivial (clarity) |
| B-4 | Handoff numbering collisions | `.ai/handoffs/to-kiro/done/` | Two `004-*` and two `005-*` files. Convention says NNN is sequential per recipient. Not harmful but noisy. | Convention hygiene |

## Clean — no findings

- **SSOT replicas:** All 3 Kiro steering replicas byte-identical to SSOT sources (orchestrator-pattern, karpathy-guidelines, agent-catalog). Verified via `diff`.
- **Tool arrays:** All 13 agent configs match the catalog's tool lists exactly.
- **JSON validity:** All 13 `.kiro/agents/*.json` files pass `json.load()`.
- **Orchestrator prompt:** Updated to ADR pointer (handoff 009 confirmed).
- **AI contracts:** All 3 CLIs (Kiro, Kimi, Claude) have ADR pointers for root-file policy — no stale inline re-listings.
- **Activity log format:** Consistent across all 3 contracts (identity, timestamp rule, terse format, prepend order).
- **Skill provenance:** `.kiro/skills/karpathy-guidelines/SKILL.md` has correct provenance pointer to `.ai/instructions/karpathy-guidelines/examples.md`.
- **Handoff protocol:** README, template, and all 3 contracts describe the same lifecycle.
- **sensitive-file-guard.sh:** Correctly blocks `.env*`, `*.key`, `*.pem`, SSH keys, `.aws/`, `.ssh/`.
- **destructive-cmd-guard.sh:** Covers `rm -rf`, `git push --force`, `git reset --hard`, `DROP TABLE/DATABASE`.
- **activity-log-inject.sh / activity-log-remind.sh:** Working correctly — inject context at spawn, remind at stop.
- **Kimi steering orchestrator-pattern.md:** First 30 lines match SSOT (Companion doc line, .ai/ lede present).

## Cross-CLI equivalence summary

| Check | Claude | Kimi | Kiro |
|---|---|---|---|
| Root-file hook allows dotfiles | ✅ `.*) exit 0` | ⚠️ Unclear — needs pipe-test | ❌ Blocks them (BUG) |
| JSON parsing in hooks | ✅ Python | ✅ Python3/Python fallback | ⚠️ grep+sed (fragile) |
| Debugger framework-dir denial | Need to check | Need to check | ❌ Missing |
| Sync map covers all instructions | ⚠️ Missing agent-catalog | ⚠️ Missing agent-catalog | ⚠️ Missing agent-catalog |
| Orchestrator .ai/ write rule surfaced | ✅ Line 13 of orchestrator.md | ✅ Line 3 of system/orchestrator.md | ✅ Lede in principles.md |

## Recommended priority

1. **F-1 / I-1** (BLOCKER): Fix Kiro's root-file-guard to allow dotfiles — add `.gitignore|.gitattributes|.editorconfig) exit 0 ;;` or a `.*) exit 0 ;;` catch-all matching Claude's approach.
2. **F-2** (BLOCKER): Add `deniedPaths` to debugger.json for all 4 framework dirs.
3. **B-1**: Delete `.ai/activity-log.md` — zero risk, immediate clarity gain.
4. **F-4**: Tighten infra-engineer YAML glob to IaC-specific dirs only.
5. **F-6 / I-3**: Add agent-catalog to `.ai/sync.md` source→destination map + copy commands.
6. **F-3**: Either expand framework-dir-guard.sh to cover `.ai/` and `.kiro/` (with orchestrator exemption) or ensure all subagent configs have proper `deniedPaths`.
7. **F-5 / B-3**: Trim doc-writer allowedPaths to match catalog, or update catalog.
8. **I-5 / B-4**: Renumber colliding handoff files in `done/` (cosmetic).
9. **B-2**: Archive research files when convenient.
10. **I-4 / F-7**: Migrate Kiro hooks to Python-based JSON parsing (nice-to-have).
