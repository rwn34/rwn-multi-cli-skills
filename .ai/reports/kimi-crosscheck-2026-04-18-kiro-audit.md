# Kimi cross-check of Kiro's audit findings

Cross-checker: kimi-cli  
Date: 2026-04-18  
Kiro report: `.ai/reports/kiro-audit-2026-04-18-rule-consistency.md`

---

## Per-finding verdict

### Bugs

| # | Finding | Kiro verdict | Kimi cross-check | Verdict |
|---|---|---|---|---|
| BUG-1 | `root-file-guard.sh` blocks ADR B/C/D dotfiles | CRITICAL | **CONFIRMED + SHARED** — `.kimi/hooks/root-guard.sh` has the EXACT same gap. Case statement L25–26 covers Category A + `.mcp.json*` but omits `.gitignore`, `.gitattributes`, `.editorconfig`. Both hooks will block legitimate dotfile writes at root. | CONFIRMED |
| BUG-2 | `debugger.json` has no path restrictions | HIGH | **NUANCED** — Kimi's `.kimi/agents/debugger.yaml` has `WriteFile`/`StrReplaceFile` in `allowed_tools` with no path restriction. Kimi lacks native `allowedPaths`/`deniedPaths` entirely, so ALL subagents are in the same boat — they rely on prompt discipline. The debugger prompt (`.kimi/agents/system/debugger.md`) does NOT explicitly say "do not write to framework dirs," which is a gap. But this is a Kimi-wide architectural limitation, not a debugger-specific config error. | NUANCED |
| BUG-3 | `framework-dir-guard.sh` doesn't block `.ai/` or `.kiro/` | MEDIUM | **CONFIRMED + SHARED** — `.kimi/hooks/framework-guard.sh` only blocks `.claude/` and `.kiro/`. It explicitly allows `.ai/` and `.kimi/` (comment says "kimi-cli owns these"). Same design choice on both sides: protect OTHER CLIs' dirs, not own. | CONFIRMED |

### Spec Drift

| # | Finding | Kiro verdict | Kimi cross-check | Verdict |
|---|---|---|---|---|
| DRIFT-1 | doc-writer has extra root-file paths | Low | **DISPUTED for Kimi** — Kimi's `doc-writer.yaml` has no path restriction at all. The prompt (`doc-writer.md`) restricts to `*.md`, `docs/**`, `CHANGELOG*`, `.ai/reports/` — matching catalog. No extra paths like `LICENSE`. | NOT APPLICABLE |
| DRIFT-2 | infra-engineer overly broad YAML glob | Medium | **DISPUTED for Kimi** — Kimi's `infra-engineer.yaml` has no path restriction. The prompt says allowed writes are `.github/**`, `scripts/**`, `infra/**`, `config/**`, `tools/**` — no broad `**/*.yml` glob. Kimi's prompt is tighter than Kiro's config. | NOT APPLICABLE |
| DRIFT-3 | e2e-tester has extra test dirs | Low | **DISPUTED for Kimi** — Kimi's `e2e-tester.yaml` has no path restriction. The prompt says `tests/e2e/**` and `.ai/reports/` only. No `cypress/**` mentioned. Matches catalog. | NOT APPLICABLE |
| DRIFT-4 | release-engineer allows full file writes | Low | **NUANCED** — Same known limitation as Kiro. Kimi's prompt says "version field only" but the tool layer can't enforce field-level restrictions. This is a prompt vs. config gap shared by both CLIs. | NUANCED |

### Bloat

| # | Finding | Kiro verdict | Kimi cross-check | Verdict |
|---|---|---|---|---|
| BLOAT-1 | `.ai/activity-log.md` stale duplicate | Delete now | **CONFIRMED** — File exists at `.ai/activity-log.md`, 4,698 bytes. Real log is at `.ai/activity/log.md`. Not referenced by any config, contract, or hook. | CONFIRMED |
| BLOAT-2 | Research files — archival candidates | When convenient | **CONFIRMED** — 12 files in `.ai/research/`, decisions landed. Archival protocol exists. | CONFIRMED |

---

## Kimi-specific gaps Kiro missed

Kiro's audit focused on Kiro-native files and did not deeply inspect Kimi's hooks. Kimi's own audit (handoff 022) found these, which Kiro's report does not mention:

1. **Wrong activity log path in Kimi hooks (BLOCKER)** — `.kimi/hooks/activity-log-inject.sh` and `.kimi/hooks/activity-log-remind.sh` both reference `.ai/activity-log.md` (hyphen) instead of `.ai/activity/log.md` (slash). The hooks silently no-op because the file never exists at the wrong path. Same bug in `.kimi/hooks/git-dirty-remind.sh` L9.

2. **Duplicate rule numbering in `.kimi/steering/agent-catalog.md`** — Two entries labeled `8.` (infra-engineer rule and the "all subagents report back" rule). Should be `8.` and `9.`.

3. **Unbound hook scripts in `.kimi/hooks/`** — `handoffs-remind.sh`, `git-dirty-remind.sh`, and `git-status.sh` exist but there is no evidence they are wired in `~/.kimi/config.toml`. If unbound, they are dead code.

4. **Kimi `framework-guard.sh` ownership claim** — The hook comment says ".ai/ and .kimi/ are allowed (kimi-cli owns these)." This is incorrect — `.ai/` is shared by all three CLIs, not owned by Kimi.

---

## Cross-CLI pattern observations

1. **Dotfile root gap is universal** — All three hooks (Claude's `pretool-write-edit.sh`, Kimi's `root-guard.sh`, Kiro's `root-file-guard.sh`) handle dotfiles differently:
   - **Claude**: Uses `case` with `.*) exit 0 ;;` — blanket allows all dotfiles at root (L66). This is the most permissive and matches ADR categories B/C/D/E.
   - **Kimi**: Case statement omits dotfiles entirely — would block them.
   - **Kiro**: Case statement omits dotfiles; comment incorrectly claims they're handled.

   **Recommendation**: Align all three hooks to Claude's pattern (`.*) exit 0 ;;`) or add an explicit dotfile arm. The ADR already permits these categories.

2. **Framework-dir guard asymmetry** — Each CLI's framework guard protects the OTHER two CLIs' dirs but not its own:
   - Kimi blocks `.claude/` + `.kiro/`
   - Kiro blocks `.kimi/` + `.claude/`
   - Claude blocks `.kimi/` + `.kiro/`
   
   This is intentional (don't cross-edit) but leaves `.ai/` unprotected by hooks. The catalog says "only orchestrator writes to framework dirs" — this is enforced by agent config (`allowedPaths` for Kiro, prompt for Kimi/Claude), not by hooks.

3. **Kimi's prompt-only enforcement is a systemic gap** — Every spec-drift item Kiro found is IMPOSSIBLE in Kimi because Kimi has no native path restriction. The prompts ARE the restriction. This means Kimi's audit surface is different: we check prompt wording, not config fields.

---

## Summary

| Category | Kiro findings | Kimi agrees | Kimi disputes / nuanced | Kimi additions |
|---|---|---|---|---|
| Bugs | 3 | 2 (BUG-1, BUG-3) | 1 (BUG-2 — systemic, not debugger-specific) | 3 (wrong hook paths, duplicate numbering, unbound hooks) |
| Spec drift | 4 | 0 | 4 (all Kiro-specific config fields) | 0 |
| Bloat | 2 | 2 | 0 | 0 |

**Bottom line**: Kiro's findings are accurate for the Kiro layer. The dotfile bug (BUG-1) is confirmed as a shared issue across Kimi and Kiro. The debugger path gap (BUG-2) manifests differently in Kimi but the underlying risk (subagent writing to framework dirs) is present. Kimi has its own hook-specific bugs that Kiro didn't catch.
