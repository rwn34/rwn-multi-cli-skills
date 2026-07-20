# 12. Framework version assigned at merge, not on feature branches

## Status

Accepted (2026-07-12).

Amends the version-bump-gate discipline referenced in
`docs/architecture/0007-target-architecture-and-roadmap.md` (P2 — "the real
net", the machine-checkable CI gate). Resolves the "How is the version-bump
discipline enforced?" open question in
`docs/specs/framework-install-drift-check.md`. Does **not** alter ADR-0005
(commit-governance backstop) — no committer-identity or territory change.

## Context

`scripts/check-version-bump.sh` (PR#44, hardened via handoff 202607120022) was a
`pull_request` gate: every PR that touched versioned framework content had to
bump `tools/multi-cli-install/package.json` `.version` **and** add a matching
`## [x.y.z]` heading to `CHANGELOG.md`, or the PR failed. That gate exists to
protect adopter drift-detection (see the load-bearing constraint below): if
framework content changes without the version moving, every onboarded project's
`.ai/.framework-version` still equals the template's `.version`, so the drift
warning stays silent and drift ships undetected.

The gate did its job but created a structural collision. `.version` and the
CHANGELOG heading are **two specific lines**, and the PR-time rule forced *every*
content-changing PR to write them. With N PRs open concurrently:

- **Per-branch collision.** Each branch bumps the same two lines to the same next
  number. The second, third, … PR to try to merge hits a merge conflict on lines
  it only touched to satisfy the gate. The parallel merge train degrades into a
  hand-resolved serial one — the maintainer rebases each branch onto the last
  merge, re-picks a version, re-writes the heading, and repeats.
- **Merge-order downgrade risk.** If branch A (bumped to 0.0.30) merges after
  branch B (bumped to 0.0.30 independently, or to a lower number picked earlier),
  the version can land equal or lower than what is already on master — the exact
  "unchanged or downgrade" case the gate's own PR#44 hardening was written to
  reject, now produced by the merge *order* rather than by author error.
- **The gate masked real failures.** In `gates.yml` the version-bump step ran
  *first* (`if: github.event_name == 'pull_request'`), before the substantive
  suites. A branch that simply hadn't bumped yet failed the gate and never ran
  the drift / hooks / backstop / installer tests — a known complaint: a
  bookkeeping miss hid whether the code was actually sound.

The bump is bookkeeping that only needs to be correct **once per unit that lands
on master** — i.e. once per merge — not once per branch. Requiring it per branch
imposes a serialization cost with no added safety, because the thing being
protected (the template `.version` moving per content-change) is a property of
*master*, not of any individual feature branch.

## Decision

**We assign the framework version at the merge point, not on feature branches,
and we verify it detectively on the master push.** (Candidate 1 of the Plan
agent's 2026-07-12 adversarial vetting.)

Concretely:

1. **Feature branches stop bumping.** A feature PR adds its notes as bullets
   under `## [Unreleased]` in `CHANGELOG.md` and does **not** touch
   `package.json` `.version` or add a `## [x.y.z]` heading. Branches no longer
   collide on those two lines, so the merge train is parallel again.

2. **The release-engineer assigns the version at the single serialized merge
   point.** At merge, one version is chosen, the accumulated `## [Unreleased]`
   bullets are promoted into one new `## [x.y.z]` heading, and the version SSOT
   is bumped once. Because merges to master are already serialized (one lands at
   a time), there is exactly one writer of those two lines per landed unit — no
   collision, and the number only ever moves forward.

3. **`check-version-bump.sh` becomes a detective check on `push: master`.** It
   compares the **previous master tip** (`github.event.before`) to the **new
   one** and applies the identical PR#44 logic: if versioned content changed, the
   version must have strictly increased and carry its `## [<new-version>]`
   CHANGELOG heading; equal, downgrade, unparseable, or an unresolvable base ref
   all fail closed. The `is_versioned` allowlist is unchanged. On feature-branch
   PRs the check does not run at all.

4. **`gates.yml` runs the check last, on push-to-master only.** The step moves
   from first-on-PR to last-on-push, after every substantive suite (SSOT drift,
   the four per-CLI hook suites, the ADR-0005 backstop, and the installer
   typecheck + tests). A missing bump can therefore never mask a real test
   failure. The substantive suites still run on PRs unchanged (they carry no
   event guard). Making `gates` a **required** status check is branch protection
   — a repo setting, out of scope for this ADR and this file.

## Consequences

### Load-bearing constraint preserved — adopter drift-detection

The whole reason the gate exists is that onboarded projects detect framework
drift by comparing their recorded `.ai/.framework-version` against the template's
`tools/multi-cli-install/package.json` `.version`. Two readers depend on this:

- **`tools/4ai-panes/Selector.ps1` `Test-FrameworkDrift`** reads
  `(… .framework-version).framework_version` and
  `(… package.json).version` and warns when the project trails the template.
- **The Node installer** — `tools/multi-cli-install/bin/multi-cli-install.ts`
  writes the marker from `VERSION`, and `src/upgrade/version.ts` reads
  `.ai/.framework-version` — compares the same two numbers on upgrade.

This only works if the template `.version` **increments once per content-change**
that lands. Candidate 1 preserves exactly that: one increment per merge. The
readers are untouched by this ADR — they read the same `.version` field they
always did. This design was chosen precisely *because* it keeps that invariant;
alternatives that dropped or batched the increment were rejected on this basis.

### Residual risk — detective, not preventive

Moving the check from `pull_request` (preventive — a bad PR cannot merge) to
`push: master` (detective — a bad merge is caught after it lands) is a real
weakening, and it is bounded, not eliminated:

- **What is exposed.** A merge that changes versioned content *without* the
  release-engineer bumping lands on master and turns the gate red *after the
  fact*. Between that push and the fix, tip-of-master carries changed content at
  an unmoved version — so a project that adopts from tip in that window would not
  see the drift.
- **Why the blast radius is small.** (a) The window is bounded by fleet reaction
  time — a red `gates` run on master is a loud, visible signal the maintainer
  acts on. (b) `.github/workflows/release.yml` does **not** cut a release until
  the version SSOT actually moves: its master-push path derives the tag from
  `package.json` `.version` and its idempotency gate no-ops when a release for
  that version already exists, so an unmoved version publishes nothing. The
  *released* artifact stream therefore never carries the un-bumped state; only
  **tip-of-master installs** are exposed, and only until the detective check is
  answered. (c) The release-engineer assigning the version is a deliberate,
  single, serialized act — the failure mode is "forgot to bump at merge", which
  the red master run names immediately.

This trade — a bounded detective window in exchange for a collision-free parallel
merge train and no merge-order downgrades — is the point of the decision.

### Positive

- **Parallel merges again.** N PRs no longer fight over two lines; the merge
  train stops being hand-serialized.
- **No merge-order downgrade.** One writer per landed unit, moving forward only.
- **Real failures stop being masked.** The bump check runs last; a bookkeeping
  miss never hides a broken suite.
- **Simpler author story.** Contributors write `## [Unreleased]` bullets and stop
  reasoning about "what's the next version" mid-flight.

### Negative

- **Preventive → detective** (bounded as above): tip-of-master can briefly carry
  changed-content-at-unmoved-version until the red master run is answered.
- **A new discipline lives with the release-engineer** — assign one version and
  promote the CHANGELOG at merge. If skipped, master goes red rather than the PR;
  the signal moves later in the pipeline.

### Neutral — what this does NOT change

- **ADR-0005 (commit-governance backstop) is untouched** — no committer-identity,
  territory, or pre-commit change. This ADR only moves *when and where* one CI
  check runs.
- **The PR#44 hardening is verbatim** — strict semver increase, downgrade + equal
  rejected, fail-closed on unparseable, and the CHANGELOG-heading requirement all
  carry over unchanged; the `is_versioned` allowlist is reused as-is.
- **Adopter-facing drift-detection is byte-for-byte unchanged** (see above).
- **`release.yml` is untouched** — its master-push auto-cut still keys on the
  `.version` SSOT.

## References

- `scripts/check-version-bump.sh` — the gate whose trigger this ADR flips
  (PR#44 + handoff 202607120022 hardening preserved verbatim).
- `.github/workflows/gates.yml` — the version-bump step, moved to
  `push: master`, run last.
- `CHANGELOG.md` — the `## [Unreleased]` → `## [x.y.z]` promotion convention this
  ADR documents.
- `.claude/agents/release-engineer.md` — the agent that assigns the version at
  merge; its merge-point discipline note.
- `docs/specs/framework-install-drift-check.md` — the drift-detection spec whose
  "how is the version-bump discipline enforced?" open question this resolves;
  `Test-FrameworkDrift` (Selector.ps1) and the installer's `version.ts` are the
  drift readers the design preserves.
- `docs/architecture/0007-target-architecture-and-roadmap.md` — P2 (the CI gate);
  this ADR amends that gate's discipline.
- `docs/architecture/0005-commit-governance-backstop.md` — unchanged by this ADR
  (recorded as a non-conflict).
- `.github/workflows/release.yml` — the auto-cut that does not release until the
  `.version` SSOT moves, bounding the detective residual.
