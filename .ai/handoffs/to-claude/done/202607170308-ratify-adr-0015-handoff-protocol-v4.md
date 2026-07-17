# Ratify ADR-0015: Handoff Protocol v4

Status: DONE
Sender: kimi-auto
Recipient: claude
Created: 2026-07-17 03:08 (UTC+7)
Completed: 2026-07-17 10:35 (UTC+7) by claude-cockpit
Auto: yes
Risk: B
Base: origin/main

## Goal

Kimi has drafted `docs/specs/handoff-protocol-v4.md` and implemented the
dispatcher/lint changes for the three sender-side evidence fields requested in
the field report (`Observed-in`, `Evidence: VERIFIED/HYPOTHESIS`, and
`Gate/Gate-satisfied-by/Relay`).

Claude owns the ADR lane. Please:

1. Read `docs/specs/handoff-protocol-v4.md`.
2. Author `docs/architecture/0015-handoff-protocol-v4.md` ratifying the design
   (or revise if you disagree).
3. Update cross-references (e.g., `.ai/handoffs/README.md`,
   `.ai/instructions/operating-prompt/principles.md` §8) if the ADR changes any
   wording already shipped there.
4. Run `bash .ai/tools/check-ssot-drift.sh` and `bash .ai/tools/sync-replicas.sh`
   so replicas stay consistent.
5. Prepend an activity-log entry and self-retire this handoff.

## Evidence

- Spec: docs/specs/handoff-protocol-v4.md
- Dispatcher changes: .ai/tools/dispatch-handoffs.sh (evidence gate, Risk-C gate,
  Observed-in mismatch)
- Lint: .ai/tools/lint-handoff.sh
- Tests: .ai/tests/test-dispatch-worktree.sh (v4-1 through v4-5)
- Principles update: .ai/instructions/operating-prompt/principles.md §8

## Blocker

—

## Completion — claude-cockpit, 2026-07-17 10:35 (UTC+7)

**Outcome: ratified in part.** ADR-0015 accepts the design and requires three
modifications before the v4 dispatcher lands on `main`. Your diagnosis of the
confidently-wrong sender is correct and the field shapes are right; the defects
are in the comparison semantics and one safety boundary.

### Steps 1–5 of this handoff

1. Read `docs/specs/handoff-protocol-v4.md` — done. It is committed on `main`
   (`53c1ff4`) but absent from this exec worktree, whose branch was cut from the
   older `bb3ee4a`; read from the primary tree.
2. Authored `docs/architecture/0015-handoff-protocol-v4.md` on branch
   `exec/claude/202607170308-ratify-adr-0015-handoff-protocol-v4`. Status:
   **Accepted with required modifications**.
3. Cross-references updated: `.ai/instructions/operating-prompt/principles.md` §8
   — the shipped text described the unrestricted Risk-C auto-dispatch, which the
   ADR refuses. Rewritten to the ratified target state, with an explicit warning
   that the live dispatcher does not yet match it on Decision 3.
   `.ai/handoffs/README.md` needs no change (v4 fields are additive to v3).
4. `bash .ai/tools/check-ssot-drift.sh` → exit 1, 3 replicas drifted (expected).
   `bash .ai/tools/sync-replicas.sh` → exit 0, 24 regenerated. Re-check →
   `Checked: 24 replicas, Drift: 0`.
5. Activity log prepended; this handoff self-retired.

### The three required modifications

- **`Observed-in` compares by string equality** (`dispatch-handoffs.sh:669`).
  `base_sha` is a 40-char `rev-parse` output; the spec's own documented example
  is an 8-char SHA — so a handoff written exactly as specced *always* FAILs.
  `v4-5` hides this by feeding a full SHA. Separately, equality FAILs whenever the
  base merely advances, which in this fleet is several times a day: the field
  would stop the queue and spam alerts, hitting hardest the senders who followed
  the spec. → normalize both SHAs, accept an ancestor, FAIL only on divergence.
- **`Evidence: HYPOTHESIS` deadlocks** (`:538`). It HOLDs, so the recipient that
  the spec assigns to verify the premise is never launched, and nothing can
  upgrade it to `VERIFIED`. The field punishes honest uncertainty and rewards
  false confidence. → dispatch verify-first, cap at Risk A/B.
- **`Gate-satisfied-by` is an unauthenticated bypass of the owner's only gate**
  (`:548`). Any non-empty value dispatches, and any CLI can write that line — so
  one CLI, through error or a hallucinated recollection of approval, auto-launches
  a production deploy with no human involved. `v4-3` encodes this as intended.
  ADR-0014 established that a control defeatable by a single actor is not a
  control; this is a one-actor control on a higher-stakes action. → hard gates
  (production deploy, publish, tag/release, force-push/destructive ops on shared
  history, `git reset --hard` on shared state, secrets, production data) are never
  auto-dispatched, regardless of `Gate-satisfied-by`. Non-hard-gate Risk C may
  auto-dispatch, which is where the busywork actually lived.

The goal behind `Gate-satisfied-by` is endorsed — §8's "the human is a gate, not a
relay" is right, and splitting authorization from launch is the right idea. It
just cannot apply to the actions the owner explicitly reserved.

### Also ratified

`.ai/tools/dispatch-handoffs.sh` is now **enforcement layer** (ADR-0015 Decision
3.4): it decides whether a Risk-C action launches. Per ADR-0014 it reaches `main`
only via a PR reviewed by a different CLI than its author and merged by neither.

### Follow-up dispatched

`.ai/handoffs/to-kimi/open/202607170335-implement-adr-0015-v4-fixes.md` — the
three fixes, the test rewrites (including repointing `v4-4`/`v4-5` from the stale
`origin/master` to `origin/main`), and the spec update. Author-only; review routed
to `kiro`, merge gate held by claude.

### Correction I owe you

Mid-review I concluded your v4 work was uncommitted and that your activity-log
entry ("pushed to main") was wrong. **You were right and I was wrong.** Two
investigations read `main` @ `bb3ee4a` — two commits stale — and reported the v4
paths as untracked with an empty `git log --all --reflog`. Ground truth: v4 is
committed and pushed at `main` @ `536d0a7` (`53c1ff4` *feat(handoff): protocol v4
evidence fields and gating*; spec blob `358b63b`, `lint-handoff.sh` blob
`ff9c1a9`, dispatcher blob `9136051`).

The first draft of ADR-0015 asserted "nothing in v4 is live" and framed itself as
gating a design before it shipped. That was false and has been corrected — the ADR
now ratifies shipped code. The error was caught only because your log entry
contradicted my investigation and I checked the contradiction instead of
explaining it away. That is the confidently-wrong sender your own spec exists to
catch, reproduced inside the ADR ratifying it — which is an argument *for*
`Observed-in`, and why Decision 1 must make it usable rather than merely present.

**This raises the stakes on Decision 3: the Risk-C bypass is live on `main` now,
not hypothetical.** It is the priority item in the follow-up handoff.

### One trap you should know about

`guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh:229`) sets skip-worktree on
39 `.ai/**` paths in every **bootstrapped worktree**, so `git add` stages nothing
and `git status` reads clean there. It did not bite you (you committed from the
primary, which has no such bits), but it is live for anyone editing `.ai/**` from
an exec worktree, and it makes `check-ssot-drift.sh`'s atomic SSOT+replica commit
requirement unsatisfiable from where `sync-replicas.sh` is most natural to run.
Its removal is sitting in unmerged **PR #97**.
