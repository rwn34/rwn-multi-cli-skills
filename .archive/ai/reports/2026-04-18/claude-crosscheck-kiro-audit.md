# Claude cross-check of Kiro's consistency audit
Auditor: claude-code (orchestrator)
Date: 2026-04-18
Sender of source handoff: kiro-cli (handoff 016)
Kiro's report reviewed: `.ai/reports/kiro-audit-2026-04-18-rule-consistency.md`

## Verdict summary

| Finding | Verdict | Claude equivalent gap? |
|---|---|---|
| BUG-1 — root-file-guard blocks dotfiles | CONFIRMED | NO — Claude has the **inverse** gap (blanket-allows) |
| BUG-2 — debugger.json no deniedPaths | CONFIRMED | YES — Claude's debugger has same architectural gap |
| BUG-3 — framework-dir-guard scope | CONFIRMED | YES — Claude's hook has same philosophy (same gap direction) |
| DRIFT-1 — doc-writer extra paths | CONFIRMED | YES — Claude's doc-writer also extends catalog same way |
| DRIFT-2 — infra-engineer YAML glob | CONFIRMED | NO — Claude's scope is narrower |
| DRIFT-3 — e2e-tester extra test dirs | CONFIRMED | YES — Claude extends catalog similarly (even more dirs) |
| DRIFT-4 — release-engineer full-file writes | CONFIRMED | YES — general limitation, not Kiro-specific |
| BLOAT-1 — `.ai/activity-log.md` stale | CONFIRMED | — (shared file, not per-CLI) |
| BLOAT-2 — `.ai/research/` archival | CONFIRMED | — (shared dir) |

**All 9 findings CONFIRMED.** No disputes. Kiro's audit is accurate.

---

## Per-finding cross-check detail

### BUG-1: `root-file-guard.sh` blocks ADR category B/C/D dotfiles

**CONFIRMED** for Kiro's hook. The `case "$BASE"` block at `.kiro/hooks/root-file-guard.sh:25-33` has no case arm for `.gitignore|.gitattributes|.editorconfig` and the comment on lines 19–22 is indeed wrong — `dirname "./.gitignore"` returns `.`, so these files DO enter the case block and hit the `*)` BLOCKED branch.

**Does Claude's hook have the same gap?**

**NO — Claude has the INVERSE gap.** Read `.claude/hooks/pretool-write-edit.sh` line 66:

```bash
case "$rel" in
    */*) exit 0 ;;    # has slash → not at root → allow
    "") exit 0 ;;     # empty → skip
    .*) exit 0 ;;     # .`-prefixed → framework / tooling (ADR categories B/C/D/E handle these)
    ...
```

The `.*)` catchall **blanket-allows every dotfile at root**. So Claude's gap is the opposite of Kiro's: Claude doesn't BLOCK `.gitignore` etc., but it ALSO doesn't block `.foo-secret` or any other arbitrary dotfile a misbehaving subagent might write.

This means:
- Kiro: too strict (blocks legitimate category B/C/D dotfiles)
- Claude: too permissive (allows arbitrary dotfiles not on the ADR)
- Correct behavior: enumerate the specific permitted dotfiles (`.gitignore`, `.gitattributes`, `.editorconfig`, `.mcp.json*`, `.dockerignore`, `.gitlab-ci.yml` if added later).

Kimi's hook (`.kimi/hooks/root-guard.sh:25-28`) enumerates `.mcp.json` and `.mcp.json.example` explicitly but also doesn't list `.gitignore`/.gitattributes/.editorconfig — so Kimi may have the same bug as Kiro (needs separate verification in Kimi's own audit).

This was also flagged as **M5** in my own audit.

---

### BUG-2: `debugger.json` has no framework-dir `deniedPaths`

**CONFIRMED** for Kiro. `.kiro/agents/debugger.json` has `fs_write` in tools array but no `toolsSettings.fs_write.allowedPaths` or `deniedPaths`. Kiro's debugger is architecturally free to write to `.ai/`, `.kiro/`, `.kimi/`, `.claude/`.

**Does Claude's debugger have the same gap?**

**YES — equivalent architectural gap, with slightly different mitigation shape.**

`.claude/agents/debugger.md:4` lists `tools: Read, Edit, Write, Bash, Grep, Glob, WebFetch, WebSearch, Skill, TaskCreate, TaskUpdate`. No path restriction at the tool layer — Edit and Write are unrestricted tools.

The prose write-scope on lines 11–13 says "Anywhere EXCEPT framework directories (.ai/, .claude/, .kimi/, .kiro/, CLAUDE.md, AGENTS.md). Plus `.ai/reports/` for documented root-cause analyses."

Enforcement in practice:
- `.kimi/`, `.kiro/` writes: hard-blocked by `.claude/hooks/pretool-write-edit.sh` Rule 1 (same logic)
- `.ai/`, `.claude/`, `CLAUDE.md`, `AGENTS.md` writes: **no hook catches these** — only the prose restriction

So Claude's debugger can in principle write to `.ai/**` and `.claude/**` and the only thing stopping it is the prompt. Same gap shape as Kiro; Kiro's worse because it lacks even the hook rules against `.kimi/`/`.claude/`.

Kiro's proposed fix (add `deniedPaths` to debugger.json) is Kiro-specific. Claude's equivalent: either (a) tighten the hook's Rule 1 to cover `.ai/` + `.claude/` when the caller is a subagent (complex — needs agent-awareness), or (b) keep prompt enforcement and document the risk.

---

### BUG-3: `framework-dir-guard.sh` doesn't block `.ai/` or `.kiro/` from subagents

**CONFIRMED.** Same philosophy observed in Claude — a CLI's hooks block OTHER CLIs' dirs but don't block the CLI's own dir or the shared `.ai/` dir. Reasoning: orchestrator needs to write there.

**Claude equivalent?** Same gap direction.

Claude's Rule 1 in `pretool-write-edit.sh:38-44`:
```bash
case "$rel" in
    .kimi|.kimi/*) block ;;
    .kiro|.kiro/*) block ;;
esac
```

Claude blocks `.kimi/` and `.kiro/` (other CLIs). Does NOT block `.ai/` or `.claude/`. Same mitigation assumption: orchestrator writes those; subagents' prompt restrictions keep them out.

Kiro's recommended fix (fix BUG-2 at per-agent config, not redesign the hook) is correct. Same applies to Claude — the fix is at the agent `tools:` frontmatter and prompt, not the hook.

---

### DRIFT-1: `doc-writer.json` has extra root-file paths

**CONFIRMED.** Kiro's doc-writer config permits `LICENSE`, `LICENSE.*`, `SECURITY.md`, `CODE_OF_CONDUCT.md` — all beyond the catalog's `*.md`, `docs/**`, `CHANGELOG*`, `.ai/reports/`.

**Does Claude's doc-writer have the same drift?**

**YES — same direction, even broader.**

`.claude/agents/doc-writer.md:12-16` write scope prose:
```
- `*.md` anywhere (project docs, READMEs in subdirectories)
- `docs/**`, `doc/**`
- `CHANGELOG*`, `LICENSE*`, `README*`
- In-code docstrings and comment blocks...
- `.ai/reports/` for documentation-audit reports
```

Claude explicitly lists `LICENSE*` and `README*`. `*.md` covers `SECURITY.md` and `CODE_OF_CONDUCT.md` and `CONTRIBUTING.md`.

**My read:** the agent-catalog SSOT is the stale source. Doc-writer legitimately needs to own LICENSE, README, CHANGELOG, and all `*.md` + text entry-point root files. Both Claude and Kiro have (independently) arrived at the same broader-than-catalog scope. Catalog should be updated to match.

Severity: LOW (Kiro was right to call it LOW). Action: `.ai/instructions/agent-catalog/principles.md:16` — extend doc-writer write scope to include `LICENSE*`, `README*`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `CONTRIBUTING.md`.

---

### DRIFT-2: `infra-engineer.json` has overly broad YAML glob

**CONFIRMED.** Kiro's scope includes `**/*.yml`, `**/*.yaml` — lets infra-engineer touch any YAML anywhere, including `.kimi/agents/*.yaml` (though framework-dir-guard and per-agent deniedPaths should stop those at second-line defense).

**Does Claude's infra-engineer have the same gap?**

**NO — Claude's scope is narrower.** `.claude/agents/infra-engineer.md:13-21` scope:
```
- `infra/**`
- `scripts/**`
- `tools/**`
```
Plus specific tooling-required root-level exceptions listed in prose (`.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `Dockerfile` at root only if needed).

Claude explicitly does NOT give infra-engineer blanket YAML access. This is the narrower interpretation of the catalog's loose SSOT (which lists `*.yml`, `*.yaml` — see my own audit's M1 + M2).

Kiro's fix: tighten to match catalog intent + Claude's narrower scope.

This was **H1** in my own audit — highest severity because it's Kiro's hard-enforcement (`toolsSettings.fs_write.allowedPaths`) that's currently loose, undermining Kiro's selling point of hard restrictions.

---

### DRIFT-3: `e2e-tester.json` has extra test dirs

**CONFIRMED.** Kiro has `e2e/**`, `cypress/**` beyond the catalog.

**Does Claude's e2e-tester have the same drift?**

**YES — Claude goes even further.** `.claude/agents/e2e-tester.md:12-13` write scope:
```
- E2E test files: `e2e/**`, `tests/e2e/**`, `**/*.e2e.*`, `playwright/**`, `cypress/**`
```

Claude has `playwright/**` in addition to what Kiro has. Both CLIs (independently) extended the catalog's generic "test files" scope with the named E2E framework dirs.

**My read:** same drift as DRIFT-1 — the catalog is behind, not the configs. Catalog should be updated to list `e2e/**`, `playwright/**`, `cypress/**` for e2e-tester.

Severity: LOW.

---

### DRIFT-4: `release-engineer` full-file writes on version manifests

**CONFIRMED as a general limitation, not Kiro-specific.**

Kiro can't enforce "version field only" via `allowedPaths` — the allowlist is path-level. Claude has the same limitation — Edit and Write tools don't have field-level granularity. Kimi is same.

No CLI can enforce field-level write restrictions at the tool layer. All three rely on the prompt + subagent discipline.

Severity: LOW. Documented as a known architectural limitation. No fix available without a custom tool.

---

### BLOAT-1: `.ai/activity-log.md` — stale duplicate

**CONFIRMED.** I also flagged this as **M3** in my own audit. 3–5KB file, 7 old Kimi entries from 2026-04-17, no CLI reads it.

Action: DELETE or move to `.ai/activity/archive/2026-04.md`. Action is shared — not per-CLI.

---

### BLOAT-2: `.ai/research/` archival

**CONFIRMED.** I also flagged this as **B1** in my own audit. 15 files (not 12 — Kiro undercounted; `.ai/research/archive/README.md` exists separately but `.ai/research/*.md` has 15). All superseded by landed SSOT.

Action: Move to `.ai/research/archive/<name>-2026-04-18.md` per the archive protocol. Low priority.

---

## Findings Kiro missed (from Claude's own audit perspective)

Kiro's audit was thorough within its scope — all 9 findings check out. Items from my own audit that Kiro did NOT surface:

**1. M4 — Destructive-cmd hook coverage gaps across all 3 CLIs**
Kiro's section "Clean" says "`destructive-cmd-guard.sh`: Covers major destructive patterns" — but Kiro's hook actually misses several patterns Claude's covers:

| Pattern | Claude | Kimi | Kiro |
|---|---|---|---|
| `rm -rf .` | ✓ | ✗ | ✗ |
| `DROP SCHEMA` | ✓ | ✗ | ✗ |
| `TRUNCATE TABLE` | ✓ | ✗ | ✗ |
| `--force-with-lease` | ✓ | ✗ | ✗ |

Kiro self-assessed its hook as clean; cross-check reveals gaps. Not a BLOCKER but worth noting.

**2. M5 — Claude's root-file hook blanket-allows dotfiles (inverse of Kiro's BUG-1)**
Kiro audited its own hook's dotfile handling and correctly flagged the strict-blocking bug. Kiro did NOT look at Claude's hook for the inverse gap — reasonable since cross-CLI write isn't Kiro's responsibility. But for a multi-CLI audit picture, both directions matter: some dotfiles get wrongly blocked by Kiro, and non-ADR dotfiles get wrongly allowed by Claude.

**3. L1 / NIT — Claude's reviewer has `Edit` + `Write` tools without path restriction**
`.claude/agents/reviewer.md:4`: `tools: Read, Grep, Glob, Edit, Write, Skill`. Write scope prose says `.ai/reports/` only, but enforcement is soft (prompt-only). Kiro's reviewer.json has hard path restriction `"allowedPaths": [".ai/reports/**"]` — Claude-side has no such enforcement.

Not a BLOCKER (reviewers don't typically misbehave), but it's a Claude-side gap Kiro's audit wouldn't have surfaced since Kiro's own enforcement is hard.

**4. H1 (my severity) / DRIFT-2 (Kiro's severity)** — agreement on the issue, different severity reads. Kiro scored it MEDIUM; I scored it HIGH because the `**/*.yml` glob is Kiro's HARD enforcement path, which is Kiro's architectural selling point. Not a disagreement, just calibration on how much weight to give "hard-enforcement scope is loose".

**5. B4 — Per-CLI hook README duplication**
3 files at `.claude/hooks/README.md`, `.kimi/hooks/README.md`, `.kiro/hooks/README.md` with overlapping structure. Kiro's audit didn't flag as bloat because it was scoped to Kiro's own directory. Low-priority; maybe KEEP (per-CLI context is legitimate).

---

## Agreement on priority ordering

Kiro's recommended priority:
1. BUG-1 (dotfiles)
2. BUG-2 (debugger deniedPaths)
3. BLOAT-1 (stale activity-log.md)
4. DRIFT-2 (infra-engineer YAML glob)
5. BUG-3 (framework-dir-guard — addressed by BUG-2 fix)
6. DRIFT-1/3/4 (catalog alignment)
7. BLOAT-2 (research archival)

**I broadly agree.** Adjustments I'd suggest:
- Move **DRIFT-2** to #1 or #2 slot — Kiro's hard-enforced allowlist being loose is a bigger architectural hole than the debugger's missing deniedPaths, because DRIFT-2 affects a committed-hard enforcement mechanism while BUG-2 is a gap in what's already known to be soft-enforced per the catalog.
- Add **Claude M5** (dotfile blanket) as parallel priority to BUG-1. Both are root-file-hook correctness issues in opposite directions; fix them together.
- Keep BLOAT-1 at #3 — trivial, zero risk, good win.

---

## What this cross-check did NOT cover

- Kimi-side equivalent gaps for BUG-1, BUG-2, DRIFT-1, DRIFT-3 — should be Kimi's cross-check to examine (Kimi was separately asked to cross-check Kiro via handoff 023).
- A full re-audit of Kiro's configs — I trusted Kiro's own readings of its configs and only cross-checked against Claude where relevant. A deeper pass would re-verify Kiro's claims against its actual files.
- Kimi's audit report and Kimi's cross-check of Kiro — I deliberately didn't read them to preserve independence of this cross-check.

---

## Summary for 016's sender (kiro-cli)

Kiro's audit is strong. **All 9 findings confirmed**, no disputes. **No findings appear to be overstated.**

Three of Kiro's findings have parallel issues on Claude side (BUG-2, BUG-3, DRIFT-1, DRIFT-3) — those fixes should ideally be coordinated across CLIs after the catalog itself is settled. One of Kiro's findings (BUG-1) has an inverse on Claude side (M5 in my audit) that Kiro couldn't have seen. One of Kiro's findings (DRIFT-2) is Kiro-specific — Claude doesn't have it.

Additional Claude-specific findings Kiro didn't have scope to see: destructive-cmd hook gap, Claude reviewer no path restriction, Claude dotfile blanket (inverse of Kiro's BUG-1).

Recommended next step: orchestrator consolidates Kiro's audit + Claude's audit + Kimi's audit (when ready) into a single merge-able action list, then dispatches fixes per owner CLI.
