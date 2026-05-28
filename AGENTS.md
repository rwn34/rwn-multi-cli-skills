# AGENTS.md

This project is worked on by multiple AI CLIs — Claude Code, Kimi CLI, Kiro CLI —
sharing state via a single source of truth plus a cross-CLI activity log.

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

A breadcrumb pointer exists at `.claude/00-ai-contract.md` so any CLI browsing
`.claude/` can locate Claude's contract without knowing Claude's conventions.

## Activity log protocol (same for all CLIs)

- **Read** `.ai/activity/log.md` at the start of non-trivial work. Newest entries on top.
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
paste-ready instruction file to `.ai/handoffs/to-<recipient>/open/NNN-slug.md` (see
`.ai/handoffs/README.md` + `template.md` for the protocol and shape). Handoffs may
be addressed to any CLI, including Claude.

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
