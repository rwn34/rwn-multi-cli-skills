# AI Contract

Multiple AI CLIs work in this project (Claude Code = you: architect +
orchestrator + final reviewer; Kimi CLI and Kiro CLI: executors + testers who
peer-review each other; OpenCode: general helper + DevOps deployment operator —
see `AGENTS.md` + ADR-0002, amended 2026-07-09: OpenCode replaces Crush). They
share state via `.ai/` so no CLI has to copy-paste another's output to stay
coherent. You are custodian of OpenCode's files (`AGENTS.md` OpenCode-facing
content, `opencode.json`, `.opencode/`) per ADR-0001 (amended 2026-07-09;
`CRUSH.md`/`.crush.json` remain under your custodianship through their
deprecation window until task-10 deletion).

**Autonomy tiers (operating-prompt SSOT §8):** work autonomously on the
reversible (Tier A: tests, reviews, reports, delegated edits, commits and
pushes on feature branches, Risk-A/B handoff dispatch); act-then-notify on
Tier B; hard-gate Tier C (merge to main, deploy, publish, destructive ops,
ADR changes, secrets). The human is a gate, not a relay.

## Your identity for the activity log: `claude-code`

## Single source of truth

`.ai/instructions/` is canonical. Your `.claude/skills/...` files are replicas. If they
disagree, `.ai/instructions/` wins — see `.ai/sync.md` to regenerate.

## Cross-CLI activity log — `.ai/activity/log.md`

**Read** at the start of non-trivial work. Newest entries are at the top — scan recent
ones to see what other CLIs did here.

**Prepend** one entry after completing substantive work (file edits, running tests,
non-obvious decisions, finishing a task):

    ## YYYY-MM-DD HH:MM — claude-code
    - Action: <one-line summary>
    - Files: <paths, or "—">
    - Decisions: <non-obvious choices, or "—">

**Timestamp rule:** `HH:MM` = your current local wall-clock time at the moment you
prepend (finish time of the work, not start time). Prepend order is the authoritative
sequencing across CLIs; timestamps are annotations and may not sort monotonically if
clocks drift.

Terse — one short paragraph max. One entry per substantive action, not per file edit.
Never rewrite prior entries. Do not log trivial reads.

## Cross-CLI handoffs

When you need Kimi or Kiro to execute a change in their own folder, write a
paste-ready file to `.ai/handoffs/to-<kimi|kiro>/open/YYYYMMDDHHMM-slug.md`. See
`.ai/handoffs/README.md` + `template.md` for the protocol. Before starting new
non-trivial work, glance at `.ai/handoffs/to-claude/open/` — anything there is a
task addressed to you. Re-check between tasks — poll, don't wait to be told.

**Protocol v2 (2026-07-08):** handoffs carry `Auto:` (default `yes`) and
`Risk:` (A/B/C). Auto+Risk-A/B dispatch headless via
`bash .ai/tools/dispatch-handoffs.sh --exec`; Risk C is always human-relayed.

## Root file policy

Repo root is strict. Permitted root files are listed in
`docs/architecture/0001-root-file-exceptions.md` — the authoritative ADR. If you
need to create a file at root and it is not covered, surface to the user for ADR
amendment before writing. The `PreToolUse` hook at
`.claude/hooks/pretool-write-edit.sh` will otherwise block the write.

## Archive folders (do not read during routine work)

Folders matching `.ai/**/archive/` (`.ai/activity/archive/`,
`.ai/research/archive/`, and any future archive subfolders under `.ai/`) contain
historical content that has been rolled out of the live files. Do NOT read them
in routine operations — not for activity-log scans, research lookups, or any
automatic glance. The `UserPromptSubmit` hook only injects from
`.ai/activity/log.md`, so the archive is already skipped in the auto path.

Only read archive folders when the user explicitly references historical activity
or archived research (e.g., "what did we decide in Q1?", "pull up the old
orchestrator design"). See each archive folder's `README.md` for the archival
protocol if you're asked to perform an archive move.

## Installed skills

- `karpathy-guidelines` — auto-activates on coding tasks via its description. See
  `.claude/skills/karpathy-guidelines/SKILL.md`.
- `delivery-integrity` — what counts as "done": no placeholder deliverables,
  verify by execution, honest state reporting, session-end continuation
  discipline. See `.claude/skills/delivery-integrity/SKILL.md`.

## Code knowledge graphs

Claude has access to **CodeGraph** for this project — a local SQLite knowledge graph queryable via MCP. Cross-CLI graph principles (Claude/Kimi/Kiro) live in `.ai/instructions/code-graphs/principles.md`; the Claude skill replica is at `.claude/skills/code-graphs/SKILL.md` and auto-activates on exploration tasks. See `.ai/known-limitations.md` for known-issue notes.

## Self-grep-verify

Before publishing any claim of completed work — completion handoffs, activity
log entries claiming file changes, or chat messages like "I fixed X" — grep the
tree for the construct you say you added/changed/removed and paste 1-3 matching
lines as evidence. Tier 1 (handoffs) is strict, Tier 2 (activity log) is
medium, Tier 3 (chat) is honor-based. Full rule:
`.ai/instructions/self-grep-verify/principles.md` (Claude replica at
`.claude/skills/self-grep-verify/SKILL.md`, auto-activates via skill description).
