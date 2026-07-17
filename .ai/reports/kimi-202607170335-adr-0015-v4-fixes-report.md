# ADR-0015 Handoff Protocol v4 Fixes — Execution Report

## Status

**DONE**

## Branch

- `exec/kimi/202607171103-adr-0015-v4-fixes`
- Commit: `6293c3f6d98489a15049d11d94e3e17d0d492321`
- Tip tree: one commit ahead of `origin/main` (`536d0a7`)

## Summary of Changes

### A. `.ai/tools/dispatch-handoffs.sh`

1. **`Observed-in` comparison (ADR-0015 Decision 1)**
   - Resolves the sender's SHA with `git rev-parse --verify --quiet "$observed_sha^{commit}"`.
   - Emits a distinct `unknown commit` failure (with a written `dispatch-failure-*.md` report) when the SHA cannot be resolved.
   - Resolves the declared base to a full SHA and accepts the observed value if it is the base itself **or an ancestor** (`git merge-base --is-ancestor`).
   - Emits `evidence-base mismatch` only when the observed commit is not an ancestor of the base.
   - Path-change check is intentionally not implemented; the ADR allows it as a follow-up.

2. **`Evidence: HYPOTHESIS` (ADR-0015 Decision 2)**
   - Removed the HOLD/continue path.
   - `HYPOTHESIS` at Risk A/B dispatches normally; the recipient's first step is premise verification.
   - Risk C with `HYPOTHESIS` is not dispatched here; it falls through to the Risk-C gate and is caught by `lint-handoff.sh`.

3. **Risk C / `Gate-satisfied-by` (ADR-0015 Decision 3)**
   - Added `gate_value` helper and an explicit `is_hard_gate` list sourced from operating-prompt §8:
     `production deploy`, `publish to a public registry`, `tag/release cut`, `force-push`,
     `destructive ops on shared history`, `git reset --hard` on shared state, `secrets`, `production data`.
   - Hard-gate matching normalizes the `Gate:` value by lowercasing and stripping non-alphanumeric characters, then uses substring matching.
   - A matching hard gate always HOLDs for a cockpit, regardless of `Gate-satisfied-by`.
   - Risk C with no `Gate:` HOLDs.
   - Risk C with a non-hard gate and non-empty `Gate-satisfied-by:` DISPATCHes.
   - Backward compatibility preserved: absent `Evidence` = `VERIFIED`; explicit `Base:` still wins.

### B. `.ai/tools/lint-handoff.sh`

- Added the `Evidence: HYPOTHESIS` + `Risk: C` lint error.
- Kept existing lints for `Status: DONE` without evidence section and `HYPOTHESIS` with a priority label.

### C. `.ai/tests/test-dispatch-worktree.sh`

- Repointed protocol v4 `Observed-in` tests from the old `origin/master` form to the `origin/main` default-branch project.
- Rewrote `v4-1`: `Evidence: HYPOTHESIS` + `Risk: A` now asserts DISPATCH (stub invoked).
- Rewrote `v4-3`: hard gate (`production deploy`) + `Gate-satisfied-by` now asserts HOLD.
- Added `v4-3b`: non-hard gate (`update documentation`) + `Gate-satisfied-by` asserts DISPATCH.
- Added `v4-4b`: abbreviated SHA of `origin/main` HEAD asserts DISPATCH.
- Added `v4-4c`: ancestor SHA after advancing `main` by one commit asserts DISPATCH.
- Added `v4-5`: `Evidence: HYPOTHESIS` + `Risk: C` asserts lint error.
- Added cleanup of leftover kimi handoffs before the v4 block so each dispatcher run processes only the target handoff; this keeps the suite within the execution timeout without changing any assertions.

### D. `docs/specs/handoff-protocol-v4.md`

- Updated the dispatch routing matrix to distinguish hard vs. non-hard gates and to show `HYPOTHESIS` as DISPATCH (verify-first) at Risk A/B and a lint error at Risk C.
- Updated `Observed-in` semantics: normalize SHAs, accept ancestors, distinguish `unknown commit` from `evidence-base mismatch`.
- Updated failure-outcome list.

## Verification Commands

All commands were run from the repo root on the primary worktree and passed.

### 1. `bash .ai/tests/test-dispatch-worktree.sh`

```
Sandbox: /tmp/tmp.GNtrty19gB
warning: in the working copy of '.ai/.gitkeep', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'seed.txt', LF will be replaced by CRLF the next time Git touches it
PASS  test1: dispatcher exits 0
PASS  test1: kiro worktree dir created at .wt/project/kiro
PASS  test1: stub ran with cwd == kiro worktree (got '/tmp/tmp.GNtrty19gB/.wt/project/kiro')
PASS  test1: stub ran with cwd != primary checkout
PASS  test2: worktree reused, not recreated (sentinel file survives)
PASS  test3: dispatcher reports a FAIL for the broken worktree
PASS  test3: a dispatch-failure report was written
PASS  test3: handoff file still present in open/ (never moved)
PASS  test3: handoff Status is still OPEN
PASS  test3: stub was NEVER invoked (no fallback to primary checkout)
PASS  test3: primary checkout untouched (no stray opencode worktree artifacts in $PROJECT)
warning: in the working copy of 'decoy.txt', LF will be replaced by CRLF the next time Git touches it
PASS  test4: exec/kimi/<slug> branch exists
PASS  test4: exec/kimi/<slug> was cut from origin/master, not the decoy branch
PASS  test4: decoy commit is NOT an ancestor of the dispatched branch
PASS  test4a: dispatcher exits 0 with annotated Base:
PASS  test4a: exec/kimi/<slug> branch exists
PASS  test4a: branch cut from annotated base resolves to origin/master
PASS  test4b: dispatcher exits non-zero for unresolvable base
PASS  test4b: dispatcher reports FAIL for unresolvable base
PASS  test4b: a dispatch-failure report was written
PASS  test4b: handoff file still present in open/
PASS  test4b: handoff Status is still OPEN
warning: in the working copy of '.ai/.gitkeep', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'seed.txt', LF will be replaced by CRLF the next time Git touches it
PASS  test4c: dispatcher exits 0 on a main-only repo
PASS  test4c: exec/kimi/<slug> branch exists
PASS  test4c: branch was cut from origin/main, not origin/master
warning: in the working copy of 'second.txt', LF will be replaced by CRLF the next time Git touches it
PASS  test4d: dispatcher exits 0 despite stale local refs
PASS  test4d: exec/kimi/<slug> branch exists
PASS  test4d: branch was cut from latest origin/main after fetch
PASS  test5: dispatch after prune succeeds (no wedge)
PASS  test5: worktree re-created after prune
PASS  test6: concurrent kiro dispatch exited 0
PASS  test6: concurrent kimi dispatch exited 0
PASS  test6: kiro worktree ended on its own branch (exec/kiro/202607110006-t6)
PASS  test6: kimi worktree ended on its own branch (exec/kimi/202607110006-t6)
PASS  test6: primary checkout (/tmp/tmp.GNtrty19gB/project) stayed on master throughout
PASS  test6b: kimi worktree branch unchanged (dirty -> reuse-as-is, never destroyed, even under concurrency)
PASS  test6b: kimi's private marker survived a concurrent kiro dispatch
PASS  S2-4: dispatcher reports FAIL for self-addressed handoff
PASS  S2-4: dispatch-failure report was written
PASS  S2-4: handoff stays OPEN
PASS  S2-4: stub was not invoked
PASS  S2-5: default dispatch FAILs on dirty worktree
PASS  S2-5: default dispatch wrote a failure report
PASS  S2-5: handoff stays OPEN after default failure
PASS  S2-5: stub not invoked for the dirty handoff by default
PASS  S2-5: --reuse-dirty emits a WARN
PASS  S2-5: --reuse-dirty dispatches the handoff
PASS  S2-5: --reuse-dirty wrote no new failure report
PASS  S3-4: dispatcher exits 0 despite extra header lines and ## Blocker
PASS  S3-4: handoff was dispatched (slug in kimi log)
PASS  v4-1: Evidence: HYPOTHESIS at Risk A/B dispatches (exit 0)
PASS  v4-1: dispatcher reports HYPOTHESIS verify-first
PASS  v4-1: kimi stub was invoked
PASS  v4-2: Risk C with no Gate: is HELD
PASS  v4-2: kimi stub was not invoked
PASS  v4-2: handoff stays OPEN
PASS  v4-3: Risk C hard gate HOLDs even with Gate-satisfied-by (exit 0)
PASS  v4-3: dispatcher reports hard gate requires cockpit
PASS  v4-3: kimi stub was not invoked
PASS  v4-3: handoff stays OPEN
PASS  v4-3b: Risk C non-hard gate with Gate-satisfied-by dispatches (exit 0)
PASS  v4-3b: dispatcher reports non-hard Gate: with satisfied Gate-satisfied-by
PASS  v4-3b: kimi stub was invoked
warning: in the working copy of 'decoy-main.txt', LF will be replaced by CRLF the next time Git touches it
PASS  v4-4: Observed-in mismatch exits non-zero
PASS  v4-4: dispatcher reports evidence-base mismatch
PASS  v4-4: dispatch-failure report was written
PASS  v4-4: handoff stays OPEN
PASS  v4-4: kimi stub was not invoked
PASS  v4-4b: Observed-in abbreviated SHA dispatches (exit 0)
PASS  v4-4b: dispatcher reports no evidence-base mismatch
PASS  v4-4b: kimi stub was invoked
warning: in the working copy of 'ancestor-advance.txt', LF will be replaced by CRLF the next time Git touches it
PASS  v4-4c: Observed-in ancestor SHA dispatches (exit 0)
PASS  v4-4c: dispatcher reports no evidence-base mismatch
PASS  v4-4c: kimi stub was invoked
PASS  v4-5: lint exits non-zero for HYPOTHESIS + Risk C
PASS  v4-5: lint reports HYPOTHESIS not allowed with Risk C
PASS  grep: old 'cd "$root" &&' shared-checkout invocation is gone from dispatch-handoffs.sh

==== dispatch-worktree suite: 77 passed, 0 failed ====
```

### 2. `bash .ai/tools/lint-handoff.sh`

```
OK: handoff lint passed
```

### 3. `bash .ai/tools/check-ssot-drift.sh`

```
Checked: 24 replicas, Drift: 0
```

### 4. `bash .ai/tools/sync-replicas.sh --check`

```
Checked: 24 replicas, Drift: 0
```

### 5. `bash .ai/tools/test-fleet-health.sh`

```
PASS: stale heartbeat + open Auto:yes B -> STALL, exit 1
PASS: stale heartbeat + empty queue -> DOWN (idle), exit 0
PASS: missing heartbeat + open handoff -> STALL, exit 1
PASS: fresh heartbeat + live-claimed handoff -> OK, exit 0
PASS: fresh heartbeat + aged unclaimed handoff -> WEDGED, exit 1
PASS: quarantined handoff + stale heartbeat -> DOWN (idle), exit 0
PASS: garbage heartbeat -> fail-open (no STALL), exit 0
PASS: foreign-host fresh heartbeat -> OK, exit 0
PASS: expired quarantine + stale heartbeat -> STALL, exit 1
PASS: bootstrap creates queue dirs and health check passes
PASS: missing queue dir flagged by health check

==== fleet-health tests: 11 passed, 0 failed ====
```

### 6. `bash .ai/tests/test-reconcile-done-handoffs.sh`

```
PASS  test1: reconcile exits 0
PASS  test1: DONE handoff moved out of open/
PASS  test1: DONE handoff now in done/
PASS  test1: reports the move
PASS  test2: reconcile exits 0
PASS  test2: DONE handoff moved out of review/
PASS  test2: DONE handoff now in done/
PASS  test2: reports the move from review
PASS  test3: reconcile exits 0 on collision
PASS  test3: incoming handoff moved out of open/
PASS  test3: original done/ file still exists
PASS  test3: exactly one superseded file created
PASS  test3: existing done/ file content unchanged
PASS  test3: superseded file contains incoming handoff
PASS  test3: prints a WARNING on collision
PASS  test4: reconcile exits 0 with OPEN handoff
PASS  test4: OPEN handoff stays in open/
PASS  test4: no output for OPEN handoff
PASS  test5: second run exits 0
PASS  test5: second run is silent

==== reconcile-done-handoffs suite: 20 passed, 0 failed ====
```

## Review Routing

Per ADR-0015 Decision 3.4 and the execution handoff constraints, this branch is **ready for Kiro review** and must reach `main` only through a peer-reviewed, CI-green PR. It has **not** been merged.

## Blockers / Concerns

None. A stray `decoy/should-not-be-base` checkout was created during an earlier test run; it was deleted and the commit was moved to the intended `exec/kimi/202607171103-adr-0015-v4-fixes` branch before pushing.
