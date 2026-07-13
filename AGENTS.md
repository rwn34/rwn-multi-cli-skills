# AGENTS.md

**This file is a ROUTER, not an identity. Determine which CLI you are from
how you were launched, then read YOUR OWN contract file below. Never adopt
another CLI's contract.**

This project is worked on by multiple AI CLIs — Claude Code (architect +
orchestrator + final reviewer), Kimi CLI (executor + tester), Kiro CLI
(executor + tester), plus OpenCode as general helper + DevOps deployment
operator (ADR-0002 Stage 2, Crush replacement per owner decision 2026-07-09)
— sharing state via a single source of truth plus a cross-CLI activity log.
Each CLI stays in its lane; role definitions and limitations live in the
operating-prompt SSOT (`.ai/instructions/operating-prompt/principles.md` §4).

## Shared framework

- `.ai/README.md` — full layout explanation
- `.ai/cli-map.md` — how each CLI's native concepts map to the shared framework
- `.ai/instructions/` — canonical (SSOT) portable behavioural rules
- `.ai/activity/log.md` — append-only cross-CLI activity ledger

## Per-CLI contract entry points

Each CLI reads its own contract from its native always-loaded path:

| CLI | Contract file |
|---|---|
| Claude Code | `/CLAUDE.md` (project root — Claude's native auto-load path) |
| Kimi CLI | `.kimi/steering/00-ai-contract.md` |
| Kiro CLI | `.kiro/steering/00-ai-contract.md` |
| OpenCode | `.opencode/contract.md` (loaded via `opencode.json` agent prompt) |

A breadcrumb pointer exists at `.claude/00-ai-contract.md` so any CLI browsing
`.claude/` can locate Claude's contract without knowing Claude's conventions.

## OpenCode's lane (OpenCode only — other CLIs skip this section)

**GitHub / repo-ops lane** (owner directive 2026-07-11, extended 2026-07-12;
operating-prompt §8/§14): OpenCode owns GitHub and DevOps *operations* — opening
PRs, **merging peer-reviewed CI-green PRs (Tier B)**, branch deletion,
**repo/tree/worktree cleanup (Tier B)**, release chores, **CI config / workflow
fixes**, tag/version consistency, repo housekeeping. **All git/GitHub mechanics
are fleet-executed — the owner does not gate them.** Claude's budget is the
smallest in the fleet, so it routes this work to OpenCode as handoffs in
`.ai/handoffs/to-opencode/open/`. Guardrails are unchanged: no source-code edits,
dry-run first for anything mutating a live environment.

**Deploy — the environment decides the gate** (ADR-0011 amendment 2026-07-12b):
**staging deploy is Tier B** (OpenCode's call — dry-run first, refuse on a dirty
tree or failing tests, then notify), **production deploy is Tier C** (owner-gated,
per-deploy human confirmation on every mutating command, all four Stage-2
conditions intact). A merge must never auto-trigger a deploy, and a staging deploy
must never auto-promote to production. Full conditions: `.opencode/contract.md`.

**OpenCode's writable lane** — enforced mechanically by
`.opencode/plugin/framework-guard.js`; everything not listed is denied:

<!-- LANE:BEGIN — machine-checked against WRITABLE_LANE in .opencode/plugin/framework-guard.js by test-guard.mjs. Change both together or the guard suite fails. -->
- `.ai/activity/log.md`
- `.ai/activity/entries/**`
- `.ai/reports/**`
- `.ai/handoffs/**`
- `.github/**`
<!-- LANE:END -->

`.ai/activity/entries/**` is permission plumbing for the ADR-0010 activity-log
spool. Nothing has migrated: log by prepending to `.ai/activity/log.md` as today.

`.github/**` is the only source-adjacent path in the lane. Project source,
`.claude/`, `.kimi/`, `.kiro/`, `.ai/instructions/` (SSOT), `docs/architecture/`
(ADRs), `infra/`, `scripts/` and secrets files are all blocked. Full contract:
`.opencode/contract.md`.

## Activity log protocol (same for all CLIs)

**Never read `.ai/activity/log.md` wholesale.** It is ~600 KB / 2,100+ lines
(370+ entries) and grows ~5–10 KB/day; a full read costs ~125k tokens on almost
entirely irrelevant history. Newest entries are at the **top**, so everything you
actually need sits in the first few dozen lines.

- **Recent activity** → if your CLI injects the top of the log into context each
  turn (Claude Code's `UserPromptSubmit` hook does), it is **already in your
  context before you ask** — use it, do not re-read. If your CLI has no inject
  hook (OpenCode), read only a **bounded top window** (`head -40
  .ai/activity/log.md`, or a `Read` with `limit`) — that bounded read *is* the
  "read at the start of non-trivial work" step.
- **Specific history** → `grep -n "<topic>" .ai/activity/log.md`, or a bounded
  read with `limit`/`offset`. Never the whole file, never `cat`.

- **Prepend** one terse entry after substantive work. Format:

        ## YYYY-MM-DD HH:MM — <cli-name>
        - Action: <one-line summary>
        - Files: <paths, or "—">
        - Decisions: <non-obvious choices, or "—">

**Timestamp rule:** the `HH:MM` is your current local wall-clock time at the moment
you prepend — i.e. finish time of the work, not start time. CLIs on different local
clocks may produce timestamps that don't sort monotonically; prepend order is
authoritative, timestamps are annotations.

Never rewrite prior entries. Do not log trivial reads. Use your CLI's identity name
(see your contract file).

## Cross-CLI handoffs

When you need another CLI to execute a change in its own folder, write a
paste-ready instruction file to `.ai/handoffs/to-<recipient>/open/YYYYMMDDHHMM-slug.md` (see
`.ai/handoffs/README.md` + `template.md` for the protocol and shape). Handoffs may
be addressed to any CLI, including Claude. The `YYYYMMDDHHMM` filename prefix is
**UTC** (`date -u +%Y%m%d%H%M`) even though your `Created:` line and activity-log
entries use local wall-clock — do not put local time in the filename.

**Protocol v3 (2026-07-09):** every handoff carries `Auto:` (default `yes`) and
`Risk:` (`A`/`B`/`C` per the autonomy tiers in the operating-prompt SSOT §8).
`Auto: yes` + Risk A/B dispatch headless via
`bash .ai/tools/dispatch-handoffs.sh --exec`; Risk C is always human-relayed.
When you are the **recipient**, self-retire on completion: set the handoff Status
to `DONE` and move the file from `open/` to `done/` yourself — the sender
validates post-hoc. If blocked, leave it in `open/` as `BLOCKED` with a verbatim
`## Blocker`. Check your own inbox between tasks — poll, don't wait to be told.

## Delivery integrity (what counts as "done")

No placeholder/stub/mock presented as finished work; verify by execution, not
inspection; report partial as partial and blocked as blocked; end sessions
with a continuation artifact for anything unfinished. Full rule:
`.ai/instructions/delivery-integrity/principles.md`.

## Self-grep-verify (claims must be grounded in the tree)

When a CLI claims completed work — in a completion handoff to
`.ai/handoffs/to-<other>/open/`, in an `.ai/activity/log.md` entry, or in a
chat message — every concrete claim must be backed by a `rg`/`grep` snippet
showing the actual line(s) in the working tree. Enforcement is asymmetric:
strict for handoffs (where another CLI builds on the work), medium for activity
log entries, soft for chat (where the user catches drift live).

Full rule: `.ai/instructions/self-grep-verify/principles.md`.

## Archive folders (skip during routine reads)

Folders matching `.ai/**/archive/` (`.ai/activity/archive/`,
`.ai/research/archive/`, and any future archive subfolders under `.ai/`) contain
historical content. Do NOT read them during routine operations. Only consult when
the user explicitly references historical activity or archived research. Each
archive folder has its own `README.md` with archival protocol.
