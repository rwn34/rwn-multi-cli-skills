# Activity Log Archive

Historical activity-log content moved out of the live spool `.ai/activity/entries/`
so the spool stays small. **AI CLIs do not read files in this directory during
routine operations.** Only consulted when the user explicitly references
historical activity (e.g., "what did we decide in March?", "when did we first
set up the hooks?").

## Layout

    archive/
    ├── README.md            this file
    ├── log-pre-spool.md     frozen pre-ADR-0010 log, verbatim — one `git mv`,
    │                        zero content transformation (ADR-0010 §6)
    └── YYYY-MM/             one directory per calendar month, holding archived
                             entry files verbatim (moved, never edited)

## Archival protocol (ADR-0010 §5)

Manual. Triggers (any is fine):

- **Month rollover** — once a calendar month has fully closed, move that month's
  entry files to `archive/YYYY-MM/`.
- **Size threshold** — if the live spool exceeds ~150 entry files, archive the
  oldest closed-month entries regardless of recency.
- **Explicit request** — user says "archive the log".

Steps:

1. `mkdir -p .ai/activity/archive/YYYY-MM`
2. `git mv .ai/activity/entries/YYYYMM*.md .ai/activity/archive/YYYY-MM/`
3. Write a new entry file in `.ai/activity/entries/` noting what was archived
   and where.
4. Never delete entries — only move. Never edit moved entries.

Archival is a **move with no content transformation**. The old cut-and-regroup
protocol (rewriting `log.md`, regrouping entries by day into monthly rollup
files) is retired: it was itself a whole-file rewrite of a shared file and
raced live writers — the exact clobber class ADR-0010 exists to remove.

Because the CLIs run in one project, any CLI can perform the archive. Archival
is a substantive action; log it in the spool like any other.

## Read rule for AI CLIs

Do NOT read `.ai/activity/archive/**` during routine work — not in the
session-start log scan, not in the `UserPromptSubmit` hook injection, not when
scanning for recent activity. The renderer (`.ai/tools/render-activity-log.sh`)
and all injection hooks read `.ai/activity/entries/` only, so archive content
is skipped by construction rather than by discipline.

Only read archive files when the user explicitly references historical activity.

## Timestamp note

Entry **filenames** are UTC sort keys (`YYYYMMDDTHHMMSSZ`); entry **headings**
inside the files are local wall-clock annotations. Sort order is filename order
— best-effort chronological, not causal (ADR-0010 §4). The frozen
`log-pre-spool.md` keeps its original convention verbatim: local wall-clock
headings, prepend order authoritative within that file.
