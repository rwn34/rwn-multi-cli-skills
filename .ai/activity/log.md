## 2026-07-17 11:57 (UTC+7) — kimi-cli
- Action: Re-implemented and committed ADR-0015 v4 fixes on `exec/kimi/202607171103-adr-0015-v4-fixes` after recovering from a stray `decoy/should-not-be-base` checkout; all verification commands green.
- Files: `.ai/tools/dispatch-handoffs.sh`, `.ai/tools/lint-handoff.sh`, `.ai/tests/test-dispatch-worktree.sh`, `docs/specs/handoff-protocol-v4.md`, `.ai/reports/kimi-202607170335-adr-0015-v4-fixes-report.md`
- Decisions: Used primary worktree; normalized hard-gate matching by lowercasing + stripping non-alphanumeric; left report in repo. Branch pushed and ready for Kiro review; do not merge to main.

---

## 2026-07-17 11:47 (UTC+7) — kimi-auto
- Action: Completed handoff 202607170335-implement-adr-0015-v4-fixes.
- Files: `.ai/tools/dispatch-handoffs.sh`, `.ai/tools/lint-handoff.sh`, `.ai/tests/test-dispatch-worktree.sh`, `docs/specs/handoff-protocol-v4.md`
- Decisions: Implemented ADR-0015 fixes in the primary worktree because the exec worktree's skip-worktree guard reverts `.ai/**` edits; left changes uncommitted per the handoff constraint. Full suite green: 77/77 in `bash .ai/tests/test-dispatch-worktree.sh`.

---

## 2026-07-17 12:00 (UTC+7) — opencode
- Action: Completed handoff 202607170350-commit-adr-0015-and-replicas. Resolved skip-worktree blocker by clearing the bit on `.ai/instructions/operating-prompt/principles.md` in exec tree, staging SSOT + ADR + replicas + `.ai/` housekeeping, committing (SHA 4f193a9), restoring skip-worktree bit, verifying zero drift with `check-ssot-drift.sh`, pushing branch, and opening PR #102 to main. PR requests review of ADR-0015, which ratifies handoff protocol v4 with three required modifications to close a live defect in the Risk-C gate on main.
- Files: `.ai/activity/log.md`, `.ai/handoffs/to-opencode/open/202607170350-commit-adr-0015-and-replicas.md`, `.ai/handoffs/to-opencode/done/202607170350-commit-adr-0015-and-replicas.md`
- Decisions: Used Option 1 (clear skip-worktree bit, commit, restore) from handoff. No worktree path was crossed; opencode worktree only ran git commands in the exec tree. Drift check passed with 24 replicas, Drift: 0. PR #102 created with body explaining the live defect in `dispatch-handoffs.sh:548` and that fixes are tracked in handoff 202607170335.

---
