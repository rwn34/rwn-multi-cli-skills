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
coordinated through shared files rather than any direct channel.

### 1. Topology — a 5-pane Windows Terminal tab per project

- **TOP pane:** a full-width horizontal strip, ~20% height (configurable),
  running **app-Claude** = the interactive orchestrator. **No polling, no
  pane-runner** — the owner's remote app attaches here. Identity: `claude-code`.
- **BOTTOM 4 panes:** `auto-Claude`, Kimi, Kiro, OpenCode — each running the
  self-driving pane-runner (ADR-0008), and each **independently pausable**
  (`p` → interactive; exit the CLI → auto-resume). Pausing or stopping one pane
  never affects the others or the top strip.

### 2. auto-Claude role and identity

- **auto-Claude** is a headless Claude **limited to Tier A/B work** on the
  `to-claude` queue: review, verification, and chaining follow-up handoffs. It
  **never** performs Tier C (merge to main, ADR create/amend, deploy,
  publish/tag, force-push, destructive ops) — those remain exclusively with
  app-Claude + the human gate (ADR-0002 autonomy tiers).
- **Distinct identity `claude-auto`** (separate from `claude-code`) for *both*
  activity-log attribution *and* claim-lock ownership, so the two Claude
  instances are always distinguishable in the shared state.

### 3. Coordination — Claude-to-Claude via files, not direct

- A per-project, per-handoff **claim-lock** (extends backlog #1/#32): before
  running a `to-claude` handoff, a consumer writes an atomic claim marker (owner
  identity + pid + timestamp). Others skip claimed items. Dead-pid/stale claims
  are reclaimable after a staleness window.
- **app-Claude checks the claim-lock/heartbeat before acting** on a `to-claude`
  item: if `claude-auto` holds it, app-Claude leaves it alone (or queues
  additional work) — it never double-processes.
- The **same lock** also resolves the already-observed Kimi-vs-Kimi /
  Kiro-vs-Kiro same-handoff double-grab.

## Consequences

- **Prerequisite ordering.** The claim-lock **MUST** land before auto-Claude is
  enabled, else the race persists. Sequence: this ADR → claim-lock → 5-pane
  layout + auto-Claude wiring.
- **Cost: one more polling Claude.** Idle polling is filesystem-only (zero
  tokens); cost is incurred only on real handoff pickup, bounded by the
  auto-continue MAX cap (ADR-0008). Pairs with backlog #6 (cost observability).
- **New identity `claude-auto`** must be registered across the CLI-identity
  surfaces (activity log, claim-lock, dispatcher/pane-runner). Minor additive
  surface.
- **Launcher change.** `Selector.ps1` / the launch script must build a 5-pane WT
  layout (1 top split + 4 bottom) instead of the current 4-pane grid; the
  installed `~/.rwn-auto` copy is updated in lockstep.
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
  auto-Claude reviewer; the 5-pane split expresses this directly.

## References

- `docs/architecture/0002-*` — role lanes + autonomy tiers (the Claude lane,
  Tier A/B/C definitions this ADR constrains auto-Claude to).
- `docs/architecture/0008-self-driving-fleet-pane-runner.md` — the self-driving
  pane-runner this ADR extends (poll → claim → run → auto-continue, MAX cap).
- `.ai/research/framework-improvement-backlog.md` — #1/#32 (claim-lock),
  #7 (concurrency safety), #6 (cost observability).
