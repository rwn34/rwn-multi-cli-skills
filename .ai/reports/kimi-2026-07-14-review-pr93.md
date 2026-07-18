# Kimi peer review — PR #93: sync-4ai-panes-install.ps1 ancestor guard

- PR: https://github.com/rwn34/rwn-multi-cli-skills/pull/93
- Branch: `exec/kiro/sync-provenance-check`
- Reviewer: kimi-cli
- Date: 2026-07-14 01:26 local

## Verdict: **Approve** (with one optional test suggestion)

I read the full diff and independently ran the test suite on a fresh worktree
pointing at `origin/exec/kiro/sync-provenance-check`.

```
==== sync-install tests: 52 passed, 0 failed ====
```

## Review questions

### 1. Does the ancestor-guard logic close the gap it claims to close?

**Yes.** The prior guard only verified three independent properties:
- the source directory is inside a git repo,
- it is the *primary* checkout (not a linked worktree), and
- the current branch is literally named `master`.

That allowed a local `master` that had been committed to or merged into locally
but never pushed to `origin` to pass. The new guard adds the necessary fourth
property: `HEAD` must be an ancestor of `origin/master`. The implementation:
- best-effort `git fetch origin master` (offline does not itself cause refusal),
- `git rev-parse --verify --quiet origin/master` to confirm the ref resolves,
- `git merge-base --is-ancestor HEAD origin/master`,
- fails closed when `origin/master` is unresolvable or when HEAD is not an
  ancestor.

This directly closes the hazard documented in the handoff: the primary checkout
could be 3 commits ahead of `origin/master` and still deploy.

### 2. Is the escape-hatch design the right call?

**Yes — option (b) is the right tradeoff.**

- **(a) strict master-only** would block legitimate pre-merge dogfooding of
  pane-runner/launcher changes. The fleet has repeatedly needed to run a local
  change before it lands on `origin/master`, so a strict gate would create
  operational friction.
- **(b) master-only default + narrow env escape** (`RWN_4AI_ALLOW_UNMERGED=1`)
  keeps the safe path the default while making the override explicit, scoped,
  and auditable (`provenance=unmerged-allowed` in the log).
- Keeping the escape hatch **separate from `-Force`/`SYNC_FORCE`** is
  important: `-Force` also bypasses the primary-checkout and detached-HEAD
  checks, which is a much larger hazard. A developer who merely wants to test
  an unmerged master commit should not have to accept the bigger risk.

The warning messages are loud and name the exact hazard, satisfying the
"defense in depth with transparency" principle.

### 3. Any gap in the new test scenarios (i/j/k/l)?

The four new scenarios cover the key cases:

| Scenario | Covered |
|---|---|
| (i) local `master` ahead of `origin/master` → refused + prior files untouched | yes |
| (j) `RWN_4AI_ALLOW_UNMERGED=1` on (i) → proceeds with warning + provenance | yes |
| (k) no `origin` remote at all → refused fail-closed | yes |
| (l) `RWN_4AI_ALLOW_UNMERGED=1` on (k) → proceeds with warning + provenance | yes |

**Optional suggestion, not blocking:** add a fifth scenario `(m)` for a
diverged `master` (local commits exist AND `origin/master` has moved forward
since the common ancestor). The existing `merge-base --is-ancestor` check
correctly rejects divergence, but the test currently only exercises the
"strictly ahead" shape. This is a low-risk coverage gap because the git
command behaves the same way in both shapes, but a dedicated test would make
the RED proof slightly stronger.

No issues found in the current test implementation.

### 4. Does this conflict with the fleet-supervisor work (#78)?

**No conflict.** PR #78 lives under `tools/4ai-panes/` (supervisor, heartbeat,
scheduled-task installer). PR #93 only touches `scripts/sync-4ai-panes-install.ps1`
and its test. The sync script is invoked by git hooks and by the pane-runner,
but the interface is unchanged: it still exits `0` on refusal and writes a log
line. The fleet supervisor treats a sync refusal as a non-fatal outcome, so the
new `refused-unmerged` / `refused-unverifiable-origin` results do not disrupt
supervisor logic.

## Issues found

None blocking.

## Files reviewed

- `scripts/sync-4ai-panes-install.ps1`
- `scripts/test-sync-4ai-panes-install.ps1`
- `CHANGELOG.md`
- `.ai/activity/log.md` (only Kiro's completion entry added)

## Tests run

```
cd /tmp/pr93-nIPujq
powershell.exe -ExecutionPolicy Bypass -File scripts/test-sync-4ai-panes-install.ps1
==== sync-install tests: 52 passed, 0 failed ====
```

The temporary worktree was removed after the run.
