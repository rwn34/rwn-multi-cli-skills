# ADR-0010 Wave-3 freeze — finish the entry-spool transition
Status: OPEN
Sender: kimi
Recipient: claude-cockpit
Owner: claude-cockpit
Created: 2026-07-21 15:55 (UTC+7)
Auto: yes
Risk: B
Observed-in: exec/kimi/20260721-adr0010-freeze-prep@edc2183
Evidence: VERIFIED (bash .ai/tests/test-render-activity-log.sh -> 3 passed, 0 failed; bash .ai/tests/test-sync-ai-state.sh -> 50 passed, 0 failed; bash scripts/git-hooks/test-pre-commit.sh -> 126 passed, 0 failed; bash .ai/tools/sync-replicas.sh --check -> Drift: 0; node .opencode/plugin/test-guard.mjs -> PASS 144 / FAIL 0)

## Goal

Complete the ADR-0010 Wave-3 freeze: move the project from the prepend-whole-file `.ai/activity/log.md` model to the entry-per-file spool (`.ai/activity/entries/*.md`) as the source of truth. Kimi has finished all work in `.ai/`, `scripts/`, and the OpenCode guard lane; the remaining changes touch `.claude/`, `.kimi/`, `.kiro/`, `opencode.json`, versioning, and the ADR closure.

## Current state

- `exec/kimi/20260721-adr0010-freeze-prep` contains:
  - `.ai/tools/render-activity-log.sh` + test
  - `.ai/instructions/operating-prompt/principles.md` updated to describe the spool; replicas regenerated
  - `.ai/tools/sync-ai-state.sh`: removed `merge_activity_log()`, removed `activity/log.md` sync-back special case, added `activity/log.md` exclusion to `manifest_for()`
  - `AGENTS.md`, `CLAUDE.md`, `.ai/README.md`, `.ai/tools/README.md`, `.ai/known-limitations.md`, `.ai/sync.md` updated
  - `.opencode/contract.md`, `.opencode/lib/lane.js`, `.opencode/plugin/test-guard.mjs` updated so OpenCode's writable lane is `.ai/activity/entries/**` only
  - `scripts/git-hooks/pre-commit` + `test-pre-commit.sh` updated: blocks entry-file deletions and staging of generated `log.md`
  - `.gitignore` excludes `.ai/activity/log.md`
  - All relevant tests pass (see Evidence).

## Target state

1. `.ai/activity/log.md` is moved into the archive and is no longer tracked by git.
2. Every CLI-native contract/hook that tells the CLI to "prepend to `.ai/activity/log.md`" is updated to "write an entry file under `.ai/activity/entries/` and run `bash .ai/tools/render-activity-log.sh`".
3. `opencode.json` references the new activity-log protocol.
4. Framework version is bumped and `CHANGELOG.md` documents the freeze.
5. `docs/architecture/0010-activity-log-spool.md` (or the relevant ADR) is marked closed/decided.
6. `.ai/instructions/self-grep-verify/principles.md` SSOT is updated so Tier 2 activity-log discipline describes the entry-spool model, and all replicas are regenerated.

## Steps

1. In the primary checkout (this repo), switch to or continue on `exec/kimi/20260721-framework-finalization`.
2. Archive the pre-spool log:
   ```bash
   mkdir -p .ai/activity/archive
   git mv .ai/activity/log.md .ai/activity/archive/log-pre-spool.md
   ```
3. Ensure `.ai/activity/log.md` is gitignored (already done in edc2183 / 31fcddd).
4. Update `.ai/instructions/self-grep-verify/principles.md` SSOT to describe the entry-spool model:
   - Tier 2 section: change "Entries in `.ai/activity/log.md`" to "Entries in `.ai/activity/entries/*.md`" and "prepended in bulk" to "written as entry files".
   - Update the committed-object example to grep across `.ai/activity/entries/*.md` rather than reading `.ai/activity/log.md` wholesale.
5. Run `bash .ai/tools/sync-replicas.sh` to regenerate `.claude/skills/self-grep-verify/SKILL.md`, `.kimi/steering/self-grep-verify.md`, and `.kiro/steering/self-grep-verify.md`. You are the only CLI that can commit all three replica paths atomically with the SSOT change (pre-commit allows claude-code to commit registered replicas under `.kimi/` and `.kiro/`).
6. Update `.claude/` native files that reference prepend/log.md:
   - `.claude/hooks/stop-reminder.sh` (reminder 1 pre-freeze branch wording)
   - `.claude/agents/orchestrator.md` (Activity log section)
   - `.claude/hooks/README.md` (stop-reminder table row)
   - `.claude/hooks/test_hooks.sh` (only if still references prepend after replica sync)
   - any `.claude/skills/*` not covered by sync-replicas (operating-prompt/delivery-integrity/self-grep-verify/orchestrator-pattern replicas already regenerated)
7. Update `.kimi/` native files (Kimi cannot commit these; you can because claude-code is allowed to commit registered replicas, and `.kimi/steering/00-ai-contract.md` plus `.kimi/hooks/*` are NOT replicas — they must be committed by Kimi. **Skip these and route to a separate Kimi handoff if any still need changes.** The current branch already has Kimi's contract/hook updates from commit 297de1a.)
8. Update `opencode.json` for the new protocol.
9. Bump `.ai/.framework-version` framework_version and installer_version to the next appropriate version (check current value first).
10. Add a `CHANGELOG.md` entry under `## Unreleased` documenting the ADR-0010 Wave-3 freeze.
11. Mark the ADR in `docs/architecture/` as closed/decided (add a "Status: CLOSED" frontmatter line or update the decision section).
12. Run the verification commands below. If green, commit with a message like `feat(adr0010): Wave-3 freeze — entry spool is the source of truth`.

## What is intentionally NOT in this handoff

- `.kiro/steering/00-ai-contract.md` and `.kiro/hooks/guards.json` still contain "prepend" language. These are **Kiro-native, non-replica files** and cannot be committed by claude-code. They are routed to Kiro in `.ai/handoffs/to-kiro/open/20260721T111700Z-kiro-contract-post-freeze-cleanup.md`.

## Verification

```bash
bash .ai/tests/test-render-activity-log.sh
bash .ai/tests/test-sync-ai-state.sh
bash scripts/git-hooks/test-pre-commit.sh
bash .ai/tools/sync-replicas.sh --check
node .opencode/plugin/test-guard.mjs
bash .ai/tools/check-changelog-unreleased.sh origin/main HEAD
```

## Next step / future note

After this handoff is retired, switch back to `exec/kimi/20260721-framework-finalization` so Kimi can continue Phase 6 (live claude→kimi→kiro→opencode→claude handoff chain) and Phase 7 (finalization report + retire the orchestrator handoff `.ai/handoffs/to-kimi-cockpit/open/202607210500-kimi-orchestrator-handover.md`).