# AI Contract

Multiple AI CLIs work in this project (Claude Code = you, Kimi CLI, Kiro CLI). They
share state via `.ai/` so no CLI has to copy-paste another's output to stay coherent.

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
paste-ready file to `.ai/handoffs/to-<kimi|kiro>/open/NNN-slug.md`. See
`.ai/handoffs/README.md` + `template.md` for the protocol. Before starting new
non-trivial work, glance at `.ai/handoffs/to-claude/open/` — anything there is a
task addressed to you.

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
