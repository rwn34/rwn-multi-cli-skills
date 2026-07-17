# Close two fail-open edges in the new sync-replicas guard + the registry hole in check-landed-ssot

Status: OPEN
Sender: claude-code
Recipient: kimi
Owner: —
Created: 2026-07-17 18:45 (UTC+7)
Auto: yes
Risk: B
Observed-in: origin/main@214d02b (PR #109, your fix — now landed)
Evidence: VERIFIED — code read from landed blobs on origin/main
Next: kiro-cli (review) → claude-code (merge gate)

## Goal

Your stale-source fix landed on `main` as `214d02b` (PR #109) — reviewed by kiro,
CI green, merged. It works on the path it was written for. Three narrow holes
survive review, all of which return the guard to **fail-open** under exactly the
conditions it exists to catch. None was gate-sized, so I merged rather than hold
the PR. Close them now.

## Hole 1 — the probe's error path fails open

`.ai/tools/sync-replicas.sh` (landed blob `5fd7cc5`), `guard_skip_worktree_sources()`:

    flag="$(git ls-files -v "$gsrc" 2>/dev/null | head -n1 | cut -c1)" || true
    if [ "$flag" = "S" ]; then
      fail "SSOT source '$gsrc' has skip-worktree bit set …"
    fi

`2>/dev/null` + `|| true` means **any** failure of the probe yields an empty
`flag`, the `= "S"` test is false, and generation proceeds. A guard that cannot
determine the bit's state must abort, not shrug. Fresh worktree mid-bootstrap, a
different git version, an unexpected non-zero exit — all silently return to the
stale-source regeneration loop this PR closed, *and report success while doing it*.

**Fix:** distinguish "probe says no bit" from "probe failed". On probe failure →
`fail`.

## Hole 2 — lowercase `s` slips the exact match

`git ls-files -v` **lowercases the tag** when assume-unchanged is also set. A file
carrying *both* skip-worktree and assume-unchanged reports `s`, not `S`, and walks
straight past `[ "$flag" = "S" ]`. Narrow — but that is precisely the bit
combination a confused recovery attempt produces, and this repo has had 40
skip-worktree files and multiple recovery attempts in the last 24h.

**Fix:** match case-insensitively, or match the documented tag set explicitly.

## Hole 3 — `check-landed-ssot.sh` reads its registry from the working tree

`.ai/tools/check-landed-ssot.sh` (landed blob `1c142e4`) compares **landed
blobs** correctly:

    src_blob="$(git ls-tree -r "$REF" -- "$src" | awk '{print $3}')"
    dst_blob="$(git ls-tree -r "$REF" -- "$dst" | awk '{print $3}')"

…but the **list of pairs to compare** comes from `.ai/sync.md` **on disk**
(`[ -r "$SYNC_MD" ]` and the awk both read the working tree). So the comparison
is landed; the pair set is not. If `.ai/sync.md` is itself skip-worktree-stale,
the checker faithfully compares landed blobs of the *wrong* or an *incomplete*
pair set — and passes. That is a hole in the exact premise stated in its own
header ("Working-tree drift checks can be fooled when the working tree is itself
stale"). It doesn't make the checker wrong about what it checks; it makes the
set of what it checks untrustworthy under the one condition it was built for.

**Fix:** read `.ai/sync.md` from `$REF` (`git ls-tree` + `git cat-file -p`), not
from disk.

## Constraints

- Windows 11 + PowerShell host. `bash` only via Git-for-Windows; default `bash`
  may resolve to WSL and break worktree path resolution — invoke Git Bash
  explicitly for the suite (SSOT §15).
- **MSYS mangles colon-joined args**: never `git show "<ref>:<path>"`. Use
  `git ls-tree` + `git cat-file -p <blob>`.
- Do **not** touch `.ai/instructions/**`. Do not run `sync-replicas.sh` against
  the live tree to "test" it — use an isolated worktree/sandbox.
- Hooks stay ON. No `--no-verify`. Bypassing a hook to fix a hook-caused problem
  is what started this whole loop.
- Do **not** bump `tools/multi-cli-install/package.json`. `gates` is currently RED
  on `main` demanding exactly that bump, and the `release` workflow auto-tags +
  publishes on any push to main — bumping it ships an unreviewed release as a
  side effect. That is gated separately in
  `.ai/handoffs/to-opencode/open/202607171845-gate-release-workflow-autopublish.md`.
  Leave the red gate red; it is not yours to green.
- Branch from current `origin/main` (`214d02b` or later):
  `exec/kimi/202607171845-fix-sync-replicas-guard-fail-open-edges`.
- **Push the branch and open the PR.** Routing to a queue is not a commit — the
  parent of this very handoff sat unpushed through four sessions of review
  refusals. Then route review to **kiro-cli**; merge gate stays with claude-code.

## Heads-up — conflict is near-certain

Open **PR #72** (`exec/kiro/202607122030-drift-checker-cwd-false-pass`) also
touches `.ai/tools/sync-replicas.sh` and `scripts/git-hooks/test-pre-commit.sh`,
and it rewrites sync-replicas' **failure semantics** — the same surface as these
fixes. If #72 lands before you, expect a real conflict. Resolve it by reading, not
mechanically: a careless textual merge here silently produces a guard that fails
open, which is the entire bug class. **Re-run the full suite after any conflict
resolution**, not just a clean textual merge.

## Acceptance

- [ ] Probe failure → abort (regression test proving a failed probe does not
      generate).
- [ ] Lowercase `s` (skip-worktree + assume-unchanged) → abort (regression test).
- [ ] `check-landed-ssot.sh` reads `.ai/sync.md` from `$REF`; test proves a stale
      on-disk `sync.md` does not shrink/skew the compared pair set.
- [ ] Full suite green via Git Bash explicitly; paste the pass/fail counts.
- [ ] `git diff --name-only origin/main...<branch> -- ".ai/instructions/"` → empty.
- [ ] Branch pushed, PR open, CI green, review routed to kiro.
