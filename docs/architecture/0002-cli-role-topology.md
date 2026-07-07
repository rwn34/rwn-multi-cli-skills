# 2. CLI Role Topology and Release Pipeline

## Status

Accepted (2026-07-07, decided by project owner)

## Context

- Multiple AI CLIs (Claude Code, Kimi CLI, Kiro CLI) work in this project and share state via `.ai/`. Without an explicit role topology, any CLI could author, review, and ship the same change — no separation of duties.
- The GitHub/release pipeline in particular needs a defined lane per step: who branches, who reviews, who gates, who merges, who deploys.
- Crush is a candidate fourth CLI (not yet onboarded; onboarding tracked separately). It currently has the weakest guardrail surface in this framework — no hooks layer, steering, or subagent roster — and deploy is the highest-risk lane, so its authority must be staged rather than granted wholesale.

## Decision

### Per-CLI roles

- **Claude Code** — architect + orchestrator + final reviewer. Owns specs, ADRs, delegation, PR gating, merge recommendation.
- **Kimi CLI** — high-throughput executor: bulk implementation, tests, mechanical refactors. Peer-reviews Kiro's work.
- **Kiro CLI** — premium-reasoning executor: complex implementation, debugging, root-cause analysis. Peer-reviews Kimi's work.
- **Crush** — narrow-scope ops/release operator (not yet onboarded; onboarding tracked separately). Staged authority:
  - **Stage 1 (at onboarding):** prepares deploys only — dry-runs, release checklists, config diffs, deploy reports. The human executes actual deploys.
  - **Stage 2 (requires an explicit amendment to this ADR):** may execute deploys with per-deploy human confirmation, once guardrail parity is demonstrated.

Rationale for Crush's narrow scope: it currently has the weakest guardrail surface (no hooks layer, steering, or subagent roster in this framework), and deploy is the highest-risk lane.

### Review flow

Executor CLI → peer CLI review (handoff + report to `.ai/reports/`) → Claude final review.

For small, low-risk changes the executor may go directly to Claude, stated explicitly in the handoff.

### GitHub/release pipeline

Separation of duties: author ≠ reviewer ≠ deployer.

1. **Branch/commit/push** — executing CLI (Kimi or Kiro) via its `infra-engineer` subagent.
2. **Open PR** — same CLI's `infra-engineer`, only on explicit user request.
3. **Peer review** — the OTHER executor's `reviewer` subagent (Kiro⇄Kimi), report to `.ai/reports/`.
4. **Pre-merge gate** (branch up-to-date, CI green, linked issue addressed, peer review passed) — Claude, as final reviewer.
5. **Merge** — Claude recommends, the user approves. A pre-authorized "merge-on-green" class for low-risk changes may be defined later by ADR amendment.
6. **Deploy** — interim (until Crush Stage 1 lands): Claude's `release-engineer`, dry-run first, explicit user confirmation, refuses on dirty tree or failing tests. Kimi and Kiro have NO deploy lane: deploy actions are out of scope for their `release-engineer` subagents. Their release-engineer configs are to be scoped down accordingly — implementation change tracked separately; this ADR is the authority.

## Consequences

- Kimi/Kiro `release-engineer` scope-down is a follow-up implementation task in their owners' territory (via handoffs).
- Crush onboarding follows `.ai/cli-map.md` § "Adding a new CLI" and is gated on this ADR.
- The SSOTs `.ai/instructions/orchestrator-pattern/principles.md` and `.ai/instructions/agent-catalog/principles.md` gain a short "CLI role lanes" section referencing this ADR (done in the same change set).

## References

- `docs/architecture/0001-root-file-exceptions.md` — root-file policy ADR (format precedent; Crush config dirs will require an amendment there at onboarding)
- `.ai/cli-map.md` § "Adding a new CLI" — Crush onboarding procedure
- `.ai/instructions/orchestrator-pattern/principles.md` — orchestrator/subagent delegation rules
- `.ai/instructions/agent-catalog/principles.md` — subagent roster incl. `infra-engineer`, `reviewer`, `release-engineer`
- `.ai/handoffs/README.md` — handoff protocol used by the review flow
