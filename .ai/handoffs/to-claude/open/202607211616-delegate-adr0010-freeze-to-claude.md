---
Status: OPEN
Sender: kimi-cockpit
Recipient: claude
Owner: claude
Created: 2026-07-21 23:16 (UTC+7)
Auto: yes
Risk: B
Base: origin/main
Observed-in: main@326a35c
Evidence: VERIFIED (bash .ai/tests/test-render-activity-log.sh -> 4/0; bash .ai/tests/test-sync-ai-state.sh -> 50/0; bash scripts/git-hooks/test-pre-commit.sh -> 126/0; bash .ai/tools/sync-replicas.sh --check -> Drift: 0; node .opencode/plugin/test-guard.mjs -> 144/0; gh pr view 134 -> state MERGED, mergeCommit c4e5db9, checks framework-check SUCCESS + gates SUCCESS)
ReturnTo: kimi-cockpit
---

# Delegate ADR-0010 Wave-3 freeze execution to claude-auto

## Background

The original freeze handoff `.ai/handoffs/to-claude-cockpit/open/20260721-adr0010-freeze-execution.md` is owned by `claude-cockpit` but the cockpit is delegating execution to the auto pane. This handoff carries the same work, with the additional constraint that **you must report completion or blocker status back to `kimi-cockpit`**.

## Precondition check (do NOT proceed if any fail)

1. `main` must be green on `gates`. If the version-bump detective is still failing ("Framework content changed but ... version was not bumped"), **stop and report this blocker to `kimi-cockpit`**. The owner must approve `0.0.53` first.
2. The canonical `.ai/` deletion root cause must be closed. If `.ai/handoffs/to-kiro/open/202607211105-diagnose-canonical-ai-deletion.md` is still OPEN, **stop and report this blocker to `kimi-cockpit`**.

Only proceed if both preconditions are satisfied.

## Work to perform

Execute the steps in `.ai/handoffs/to-claude-cockpit/open/20260721-adr0010-freeze-execution.md`:

1. Archive the pre-spool log atomically:
   ```bash
   mkdir -p .ai/activity/archive
   git mv .ai/activity/log.md .ai/activity/archive/log-pre-spool.md
   ```
2. Update `.ai/instructions/self-grep-verify/principles.md` SSOT if still needed (the Tier 2 spool-model update may already be done via PR #134; re-verify).
3. Run `bash .ai/tools/sync-replicas.sh` to regenerate replicas.
4. Update `.claude/hooks/stop-reminder.sh`, `.claude/agents/orchestrator.md`, `.claude/hooks/README.md`, and any other `.claude/` native files still referencing prepend/log.md.
5. Update `opencode.json` for the new protocol.
6. Bump `.ai/.framework-version` framework_version and installer_version to the next appropriate version.
7. Add a `CHANGELOG.md` entry documenting the freeze.
8. Mark the ADR in `docs/architecture/` as closed/decided.
9. Run the verification commands listed in the original freeze handoff.
10. Open a PR, run checks, and merge.

## Return path

When done (or blocked), create a return handoff addressed to `kimi-cockpit`:
- Place it in `.ai/handoffs/to-kimi-cockpit/open/`
- Name it `YYYYMMDDHHMM-claude-adr0010-freeze-return.md`
- Include: branch/PR number, final commit SHA, verification output, and any unresolved blockers

Do not self-retire this handoff; leave that to `kimi-cockpit`.
