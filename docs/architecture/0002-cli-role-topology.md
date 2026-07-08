# 2. CLI Role Topology and Release Pipeline

## Status

Accepted (2026-07-07, decided by project owner)

Amended 2026-07-08 (owner directive): Kimi/Kiro lanes extended to executor + tester; Crush granted Stage 2 (deploy execution, human-gated) + general-helper duties. Crush onboarding completed 2026-07-07.

## Context

- Multiple AI CLIs (Claude Code, Kimi CLI, Kiro CLI) work in this project and share state via `.ai/`. Without an explicit role topology, any CLI could author, review, and ship the same change — no separation of duties.
- The GitHub/release pipeline in particular needs a defined lane per step: who branches, who reviews, who gates, who merges, who deploys.
- Crush is a candidate fourth CLI (not yet onboarded; onboarding tracked separately). It currently has the weakest guardrail surface in this framework — no hooks layer, steering, or subagent roster — and deploy is the highest-risk lane, so its authority must be staged rather than granted wholesale. *[Amendment 2026-07-08: Crush was onboarded 2026-07-07 and Stage 2 has been granted — see Decision. The guardrail-surface fact still holds.]*

## Decision

### Per-CLI roles

- **Claude Code** — architect + orchestrator + final reviewer. Owns specs, ADRs, delegation, PR gating, merge recommendation.
- **Kimi CLI** — high-throughput executor + tester: bulk implementation, test authoring/execution, mechanical refactors. Peer-reviews Kiro's work. *[Amended 2026-07-08: tester lane added.]*
- **Kiro CLI** — premium-reasoning executor + tester: complex implementation, debugging, root-cause analysis, test authoring/execution. Peer-reviews Kimi's work. *[Amended 2026-07-08: tester lane added.]*
- **Crush** — general helper + DevOps deployment operator (onboarded 2026-07-07). *[Amended 2026-07-08: this block replaces the original Stage 1/Stage 2 staged-authority language; Stage 2 is now GRANTED by owner directive.]*
  - **Deploy execution (Stage 2, granted 2026-07-08):** Crush may execute deploys with (a) mandatory dry-run first, (b) per-deploy human confirmation — deploys remain Tier-C hard-gated in the autonomy policy, (c) refusal on dirty tree or failing tests.
  - **General helper:** small cross-cutting ops chores (env checks, housekeeping scripts, release checklists) within the `CRUSH.md` SAFETY RULES write scope.
  - **Residual risk (unchanged by this amendment):** Crush still has NO hook layer (see `.ai/known-limitations.md` § Crush) — its guardrails are prompt-level only. Deploy briefs must be exact, and every mutating command human-confirmed.

Rationale for Crush's originally narrow scope: it has the weakest guardrail surface (no hooks layer, steering, or subagent roster in this framework), and deploy is the highest-risk lane. That gap persists post-amendment — it is why Stage 2 stays human-gated per deploy rather than autonomous.

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
6. **Deploy** — *[Amended 2026-07-08]* Crush executes (dry-run first + per-deploy human confirmation; refuses on dirty tree or failing tests). Claude's `release-engineer` is the FALLBACK deploy lane when Crush is unavailable, under the same conditions. Kimi and Kiro have NO deploy lane — unchanged: deploy actions are out of scope for their `release-engineer` subagents. Their release-engineer configs are to be scoped down accordingly — implementation change tracked separately; this ADR is the authority.

## Consequences

- Kimi/Kiro `release-engineer` scope-down is a follow-up implementation task in their owners' territory (via handoffs).
- Crush onboarding follows `.ai/cli-map.md` § "Adding a new CLI" and is gated on this ADR. *[Completed 2026-07-07.]*
- The SSOTs `.ai/instructions/orchestrator-pattern/principles.md` and `.ai/instructions/agent-catalog/principles.md` gain a short "CLI role lanes" section referencing this ADR (done in the same change set).
- *[Amendment 2026-07-08]* `CRUSH.md`, the operating-prompt SSOT §4, and the agent-catalog role-lane sections must be regenerated to match this amendment (tracked in the 2026-07-08 rebuild session).

## References

- `docs/architecture/0001-root-file-exceptions.md` — root-file policy ADR (format precedent; Crush config dirs will require an amendment there at onboarding)
- `.ai/cli-map.md` § "Adding a new CLI" — Crush onboarding procedure
- `.ai/instructions/orchestrator-pattern/principles.md` — orchestrator/subagent delegation rules
- `.ai/instructions/agent-catalog/principles.md` — subagent roster incl. `infra-engineer`, `reviewer`, `release-engineer`
- `.ai/handoffs/README.md` — handoff protocol used by the review flow
