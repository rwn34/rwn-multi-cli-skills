# Review: fix sync-replicas stale-source loop

Status: DONE
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-07-17 15:12 (UTC+7)
Auto: yes
Risk: B
ReviewOf: .ai/handoffs/to-kimi/open/202607170800-fix-sync-replicas-stale-source-loop.md
Branch: exec/kimi/202607170800-fix-sync-replicas-stale-source-loop
Commit: 5a91d32

## Goal

Review the implementation that closes the sync-replicas stale-source loop
(ADR-0015 follow-up). The change is on the exec branch above; do not merge.

## What changed

1. `.ai/tools/sync-replicas.sh` now checks `git ls-files -v <ssot>` for every
   SSOT source before reading it. If the flag is `S` (skip-worktree), it aborts
   with a message naming the file and the fix
   (`git update-index --no-skip-worktree <path>`). `--check` stderr is now
   surfaced so the refusal is visible.
2. `scripts/git-hooks/pre-commit` captures and echoes sync-replicas stderr; if
   the generator aborts, the commit fails loudly instead of proceeding with
   stale or un-regenerated replicas.
3. New `.ai/tools/check-landed-ssot.sh` compares committed blobs of SSOT sources
   and replicas, independent of the working tree. Byte-copy replicas must share
   the source blob; `SKILL.md` replicas must have a body matching the source
   blob.
4. The landed-blob check is wired into `.github/workflows/framework-check.yml`
   and `.github/workflows/gates.yml`.
5. Regression tests in `scripts/git-hooks/test-pre-commit.sh` cover:
   - (a) sync-replicas aborts on a skip-worktree SSOT source;
   - (b) the hook refuses the commit when sync-replicas aborts;
   - (c) the landed-blob checker catches stale-source laundering that the
     working-tree drift check reports as `Drift: 0`.

## How to verify

```bash
# Switch to the branch
git checkout exec/kimi/202607170800-fix-sync-replicas-stale-source-loop

# Run the pre-commit backstop test suite (includes new regressions)
bash scripts/git-hooks/test-pre-commit.sh

# Run the landed-blob checker against HEAD
bash .ai/tools/check-landed-ssot.sh

# Confirm the skip-worktree guard aborts in a fresh temp repo fixture
# (the test suite above already does this, but a manual spot-check is fine)
```

Expected: `scripts/git-hooks/test-pre-commit.sh` reports 119 passed, 0 failed.

## Review criteria

- [ ] Skip-worktree guard fails closed and names the exact source + fix.
- [ ] Hook propagates the abort and the error is visible to the committer.
- [ ] Landed-blob check is independent of working tree and catches the
      laundering scenario.
- [ ] CI wiring is in both `framework-check.yml` and `gates.yml`.
- [ ] No `.ai/instructions/**` source files were modified (this fix is tooling
      and checks, not SSOT content).
- [ ] No merge performed.

## Next steps

If approved, emit a final-review handoff to `to-claude/review/` so Claude can
approve before OpenCode deploys/merges. If rejected, move this handoff back to
`to-kimi/open/` with `Status: BLOCKED` and a `## Blocker` section.

## Blocker

—

## Resolution — 2026-07-17 22:42 (UTC+7), kiro-cli

**Retiring this handoff as DONE. It was never actually closed — a prior
kiro-cli entry (2026-07-17 20:54, see activity log) mistook it for a stray
duplicate of a `done/` copy that does not exist, and deleted a copy that
turned out to be a re-creation of this same file rather than closing this
one.** Verified directly rather than trusting that log entry's premise:

    $ git log --oneline --all -- ".ai/handoffs/to-kiro/done/202607170812-review-sync-replicas-stale-source-loop.md"
    (empty — no such path was ever committed under to-kiro/done/)

The `done/` path referenced by
`.ai/handoffs/to-claude/done/202607171556-final-review-sync-replicas-fix.md`
(lines 18/58) was aspirational — this handoff was approved in place (my own
15:56 entry, embedded above under this same file) but never moved to
`to-kiro/done/`. The 20:54 entry's "stray duplicate" diagnosis does not hold:
`git log --all` shows no such path was ever committed anywhere in history.

**Substance is unaffected — the underlying review verdict already stands and
the reviewed work has since merged to `main`.** Independently re-verified now:

    $ git log --oneline -1 214d02b
    214d02b Merge pull request #109 from rwn34/exec/kimi/202607170800-fix-sync-replicas-stale-source-loop

    $ gh pr view 109 --json state,mergedAt,mergeCommit
    {"mergeCommit":{"oid":"214d02bff7fe65594f7477ea25067a6e0f9ee839"},"mergedAt":"2026-07-17T11:39:52Z","state":"MERGED"}

PR #109 is `MERGED`. My original peer-review verdict (`APPROVED`, commit
`5a91d32`) was carried through claude-code's final review — proven not
assumed, via `git range-diff` showing the rebase (`5a91d32` → `0b82cac`, tip
`8247015`) preserved the reviewed patch byte-for-byte (patch-hash
`a18fefd6e895590e8e56bfec4872bbcf4c62de6d` on both sides) — and merged as
`214d02b`. Nothing further to review; this handoff is now closed for real.

No code, `.ai/instructions/**`, or SSOT changes were made to process this
retirement — only this handoff's own status block and this section.
