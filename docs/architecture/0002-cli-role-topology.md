# 2. CLI Role Topology and Release Pipeline

## Status

Accepted (2026-07-07, decided by project owner)

Amended 2026-07-08 (owner directive): Kimi/Kiro lanes extended to executor + tester; Crush granted Stage 2 (deploy execution, human-gated) + general-helper duties. Crush onboarding completed 2026-07-07.

Amended 2026-07-09 (owner directive): OpenCode replaces Crush as the fourth
CLI — same role lane (general helper + Stage-2 deployment operator), same
Stage-2 conditions carried over verbatim. The TUI contingency raised by the
smoke test was RESOLVED same day via option (a): owner confirmed the TUI
renders correctly in the daily-driver Windows Terminal (the smoke test's DLL
error 126 occurred only under headless/redirected launches). Crush's history
remains in this ADR as record; Crush-specific text below is superseded where
marked.

## Context

- Multiple AI CLIs (Claude Code, Kimi CLI, Kiro CLI) work in this project and share state via `.ai/`. Without an explicit role topology, any CLI could author, review, and ship the same change — no separation of duties.
- The GitHub/release pipeline in particular needs a defined lane per step: who branches, who reviews, who gates, who merges, who deploys.
- Crush is a candidate fourth CLI (not yet onboarded; onboarding tracked separately). It currently has the weakest guardrail surface in this framework — no hooks layer, steering, or subagent roster — and deploy is the highest-risk lane, so its authority must be staged rather than granted wholesale. *[Amendment 2026-07-08: Crush was onboarded 2026-07-07 and Stage 2 has been granted — see Decision. The guardrail-surface fact still holds.]*
- *[Amendment 2026-07-09]* Crush exhibited identity drift in daily use.
  Root cause: its contract (`CRUSH.md`) is loaded once per session with no
  per-turn reinforcement, it has no hook layer, and the daily `--yolo`
  launch removed the last interactive friction — so nothing mechanical ever
  re-asserted the SAFETY RULES after context grew. This confirmed the
  original Context observation ("weakest guardrail surface") as a practical
  failure, not just a theoretical one. OpenCode was selected as replacement
  because its guardrails are mechanical, not prompt-level: its permission
  system (`allow`/`ask`/`deny`) removes denied tools from the model's tool
  list at the harness level (smoke-test proven 2026-07-09), it supports JS
  plugin hooks (worktree-confinement / fleet-whitelist parity with the
  other CLIs' hook layers), and it has an agents system for role scoping.

## Decision

### Per-CLI roles

- **Claude Code** — architect + orchestrator + final reviewer. Owns specs, ADRs, delegation, PR gating, merge recommendation.
- **Kimi CLI** — high-throughput executor + tester: bulk implementation, test authoring/execution, mechanical refactors. Peer-reviews Kiro's work. *[Amended 2026-07-08: tester lane added.]*
- **Kiro CLI** — premium-reasoning executor + tester: complex implementation, debugging, root-cause analysis, test authoring/execution. Peer-reviews Kimi's work. *[Amended 2026-07-08: tester lane added.]*
- **OpenCode** — general helper + DevOps deployment operator. *[Amended
  2026-07-09: OpenCode replaces Crush in this lane by owner directive. The
  role definition is unchanged from the 2026-07-08 amendment; only the CLI
  filling it changes.]*
  - **Deploy execution (Stage 2, carried over):** OpenCode may execute
    deploys under the same four conditions Crush held, carried verbatim
    from the Crush contract:
    1. **Dry-run first, always** (`--dry-run`, `terraform plan`, staging
       target) and paste the dry-run output before proposing the real run.
    2. **Per-deploy human confirmation** — every mutating deploy command is
       individually confirmed by the human in-session. Deploys are Tier-C
       hard-gated (operating-prompt §8) no matter who executes them.
       *[Amended 2026-07-12b by ADR-0011: this condition now applies to
       **PRODUCTION** deploys only. **Staging** deploys are Tier B —
       fleet-authorized, act-then-notify, no per-deploy human confirmation.
       Conditions 1, 3 and 4 apply to BOTH environments, unchanged. A staging
       deploy must never auto-promote to production.]*
    3. **Only commands enumerated in an approved deploy brief** (a handoff
       in the deploy inbox). Never improvise a command that is not in the
       brief — if the brief is wrong, STOP and report.
    4. **Refuse on dirty working tree or failing tests.** No exceptions.
  - **General helper:** small cross-cutting ops chores (env checks,
    housekeeping scripts, release checklists) within the OpenCode contract
    write scope (successor to the `CRUSH.md` SAFETY RULES scope).
  - **Guardrail surface (improvement over Crush):** unlike Crush, OpenCode's
    boundaries are enforced mechanically: `deny` rules strip tools at the
    harness level (the model cannot call what it cannot see), and JS plugin
    hooks provide worktree-confinement and fleet-whitelist parity with the
    Claude/Kimi/Kiro hook layers. Stage 2 nonetheless remains human-gated
    per deploy — the gate is policy, not a workaround for missing tooling.
  - **Identity / inbox:** activity-log identity changes `crush` →
    `opencode`; handoff inbox changes `.ai/handoffs/to-crush/` →
    `.ai/handoffs/to-opencode/`. The `to-crush/done/` history is preserved
    read-only (never rewritten, per handoff protocol).
  - **Key handling (owner directive 2026-07-09: "use the key as is"):**
    provider API keys remain user-scope local literals, migrated
    programmatically (value never displayed) from Crush's
    `%LOCALAPPDATA%\crush\crush.json` into OpenCode's user-scope global
    config (`~/.config/opencode/opencode.json`) — same security posture as
    today, zero owner action. The REPO-level `opencode.json` carries NO key
    material of any kind; OpenCode merges global + project config at
    runtime. (The repo-level `.crush.json` was verified key-free —
    `{ "mcp": {} }` — the inline-literal storage exists in the user-scope
    config only, and stays user-scope.)
  - **Smoke-test record (2026-07-09, opencode-ai 1.17.15, native
    Windows):** headless run PASS; permission `deny` PASS (harness-level
    tool removal); JS plugin hooks PASS; `{env:}` substitution PASS;
    TUI failed under headless/redirected launch (OpenTUI DLL error 126)
    but was confirmed working same day in the owner's real Windows
    Terminal session — contingency (a) RESOLVED; swap unconditional.

Rationale for Crush's originally narrow scope: it has the weakest guardrail surface (no hooks layer, steering, or subagent roster in this framework), and deploy is the highest-risk lane. That gap persists post-amendment — it is why Stage 2 stays human-gated per deploy rather than autonomous. *[Amendment 2026-07-09: the "no hooks layer" gap this paragraph describes
is closed by the OpenCode swap (harness-level permissions + plugin hooks).
The per-deploy human gate is retained as policy regardless.]*

### Review flow

Executor CLI → peer CLI review (handoff + report to `.ai/reports/`) → Claude final review.

For small, low-risk changes the executor may go directly to Claude, stated explicitly in the handoff.

### GitHub/release pipeline

Separation of duties: author ≠ reviewer ≠ deployer.

1. **Branch/commit/push** — executing CLI (Kimi or Kiro) via its `infra-engineer` subagent.
2. **Open PR** — same CLI's `infra-engineer`, only on explicit user request.
3. **Peer review** — the OTHER executor's `reviewer` subagent (Kiro⇄Kimi), report to `.ai/reports/`.
4. **Pre-merge gate** (branch up-to-date, CI green, linked issue addressed, peer review passed) — Claude, as final reviewer.
5. **Merge** — Claude recommends, the user approves. A pre-authorized "merge-on-green" class for low-risk changes may be defined later by ADR amendment. *[Amended 2026-07-12 by ADR-0011: merge is Tier B — the fleet merges a peer-reviewed, CI-green PR and notifies the owner after. No owner pre-approval.]*
6. **Deploy** — *[Amended 2026-07-08]* *[Amended 2026-07-09]* *[Amended 2026-07-12b by ADR-0011: **staging** deploy is Tier B (the fleet's call — dry-run first, refuse on dirty tree or failing tests, no human confirmation); **production** deploy stays Tier C, owner-gated per deploy, with all four Stage-2 conditions intact. A staging deploy must never auto-promote to production.]* OpenCode executes (dry-run first + per-deploy human
confirmation for production; refuses on dirty tree or failing tests). Claude's
`release-engineer` is the FALLBACK deploy lane when OpenCode is
unavailable, under the same conditions. Kimi and Kiro have NO deploy lane — unchanged: deploy actions are out of scope for their `release-engineer` subagents. Their release-engineer configs are to be scoped down accordingly — implementation change tracked separately; this ADR is the authority.

## Consequences

- Kimi/Kiro `release-engineer` scope-down is a follow-up implementation task in their owners' territory (via handoffs).
- Crush onboarding follows `.ai/cli-map.md` § "Adding a new CLI" and is gated on this ADR. *[Completed 2026-07-07.]*
- The SSOTs `.ai/instructions/orchestrator-pattern/principles.md` and `.ai/instructions/agent-catalog/principles.md` gain a short "CLI role lanes" section referencing this ADR (done in the same change set).
- *[Amendment 2026-07-08]* `CRUSH.md`, the operating-prompt SSOT §4, and the agent-catalog role-lane sections must be regenerated to match this amendment (tracked in the 2026-07-08 rebuild session).
- *[Amendment 2026-07-09]* The Crush→OpenCode swap touches every file that
  names Crush in an operative (non-historical) way — root contracts, SSOT
  principles + their three replica channels, hooks/tests, the 4AI-panes
  launcher, the installer and its asset tree, dispatch tooling, and the
  fleet scripts. The grep-derived migration checklist lives in
  `.ai/research/adr-drafts-crush-to-opencode.md` §3 until executed.
  Historical records (activity log, done/ handoffs, dated research notes,
  prior ADR text) are NOT rewritten.
- *[Amendment 2026-07-09]* `CRUSH.md` and `.crush.json` are deprecated on
  landing of this amendment and physically deleted only after the swap's
  end-to-end verification gate (swap workstream task 10); ADR-0001's root
  exceptions for them are removed in the same commit as the deletion (see
  ADR-0001 amendment of the same date).

## References

- `docs/architecture/0001-root-file-exceptions.md` — root-file policy ADR (format precedent; Crush config dirs will require an amendment there at onboarding)
- `.ai/cli-map.md` § "Adding a new CLI" — Crush onboarding procedure
- `.ai/instructions/orchestrator-pattern/principles.md` — orchestrator/subagent delegation rules
- `.ai/instructions/agent-catalog/principles.md` — subagent roster incl. `infra-engineer`, `reviewer`, `release-engineer`
- `.ai/handoffs/README.md` — handoff protocol used by the review flow
