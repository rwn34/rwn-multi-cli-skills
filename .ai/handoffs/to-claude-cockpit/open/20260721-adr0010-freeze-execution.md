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

## Steps

1. In the primary checkout (this repo), switch to or continue on `exec/kimi/20260721-adr0010-freeze-prep`.
2. Archive the pre-spool log:
   ```bash
   mkdir -p .ai/activity/archive
   git mv .ai/activity/log.md .ai/activity/archive/log-pre-spool.md
   ```
3. Ensure `.ai/activity/log.md` is gitignored (already done in edc2183).
4. Update `.claude/` files that reference prepend/log.md:
   - `.claude/hooks/stop-reminder.sh`
   - `.claude/settings.json`
   - `.claude/agents/orchestrator.md`
   - `.claude/hooks/README.md`
   - `.claude/hooks/test_hooks.sh`
   - any `.claude/skills/*` not covered by sync-replicas (operating-prompt/delivery-integrity/self-grep-verify/orchestrator-pattern replicas already regenerated)
5. Update `.kimi/` files:
   - `.kimi/steering/00-ai-contract.md`
   - `.kimi/hooks/activity-log-remind.sh`
   - `.kimi/hooks/activity-log-inject.sh`
   - `.kimi/hooks/git-dirty-remind.sh`
   - `.kimi/hooks/README.md`
   - `.kimi/hooks/test_hooks.sh`
6. Update `.kiro/` files:
   - `.kiro/steering/00-ai-contract.md`
   - `.kiro/hooks/activity-log-remind.sh`
   - `.kiro/hooks/activity-log-inject.sh`
   - `.kiro/hooks/guards.json`
   - `.kiro/hooks/handoff-queue-count.sh`
   - `.kiro/hooks/README.md`
   - `.kiro/hooks/test_hooks.sh`
   - `.kiro/agents/*.json`
7. Update `opencode.json` for the new protocol.
8. Run `bash .ai/tools/sync-replicas.sh --check` and fix any drift.
9. Bump `.ai/.framework-version` framework_version and installer_version to 0.0.47 (or next appropriate).
10. Add a `CHANGELOG.md` entry under `## Unreleased` documenting the ADR-0010 Wave-3 freeze.
11. Mark the ADR in `docs/architecture/` as closed/decided (add a "Status: CLOSED" frontmatter line or update the decision section).
12. Run the verification commands below. If green, commit with a message like `feat(adr0010): Wave-3 freeze — entry spool is the source of truth`.

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