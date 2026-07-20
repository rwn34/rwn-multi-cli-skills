# AI Contract

Multiple AI CLIs work in this project (Claude Code, Kimi CLI, Kiro CLI = you). They
share state via `.ai/` so no CLI has to copy-paste another's output to stay coherent.

## Your identity for the activity log: `kiro`

You are the interactive Kiro CLI session. The bare name `kiro` is also the
headless auto-pane identity; there is no `kiro-cockpit`. Use `kiro` for
activity-log entries you prepend here.

## Single source of truth

`.ai/instructions/` is canonical. Your `.kiro/steering/*.md` files are replicas. If they
disagree, `.ai/instructions/` wins — see `.ai/sync.md` to regenerate.

## Cross-CLI activity log — `.ai/activity/entries/` (spool; ADR-0010)

The activity log is an **entry-per-file spool**, not a shared file you edit. Each
substantive action gets its **own new file** — you never open, prepend to, or
rewrite anyone else's entry, and you never rewrite your own prior entries.

**Recent activity is already in your context — do not re-read it.** Your
`agentSpawn` hook (`.kiro/hooks/activity-log-inject.sh`) injects the newest
activity automatically at session start (`log.md`'s top 40 lines pre-freeze,
the newest 8 `entries/` files post-freeze — see the Fallback note below for the
exact switch). Re-reading it yourself wastes tokens on something already
sitting in front of you.

**Specific history** (a topic from before the injected window) →
`grep -n "<topic>" .ai/activity/log.md` pre-freeze, or grep across
`.ai/activity/entries/*.md` post-freeze. Never read either wholesale — `log.md`
is 600KB+/2,100+ lines and almost entirely irrelevant to any one task.

**Write one entry file** after completing substantive work (file edits, running
tests, non-obvious decisions, finishing a task) — never edit or delete another
entry:

    .ai/activity/entries/<YYYYMMDDTHHMMSSZ>-kiro-<slug>-<rand4>.md

- `<YYYYMMDDTHHMMSSZ>` — **UTC**, second precision, ISO-8601 basic form (this is
  the filename's sort key — it must be UTC even though the body heading below
  stays local time).
- `<slug>` — short kebab-case topic.
- `<rand4>` — four random lowercase hex characters (distinguishes two concurrent
  writers, e.g. an interactive and a headless Kiro session, at the same second).

The file's **body** keeps the same heading + shape as before — only the storage
location changed, not the content format:

    ## YYYY-MM-DD HH:MM — kiro
    - Action: <one-line summary>
    - Files: <paths, or "—">
    - Decisions: <non-obvious choices, or "—">

**Timestamp rule (body heading):** use your current local wall-clock time at the
moment you write the entry — i.e. after the work is finished, not when you
started. This is unchanged from before; only the **filename** timestamp is UTC.

**Ordering:** entries sort by filename (UTC timestamp), which is best-effort
chronological — not causal, and not an authoritative "who-wrote-first" record
the way the old shared-file prepend order was informally treated. On one
machine with one clock this is reliable in practice.

Terse — one short paragraph max per entry. One entry file per substantive
action, not per file edit. Do not log trivial reads.

**Fallback (transitional, until the freeze lands):** `.ai/activity/log.md` is
still the live, authoritative file **as long as it exists** — read (bounded,
never wholesale) and prepend to it exactly as before, even if
`.ai/activity/entries/` already contains some files (other CLIs may be
dogfooding the spool early; those entries are stale relative to `log.md` until
the freeze). Only once `log.md` is gone (git-mv'd to archive — the freeze,
Kimi's Wave 3) does `entries/` become authoritative and do you switch to
writing entry files. Never write to `log.md` once it has been removed — that
reintroduces the write race ADR-0010 exists to remove.

## Cross-CLI handoffs

When another CLI needs you to execute a change in `.kiro/` or in Kiro's portion of the
shared docs, it writes a paste-ready instruction file to
`.ai/handoffs/to-kiro/open/YYYYMMDDHHMM-slug.md`. Glance at that directory when a session starts
or when the user references a handoff. Follow the protocol in
`.ai/handoffs/README.md`: review, execute the steps, prepend an activity-log entry,
report back.

**Filename basis = UTC.** The `YYYYMMDDHHMM` prefix is a **UTC** timestamp
(`date -u +%Y%m%d%H%M`), while the `Created:` line inside the file and your
activity-log entries use **local wall-clock** time. Both refer to the same
instant — do NOT put local time in the filename. A CLI in UTC+7 finishing at
`22:17` local writes the filename with `1517` (UTC) but `Created: 22:17`
(local). Mixing them desynchronizes sort order across CLIs on different clocks.

**Recipient self-retires (protocol v3).** When you complete a handoff addressed
to you, set its Status to `DONE` inline (listing what you actually touched) and
move the file from `.ai/handoffs/to-kiro/open/` to `.ai/handoffs/to-kiro/done/`
yourself — do not wait for the sender. The sender validates post-hoc. If you are
**blocked**, leave the file in `open/`, set Status `BLOCKED`, and append a
`## Blocker` section with the verbatim error (never a paraphrase).

You can send handoffs too — write to `.ai/handoffs/to-claude/open/` or
`.ai/handoffs/to-kimi/open/` (UTC filename) when you need those CLIs to change
files in their folders. As sender under v3 you validate post-hoc rather than
moving the file yourself.

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
