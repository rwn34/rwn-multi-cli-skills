# 9. Operator-over-Fleet — 5-Pane Topology, Auto-Claude Reviewer, and Claude-to-Claude Claim-Lock Coordination

## Status

Accepted (owner-directed 2026-07-10).

This ADR **extends ADR-0008** (the self-driving pane-runner). It **supersedes**
two earlier stances: the implicit "the Claude pane runs headless as a worker"
posture, and the transient "per-pane bare toggle" idea — both dropped.

## Context

- ADR-0008 established the self-driving pane-runner: each pane headless-polls its
  own `to-<cli>/open/` queue (poll → claim → run → auto-continue).
- The owner drives Claude through a remote app that **attaches** to a `claude`
  process running on the PC. That app-Claude is the interactive
  orchestrator/architect — this framework's Claude lane (ADR-0002).
- **Problem observed:** if a Claude *pane* also headless-polls `to-claude/`
  **and** the app-Claude orchestrates, two Claude instances consume the same
  `to-claude` queue → double-processing race. The race is real: on 2026-07-10,
  Kiro and a Claude-dispatched coder **both** acted on the same handoff
  (`202607101530`) simultaneously.
- **Owner's insight (2026-07-10):** keep *both* Claudes, but coordinate them like
  any other cross-CLI pair — through the shared `.ai/` files (handoffs + a
  claim-lock), never a direct link — and make the layout explicit.

## Decision

We adopt an **operator-over-fleet** topology: one interactive Claude on top
driving four self-driving workers below, with the two Claude instances
coordinated through shared files rather than any direct channel. *(The single
top operator is superseded — see Amendment (2026-07-10): the top row now carries
**two** interactive operators, Claude + Kimi.)*

### 1. Topology — a 5-pane Windows Terminal tab per project *(superseded — see Amendment (2026-07-10): 2+4 dual-operator, 6 panes)*

- **TOP pane:** a full-width horizontal strip, ~20% height (configurable),
  running **app-Claude** = the interactive orchestrator. *(Superseded — see
  Amendment (2026-07-10): the top strip is now 50% height and split into two
  side-by-side cockpits, Claude + Kimi.)* **No polling, no
  pane-runner** — the owner's remote app attaches here. Identity: `claude`.
- **BOTTOM 4 panes:** `auto-Claude`, Kimi, Kiro, OpenCode — each running the
  self-driving pane-runner (ADR-0008), and each **independently pausable**
  (`p` → interactive; exit the CLI → auto-resume). Pausing or stopping one pane
  never affects the others or the top strip.

### 2. `claude` auto-pane role and identity

- **`claude`** is a headless Claude auto pane **limited to Tier A/B work** on the
  `to-claude` queue: review, verification, chaining follow-up handoffs, and
  other Tier-A/B actions. It **never** performs Tier C (**production deploy,
  publish/tag, force-push, destructive ops on shared history, secrets changes**)
  — those remain exclusively with app-Claude + the human gate (ADR-0002/ADR-0011
  autonomy tiers). Merge to main and ADR authorship/amendment are Tier B, not
  Tier C, but they are outside this pane's queue lane.
- **Distinct identity `claude`** (separate from `claude-cockpit`) for *both*
  activity-log attribution *and* claim-lock ownership, so the two Claude
  instances are always distinguishable in the shared state.

### 3. Coordination — Claude-to-Claude via files, not direct

- A per-project, per-handoff **claim-lock** (extends backlog #1/#32): before
  running a `to-claude` handoff, a consumer writes an atomic claim marker (owner
  identity + pid + timestamp). Others skip claimed items. Dead-pid/stale claims
  are reclaimable after a staleness window.
- **app-Claude checks the claim-lock/heartbeat before acting** on a `to-claude`
  item: if `claude` holds it, app-Claude leaves it alone (or queues
  additional work) — it never double-processes.
- The **same lock** also resolves the already-observed Kimi-vs-Kimi /
  Kiro-vs-Kiro same-handoff double-grab.

## Consequences

- **Prerequisite ordering.** The claim-lock **MUST** land before `claude` is
  enabled, else the race persists. Sequence: this ADR → claim-lock → 5-pane
  layout + `claude` wiring.
- **Cost: one more polling Claude.** Idle polling is filesystem-only (zero
  tokens); cost is incurred only on real handoff pickup, bounded by the
  auto-continue MAX cap (ADR-0008). Pairs with backlog #6 (cost observability).
- **New identity `claude`** must be registered across the CLI-identity
  surfaces (activity log, claim-lock, dispatcher/pane-runner). Minor additive
  surface.
- **Launcher change.** `Selector.ps1` / the launch script must build a 5-pane WT
  layout (1 top split + 4 bottom) instead of the current 4-pane grid; the
  installed `~/.rwn-auto` copy is updated in lockstep. That lockstep is now
  **mechanical, not aspirational** — enforced by the `post-merge` /
  `post-checkout` git hooks + sync script specified in
  `docs/specs/4ai-panes-install-sync.md`, which byte-sync the allowlisted tool
  files into the install whenever a merge/checkout touches `tools/4ai-panes/**`.
  *(Superseded — see
  Amendment (2026-07-10): the default build is now a 6-pane 2+4 layout with
  `$topStripFraction = 0.50`; the 1+4 layout is retained as the `5pane`
  fallback.)*
- **Supersedes the "per-pane bare toggle" idea** — unnecessary now, since the top
  pane is bare by construction and the bottom four always self-drive.

## Alternatives considered

- **(A) Single Claude (app only), no Claude worker pane.** Rejected — the
  `to-claude` queue stalls whenever the human is away; loses self-driving
  review/chaining.
- **(B) All four panes headless including Claude, no separate interactive app
  orchestrator.** Rejected — no interactive seat, and two Claudes still collide
  without the claim-lock.
- **(C) Per-pane bare toggle with the Claude pane as the *sole* orchestrator.**
  Rejected by owner — the owner wants the app as orchestrator *and* a headless
  `claude` reviewer; the 5-pane split expresses this directly.

## References

- `docs/architecture/0002-*` — role lanes + autonomy tiers (the Claude lane,
  Tier A/B/C definitions this ADR constrains `claude` to).
- `docs/architecture/0008-self-driving-fleet-pane-runner.md` — the self-driving
  pane-runner this ADR extends (poll → claim → run → auto-continue, MAX cap).
- `.ai/research/framework-improvement-backlog.md` — #1/#32 (claim-lock),
  #7 (concurrency safety), #6 (cost observability).

## Amendment (2026-07-10): dual-operator 2+4 topology

Owner-approved: the topology evolves from **1+4 "operator-over-fleet"** to
**2+4 "dual-operator-over-fleet"** — six panes per tab instead of five. The
**top row is now 50% height and split into two side-by-side interactive,
non-polling cockpits**: app-Claude (identity `claude-cockpit`, no pane-runner) on
the left and **`kimi-cockpit`** (bare `kimi --yolo`, no pane-runner, no polling, no
handoff claims) on the right — both are human-driven operator seats. By owner
intent, the two seats have distinct roles: **top-left Claude** is the owner's
app-paired / remote-control session (a session-sharing seat with the Claude
app), not a fleet executor, while **top-right Kimi** is the owner's
general-purpose operator for asides and ad-hoc "btw" questions, not an executor
lane. Useful consequence: because top-Kimi handles Q&A and asides rather than
repo edits, it rarely contends with the `kimi` bottom worker over `.kimi/`,
so the two-Kimi write-race risk is lower than the raw "Kimi runs twice" framing
implies. The **bottom row is unchanged from the original decision**: four side-by-side
auto-polling self-driving pane-runner workers — `claude`, Kiro, Kimi,
OpenCode. Consequently **Kimi now runs in two roles simultaneously, exactly
mirroring Claude's existing split**: an interactive top cockpit and a
`kimi` bottom worker that polls `to-kimi/`; two Kimi processes touch
`.kimi/`, but the ADR-0008 claim-lock keeps the auto worker from double-grabbing
handoffs while the interactive one is human-paced. The **read-side claim race**
previously flagged only for app-Claude (the "#42 half-closed race" — an
interactive operator may act on a handoff a worker also grabs, because the
operator does not yet check `Test-HandoffClaimed` before acting) **now extends
to the second operator, Kimi**; it is an **open follow-up of the same severity
as the Claude case** and must be closed for both operators before either is
relied on for unattended dispatch. On layout selection, the **new default build
is the 2+4 six-pane layout**; the prior **1+4 (`5pane`)** and flat **4-pane
(`4grid`)** layouts are retained as `RWN_PANE_LAYOUT` fallbacks for rollback.
`tools/4ai-panes/Selector.ps1` implements this as the `6pane` default build
(`$topStripFraction = 0.50`), with `5pane` (1+4) and `4grid` retained as
`RWN_PANE_LAYOUT` fallbacks.
