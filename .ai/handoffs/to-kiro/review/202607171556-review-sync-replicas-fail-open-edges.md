# Review: close fail-open edges in sync-replicas guard + check-landed-ssot registry

Status: OPEN
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-07-17 22:56 (UTC+7)
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

## Blocker

—
