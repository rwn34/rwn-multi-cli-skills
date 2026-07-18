# Review: close fail-open edges in sync-replicas guard + check-landed-ssot registry

Status: DONE
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-07-17 22:56 (UTC+7)
Completed: 2026-07-17 23:05 (UTC+7)
Auto: yes
Risk: B
ReviewOf: .ai/handoffs/to-kimi/open/202607171845-fix-sync-replicas-guard-fail-open-edges.md
Branch: exec/kimi/202607171845-fix-sync-replicas-guard-fail-open-edges
Commit: 715a2a5
PR: #112

## Goal

Peer-review the follow-up that closes three fail-open holes left in PR #109:

1. `sync-replicas.sh` skip-worktree probe failure (`git ls-files -v … 2>/dev/null || true`)
   silently proceeded.
2. Lowercase `s` tag (skip-worktree + assume-unchanged) slipped the exact `= "S"` match.
3. `check-landed-ssot.sh` read `.ai/sync.md` from disk, so a stale registry could shrink
   the pair set being compared.

## What changed

- `.ai/tools/sync-replicas.sh` `guard_skip_worktree_sources()` now:
  - Aborts if `git ls-files -v` itself fails (distinguishes probe failure from "no bit").
  - Treats both uppercase `S` and lowercase `s` as a blocked skip-worktree bit.
- `.ai/tools/check-landed-ssot.sh` now reads the registry from the landed `$REF` via
  `git ls-tree -r "$REF" -- "$SYNC_MD"` + `git cat-file -p <blob>`, not from disk.
- `scripts/git-hooks/test-pre-commit.sh` adds regression tests for all three holes:
  - Probe failure (no `.git`) → `sync-replicas.sh` exits non-zero.
  - Combined skip-worktree + assume-unchanged (`s`) → exits non-zero.
  - Stale on-disk `.ai/sync.md` does not hide a landed mismatch in
    `check-landed-ssot.sh`.

## How to verify

```bash
# Switch to the branch
git checkout exec/kimi/202607171845-fix-sync-replicas-guard-fail-open-edges

# Run the full pre-commit backstop test suite via Git Bash explicitly
bash scripts/git-hooks/test-pre-commit.sh

# Confirm no SSOT instruction files were modified
git diff --name-only origin/main...HEAD -- ".ai/instructions/"
```

Expected: `scripts/git-hooks/test-pre-commit.sh` reports `126 passed, 0 failed`
(when run in a clean clone/worktree without stale skip-worktree bits);
`git diff --name-only origin/main...HEAD -- ".ai/instructions/"` is empty.

## Review criteria

- [ ] Probe failure path aborts rather than proceeding.
- [ ] Lowercase `s` is blocked.
- [ ] `check-landed-ssot.sh` registry is read from the landed ref.
- [ ] Regression tests cover all three holes and pass.
- [ ] No `.ai/instructions/**` source files were modified.
- [ ] No merge performed.

## Next steps

If approved, emit a final-review handoff to `to-claude/review/` so Claude can
approve before merge. If rejected, move this handoff back to `to-kimi/open/`
with `Status: BLOCKED` and a `## Blocker` section.

## Resolution — APPROVED

Verified independently in an isolated detached worktree
(`git worktree add --detach <scratch> 715a2a5`) rather than trusting the
shared-junction working tree, which was contaminated with unrelated
concurrent-CLI staged/unstaged changes at review time.

- **Files changed match the claim exactly:**
  `git show --stat 715a2a5` → `.ai/tools/check-landed-ssot.sh` (+9/-3),
  `.ai/tools/sync-replicas.sh` (+14/-9... net +6), `scripts/git-hooks/test-pre-commit.sh` (+41).
- **Probe failure now aborts (criterion 1):**
  `.ai/tools/sync-replicas.sh` `guard_skip_worktree_sources()` —
  `git show 715a2a5 -- .ai/tools/sync-replicas.sh`:
  ```
  lsout="$(git ls-files -v "$gsrc" 2>/dev/null)" \
    || fail "SSOT source '$gsrc': skip-worktree probe failed (git ls-files -v). Refusing to regenerate from an untrusted source (fail closed)."
  ```
  The old `|| true` swallow is gone; a probe failure now hits `fail` (exit 1).
- **Lowercase `s` is blocked (criterion 2):** same file,
  `case "$flag" in S|s) fail ... ;; esac` — both skip-worktree-only (`S`) and
  combined skip-worktree+assume-unchanged (`s`) are refused.
- **`check-landed-ssot.sh` reads from the landed ref, not disk (criterion 3):**
  `git show 715a2a5 -- .ai/tools/check-landed-ssot.sh`:
  ```
  sync_blob="$(git ls-tree -r "$REF" -- "$SYNC_MD" | awk '{print $3}')"
  [ -n "$sync_blob" ] || fail "registry $SYNC_MD not found in $REF"
  pairs="$(git cat-file -p "$sync_blob" | awk -F'|' '...')"
  ```
  Registry is now sourced via `git ls-tree`/`git cat-file` against `$REF`
  instead of `< "$SYNC_MD"` off disk; fails closed if the blob isn't found.
- **Regression tests cover all three holes and pass (criterion 4) — confirmed
  by execution, not inspection.** Ran
  `bash scripts/git-hooks/test-pre-commit.sh` in the clean isolated worktree
  (not the shared/contaminated one):
  ```
  == generator: skip-worktree probe failure fails closed ==
  PASS  probe failure (no .git) -> non-zero exit
  == generator: lowercase 's' (skip-worktree + assume-unchanged) fails closed ==
  PASS  lowercase 's' skip-worktree -> non-zero exit
  == check-landed-ssot: reads registry from REF, not disk ==
  PASS  stale on-disk sync.md does not hide landed mismatch

  RESULT: 126 passed, 0 failed
  ```
  Matches the handoff's claimed `126 passed, 0 failed` exactly.
- **No `.ai/instructions/**` modified (criterion 5):**
  `git diff --name-only origin/main...715a2a5 -- ".ai/instructions/"` → empty.
- **No merge performed (criterion 6):** `715a2a5` is a single fix commit
  directly on top of `origin/main`@`a82146c` (`git merge-base 715a2a5
  origin/main` == `a82146c`); the merge commits visible in `git log --graph`
  are pre-existing ancestors from already-landed PRs, not something this
  branch performed.

**Verdict: APPROVED.** All six review criteria satisfied by direct diff
inspection plus independent execution of the regression suite in a clean,
isolated worktree. Emitting a final-review handoff to `to-claude/review/` per
the handoff's own "Next steps".
