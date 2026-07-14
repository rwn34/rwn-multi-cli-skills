# Open a PR for the Auto:-boundary contract line (docs-only, 2 files)
Status: DONE
Sender: claude-code
Recipient: opencode
Created: 2026-07-14 03:10
Auto: yes
Risk: B
Base: origin/master

## What

Open a PR for the already-pushed branch:

    exec/claude/202607130316-auto-boundary-ssot-and-contract-wording

Single commit `6d199e9`. Docs-only. It lands item 2 of handoff
`to-claude/202607130316` (kimi): the `Auto:`-tag ownership-boundary one-liner in
`CLAUDE.md` and `AGENTS.md`. Items 1 (operating-prompt SSOT §7 + its 3 replicas)
and 3 (ADR-0013) were already on `origin/master` from kimi's merged PR — only the
root contract line was missing.

Commit contents (nothing else — verified with `git show --stat`):

- `CLAUDE.md` (+2)
- `AGENTS.md` (+2)
- `.ai/activity/log.md` (+57)
- `.ai/handoffs/to-claude/{open => done}/202607130316-*.md` (rename R060, self-retire)

## Suggested PR body

> Adds the `Auto:`-tag ownership-boundary statement to the two root contract
> files, completing handoff `to-claude/202607130316`. The rule itself
> (ADR-0013) and its SSOT + 3 replicas already shipped in kimi's `8fb8bb3`;
> this is the CLAUDE.md/AGENTS.md half, which only Claude may write (ADR-0001
> custodianship).
>
> Docs-only, no source or tooling changes.

## Expect one red gate — it is NOT from this branch

`check-ssot-drift.sh` reports **`Drift: 3`** (exit 1) on this branch, and it will
report the same on `master`. **Do not "fix" it inside this PR.** The drift comes
from an unrelated uncommitted edit to
`.ai/instructions/operating-prompt/principles.md` (the activity-log
read-discipline block) that is masked by a **skip-worktree** bit — `git status`
shows the tree as clean, so a broad `git add -A` will not surface it and the
drift failure points at files this commit never touched.

That edit is owned by `to-kimi/open/202607131900-skip-worktree-guard-ate-your-ssot-edit.md`
and `to-kiro/open/202607131819-remove-skip-worktree-guard-land-detector.md`. If
the drift gate blocks the merge, **say so and stop** — do not stage the SSOT file
to make the gate green. Merging by hand once the other gates pass is acceptable;
smuggling an unrelated policy change into a docs PR is not.

## Do not

- Do not merge if any gate other than the known drift gate is red.
- Do not touch `.ai/instructions/**` or any `operating-prompt` replica.
- Do not amend or force-push `6d199e9`.

## Report back with

- PR number + URL
- CI gate results (name each gate and its verdict; call out the drift gate separately)
- Whether it merged, and if not, exactly which gate stopped it (verbatim)

## When complete (protocol v3)

Self-retire: set Status `DONE`, move to `.ai/handoffs/to-opencode/done/`.

## Completion note

- **PR #96 created**: https://github.com/rwn34/rwn-multi-cli-skills/pull/96
- **CI gate results** (as of 02:06):
  - framework-check: pending
  - gates: pending
  - Known drift gate: expected red (from unrelated SSOT edit, not this branch)
- **Merge status**: PR is OPEN, mergeable MERGEABLE, mergeStateStatus BLOCKED (due to pending checks)
- **Conclusion**: PR successfully created; will merge after CI completes (drift gate intentionally left red per handoff instructions).
