# Handoff Protocol v4

## Summary

Protocol v4 adds three sender-side evidence fields to the handoff status block so
that confidently-wrong senders can be caught mechanically instead of burning
executor budget on re-verification:

- `Observed-in: <branch>@<sha>` — required when asserting file-level facts.
- `Evidence: VERIFIED | HYPOTHESIS` — epistemic status; `HYPOTHESIS` dispatches
  verify-first at Risk A/B and is capped there (`HYPOTHESIS` + `Risk: C` is a
  lint error).
- `Gate: <what>` + `Gate-satisfied-by: <who>@<when>` + `Relay: <actor>` — splits
  the *human gate* (who must authorize) from the *relay* (who launches), so Risk C
  does not force the owner to become a manual router.

Status-block parsing is key-based, not positional. Extra header lines
(`Owner:`, `Reopened:`, `Rescoped:`) and a `## Blocker` above the sender block are
valid.

## Status block example

```markdown
# Production deploy v2.3.1
Status: OPEN
Sender: claude-cockpit
Recipient: opencode-auto
Created: 2026-07-16 19:31 (UTC+7)
Auto: yes
Risk: C
Gate: production deploy
Gate-satisfied-by: owner@2026-07-16 19:35 (UTC+7)
Relay: opencode-auto
Evidence: VERIFIED
Observed-in: origin/main@a1b2c3d4
Base: origin/main

## Goal
Deploy v2.3.1 to production after CI is green.

## Evidence
- CI run: https://github.com/.../actions/runs/12345 (green)
- Peer review: #88 approved by kiro-auto
```

## Field semantics

### `Observed-in: <branch>@<sha>`

- Required when the handoff body asserts concrete file-level facts
  ("`package.json` line 12 says X", "lockfile version is Y").
- The `<branch>` part is advisory; the `<sha>` part is authoritative.
- The dispatcher resolves both the claimed SHA and the dispatch base (honoring
  an explicit `Base:` line, otherwise discovering the repo default branch) to
  full 40-character SHAs. The claimed SHA may be abbreviated.
- The claim passes if the observed commit is the base itself or an ancestor of
  the base. Equality-only comparison would fail on every merge once the base
  advances; ancestry keeps the field usable.
- On divergence (the claimed commit is not an ancestor of the base) the
  dispatcher writes a `dispatch-failure-<ts>-<cli>-<slug>.md` report with stage
  `evidence-base mismatch`, leaves the handoff OPEN, and does not launch the
  CLI. An unresolvable claimed SHA produces a distinct `unknown commit` failure.
  These are first-class sender-wrong outcomes, not BLOCKED recipients.

### `Evidence: VERIFIED | HYPOTHESIS`

- Absent or `VERIFIED` — auto-dispatch under normal Risk rules.
- `HYPOTHESIS` at `Risk: A/B` — the dispatcher DISPATCHes the recipient with
  premise-verification as the recipient's explicit first step. The recipient
  either upgrades the field to `VERIFIED` and proceeds, or retires the handoff
  as NOT-A-BUG/BLOCKED with the disproof recorded.
- `HYPOTHESIS` is capped at `Risk: A/B`. `Evidence: HYPOTHESIS` + `Risk: C` is a
  lint error in `.ai/tools/lint-handoff.sh`, not a dispatchable state.
- A hypothesis must not carry a priority label (enforced by
  `.ai/tools/lint-handoff.sh`). A guess is not allowed to drive queue priority.

### `Gate:`, `Gate-satisfied-by:`, `Relay:`

- `Gate:` names the action that requires authorization. Some gates are *hard
  gates* reserved for the owner/cockpit regardless of `Gate-satisfied-by`:
  production deploy, publish to a public registry, tag/release cut, force-push
  or destructive ops on shared history, `git reset --hard` on shared state,
  secrets, and production data.
- `Gate-satisfied-by:` records who authorized the gate and when. For non-hard
  gates, once present the orchestrator may relay the launch and the dispatcher
  may auto-dispatch a Risk C handoff. Hard gates always HOLD for a cockpit.
- `Relay:` clarifies the actor that physically launches the action when it differs
  from the `Recipient`. If omitted, the recipient is the relay.
- This preserves the safety property — no ungated irreversible action, and no
  single-actor bypass of the owner's highest-stakes gates — while deleting the
  human-busywork the framework explicitly rejects.

## Dispatch routing matrix

| Risk | Gate type | Gate satisfied | Evidence    | Result  |
|------|-----------|----------------|-------------|---------|
| A/B  | n/a       | n/a            | VERIFIED    | DISPATCH |
| A/B  | n/a       | n/a            | HYPOTHESIS  | DISPATCH (verify-first) |
| C    | none      | n/a            | any         | HOLD     |
| C    | hard      | any            | any         | HOLD     |
| C    | non-hard  | no             | any         | HOLD     |
| C    | non-hard  | yes            | VERIFIED    | DISPATCH |
| C    | non-hard  | yes            | HYPOTHESIS  | lint error |

## Failure outcomes

- **Self-addressed** (`Sender == Recipient`): FAIL, report written, handoff stays
  OPEN.
- **Evidence-base mismatch / unknown commit**: FAIL, report written, handoff stays
  OPEN, routed back to sender.
- **Ungated Risk C**: HOLD, handoff stays OPEN.
- **Hard-gate Risk C**: HOLD, handoff stays OPEN.
- **Non-hard-gate Risk C without Gate-satisfied-by**: HOLD, handoff stays OPEN.

## Tooling

- `.ai/tools/dispatch-handoffs.sh` implements evidence gating, Risk-C gating, and
  the Observed-in base comparison.
- `.ai/tools/lint-handoff.sh` enforces:
  - `Status: DONE` must have a non-empty `Evidence`, `Report`, `Verification`, or
    `Output` section.
  - `Evidence: HYPOTHESIS` must not carry a priority label.
  - `Evidence: HYPOTHESIS` must not be paired with `Risk: C`.
  - `Observed-in:` is required when the handoff body asserts file-level facts
    (heuristic: mentions a repo path, git command, line number, or commit SHA).
- `.ai/handoffs/template.md` contains the new optional fields and comments.

## Migration

- In-flight handoffs without the new fields continue to work. Absent `Evidence`
  is treated as `VERIFIED` for backward compatibility.
- Existing Risk-C handoffs that rely on the legacy human-relay pattern keep that
  behavior. Add `Gate-satisfied-by:` only when the owner has explicitly
  authorized the action and auto-dispatch is desired.
- An explicit `Base:` line still wins over default-branch discovery.

## Known future breakage

- `origin/HEAD` and `origin/<branch>` remote-tracking refs go stale without a
  `git fetch`. A long-lived executor worktree can therefore resolve its base to
  an older commit. Consider a periodic fetch or a base-freshness check before
  cutting the `exec/<cli>/<slug>` branch.
