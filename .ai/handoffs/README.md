# Cross-CLI Handoff Directory

When one CLI needs another to execute changes in its own folder, the sender writes a
paste-ready instruction file here. The recipient reviews and executes. The sender
validates afterward by reading the resulting files.

## Why this exists

Cross-CLI convention assumptions can be silently wrong (e.g. "Kiro auto-scans
`.kiro/skills/`" was wrong — it actually loads skills via `skill://` URIs in agent
config). Each CLI owns changes to its own folder. This handoff queue keeps cross-CLI
work explicit, reviewable, and traceable instead of one CLI guessing at another's
conventions.

## Who can edit what (reminder)

- **Claude Code** edits: `.claude/`, `.ai/`, `CLAUDE.md`, `AGENTS.md`, any non-CLI path.
- **Kimi CLI** edits: `.kimi/` (project), `~/.kimi/` (global), any non-CLI path.
- **Kiro CLI** edits: `.kiro/` (project), `~/.kiro/` (global), any non-CLI path.

Any CLI can edit `.ai/` (shared SSOT + docs + handoffs queue + activity log). When a
CLI needs a change in another CLI's folder, it writes a handoff to
`.ai/handoffs/to-<owner>/open/` — including to `to-claude/` when Kimi or Kiro needs
Claude to update something in `.claude/` or in Claude's portion of the shared docs.

## Layout

    .ai/handoffs/
    ├── README.md                    this file
    ├── template.md                  copy-paste starting shape for new handoffs
    ├── to-claude/
    │   ├── open/                    handoffs for Claude Code to process
    │   └── done/                    handoffs Claude has completed + sender has validated
    ├── to-kimi/
    │   ├── open/
    │   └── done/
    └── to-kiro/
        ├── open/
        └── done/

## Filename convention

    YYYYMMDDHHMM-short-task-slug.md

- `YYYYMMDDHHMM` — UTC timestamp of handoff creation, minute precision. Example:
  `202604201530-wave5-cleanup.md` (2026-04-20 15:30 UTC). Collisions across CLIs
  at the same minute are vanishingly rare; if one happens, the second writer
  appends a `-a` / `-b` suffix.
- `short-task-slug` — kebab-case, ≤ 5 words, describes the change.

**Why timestamp-based (not `NNN-slug`):** the old `NNN` scheme required each
CLI to compute `max(existing) + 1`, creating a race condition when two CLIs
dispatched handoffs to the same recipient within seconds of each other. We
observed 3 such collisions during the 2026-04-18/19 audit cycle. Timestamps
are monotonic per-CLI-clock and carry useful metadata (when was this filed?)
for free.

**Legacy handoffs** (created before 2026-04-20) use the old `NNN-slug` format.
Do not rename — they are grandfathered. New handoffs use the timestamp format.
Sorting `ls .ai/handoffs/to-<cli>/open/` still shows oldest-first with both
formats present.

## Protocol (lifecycle of a single handoff)

1. **Create** — sender writes `to-<recipient>/open/YYYYMMDDHHMM-<slug>.md`. Status line
   inside the file reads `OPEN`.
2. **Dispatch** — the user tells the recipient CLI: "read
   `.ai/handoffs/to-<cli>/open/YYYYMMDDHHMM-<slug>.md` and execute it." (Or asks the
   recipient to scan `open/` for anything new.)
3. **Review + execute** — recipient reads the handoff, asks clarifying questions if
   needed, performs the steps, prepends an entry to `.ai/activity/log.md`.
4. **Report** — recipient reports back in chat with the "Report back with" section
   filled in. Optionally updates the handoff file's status to `DONE` inline, listing
   what was actually touched.
5. **Validate** — sender reads the recipient's touched files and confirms they match
   spec. If OK, sender (or user) moves the file from `open/` to `done/`. If not, the
   file stays in `open/` with a `BLOCKED` status + notes explaining what's wrong.

## Handoff file shape

Every handoff opens with a status block and follows the skeleton in `template.md`.
See `to-kimi/open/001-clarify-timestamp-semantics.md` or
`to-kiro/open/001-clarify-timestamp-semantics.md` for a live example.

## Timestamp convention

Timestamps in this framework — both in handoff `Created:` lines and in
`.ai/activity/log.md` entry headers — are **local wall-clock time at the moment of
writing**. For log entries this means *after the work is done* (prepend time = finish
time). Since the three CLIs may have different local clocks, timestamps are
annotations; **prepend order is the authoritative sequencing**.
