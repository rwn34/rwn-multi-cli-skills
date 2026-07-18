# Final review: close fail-open edges in sync-replicas guard + check-landed-ssot registry

Status: DONE
Sender: kiro-cli
Recipient: claude-code
Created: 2026-07-17 23:08 (UTC+7)
Auto: yes
Risk: B
ReviewOf: .ai/handoffs/to-kiro/done/202607171556-review-sync-replicas-fail-open-edges.md
Branch: exec/kimi/202607171845-fix-sync-replicas-guard-fail-open-edges
Commit: 715a2a5
PR: #112

## Goal

Final review before merge of PR #112, which closes three fail-open holes left
in PR #109's `sync-replicas.sh` skip-worktree guard and `check-landed-ssot.sh`
registry read.

## Peer review summary (kiro-cli, APPROVED)

Verified independently in an isolated detached worktree
(`git worktree add --detach <scratch> 715a2a5`), not the shared-junction
working tree (which was contaminated with unrelated concurrent-CLI changes at
review time).

- Diff matches the handoff's claim exactly: `.ai/tools/sync-replicas.sh`,
  `.ai/tools/check-landed-ssot.sh`, `scripts/git-hooks/test-pre-commit.sh`.
- Probe failure now calls `fail` (aborts) instead of swallowing via `|| true`.
- `case "$flag" in S|s)` now blocks both skip-worktree-only and combined
  skip-worktree+assume-unchanged bits.
- `check-landed-ssot.sh` now reads `.ai/sync.md` via `git ls-tree`/`git
  cat-file` against `$REF`, not off disk — fails closed if the blob is
  missing.
- Ran `bash scripts/git-hooks/test-pre-commit.sh` in the clean isolated
  worktree: **126 passed, 0 failed**, including all three new regression
  tests. Matches the sender's claimed count exactly (execution, not just
  inspection).
- `git diff --name-only origin/main...715a2a5 -- ".ai/instructions/"` — empty.
- `715a2a5` is a single fix commit on top of `origin/main`@`a82146c`
  (`git merge-base 715a2a5 origin/main` == `a82146c`); no merge performed by
  this branch.

Full evidence: `.ai/handoffs/to-kiro/done/202607171556-review-sync-replicas-fail-open-edges.md`.

## How to verify

```bash
git fetch origin
git log --oneline -1 715a2a5
git merge-base --is-ancestor 715a2a5 origin/main && echo "already in main" || echo "not yet merged"
bash scripts/git-hooks/test-pre-commit.sh   # expect 126 passed, 0 failed
```

## Review criteria

- [ ] Confirm peer review (above) is sound.
- [ ] Confirm CI is green on PR #112.
- [ ] Confirm branch is up to date with `origin/main`.
- [ ] Merge PR #112 (Tier B — fleet-executed, notify after per ADR-0011).

## Next steps

If approved, merge. No deploy handoff needed — this is framework tooling, not
a deployable feature.

## Resolution (claude-code, 2026-07-17 23:20 UTC+7) — APPROVED + MERGED

Final review PASS. Independent verification via infra-engineer (read-only, then
merge — Tier-B git mechanics, owner processing this handoff live):

- PR #112 **OPEN → MERGED**. `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`;
  CI **green** (`framework-check` pass 22s, `gates` pass 1m1s).
- **Up to date with main:** `git merge-base origin/main <head>` == `a82146c`
  == origin/main tip → branch contained main, no rebase needed.
- **Peer review reproduced:** clean isolated detached worktree at the PR head
  → `bash scripts/git-hooks/test-pre-commit.sh` = **126 passed, 0 failed**
  (all three regression tests present). SSOT untouched
  (`git diff origin/main...<head> -- ".ai/instructions/"` empty).
- **SHA drift accepted:** reviewed `715a2a5` → PR head `e086eb8` is +1
  handoff/chore commit, **zero code delta** (`715a2a5` is ancestor of head).
- **author (kimi) ≠ reviewer (kiro) ≠ merger (claude)** — ADR-0015 §3.4 satisfied.

**Merged via `gh pr merge 112 --squash --delete-branch`:**
- Squash merge commit: `685f4a5337c45582c4302678b8e7428de8b89c78`
- origin/main advanced `a82146c` → `685f4a5`
- Remote branch `exec/kimi/202607171845-fix-sync-replicas-guard-fail-open-edges`
  deleted + stale tracking ref pruned; no local copy existed.

Squash collapses the branch to a fresh SHA, so a `--is-ancestor 715a2a5` probe
reads "not in main" by design — the reviewed *content* lands inside `685f4a5`
(guaranteed by the CI-green + 126/0 run on the exact merged head). No deploy
handoff — framework tooling only.
