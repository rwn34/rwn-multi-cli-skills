# Kimi CLI consistency audit — 2026-04-18

Audited ~30 files across shared policy, Kimi-native, and sibling-CLI layers.

---

## Inconsistencies

| # | Rule | File A (says X) | File B (says Y) | Severity |
|---|---|---|---|---|
| 1 | Orchestrator write scope | SSOT `.ai/instructions/orchestrator-pattern/principles.md` L17: orchestrator can write to `.ai/`, `.kiro/`, `.kimi/`, `.claude/` | Claude `.claude/agents/orchestrator.md` L13: orchestrator writes only `.ai/`, `.claude/`, `CLAUDE.md`, `AGENTS.md` — **read-only** for `.kimi/` and `.kiro/` | WARN |
| 2 | Root dotfile allowlist | ADR-0001 categories B/C/D allow `.gitignore`, `.gitattributes`, `.editorconfig` at root | Kimi `.kimi/hooks/root-guard.sh` L25–26: case statement does NOT include dotfiles — only Category A + `.mcp.json*` | BLOCKER |
| 3 | Root dotfile allowlist (same as #2) | ADR-0001 categories B/C/D | Kiro `.kiro/hooks/root-file-guard.sh` L10–22: case statement does NOT include dotfiles | BLOCKER |
| 4 | Activity log path | Actual file: `.ai/activity/log.md` (slash) | Kimi `.kimi/hooks/activity-log-inject.sh` L4: checks `.ai/activity-log.md` (hyphen) | BLOCKER |
| 5 | Activity log path (same as #4) | Actual file: `.ai/activity/log.md` | Kimi `.kimi/hooks/activity-log-remind.sh` L4: checks `.ai/activity-log.md` | BLOCKER |
| 6 | Hook JSON parsing | Kimi hooks use `python3` then `python` fallback | Kiro hooks use `grep` + `sed` (no python) | INFO |
| 7 | Framework dir ownership | `.ai/` is shared by all CLIs per `.ai/README.md` | Kimi `.kimi/hooks/framework-guard.sh` L4: ".ai/ and .kimi/ are allowed (kimi-cli owns these)" | INFO |
| 8 | Agent catalog rule numbering | `.kimi/steering/agent-catalog.md` L317: `8. **Infra-engineer** handles git operations...` | `.kimi/steering/agent-catalog.md` L318: `8. All subagents report back...` — duplicate "8." | WARN |

## Flaws

| # | Category | File + line | Description | Severity |
|---|---|---|---|---|
| 1 | Live bug | `.kimi/hooks/root-guard.sh` L25–26 | Blocks legitimate ADR-approved dotfiles (`.gitignore`, `.gitattributes`, `.editorconfig`) at root because case statement omits them | BLOCKER |
| 2 | Live bug | `.kimi/hooks/activity-log-inject.sh` L4–6 | Looks for `.ai/activity-log.md` (hyphen) instead of `.ai/activity/log.md` (slash). Hook silently no-ops because file never exists at wrong path | BLOCKER |
| 3 | Live bug | `.kimi/hooks/activity-log-remind.sh` L4 | Same wrong path — mtime check on non-existent file means reminder never fires | BLOCKER |
| 4 | Live bug | `.kimi/hooks/git-dirty-remind.sh` L9 | Grep pattern `activity-log.md` and `\.ai/activity-log\.md` both use hyphen path; should be `activity/log.md` | WARN |
| 5 | Live bug | `.kimi/hooks/activity-log-inject.sh` L5 | Header text says "top of .ai/activity-log.md" — wrong filename displayed to user | INFO |
| 6 | Prompt drift | `.kimi/agents/system/coder-executor.md` L7 | Says "write anywhere EXCEPT framework directories" — does not mention reports dir restriction from catalog | WARN |
| 7 | ~~Handoff hygiene~~ | ~~`.ai/handoffs/to-claude/open/014-final-review-template-cleanup.md`~~ | ~~Already moved to `done/` — finding retracted.~~ | ~~—~~ |
| 8 | Enforcement gap | `.kimi/agents/reviewer.yaml` L13–14 | `WriteFile`/`StrReplaceFile` in allowed_tools with no path restriction. Prompt restricts to `.ai/reports/` but tool layer doesn't enforce it | WARN |
| 9 | Hook coverage gap | `.kimi/hooks/handoffs-remind.sh`, `git-dirty-remind.sh`, `git-status.sh` | Exist in `.kimi/hooks/` but no evidence they are wired up in `~/.kimi/config.toml`. If unbound, they are dead code that could confuse maintainers | INFO |
| 10 | Missing report | `.ai/reports/` | Directory exists with only `README.md`. No actual diagnostic reports written yet despite multiple reviewer/security-auditor sessions | INFO |

## Bloat

| # | Type | Location | Rationale for removal/consolidation | Savings |
|---|---|---|---|---|
| 1 | Dead code (if unbound) | `.kimi/hooks/handoffs-remind.sh` | If not wired in `~/.kimi/config.toml`, this script is unreachable | 14 lines |
| 2 | Dead code (if unbound) | `.kimi/hooks/git-dirty-remind.sh` | If not wired in `~/.kimi/config.toml`, this script is unreachable | 15 lines |
| 3 | Dead code (if unbound) | `.kimi/hooks/git-status.sh` | If not wired in `~/.kimi/config.toml`, this script is unreachable | ~? lines |
| 4 | Duplicate "Docs resource" section | `.kimi/agents/system/*.md` (all 13 agents) | Every agent prompt repeats the same 4-bullet docs path list. Could be a single shared pointer, but each prompt is independent by design — marginal | INFO |

## Clean — no findings

- **Tier 1 shared policy**: All SSOT files are internally consistent. `.ai/sync.md` copy-command map is complete for current instructions.
- **Tier 2 Kimi steering replicas**: `.kimi/steering/orchestrator-pattern.md` is byte-identical to SSOT (just re-synced). `.kimi/steering/karpathy-guidelines.md` is byte-identical to SSOT.
- **Tier 3 sibling CLI cross-check**: Kiro's `.kiro/agents/orchestrator.json` prompt now correctly points to ADR-0001 (fixed in handoff 009). Kiro's `.kiro/steering/00-ai-contract.md` correctly points to ADR.
- **Kimi agent configs**: All 13 `.kimi/agents/*.yaml` files exist and use consistent `extend: default` pattern.
- **Kimi orchestrator prompt**: Root-file policy correctly points to ADR-0001 (fixed in handoff 020).

---

## Recommendations by priority

### BLOCKER (fix immediately)
1. **Fix Kimi hook paths** — `.kimi/hooks/activity-log-inject.sh` and `activity-log-remind.sh` reference `.ai/activity-log.md` → should be `.ai/activity/log.md`. Also fix `git-dirty-remind.sh` grep pattern.
2. **Fix Kimi root-guard dotfiles** — Add `.*)` or explicit `.gitignore|.gitattributes|.editorconfig` to the case statement in `.kimi/hooks/root-guard.sh` to match ADR categories B/C/D.
3. **Fix Kiro root-file-guard dotfiles** — Same issue in `.kiro/hooks/root-file-guard.sh`. Kiro should fix via its own handoff.

### WARN (fix this session)
4. **Fix agent-catalog rule numbering** — Change second "8." to "9." in `.kimi/steering/agent-catalog.md` L318.
5. **Clarify SSOT orchestrator write scope** — Add a note in `.ai/instructions/orchestrator-pattern/principles.md` that per-CLI implementations may further restrict the orchestrator from writing to sibling CLI folders (Claude can't write `.kiro/` or `.kimi/`).

### INFO (nice-to-have)
7. **Audit unbound Kimi hooks** — Check `~/.kimi/config.toml` to see if `handoffs-remind.sh`, `git-dirty-remind.sh`, `git-status.sh` are wired. If not, either wire them or remove them to avoid confusion.
8. **Write first diagnostic report** — Next time `reviewer` or `security-auditor` runs, have it write to `.ai/reports/` to validate the naming convention and directory structure.
