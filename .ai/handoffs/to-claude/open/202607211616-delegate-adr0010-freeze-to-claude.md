---
Status: BLOCKED
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

## Blocker

**Precondition 2 fails. No freeze work was performed.** Handoff stays in `open/`
as `Status: BLOCKED` per protocol v4 step 5.

Checked by `claude` (auto pane, branch
`exec/claude/202607211616-delegate-adr0010-freeze-to-claude`, HEAD `f3d37e9`) at
2026-07-21 23:18 (UTC+7).

### Precondition 1 — `main` green on `gates`: SATISFIED

    $ gh run list --branch main --workflow gates --limit 3
    completed	success	chore(ai): add activity-log entry for auto-pane delegations	gates	main	push	29847936594	8s	2026-07-21T16:17:39Z
    completed	success	chore(ai): delegate ADR-0010 freeze and canonical .ai/ deletion root …	gates	main	push	29847900251	9s	2026-07-21T16:17:10Z
    completed	success	chore(ai): retire stale finalization report handoff to claude-cockpit	gates	main	push	29847512513	23s	2026-07-21T16:12:01Z

No version-bump-detective failure observed on `main`.

### Precondition 2 — canonical `.ai/` deletion root cause closed: NOT SATISFIED

`.ai/handoffs/to-kiro/open/202607211105-diagnose-canonical-ai-deletion.md` is
still present in `to-kiro/open/` and still reads:

    Status: OPEN
    Recipient: kiro
    Owner: kiro
    Auto: no

It has not been moved to `to-kiro/done/` (`glob .ai/handoffs/**/done/*canonical*`
→ no matches), and the most recent activity entry on the subject confirms the
diagnosis is still outstanding:

    .ai/activity/entries/20260721T114200Z-kimi-cli-worktree-deletion-incident-d95f.md
    - Decisions: Treat this as a live recurrence of the canonical-deletion bug already
      under investigation in `.ai/handoffs/to-kiro/open/202607211105-diagnose-canonical-ai-deletion.md`.
      … The root cause still needs Kiro's diagnosis.

Per this handoff's own instruction ("stop and report this blocker to
`kimi-cockpit`"), execution stopped before step 1. Nothing was archived, no
replicas were regenerated, no version was bumped, no PR was opened.

### Why stopping is the right call here, beyond the literal instruction

The freeze's first step is `git mv .ai/activity/log.md
.ai/activity/archive/log-pre-spool.md` and its last steps are a PR + merge —
i.e. it commits a large, tracked reorganisation of `.ai/` and then runs the
dispatcher lane. The unfixed bug deletes the canonical `.ai/` tree during
`dispatch-handoffs.sh --exec` and presents the wipe as ordinary unstaged
deletions. Landing the freeze while that is live is exactly the scenario the
diagnose handoff names as "what breaks first": a routine `git add -A` during the
freeze would commit the coordination plane's destruction on top of a commit that
legitimately moves a large part of it — making the two indistinguishable in
review.

### Unblock condition

Retire `202607211105-diagnose-canonical-ai-deletion.md` to `to-kiro/done/` with
the fix merged (it is `Auto: no` by design — it must be launched manually, never
via `dispatch-handoffs.sh --exec`). Then re-dispatch this handoff; both
preconditions will hold and the freeze can run unchanged.
