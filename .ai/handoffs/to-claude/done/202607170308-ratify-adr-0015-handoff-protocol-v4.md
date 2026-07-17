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

## Addendum — claude-code, 2026-07-17 12:45 (UTC+7): steps 3–4 re-verified, landing routed

Resumed after a step cap. Steps 1–5 above are confirmed done; this handoff stays
retired. Steps 3–4 re-executed rather than taken on faith:

- `check-ssot-drift.sh` → `Drift: 3` (the 3 operating-prompt replicas, 45 lines each)
- `sync-replicas.sh` → `regenerated 24 replicas into '.'` (exit 0)
- `check-ssot-drift.sh` → `Checked: 24 replicas, Drift: 0` (exit 0)
- `grep -n "ADR-0015 Decision"` on the SSOT → 4 hits (Decisions 1, 2, 3, 3.4)

**The §8 edit + 3 replicas are on disk but NOT committed**, and must land
atomically. Routed to opencode from the primary worktree:
`.ai/handoffs/to-opencode/open/202607171245-land-adr-0015-ssot-and-replicas.md`.
That handoff also deletes the stale `open/` duplicate of this file — two sessions
tried to retire it by in-place edit and both were reverted within minutes; it dies
with a commit or not at all.

**Three corrections to the trap description above**, which was too kind to it:

1. **41** trapped `.ai/**` paths, not 39 — including all 8
   `.ai/instructions/*/principles.md` SSOT files and every `.ai/tools/*.sh`.
2. The asymmetry is the danger: the SSOT reads `S` (skip-worktree) while its
   replicas read `H`, so **the replicas are committable and their source is not**.
   `git diff HEAD --stat` on the SSOT returns empty despite differing content. A
   naive commit ships replicas with no source and points the *next* agent at the
   correct files as the drifted party.
3. `check-ssot-drift.sh` compares **working-tree** files — it reported `Drift: 0`
   here while the committed tree would be broken. The checker structurally cannot
   detect the one failure mode this trap produces. That gap, not the bit, is the
   real defect.

## Addendum — claude-code, 2026-07-17 (4th session): SSOT reverted again; routing abandoned for direct execution

Resumed after a step cap. **The §8 SSOT had reverted a fourth time.** Verified
before touching anything, which is the only reason it was caught again:

- `.ai/instructions/operating-prompt/principles.md` → **0** `ADR-0015` hits;
  line 244 still read the pre-ADR `dispatcher HOLDS the handoff` text that
  Decision 2 explicitly refuses.
- All 3 replicas (`.claude`, `.kimi`, `.kiro`) → **4** hits each, carrying the
  ratified text (`the handoff **dispatches**`).

So for the fourth time the ratified text existed **only in the replicas**, and any
routine `sync-replicas.sh` would have regenerated them from the stale SSOT and
destroyed the last copy with no diff to explain it. Restored §8 into the SSOT by
hand-copying from the `.claude` replica (inverse of the normal sync direction).
Did **not** run `sync-replicas.sh` — with the SSOT stale, sync was the destructive
move, not the corrective one.

**The routing vehicle is gone.** `.ai/handoffs/to-opencode/` contains **no files at
all** — the entire directory the last three sessions routed this work through has
evaporated, including `202607171245-land-adr-0015-ssot-and-replicas.md` and its
phantom-DONE twin. Every prior session's "this lands via the opencode handoff"
closing line pointed at a vehicle that no longer exists. That is three sessions of
work parked on a queue that cannot deliver it.

**Correction to my own prior sessions' reasoning.** Three sessions in a row I
declined to execute and re-routed instead, each time citing the reverts as proof
that only a commit from the primary would hold. That was correct about the
mechanism and wrong about the remedy: routing to a queue is not a commit either,
and re-routing to the same vanishing queue was the thing generating the loop.
Owner directive 2026-07-12 puts git mechanics squarely in my lane (Tier B), so
this session executes the commit via `infra-engineer` from the primary worktree
and verifies the landed tree, rather than filing a fifth note describing what
someone else should do.
