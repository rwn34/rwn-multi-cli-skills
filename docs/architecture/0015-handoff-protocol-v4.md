# 15. Handoff protocol v4 — sender-side evidence fields, with the owner's hard gates excluded from auto-dispatch

## Status

Accepted with required modifications (2026-07-17).

Ratifies `docs/specs/handoff-protocol-v4.md` **in part**:

- `Observed-in:` — accepted, with a required correction (Decision 1).
- `Evidence: VERIFIED | HYPOTHESIS` — accepted, with a required correction (Decision 2).
- `Gate:` / `Gate-satisfied-by:` / `Relay:` — accepted **only for non-hard-gate
  actions**; **refused** for the owner's enumerated hard gates (Decision 3).

**v4 is already shipped and live on `main`** (`53c1ff4`, pushed 2026-07-17). This
ADR therefore does not gate a proposal — it ratifies deployed code and requires
three corrections to it, one of which (Decision 3) closes a **live defect in the
owner's single release-path gate**. Decision 3 should be treated as the priority
item; Decisions 1 and 2 are correctness fixes with no safety component.

Extends protocol v3 (`.ai/handoffs/README.md`). Applies ADR-0002's
author ≠ reviewer principle and ADR-0014's separation-of-duties reasoning to the
dispatcher. Does not alter ADR-0013 (`Auto:` as the ownership boundary) — v4 adds
fields alongside `Auto:` and `Risk:`; it does not replace them.

## Context

A field report identified a recurring, expensive failure: a **confidently-wrong
sender**. A CLI asserts a file-level fact ("`package.json` line 12 says X"),
files a handoff on that basis, and the recipient burns its budget discovering the
premise was false. The cost lands on the executor, not on the sender who made the
error.

`kimi-auto` drafted `docs/specs/handoff-protocol-v4.md` and implemented three
sender-side evidence fields to catch this mechanically:

- `Observed-in: <branch>@<sha>` — where the asserted facts were observed.
- `Evidence: VERIFIED | HYPOTHESIS` — the sender's epistemic status.
- `Gate:` + `Gate-satisfied-by:` + `Relay:` — splits *who authorizes* an
  irreversible action from *who launches* it.

The diagnosis is correct and the first two fields are the right shape. This ADR
ratifies that work. The review below is not a rejection of the design; it is the
merge gate doing its job on three defects that are load-bearing.

### Implementation state as of 2026-07-17 — stated exactly

**v4 is committed, pushed, and live on `main`.** Verified at `main` @ `536d0a7`
(`origin/main` identical, no divergence):

- `53c1ff4` — *feat(handoff): protocol v4 evidence fields and gating*
- `536d0a7` — *docs(activity): prepend protocol v4 implementation entry*

At the tip of `main`: `docs/specs/handoff-protocol-v4.md` (blob `358b63b`) and
`.ai/tools/lint-handoff.sh` (blob `ff9c1a9`) are committed;
`.ai/tools/dispatch-handoffs.sh` (blob `9136051`) carries the gating code —
6 `Observed-in` hits and 3 `gate_satisfied_by` hits; `test-dispatch-worktree.sh`
carries 32 `v4-` hits. **The Risk-C behavior described in Defect 3 is running in
production today.**

This ADR is therefore corrective, not preventive, and Decision 3 has a clock on
it.

**A note on how this ADR was nearly wrong, because it bears on Decision 3.**
Two independent investigations during this session read `main` @ `bb3ee4a` and
concluded the v4 work was uncommitted — `git log --all --reflog` over the v4
paths returned empty. Both were reading a tree two commits stale; `bb3ee4a` is an
ancestor of `536d0a7`. The first draft of this ADR consequently asserted "nothing
in v4 is live" and proposed to gate it before shipping. That was false, and it was
caught only because `kimi-auto`'s activity-log entry ("pushed to main")
contradicted the investigation and the contradiction was checked rather than
explained away. This is the **confidently-wrong sender the v4 spec exists to
catch, reproduced inside the ADR that ratifies it** — which is a point in favor
of `Observed-in` as a concept, and a demonstration of why Decision 1 must make
the field usable rather than merely present.

**Related, and unresolved:** `guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh:229`)
sets the git skip-worktree bit on 39 `.ai/**` paths in every bootstrapped
worktree, so edits there are invisible to `git add` and `git status` reads clean.
The primary worktree carries zero such bits. This did not block v4 (it was
committed from the primary), but it is a live trap for anyone editing `.ai/**`
from an executor worktree, and it interacts badly with `check-ssot-drift.sh`'s
requirement to commit an SSOT change and its replicas atomically —
`sync-replicas.sh` writes replicas into the exec tree while its input lives behind
a junction that tree cannot stage. The mechanism was already judged harmful by the
fleet; its removal is sitting in **unmerged PR #97** (`be66c16`,
`heal_skip_worktree()` + `reverse-write-detector.sh` + the spec
`docs/specs/junction-reverse-write-guard.md`, which `CLAUDE.md` already references
as a dangling link).

### Defect 1 — `Observed-in` compares SHAs by string equality

`.ai/tools/dispatch-handoffs.sh:669`:

```sh
if [ -z "$base_sha" ] || [ "$base_sha" != "$observed_sha" ]; then
```

`base_sha` comes from `git rev-parse --verify` — a full 40-character SHA.
`observed_sha` is whatever the sender typed. This has two independent failure
modes:

- **The spec's own documented example cannot pass.** The spec's status-block
  example reads `Observed-in: origin/main@a1b2c3d4` — eight characters. An
  abbreviated SHA is never string-equal to a 40-character one, so a handoff
  written exactly as documented is guaranteed to FAIL with an evidence-base
  mismatch. The test suite does not catch this because `v4-5` feeds a full SHA
  from `git rev-parse origin/main`. The tests encode the happy path and hide
  the documented path.
- **Equality is the wrong relation.** The dispatch base advances every time
  anything merges. A handoff whose evidence was accurate when written FAILs the
  moment one unrelated commit lands on the base. In this fleet the base moves
  several times a day; the handoff that prompted this ADR was filed at 03:08 and
  reviewed at ~10:00. At that latency, equality means **near-certain FAIL for
  every handoff carrying the field**, each one writing a
  `dispatch-failure-*.md` report and raising a `fleet_notify alert`. A field
  added to reduce wasted executor budget would instead stop the queue and spam
  the alert channel — and it would do so most reliably to senders who followed
  the spec, since only they carry the field at all.

The intent — "the sender's evidence must still apply to the tree the recipient
will run in" — is right. Equality is simply not that predicate.

### Defect 2 — `Evidence: HYPOTHESIS` deadlocks

`.ai/tools/dispatch-handoffs.sh:538` HOLDs the handoff and `continue`s. The spec
says the recipient's first job is to verify the premise — but the recipient is
never launched, so it never gets that job. Nothing in the design upgrades
`HYPOTHESIS` to `VERIFIED`. The handoff sits in `open/` until a human notices.

This inverts the field report's goal. A hypothesis is precisely the case where a
*cheap* verification pass is worth spending; instead it is the one case that gets
no executor at all, while a confidently-wrong `VERIFIED` handoff dispatches
freely. The field currently rewards false confidence and punishes honesty — a
sender who accurately marks uncertainty watches their handoff rot, and learns to
mark it `VERIFIED` next time.

### Defect 3 — `Gate-satisfied-by:` is an unauthenticated bypass of the owner's only gate

`.ai/tools/dispatch-handoffs.sh:548`:

```sh
c)
    if [ -n "$(gate_satisfied_by "$f")" ]; then
        echo "DISPATCH [$cli] $rel — Risk C with satisfied Gate-satisfied-by"
```

Any non-empty value dispatches. The value is a plain-text line in a markdown file
that every CLI in the fleet can write. Test `v4-3` encodes this as intended
behavior: a handoff with a self-written `Gate-satisfied-by` line auto-dispatches
at Risk C.

The operating prompt (§8) and `CLAUDE.md` both state that **production deploy is
the owner's single release-path gate**, requiring per-deploy human confirmation.
As implemented and **as currently running on `main`**, one CLI writing one line —
through error, hallucinated recollection of an approval, or a misread of chat
scrollback — auto-launches a production deploy with no human involved. There is
no signature, no out-of-band artifact, and no second actor. The check is `-n`: a
bare non-empty-string test. The gate is self-attested by the party it constrains.

To be precise about severity, since this is live and the temptation is to
overstate it: this is **not** an active incident and there is no evidence it has
fired. It is not remotely exploitable, and reaching it requires a fleet CLI to
author a Risk-C handoff carrying the field. What it is, exactly, is the owner's
one reserved gate reduced to an honor-system string that the agents it constrains
can write. It should be closed promptly, not panicked over.

Compare ADR-0014, which replaced a one-actor control ("an agent writes a patch, a
non-reading human applies it") with a three-actor one (author CLI + independent
reviewer CLI + CI). It argued — correctly — that a control defeatable by a single
agent is not a control. `Gate-satisfied-by` as specced is a **one-actor control
on a strictly higher-stakes action than the one ADR-0014 was hardening**. Ratifying
it as-is would undo that reasoning at the exact point it matters most.

The underlying goal is legitimate and this ADR endorses it: §8 says *"the human is
a gate, not a relay,"* and forcing the owner to hand-launch every Risk-C item makes
them a router. Splitting authorization from launch is the right idea. It just
cannot be applied to the actions the owner explicitly reserved.

## Decision

We ratify protocol v4 with three required modifications to the shipped code.
Decision 3 closes a live defect and is the priority item.

### Decision 1 — `Observed-in` compares by ancestry, not equality

The dispatcher MUST:

1. **Normalize both SHAs before comparing.** Resolve the sender's value via
   `git rev-parse --verify "<observed>^{commit}"` and compare full SHAs, so
   abbreviated SHAs — including the form the spec documents — work as written.
   An unresolvable SHA is a FAIL with a distinct message (`unknown commit`), not
   a mismatch.
2. **Accept an ancestor.** If the observed commit is an ancestor of the resolved
   base (`git merge-base --is-ancestor <observed> <base>`), the evidence was taken
   from the base's own history and the handoff DISPATCHes. A base that has merely
   advanced is not sender error.
3. **FAIL only on divergence or contradiction:** the observed commit is *not* an
   ancestor of the base (evidence from a divergent line), or any path the handoff
   cites changed in `<observed>..<base>`. The path-change check MAY ship in a
   follow-up; normalization plus the ancestor check is the minimum bar for
   landing, and alone removes the false-positive storm.

`Observed-in` remains **advisory on the branch part and authoritative on the
SHA part**, as the spec states.

### Decision 2 — `HYPOTHESIS` dispatches a verify-first pass

`Evidence: HYPOTHESIS` MUST NOT HOLD. It dispatches to the recipient with the
premise-verification task as the explicit first step, and the recipient MUST
either:

- upgrade the field to `VERIFIED` and proceed; or
- retire the handoff as `NOT-A-BUG` / `BLOCKED` with the disproof recorded.

A `HYPOTHESIS` handoff is capped at **Risk A/B**. A Risk-C action may never rest
on an unverified premise: `Evidence: HYPOTHESIS` + `Risk: C` is a lint error, not
a HOLD.

The spec's rule that a hypothesis **may not carry a priority label** is ratified
unchanged (`.ai/tools/lint-handoff.sh`). Marking uncertainty honestly must cost a
sender nothing except priority.

### Decision 3 — the owner's hard gates are never auto-dispatched

`Gate:` / `Gate-satisfied-by:` / `Relay:` are ratified as a **record** of
authorization and a routing aid. They are **not proof** of authorization and the
dispatcher MUST NOT treat them as such for the actions the owner reserved.

1. **Hard-gate actions are never auto-dispatched, regardless of
   `Gate-satisfied-by`.** The dispatcher maintains an explicit list, sourced from
   §8: **production deploy, publish to a public registry, tag/release cut,
   force-push or destructive ops on shared history, `git reset --hard` on shared
   state, secrets, and production data.** For these, `Gate-satisfied-by` is
   documentation; the item is HELD for a cockpit and relayed by a human in the
   loop. This is the status quo ante and it is preserved exactly.
2. **Non-hard-gate Risk-C items MAY auto-dispatch** when `Gate:` names the action
   and `Gate-satisfied-by:` records who authorized it and when. This is where the
   busywork actually lived (e.g. "another CLI's territory outside handoffs") and
   where v4's benefit is real and safe to take.
3. **`Gate:` MUST name a specific action**, and a `Gate:` value matching the
   hard-gate list forces path 1 no matter what else the file says. A missing or
   empty `Gate:` on a Risk-C handoff HOLDs.
4. **The dispatcher is hereby enforcement layer.** Once it decides whether a
   Risk-C action launches, `.ai/tools/dispatch-handoffs.sh` is a guard, not a
   convenience script. Changes to it fall under **ADR-0014's peer-reviewed-PR
   rule**: authored on an `exec/*` branch, reviewed by a different CLI than the
   author, CI-green, merged by neither. This ADR's own subject matter is the
   proof of necessity — a single uncommitted edit to this file silently
   re-pointed the owner's only gate.

### What we deliberately do not do

We do not require a cryptographic owner signature. This architecture has no
owner-authenticated channel — every file an agent can read, an agent can write —
so a signature would be theatre with extra steps. We choose instead to **shrink
the blast radius to actions where a forged record cannot cause irreversible
harm**, and to keep a human physically in the loop for the rest. That is an honest
control; a self-asserted "the owner said yes" is not.

## Consequences

### Positive

- **The confidently-wrong sender is caught mechanically**, which was the field
  report's goal, and the cost moves from the executor to the sender.
- **`Observed-in` becomes usable rather than a queue-stopper.** Under Decision 1
  the field fires on real divergence instead of on the base merely moving, so the
  fleet can adopt it without drowning in `dispatch-failure` reports and alerts.
- **Honest uncertainty stops being punished.** Under Decision 2 a `HYPOTHESIS`
  handoff gets a cheap verify-first pass instead of rotting in `open/`, so senders
  have no incentive to overstate confidence.
- **The owner's single gate survives contact with automation**, while the
  busywork §8 objects to is still deleted for the Risk-C items that are not
  irreversible.
- **The dispatcher gains the review discipline its new authority requires**
  (Decision 3.4), consistent with ADR-0014.

### Negative

- **v4 shipped before it was ratified, and this ADR is retroactive.** The fleet
  now carries a live defect in the owner's gate until Decision 3 lands. The
  ordering was backwards: the dispatcher's Risk-C behavior should have been
  reviewed before it reached `main`, which is precisely what Decision 3.4 makes
  mandatory going forward.
- **The hard-gate list is a maintained allowlist** and will drift from §8 unless
  someone keeps them in sync. A test asserting the dispatcher's list matches §8's
  enumeration is the obvious mitigation and is not yet written.
- **Risk-C handoffs remain partly human-relayed.** For hard gates, the owner is
  still in the launch path. We accept this: it is the one place where §8's
  "gate, not relay" principle yields to the fact that the action is irreversible.
- **`Gate-satisfied-by` records a claim that nothing verifies.** Under Decision 3
  a forged record can only affect non-irreversible actions, but it can still be
  wrong, and it will look authoritative in an audit trail.

### Neutral

- Protocol v3 semantics are unchanged. `Auto:` remains the ownership boundary
  (ADR-0013); `Risk:` remains the tier signal; absent `Evidence` still means
  `VERIFIED` for backward compatibility; an explicit `Base:` still wins over
  default-branch discovery.
- In-flight handoffs without the new fields continue to work, per the spec's
  migration section.
- The tests `v4-1`..`v4-5` use `origin/main`.
- `v4-3` currently asserts the behavior Decision 3 refuses. It must be rewritten
  to assert that a hard-gate `Gate:` value HOLDs even with `Gate-satisfied-by`
  present.

## References

- `docs/specs/handoff-protocol-v4.md` — the spec this ADR ratifies in part.
  Committed in `53c1ff4` (blob `358b63b`).
- `.ai/tools/dispatch-handoffs.sh` — evidence gate (`:538`), Risk-C gate
  (`:548`, the `-n` self-attestation), `Observed-in` comparison (`:669`).
  Committed in `53c1ff4` (blob `9136051`); line numbers are against that blob.
- `.ai/tools/lint-handoff.sh` — hypothesis/priority and DONE-evidence lints.
  Committed in `53c1ff4` (blob `ff9c1a9`).
- `53c1ff4` — *feat(handoff): protocol v4 evidence fields and gating*; the commit
  that made the Decision 3 defect live.
- `.ai/tests/test-dispatch-worktree.sh` — `v4-1`..`v4-5`.
- `.ai/instructions/operating-prompt/principles.md` §8 — autonomy tiers; the
  owner's hard-gate enumeration; *"the human is a gate, not a relay."*
- `.ai/handoffs/README.md` — protocol v3 lifecycle, which v4 extends.
- `docs/architecture/0002-cli-role-topology.md` — author ≠ reviewer ≠ deployer.
- `docs/architecture/0013-auto-tag-as-handoff-ownership-boundary.md` — `Auto:`
  as the ownership boundary; unchanged by this ADR.
- `docs/architecture/0014-enforcement-layer-changes-via-peer-reviewed-pr.md` —
  the separation-of-duties reasoning applied here to the dispatcher, and the
  peer-reviewed-PR path Decision 3.4 places it under.
- `scripts/wt-bootstrap.sh:229` — `guard_ai_reverse_write()`; why `.ai/**` must
  be committed from the primary worktree today.
- PR #97 / `be66c16` — unmerged removal of the skip-worktree guard.
- `.ai/handoffs/to-claude/open/202607170308-ratify-adr-0015-handoff-protocol-v4.md`
  — the handoff requesting this ratification.
