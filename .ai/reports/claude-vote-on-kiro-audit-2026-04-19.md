# Claude's vote on Kiro audit findings — 2026-04-19

Per handoff `017-vote-on-kiro-audit-findings.md` from kiro-cli.
Kiro's source report: `.ai/reports/kiro-audit-2026-04-18.md` (16 findings).
Cross-reference: `.ai/reports/claude-audit-2026-04-19.md`, `.ai/reports/consolidated-audit-2026-04-19.md`.

## Per-finding votes

| # | Finding | Vote | Notes |
|---|---|---|---|
| **BLOCKERs** |
| F-3 | doc-writer `**/*.md` allowedPaths lets subagent write any `.md` including framework dirs; hooks don't fire on subagents | **AGREE — strong** | Confirmed via re-read of `.kiro/agents/doc-writer.json`. This is the most serious finding — edit-boundary rule is effectively opt-out for any `.md` target. I missed this in my own audit scope (explicit gap flagged in my report's "Scope notes"). Proposed fix: narrow to `*.md` (root-level) + `docs/**/*.md` + named root files (`CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`). |
| F-4 | Kimi hooks `read JSON` stdin consumption — all 4 preToolUse hooks fail-open | **AGREE — strong** | Confirmed via re-read of `.kimi/hooks/root-guard.sh:6`, `framework-guard.sh:7`, `destructive-guard.sh:5`, `sensitive-guard.sh:6`. Pattern `read JSON` followed by `python -c "json.load(sys.stdin)"` consumes stdin before python reads. Your analysis explains Kimi's Wave 1 observation that "Pipe-tests on Windows bash were unreliable (all returned exit 0)" — not Windows, the hooks themselves. Kimi has been asked to pipe-test on their end to confirm (via handoff 027). |
| **WARNs** |
| I-1 | Orchestrator prompt says writes-to-4-dirs; hook blocks 2 of them; prompt misleading | **AMEND → INFO** | Agree prompt is misleading, but the SSOT's "Per-CLI nuance" paragraph (added 2026-04-18 Wave 2) already documents that per-CLI implementations narrow the SSOT permission. The prompt is correct at SSOT level; the hook is correct at CLI level. A subagent reading the orchestrator prompt understands it as SSOT intent. **If** you disagree and still think this is WARN, the fix is a 3-line addition to each CLI's orchestrator prompt clarifying the narrowing. Low-priority either way. |
| I-2 | `infra-engineer.json` prompt references stale paths (`Dockerfile*`, `**/*.yml`, `infrastructure/**`) | **AGREE → INFO (severity downgrade)** | Prompt text is free-form advisory; `allowedPaths` is the hard enforcement layer and is correctly tightened. Prompt drift is cosmetic, not a live bug. Already flagged in your own activity-log 2026-04-18 13:20 as "Wave 4 INFO follow-up". Keep that classification. |
| I-5 / F-5 | Kiro subagent configs have no `hooks` section — subagents may bypass hook guards | **AGREE — but conditional** | Agree this is a real concern **if** Kiro runtime does not inherit orchestrator-registered hooks to spawned subagents. This is empirically verifiable — please test by dispatching a trivial coder task that tries to write `evil.txt` at root and observe whether `root-file-guard.sh` fires. If it fires, downgrade F-5 to INFO (docs note only). If it doesn't, upgrade to BLOCKER (all 12 subagent configs need hook wiring). Requested explicitly in my handoff 013 to you. |
| F-1 | `tester.json` allowedPaths missing `*_test.*` and `*_spec.*` from catalog | **AGREE** | Minor but real — catalog is the authoritative scope doc. One-line fix. |
| F-2 | `e2e-tester.json` allowedPaths missing `playwright/**`, `**/*.e2e.*`, config patterns | **AGREE** | Same reasoning — catalog alignment. Bundle with F-1 fix. |
| **INFOs** |
| I-4 | Kiro destructive-cmd guard literal-case; Kimi lowercases; mixed-case bypasses Kiro | **AMEND → WARN** | Actually this IS exploitable — a malicious or confused subagent could issue `Drop Database production;` and Kiro's guard would miss it. Low probability but real. One-line fix: `CMD_LOWER=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')` at the top, then match against lowercase. I think WARN is right severity. |
| I-3 | doc-writer `**/*.md` broader than catalog | **AGREE — duplicate of F-3** | Same root issue; don't count twice in the matrix. My consolidated matrix already merged these. |
| F-6 | Handoff numbering collisions (010, 004, 005 reused in Kiro done/) | **AGREE — INFO** | Historical; no action needed unless someone relies on monotonic ordering. Flag for any future archival protocol. |
| B-1 | Unfilled `[TODO]` templates (SECURITY.md, CHANGELOG.md, etc.) | **AGREE — INFO, keep** | Intentional scaffolding; template pattern for new projects. Delete-when-instantiated, not audit-blocker. |
| B-2 | `docs/*/TEMPLATE.md` pollute `file://docs/**/*.md` resource loads | **AGREE — worth fixing** | Good catch. Moving to `docs/_templates/` is ~5 minutes and cleans up every agent that loads docs-as-resource. Propose upgrading B-2 to **INFO-actionable** (vs. INFO-noted) and bundling with the next doc-writer dispatch. |
| B-3 | Handoff `done/` accumulation (54 files) | **AGREE — INFO** | Time for an archival protocol. Mirror `.ai/activity/archive/` pattern: `.ai/handoffs/to-<cli>/archive/YYYY-MM/`. Propose dispatching to doc-writer after fix waves land. |
| B-4 | Duplicate audit reports (8 from 2026-04-18 cycle) | **AGREE — INFO, archive soon** | Matches my B1. After this vote cycle closes, move the 04-18 reports to `.ai/reports/archive/` keeping the consolidated + claude-audit-04-19 + this vote file as active. |
| B-5 | Kiro hooks README duplicates info in orchestrator.json hooks section | **DISAGREE — keep** | Docs and config serve different readers. README is for humans skimming the hook dir; JSON is for the runtime. Duplication is intentional. Same reasoning for `.kimi/hooks/README.md`. |

## Votes beyond Kiro's 16 (from Claude's audit + Kimi's audit)

The 22-finding consolidated matrix (`.ai/reports/consolidated-audit-2026-04-19.md`)
adds these beyond Kiro's 16 — Kiro is asked to vote on them via my handoff 013:

- **Claude finding** (matrix #6): `.claude/hooks/pretool-write-edit.sh` missing `*.p12|*.pfx` sensitive-pattern. **My self-vote: AGREE — WARN. Claude self-fix, one line.**
- **Claude finding** (matrix #5): `.kiro/hooks/sensitive-file-guard.sh` missing `id_ed25519*` (only `id_rsa*` blocked). **Kiro-owned; my vote: AGREE — WARN.**
- **Claude finding** (matrix #7, #11): `.kimi/hooks/README.md` stale path + incomplete allowlist description. **My vote: AGREE — WARN for #7 (doc↔behavior mismatch), INFO for #11 (just incomplete).**
- **Kimi finding** (matrix #9): `.kimi/agents/reviewer.yaml` `WriteFile`/`StrReplaceFile` without path restriction. **My vote: AGREE — WARN. Mirrors Claude's reviewer situation (which got a FORBIDDEN-paths prompt section in Wave 2).**
- **Kimi finding** (matrix #13): `.kimi/agents/system/coder-executor.md` prompt doesn't mention reports-dir restriction. **My vote: AGREE — WARN, one-line prompt fix.**
- **Kimi finding** (matrix #18): unbound Kimi hooks (`handoffs-remind.sh`, `git-dirty-remind.sh`, `git-status.sh`). **My vote: AGREE — INFO, either wire them or remove.**

## Proposed action plan

### Wave 4a — BLOCKERs (dispatch immediately)

1. **Kimi self-fix** — remove `read JSON` from all 4 preToolUse hooks. Switch to Claude's `input=$(cat)` + `echo "$input" | python` pattern or Kiro's direct-stdin-to-python pattern. Re-run pipe-tests to verify Wave 1 dotfile allowlist and Wave 2+3 destructive-guard now actually fire. **Handoff needed: `to-kimi/028-fix-hook-stdin-bug.md`** (after vote closes).
2. **Kiro self-fix** — tighten `.kiro/agents/doc-writer.json` allowedPaths from `**/*.md` to `*.md` + `docs/**/*.md` + named root files. **Kiro direct fix (own framework dir).**

### Wave 4b — WARNs that are one-line fixes (same wave or next)

3. **Claude self-fix** — add `*.p12|*.pfx` to `.claude/hooks/pretool-write-edit.sh` sensitive-pattern list.
4. **Kiro self-fix** — add `id_ed25519*` to `.kiro/hooks/sensitive-file-guard.sh`.
5. **Kiro self-fix** — add `*_test.*` and `*_spec.*` to `.kiro/agents/tester.json` (F-1).
6. **Kiro self-fix** — add `playwright/**`, `**/*.e2e.*`, config patterns to `.kiro/agents/e2e-tester.json` (F-2).
7. **Kiro self-fix** — lowercase-normalize `.kiro/hooks/destructive-cmd-guard.sh` (my AMEND on I-4).
8. **Kimi via handoff** — fix `.kimi/hooks/README.md` path (`.ai/activity/log.md`) and complete the allowlist description.
9. **Kimi via handoff** — add reports-dir restriction note to `.kimi/agents/system/coder-executor.md`.

### Wave 4c — verification + doc fixes

10. **Kiro empirical test** — does runtime inherit hooks to subagents? Result decides F-5 severity.
11. **SSOT clarification** (optional) — if any CLI still feels I-1 is WARN-worthy, add a clarifying sentence to the SSOT orchestrator-pattern about per-CLI narrowing. All 3 CLIs currently have this right at their own layer; SSOT is correct; the gap is purely explainability.
12. **Prompt-text drift** on `infra-engineer.json` (I-2) — cosmetic, Kiro fixes if doing above.

### Wave 5 — bloat cleanup (separate session)

13. Move `docs/*/TEMPLATE.md` → `docs/_templates/` (doc-writer dispatch, B-2).
14. Archive `.ai/reports/` 2026-04-18 files to `.ai/reports/archive/` (B-4).
15. Propose + implement handoff done/ archival protocol (B-3).

## Severity disputes

Two items where I propose a different severity than Kiro:

- **I-1 → INFO** (you had it as WARN) — see my note above. SSOT Per-CLI-nuance paragraph already documents the narrowing.
- **I-4 → WARN** (you had it as INFO) — mixed-case SQL exploit is real. Lowercase-normalize is one line.

Net: severity deltas cancel each other (one up, one down).

## Collaboration notes

- I filed handoff `013-audit-consensus-vote.md` to you (Kiro) asking for your vote on the **consolidated 22-finding matrix** (which includes Claude's + Kimi's findings you didn't see). Please complete that in addition to reading this vote file.
- I filed handoff `027-audit-consensus-vote.md` to Kimi (after your `026-vote-on-kiro-audit-findings.md` took the 026 slot). Shim at `026-audit-consensus-vote.md` explains the collision. Apologies — I didn't check inbox before filing.
- Once Kimi + Kiro vote tallies land, Claude synthesizes the consensus action plan and surfaces to user for wave-dispatch approval.

## Activity-log entry already prepended
See `.ai/activity/log.md` 2026-04-19 16:20 — claude-code entry for the consolidation + handoff dispatch context.
