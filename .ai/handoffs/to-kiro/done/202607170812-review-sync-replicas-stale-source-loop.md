# Review: fix sync-replicas stale-source loop

Status: DONE
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-07-17 15:12 (UTC+7)
Completed: 2026-07-17 15:55 (UTC+7)
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

- [x] Skip-worktree guard fails closed and names the exact source + fix.
- [x] Hook propagates the abort and the error is visible to the committer.
- [x] Landed-blob check is independent of working tree and catches the
      laundering scenario.
- [x] CI wiring is in both `framework-check.yml` and `gates.yml`.
- [x] No `.ai/instructions/**` source files were modified (this fix is tooling
      and checks, not SSOT content).
- [x] No merge performed (by this reviewer — see Resolution note on the merge
      that subsequently happened via a separate final-review step).

## Next steps

If approved, emit a final-review handoff to `to-claude/review/` so Claude can
approve before OpenCode deploys/merges. If rejected, move this handoff back to
`to-kimi/open/` with `Status: BLOCKED` and a `## Blocker` section.

## Blocker

—

## Resolution (2026-07-17 15:55 UTC+7, kiro-cli)

**APPROVED.** Verified by execution against `5a91d32` (isolated detached
worktrees, no changes to this worktree's own branch, no merge performed):

- Diffed `749e1b0..5a91d32` — exactly the 6 files claimed, zero
  `.ai/instructions/**` touched (`git diff` = 0 lines).
- `.ai/tools/sync-replicas.sh`: confirmed `guard_skip_worktree_sources()`
  checks `git ls-files -v` per source, aborts on flag `S` naming the file and
  `git update-index --no-skip-worktree`; `--check` now captures and echoes
  generator stderr instead of swallowing it.
- `scripts/git-hooks/pre-commit`: confirmed both the `claude-code` and
  non-`claude-code` regeneration paths capture `sync-replicas.sh` stderr and
  call `fail_closed` with the generator's abort message surfaced, for both
  the in-place and `--dest-root` invocations.
- `.ai/tools/check-landed-ssot.sh`: confirmed it reads only `git ls-tree` /
  `git cat-file` (committed blobs) — no working-tree reads. Ran it directly
  against `5a91d32`: `Checked: 24 landed SSOT pairs, Mismatches: 0`, exit 0.
- CI wiring confirmed in both `.github/workflows/framework-check.yml` and
  `.github/workflows/gates.yml` ("Landed SSOT blob consistency check" step,
  identical in both).
- Regression tests (a)/(b)/(c) all present in
  `scripts/git-hooks/test-pre-commit.sh` and match the handoff's description,
  including (c)'s deliberate reproduction of the laundering pattern (source
  unstaged, replicas staged, `--no-verify` commit) that proves the new
  landed-blob check catches what the working-tree drift check misses.
- Ran the full suite via Git Bash explicitly (default `bash` on this host's
  PATH resolves to WSL, which breaks git-worktree path resolution — a known
  MSYS/WSL pitfall, SSOT §15): **119 passed, 0 failed**, matching the
  handoff's claim exactly.
- One flake surfaced on first attempt (via the `execute_cmd` PowerShell path,
  which appears to route through WSL for this host): `generator in place
  produces no changes (idempotent)` failed with 115/1. Traced to a file-mode
  (`100755`→`100644`) bit flip on `SKILL.md` files under `cp -R`, content
  byte-identical. **Confirmed pre-existing and unrelated to this fix** — the
  identical failure reproduces on the pre-fix commit `749e1b0` too
  (107 passed, 1 failed there; same 8-test delta from the new regressions).
  Not a defect in the reviewed change.

All review criteria met. No merge performed by this reviewer (out of scope for
peer review).

## Next steps

Emitting `to-claude/review/202607171556-final-review-sync-replicas-fix.md`
for Claude's final approval before OpenCode deploys/merges, per the
handoff's own "Next steps" and the review-pipeline protocol.

## Update (2026-07-17 18:35 UTC+7, kiro-cli) — retiring this handoff; fix already merged

This handoff was left uncommitted in the `exec/kiro/202607170812-...` worktree
after the 15:55 approval above. In the interim, the reviewed branch was rebased
(`5a91d32` → `0b82cac`, byte-identical patch — confirmed via
`git range-diff 5a91d32^..5a91d32 0b82cac^..0b82cac`, both sides hash to patch-text
`a18fefd6e895590e8e56bfec4872bbcf4c62de6d`), Claude completed the final review
(`.ai/handoffs/to-claude/review/202607171556-final-review-sync-replicas-fix.md`),
and the fix **merged to `main` as PR #109 (`214d02b`)**. Independently
re-verified on the actual landed state before writing this update:

```
$ git log --oneline origin/main -3
214d02b Merge pull request #109 from rwn34/exec/kimi/202607170800-fix-sync-replicas-stale-source-loop
8247015 chore(handoff): self-retire sync-replicas fix + route review to Kiro
0b82cac fix(ssot): close stale-source sync-replicas loop (skip-worktree guard + landed-blob check)

$ git diff cfd5750 0b82cac --stat
 .ai/tools/check-landed-ssot.sh        | 109 ++++++
 .ai/tools/sync-replicas.sh            |  38 +++-
 .github/workflows/framework-check.yml |   7 +++
 .github/workflows/gates.yml           |   7 +++
 scripts/git-hooks/pre-commit          |  28 ++++-
 scripts/git-hooks/test-pre-commit.sh  |  51 ++++
 6 files changed, 236 insertions(+), 4 deletions(-)
```

Re-ran the full suite and the landed-blob check independently, in a clean
detached worktree at `0b82cac` (isolated from any other in-progress work):
`scripts/git-hooks/test-pre-commit.sh` → **119 passed, 0 failed**;
`.ai/tools/check-landed-ssot.sh` → `Checked: 24 landed SSOT pairs, Mismatches: 0`.
Both match the figures already recorded above and confirmed independently a
second time.

**This handoff is retired (moved `review/` → `done/`) as a bookkeeping-only
action.** The substantive review was already complete and correct; nothing in
the merged PR contradicts it. No further action needed from `kiro-cli` on this
item — see `to-claude/review/202607171556-final-review-sync-replicas-fix.md`
for the full post-merge record (blockers found and cleared, follow-up handoffs
filed) and the live release-workflow hazard flagged there, which is a separate,
still-open concern.
