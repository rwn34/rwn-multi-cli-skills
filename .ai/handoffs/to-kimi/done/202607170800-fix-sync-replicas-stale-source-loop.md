# Fix the sync-replicas stale-source loop (P0 — it silently reverts ratified SSOT text)

Status: DONE
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 15:00 (UTC+7)
Auto: yes
Risk: B
Base: origin/main
Observed-in: main@749e1b0
Evidence: VERIFIED
Completed: 2026-07-17 15:12 (UTC+7)
Touched:
  - .ai/tools/sync-replicas.sh — skip-worktree source guard + surfaced --check stderr
  - scripts/git-hooks/pre-commit — surfaces sync-replicas stderr and fails commit on abort
  - .ai/tools/check-landed-ssot.sh — new landed-blob consistency checker
  - .github/workflows/framework-check.yml — added landed-blob check step
  - .github/workflows/gates.yml — added landed-blob check step
  - scripts/git-hooks/test-pre-commit.sh — regression tests for (a), (b), (c)
Branch: exec/kimi/202607170800-fix-sync-replicas-stale-source-loop
Commit: 5a91d32

## Goal

A four-session revert loop silently destroyed ratified ADR-0015 §8 text three
times before it finally landed on the fifth attempt (PR #106, `749e1b0`). The
**content** is fixed. The **loop is still live** and will re-fire on the next
`claude-code` commit that stages `.ai/instructions/**` from a bootstrapped
worktree. Close it.

## The mechanism (verified, not hypothesised)

Two safe-looking mechanisms compose into a data-destroyer:

1. `guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh`) sets **skip-worktree**
   on ~41 `.ai/**` paths in every bootstrapped worktree — including all 8
   `.ai/instructions/*/principles.md` SSOT files. There, `git add` stages nothing
   and `git status` reads clean, so an edit to the SSOT is invisible to git.
2. The **pre-commit hook auto-syncs**: when the committer is `claude-code` and
   `.ai/instructions/**` is staged, it runs `sync-replicas.sh` and force-stages
   the regenerated replicas.

Composed: the guard hides the real SSOT edit → the hook regenerates the replicas
**from the stale SSOT** → the ratified text a session just wrote is overwritten,
and the commit's own stat *claims* it updated the replicas.

Worked example — commit `4f193a9`: its stat brags
`.claude/skills/operating-prompt/SKILL.md | 54 ++----` while the resulting blob
is the **stale** one. That is the laundering step. Nothing alarms.

## Why the existing detector cannot catch this

`check-ssot-drift.sh` compares **working-tree** files and reported
`Checked: 24 replicas, Drift: 0` throughout the entire multi-session window in
which `main` was provably broken. It proves only that the 4 files agree *with
each other* — a consistently-wrong set still prints `Drift: 0`. It is a false
negative by construction, not a guarantee.

## Required fixes

1. **`sync-replicas.sh` must refuse to run against a skip-worktree source.**
   Right now the one file the generator trusts is exactly the file git has been
   told to stop looking at. For each SSOT it is about to read, check
   `git ls-files -v <ssot>`; if the bit reads `S`, **abort with a non-zero exit
   and a message naming the file and the fix** (`git update-index
   --no-skip-worktree <path>`). Never silently regenerate from a source git is
   ignoring.
2. **The pre-commit hook auto-sync must inherit that refusal** — if
   `sync-replicas.sh` aborts, the commit must fail loudly rather than proceed
   with un-regenerated (or stale-regenerated) replicas.
3. **Add a CI check that compares landed blobs, not the working tree.** Per the
   post-merge review of #106: gate on `git ls-tree origin/main` blob shas across
   the SSOT + its replicas. Working-tree greps are what lied to four sessions;
   only landed-blob evidence counts. Note that `principles.md`, `.kimi/`, and
   `.kiro/` currently resolve to the *same* blob (`1e55370`) — that identity is a
   happy accident of the current sync, not an enforced invariant, and it forks the
   moment any CLI edits its own steering.
4. **Regression tests** covering: (a) `sync-replicas.sh` aborts when its SSOT
   carries `S`; (b) the hook fails the commit when sync aborts; (c) a stale-source
   regeneration cannot produce a `Drift: 0` green.

## Constraints

- `sync-replicas.sh` and the pre-commit hook are **enforcement layer** (the same
  reasoning as ADR-0015 Decision 3.4 for the dispatcher): they decide whether
  corrupted state reaches `main`. So ADR-0014 applies — author on an `exec/*`
  branch, **review routed to a different CLI than the author** (`kiro`), CI-green,
  and **merged by neither**. The merge gate is claude's.
- Do **not** commit `.ai/**` edits from a bootstrapped worktree without first
  confirming `git ls-files -v` reads `H` on every path you intend to land. If it
  reads `S`, you are about to reproduce this exact bug.
- The root cause of the guard half — `guard_ai_reverse_write()` — has a removal
  sitting in **unmerged PR #97**. Coordinate rather than duplicate: if #97 lands
  the guard removal, fix 1 is still required (the generator must never trust an
  ignored source, guard or no guard).

## Evidence

- Merge that landed the content (and the full post-mortem in its body): PR #106,
  merge commit `749e1b0`, branch `exec/claude/202607170308-land-adr-0015-ssot-atomic`
- Laundering example: commit `4f193a9` (stat vs. resulting blob disagree)
- Completion record with the 4-session history:
  `.ai/handoffs/to-claude/done/202607170308-ratify-adr-0015-handoff-protocol-v4.md`
- Guard: `scripts/wt-bootstrap.sh` → `guard_ai_reverse_write()`
- False-negative detector: `.ai/tools/check-ssot-drift.sh`

## Blocker

—
