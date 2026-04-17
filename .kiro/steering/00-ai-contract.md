# AI Contract

Multiple AI CLIs work in this project (Claude Code, Kimi CLI, Kiro CLI = you). They
share state via `.ai/` so no CLI has to copy-paste another's output to stay coherent.

## Your identity for the activity log: `kiro-cli`

## Single source of truth

`.ai/instructions/` is canonical. Your `.kiro/steering/*.md` files are replicas. If they
disagree, `.ai/instructions/` wins — see `.ai/sync.md` to regenerate.

## Cross-CLI activity log — `.ai/activity/log.md`

**Read** at the start of non-trivial work. Newest entries are at the top — scan recent
ones to see what other CLIs did here.

**Prepend** one entry after completing substantive work (file edits, running tests,
non-obvious decisions, finishing a task):

    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: <one-line summary>
    - Files: <paths, or "—">
    - Decisions: <non-obvious choices, or "—">

**Timestamp rule:** use your current local wall-clock time at the moment you prepend
the entry — i.e. after the work is finished, not when you started. CLIs running in
different timezones or with drifted clocks may produce timestamps that don't sort
monotonically; **prepend order is the authoritative sequencing**, timestamps are
annotations.

Terse — one short paragraph max. One entry per substantive action, not per file edit.
Never rewrite prior entries. Do not log trivial reads.

## Cross-CLI handoffs

When another CLI needs you to execute a change in `.kiro/` or in Kiro's portion of the
shared docs, it writes a paste-ready instruction file to
`.ai/handoffs/to-kiro/open/NNN-slug.md`. Glance at that directory when a session starts
or when the user references a handoff. Follow the protocol in
`.ai/handoffs/README.md`: review, execute the steps, prepend an activity-log entry,
report back. The sender validates and moves the file to `.ai/handoffs/to-kiro/done/` on
success.

You can send handoffs too — write to `.ai/handoffs/to-claude/open/` or
`.ai/handoffs/to-kimi/open/` when you need those CLIs to change files in their folders.

## Archive folders (skip during routine reads)

Folders matching `.ai/**/archive/` (`.ai/activity/archive/`,
`.ai/research/archive/`, and any future archive subfolders under `.ai/`) contain
historical content. Do NOT read them during routine operations. Only consult when the
user explicitly references historical activity or archived research (e.g., "what
happened last month?", "pull up the old research on X"). See each archive folder's
`README.md` for the archival protocol if you're asked to perform an archive move.

## Root file policy

Strict: only files explicitly listed in the ADR are permitted at project root.
See `docs/architecture/0001-root-file-exceptions.md` for the full exception list
and the process for adding new exceptions. Do not re-state the list here — the ADR
is the single authority.
