# Saja-Project Cockpit / Auto Handoff Workflow

**Scope:** framework-level design for the six-actor model discovered in
`saja-qr` and intended as the reusable pattern for all `saja-*` repos.

**Actors:**

| Actor | Identity | Mode | Primary role |
|-------|----------|------|--------------|
| `claude-cockpit` | interactive Claude Code chat | cockpit | architecture, orchestration, final review, human relay |
| `kimai-cockpit` | interactive Kimi CLI chat | cockpit | executor/tester, dispatcher to auto |
| `claude-auto` | headless Claude pane-runner | auto | spec/plan design, final review |
| `kimai-auto` | headless Kimi pane-runner | auto | backend + shell package implementation |
| `kiro-auto` | headless Kiro pane-runner | auto | frontend implementation |
| `opencode-auto` | headless OpenCode pane-runner | auto | deploy, GitHub ops |

> Note: the bash tooling uses `kimi` as the queue/cli name; `owner_for()` maps
> `kimi` and `kimi-auto` to the auto identity `kimai-auto`.
> Handoff files should use the canonical eight-actor identity in `Sender:` /
> `Recipient:` / `Owner:`.

## 1. Routing table — which task type goes to which actor

| Task type | Primary actor | Why |
|-----------|---------------|-----|
| Architecture / ADR / big-picture design | `claude-cockpit` | owns cross-cutting decisions and SSOT |
| Breaking a feature into staged handoffs | `claude-cockpit` or `claude-auto` | planning is spec work; cockpit does it when human steering matters |
| Backend / shell package implementation | `kimai-auto` | executor/tester lane |
| Frontend implementation | `kiro-auto` | frontend lane |
| Code review (peer) | different actor than author (see §5) | author ≠ reviewer (ADR-0002) |
| Final review | `claude-auto` or `claude-cockpit` | `claude-auto` for routine CI-green merges; cockpit for contentious or first-of-kind |
| Deploy to staging | `opencode-auto` | Tier B, dry-run first |
| Deploy to production | `opencode-auto` **after** explicit owner gate | Tier C, owner authorizes, orchestrator relays |
| GitHub ops (PR open/merge, branch delete, release chore) | `opencode-auto` | Tier B once CI green |
| Worktree/dispatcher/framework hygiene | `kimai-auto` or `opencode-auto` | who touches `.ai/tools/` / `scripts/` / `.github/` |
| Human-relayed Risk-C actions | `claude-cockpit` or `kimai-cockpit` | cockpit records authorization and relays |

## 2. Status-block conventions

Use the protocol-v4 status block from `.ai/handoffs/template.md`. The
six-actor model changes how three existing fields are interpreted:

### 2.1 `Sender:` / `Recipient:` / `Owner:` include mode

Always use the six-actor identity:

```markdown
Sender: kimai-cockpit
Recipient: claude-auto
Owner: claude-auto
```

`Owner:` is optional but recommended. It means "who currently owns this
handoff" — useful when a handoff is passed between auto panes or back to a
cockpit. When omitted, `Recipient:` is the owner.

### 2.2 `Auto:` and `Risk:` decide the pane, not just the tier

- `Auto: yes` + `Risk: A/B` → dispatched to `<recipient>-auto` headless pane.
- `Auto: no` or `Risk: C` (hard gate) → owned by a cockpit; never auto-dispatched.
- `Auto: yes` + `Risk: C` + `Gate:` + `Gate-satisfied-by:` + non-hard-gate action
  → may be relayed by the orchestrator cockpit to `<recipient>-auto` after the
  gate is recorded. See principles.md §8 and ADR-0015 Decision 3.

### 2.3 `Mode:` is implicit in the identity

Do not add a separate `Mode:` line. The mode is encoded in the identity suffix:
`-cockpit` vs `-auto`. The dispatcher's `owner_for()` already maps every queue
name to the correct auto identity; the handoff file reinforces the intended
mode by naming the full identity.

### 2.4 Encoding the next actor

Use the routing fields already present in the template:

- `ReviewBy: <actor>` — executor emits a review handoff to `to-<actor>/review/`
  on done.
- `FinalReview: <actor>` — reviewer emits a final-review handoff to
  `to-<actor>/review/`.
- `Deploy: yes` — final reviewer emits a deploy handoff to `to-opencode/open/`.
- `Next: <actor>` — general next-actor routing when the above fields do not fit.

`Next:` is the catch-all for chains that do not map cleanly to
review/final-review/deploy, e.g.:

```markdown
# Next: opencode-auto
# Next: kimai-cockpit
```

When `Next:` points at a cockpit, the auto pane writes the next handoff with
`Auto: no` so the dispatcher leaves it for the cockpit.

## 3. Visibility model

A cockpit that dispatches a handoff needs to know:

1. **Was it picked up?** Look at the recipient's claim sidecar:
   `.ai/.heartbeat-<owner>.json` and `.ai/.claim-<owner>.json` (see
   `.ai/tools/claim-handoff.sh`). A fresh heartbeat + a claim whose `handoff`
   field matches the dispatched filename means it was picked up.
2. **What is progress?** Read the recipient's pane log if available, or poll
   `.ai/activity/log.md` for an entry naming the handoff. The canonical command:
   `grep -n "<handoff-filename>" .ai/activity/log.md`.
3. **Did it finish?** Check `to-<recipient>/done/` for the retired handoff, or
   `to-<recipient>/review/` if it emitted a review handoff.

`fleet-health.sh` is the cockpit's consolidated dashboard:

```bash
bash .ai/tools/fleet-health.sh
```

It reports STALL, WEDGED, missing queue dirs, junctioned `.ai/`, stale
worktrees, and encoding problems.

## 4. Multi-stage handoff chain — canonical lifecycle

Example: a feature that needs planning → backend → frontend → review → deploy.

```text
claude-cockpit
  └── writes to-claude-auto/open/202607181530-plan-feature.md
      └── claude-auto plans, writes to-kimai-auto/open/202607181600-backend-feature.md
          └── kimai-auto implements backend, writes to-kiro-auto/open/202607181700-frontend-feature.md
              └── kiro-auto implements frontend, writes to-kimai-auto/review/202607181800-review-frontend.md
                  └── kimai-auto reviews, writes to-claude-auto/review/202607181900-final-review-feature.md
                      └── claude-auto final-reviews, writes to-opencode-auto/open/202607182000-deploy-staging-feature.md
                          └── opencode-auto deploys to staging, writes to-kimai-cockpit/open/202607182100-validate-staging.md
                              └── kimai-cockpit validates in chat, closes loop
```

Rules for the chain:

1. **Plan from a spec actor.** `claude-auto` writes the plan unless the feature
   is architectural or contentious, in which case `claude-cockpit` plans.
2. **Implementation panes run in parallel when independent.** If backend and
   frontend can be built against mocked contracts, dispatch both and add a
   handoff dependency note in the target state.
3. **Review is a precondition, not a sibling.** `ReviewBy:` must complete and
   retire to `done/` before `FinalReview:` is dispatched. The dispatcher's
   polling order is oldest-first, but a cockpit can enforce sequencing by not
   creating the final-review handoff until the peer-review handoff is retired.
4. **Final review gates deploy.** `FinalReview:` is either `claude-auto`
   (routine) or `claude-cockpit` (first-of-kind or contentious).
5. **Deploy is separate from merge.** Merge is Tier B; deploy to staging is Tier
   B; deploy to production is Tier C with owner gate. Never let a merge auto-trigger
   a deploy (principles.md §8 coupling rule).
6. **Return to a cockpit at boundaries.** After staging deploy, return to a
   cockpit (`kimai-cockpit` or `claude-cockpit`) for validation and the
   production-deploy decision.

## 5. Failure / retry / escalation

| Situation | Outcome | Routed to |
|-----------|---------|-----------|
| Auto pane does not pick up within timeout | `fleet-health.sh` reports WEDGED/STALL | sender cockpit |
| Claim sidecar stale (heartbeat dead) | `fleet-health.sh` reports STALL | sender cockpit; may kill pane (§8.1) |
| Evidence-base mismatch (`Observed-in` diverges) | dispatch FAIL, handoff stays OPEN | sender, with "evidence-base mismatch" |
| `HYPOTHESIS` premise disproven | recipient retires `NOT-A-BUG` with disproof | sender |
| Recipient blocked after reasonable effort | `Status: BLOCKED`, file stays in `open/` | sender cockpit |
| Self-addressed handoff (`Sender == Recipient`) | dispatch FAIL | sender |
| Risk C without gate or with hard gate | dispatch HOLD | recipient cockpit for relay |
| Dirty worktree | dispatch FAIL by default | sender cockpit decides cleanup |
| Review finds defect | reviewer reopens as `BLOCKED` or emits fix handoff | original implementer |

**Retry rule:** the dispatcher retries a failed dispatch up to its configured
limit, then quarantines. A cockpit must inspect quarantined handoffs in
`.ai/handoffs/.quarantine/`; do not auto-retry indefinitely.

**Escalation rule:** an executor blocked >2 times on identical state escalates
to the sender rather than re-verifying a third time. The correct vocabulary is
"evidence-base mismatch" or "verification-impossible", not `BLOCKED`.

## 6. Cleanup rules for stale claim sidecars

A claim sidecar (`.ai/.claim-<actor>.json`) is stale when:

1. Its heartbeat file (`.ai/.heartbeat-<actor>.json`) is dead or missing, OR
2. The handoff it claims is no longer in `open/` or `review/` (retired or
   superseded), OR
3. The claim age exceeds the fleet timeout without a progress log entry.

A cockpit may remove a stale sidecar when all three are true. A running auto
pane must release its claim via `release-handoff.sh` before exit; a cockpit
should never remove a live claim.

## 7. Activity-log identity

Use the six-actor identity in the activity log:

```markdown
## 2026-07-18 22:00 (UTC+7) — kimai-auto
- Action: implemented backend per handoff 202607181600-backend-feature
- Files: src/backend/...
- Decisions: -
```

The existing `cli-name` field in the activity-log header is sufficient; the
name itself becomes the full identity (`kimai-auto`, `claude-cockpit`, etc.).
No new field is needed.

## 8. Tooling / SSOT changes required

No tooling or SSOT changes are required. The current stack already supports
this workflow:

- `.ai/handoffs/template.md` has the six-actor `Sender:`/`Recipient:` identities
  and the v4 evidence fields.
- `.ai/tools/dispatch-handoffs.sh` routes `Auto: yes` + Risk A/B to the auto
  pane and enforces `Observed-in`, `HYPOTHESIS`, and gate rules.
- `.ai/tools/fleet-health.sh` gives the cockpit visibility.
- `.ai/tools/reconcile-done-handoffs.sh` moves retired handoffs and handles
  collision suffixes.
- `.ai/instructions/operating-prompt/principles.md` §8 already distinguishes
  cockpit (human gate/relay) from auto pane behavior via `Gate:` /
  `Gate-satisfied-by:` / `Relay:` and the hard-gate list; no amendment is
  needed for this workflow.

What is new is **convention and documentation**: this file, the example chain,
the routing discipline in §1–§4, and the README cross-reference.

## 9. Open questions resolved

- **Should `Sender:`/`Recipient:` include mode?** Yes — use the full six-actor
  identity (`kimai-cockpit`, `claude-auto`).
- **How encode the intended next actor when an auto pane finishes?** Use
  `ReviewBy:`, `FinalReview:`, `Deploy: yes`, or `Next:`.
- **What is the cleanup rule for stale claim sidecars?** Remove only when
  heartbeat is dead, claimed handoff is gone, and claim age exceeds timeout.
- **Does activity-log identity become `kimai-cockpit` vs `kimai-auto`?** Yes,
  use the full identity in the header; no new field is needed.
