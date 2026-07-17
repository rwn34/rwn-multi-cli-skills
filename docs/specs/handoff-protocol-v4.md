# Handoff Protocol v4

## Summary

Protocol v4 adds three sender-side evidence fields to the handoff status block so
that confidently-wrong senders can be caught mechanically instead of burning
executor budget on re-verification:

- `Observed-in: <branch>@<sha>` — required when asserting file-level facts.
- `Evidence: VERIFIED | HYPOTHESIS` — epistemic status; `HYPOTHESIS` blocks
  auto-dispatch.
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
- The dispatcher resolves the dispatch base (honoring an explicit `Base:` line,
  otherwise discovering the repo default branch), computes its commit SHA, and
  compares it to the handoff's claimed SHA.
- On mismatch the dispatcher writes a `dispatch-failure-<ts>-<cli>-<slug>.md`
  report with stage `evidence-base mismatch`, leaves the handoff OPEN, and does
  not launch the CLI. This is a first-class sender-wrong outcome, not a BLOCKED
  recipient.

### `Evidence: VERIFIED | HYPOTHESIS`

- Absent or `VERIFIED` — auto-dispatch under normal Risk rules.
- `HYPOTHESIS` — the dispatcher HOLDS the handoff. The recipient's first job is
  to verify the premise and either upgrade the field to `VERIFIED` or retire the
  handoff as NOT-A-BUG.
- A hypothesis must not carry a priority label (enforced by
  `.ai/tools/lint-handoff.sh`). A guess is not allowed to drive queue priority.

### `Gate:`, `Gate-satisfied-by:`, `Relay:`

- `Gate:` names the irreversible action that requires authorization
  (e.g. `production deploy`, `npm publish`, `force-push`).
- `Gate-satisfied-by:` records who authorized the gate and when. Once present,
  the orchestrator may relay the launch; the dispatcher may auto-dispatch a Risk C
  handoff.
- `Relay:` clarifies the actor that physically launches the action when it differs
  from the `Recipient`. If omitted, the recipient is the relay.
- This preserves the safety property — no ungated irreversible action — while
  deleting the human-busywork the framework explicitly rejects.

## Dispatch routing matrix

| Risk | Gate satisfied | Evidence    | Result  |
|------|----------------|-------------|---------|
| A/B  | n/a            | VERIFIED    | DISPATCH |
| A/B  | n/a            | HYPOTHESIS  | HOLD     |
| C    | no             | any         | HOLD     |
| C    | yes            | VERIFIED    | DISPATCH |
| C    | yes            | HYPOTHESIS  | HOLD     |

## Failure outcomes

- **Self-addressed** (`Sender == Recipient`): FAIL, report written, handoff stays
  OPEN.
- **Evidence-base mismatch**: FAIL, report written, handoff stays OPEN, routed
  back to sender.
- **Ungated Risk C**: HOLD, handoff stays OPEN.
- **HYPOTHESIS**: HOLD, handoff stays OPEN.

## Tooling

- `.ai/tools/dispatch-handoffs.sh` implements evidence gating, Risk-C gating, and
  the Observed-in base comparison.
- `.ai/tools/lint-handoff.sh` enforces:
  - `Status: DONE` must have a non-empty `Evidence`, `Report`, `Verification`, or
    `Output` section.
  - `Evidence: HYPOTHESIS` must not carry a priority label.
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
