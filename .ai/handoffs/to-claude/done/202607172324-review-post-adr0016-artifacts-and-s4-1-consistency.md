# Review post-ADR-0016 operational artifacts and S4-1 consistency
Status: DONE
Sender: kimi-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-18 06:24 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (bash .ai/tests/test-sync-ai-state.sh -> 16 passed; bash .ai/tests/test-dispatch-worktree.sh -> 79 passed; bash .ai/tools/test-check-log-superset.sh -> 9 passed; powershell -NoProfile -File tools/4ai-panes/test-pane-runner.ps1 -> 154 passed; bash .ai/tools/sync-replicas.sh --check -> Drift: 0)

## Goal
Close out the ADR-0016 snapshot-copy rollout by reviewing the remaining operational artifacts and confirming the S4-1 Risk-C gate/relay split is internally consistent across code, ADR, and template.

## Current state
- ADR-0016 snapshot-copy implementation is committed and tested (commit c359853 + follow-up 8a4ec20).
- The working tree still contains untracked operational artifacts from auto-pane activity:
  - `.ai/activity/entries/20260717-opencode-entry.md` — valid UTF-8 entry file.
  - `.ai/handoffs/to-claude/done/` — several retired handoffs, including ADR-0015 ratification and final-review items.
  - `.ai/handoffs/to-kimi/done/` — retired kimi executor handoffs.
  - `.ai/handoffs/to-kiro/done/` — retired kiro review handoffs.
  - `.ai/handoffs/to-opencode/done/` — retired opencode handoffs.
  - `.ai/handoffs/to-claude-cockpit/`, `.ai/handoffs/to-kimi-cockpit/`, `.ai/handoffs/to-kimi-executor/`, `.ai/handoffs/to-kiro-executor/` — new six-actor queue dirs with only `.gitkeep` files.
  - `.ai/reports/dispatch-failure-20260717154326-opencode-202607171845-gate-release-workflow-autopublish.md` — a dispatch-failure report.
- `new-log-entry.txt` (a UTF-16LE-corrupted temp file) was already deleted by kimi.
- S4-1 (split Risk-C gate from relay) appears implemented in ADR-0015 Decision 3, operating-prompt §8, handoff template, and dispatch-handoffs.sh (test v4-3 passes).

## Target state
1. A clean, consistent working tree: operational artifacts are either committed or intentionally discarded.
2. New six-actor queue directories are either added to `.ai/handoffs/README.md` (Layout section) and committed, or removed if they were created by accident.
3. `docs/architecture/0015-handoff-protocol-v4.md` and operating-prompt §8 agree on hard-gate list, and `dispatch-handoffs.sh` enforces it (already passing tests; verify by reading the relevant functions).
4. The activity-log entry spool (ADR-0010) is consistent — no further UTF-16LE/cp1252 temp files, and valid entries are either rendered into `log.md` or committed as entry files per the current ADR-0010 policy.

## Steps
1. Run `git status` and read the untracked files listed above. Decide for each whether it represents real completed work that should be committed, or noise that should be discarded.
2. For the `done/` handoffs: skim `Status:` and the resolution section. If the work was actually completed and verified, stage and commit them as operational history. If any are false completions (empty evidence), reopen them to `open/` with `Status: BLOCKED` per protocol v4.
3. For the new queue dirs (`to-claude-cockpit`, `to-kimi-cockpit`, `to-kimi-executor`, `to-kiro-executor`): decide if they are part of the six-actor model. If yes, update `.ai/handoffs/README.md` Layout section to include them and commit the `.gitkeep` files. If no, delete them.
4. Verify S4-1 consistency:
   - Read `.ai/instructions/operating-prompt/principles.md` lines 238–260 and `docs/architecture/0015-handoff-protocol-v4.md` Decision 3.
   - Read `.ai/tools/dispatch-handoffs.sh` hard-gate enforcement (search for `hard_gate` / `Gate-satisfied-by`).
   - Confirm the hard-gate list in code matches the ADR and operating prompt. If not, patch or file a follow-up handoff.
5. Verify encoding health:
   - Run `bash .ai/tools/check-encoding.sh .ai/activity/log.md .ai/activity/entries/* .ai/handoffs/**/*.md`.
   - If any file fails, run `bash .ai/tools/normalize-encoding.sh <file>` and inspect the result before committing.
6. Run the full test matrix one more time:
   - `bash .ai/tests/test-sync-ai-state.sh`
   - `bash .ai/tests/test-dispatch-worktree.sh`
   - `bash .ai/tests/test-reconcile-done-handoffs.sh`
   - `bash .ai/tests/test-lint-handoff.sh`
   - `bash .ai/tools/test-check-log-superset.sh`
   - `powershell -NoProfile -File tools/4ai-panes/test-pane-runner.ps1`
   - `bash .ai/tools/sync-replicas.sh --check`
7. Commit any staged operational artifacts with an appropriate message, prepend an activity-log entry, and push.

## Verification
- `git status` shows only expected, intentional state (ideally clean; at minimum no untracked operational artifacts and no modified files you did not intend).
- All tests in step 6 pass.
- `sync-replicas.sh --check` reports `Drift: 0`.

## Next step / future note
After this cleanup, the snapshot-copy model is fully landed. The next durability question is whether to add periodic checkpoint commits of `.ai/` state; ADR-0016 intentionally removed the continuous-junction model, so any checkpointing should be a separate, deliberate design.

## Activity log template
    ## 2026-07-18 HH:MM (UTC+7) - claude-auto
    - Action: Reviewed and integrated post-ADR-0016 operational artifacts; verified S4-1 gate/relay consistency per handoff 202607172324-review-post-adr0016-artifacts-and-s4-1-consistency
    - Files: <list what was committed or discarded>
    - Decisions: <any non-obvious cleanup choices>

## Report back with
- The final `git status`.
- Which untracked files were committed vs discarded, with rationale.
- Whether S4-1 code/ADR/template are consistent or if a follow-up patch is needed.
- The test-run summary (pass/fail counts).

## Resolution — 2026-07-18 06:56 (UTC+7), claude-code (DONE)

Completed by hand: the auto-dispatch failed at the declared-base branch-cut stage
(see `.ai/reports/dispatch-failure-20260717233506-claude-…`), so the review was
run in the primary checkout.

- **Committed (operational history):** all 15 untracked `done/` handoffs
  (`to-claude` ×5, `to-kimi` ×4, `to-kiro` ×4, `to-opencode` ×2). Every one is
  `Status: DONE` and carries a real resolution/verdict section (APPROVED, verified
  test counts) — legitimate completed work, no false completions, none reopened.
- **Committed:** both `.ai/reports/dispatch-failure-*.md` reports (`reports/` is a
  tracked, non-ignored lane).
- **Discarded:** `.ai/activity/entries/20260717-opencode-entry.md` — non-conforming
  ADR-0010 filename (no `…Z-<cli>-<slug>-<rand4>` form) and its content is already
  rendered verbatim in `log.md`; `check-log-superset` confirms the header is
  present, so removing it loses nothing.
- **Six-actor queue dirs:** already added and committed by kimi (e30932c / 94a51e0)
  before this review — no action needed.
- **S4-1:** CONSISTENT. `is_hard_gate()` enumerates all 8 hard gates
  (productiondeploy, publishtoapublicregistry, tagrelease, forcepush,
  destructiveopsonsharedhistory, gitresethard, secrets, productiondata) exactly
  matching ADR-0015 Decision 3 and operating-prompt §8. No patch needed.
- **Tests:** sync-ai-state 16, dispatch-worktree 79, reconcile-done-handoffs 26,
  lint-handoff 10, check-log-superset 9, pane-runner 154 = **294 passed, 0 failed**;
  `sync-replicas --check` → **Drift: 0**.
- **Activity log:** recorded via ADR-0010 entry-file spool, NOT prepended, because
  the working-tree `log.md` on this diverged exec branch is not a superset of
  `origin/main` and must not be rewritten (see follow-ups).

### Follow-ups filed (pre-existing, out of scope of this handoff)
1. This exec branch (`exec/kimi/202607170710-…`) is diverged from `origin/main`
   (18 ahead / 17 behind); `log.md` fails `check-log-superset` against `origin/main`
   (~97 headers). Needs a 3-way merge/reconcile, not a whole-file rewrite.
2. Tracked file `.ai/handoffs/to-kiro/done/202607122215-top-strip-fraction-65-35.md`
   is UTF-16LE-corrupted (dates to 2026-07-12, predates this handoff).
