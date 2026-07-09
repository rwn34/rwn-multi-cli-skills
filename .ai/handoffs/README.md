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

- **Claude Code** edits: `.claude/`, `.ai/`, `CLAUDE.md`, `AGENTS.md`, any non-CLI path. Also custodian of Crush's files (`CRUSH.md`, `.crush.json`) per ADR-0001.
- **Kimi CLI** edits: `.kimi/` (project), `~/.kimi/` (global), any non-CLI path.
- **Kiro CLI** edits: `.kiro/` (project), `~/.kiro/` (global), any non-CLI path.
- **Crush** edits: `.ai/` only (activity log, reports, handoffs). Its own config is Claude-maintained — Crush requests changes via `to-claude/`.

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
    ├── to-kiro/
    │   ├── open/
    │   └── done/
    └── to-crush/
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

## Protocol v2 (lifecycle of a single handoff) — 2026-07-08

Every handoff carries two routing fields in its status block:
`Auto:` (default **yes**) and `Risk:` (**A**/**B**/**C** per the autonomy tiers
in `.ai/instructions/operating-prompt/principles.md` §8). A missing `Risk:`
line is treated as C — conservative by default.

1. **Create** — sender writes `to-<recipient>/open/YYYYMMDDHHMM-<slug>.md`. Status
   line inside the file reads `OPEN`. Set `Auto:` and `Risk:` honestly — a
   Risk-C task labeled B to sneak past the gate is a delivery-integrity
   violation.
2. **Dispatch (auto, default for Risk A/B)** — run
   `bash .ai/tools/dispatch-handoffs.sh --exec` (dry-run without `--exec`): it
   launches the recipient CLI headless (one-shot) for every `Auto: yes` +
   Risk A/B handoff. Any idle CLI, a polling loop, or the user can trigger the
   dispatcher — it is safe to run repeatedly. Windows Terminal panes can't be
   driven programmatically, so this spawns fresh instances — see
   `.ai/research/4ai-panes-integration-notes.md`.
2b. **Dispatch (manual — Risk C, or `Auto: no`)** — the user tells the recipient
   CLI: "read `.ai/handoffs/to-<cli>/open/YYYYMMDDHHMM-<slug>.md` and execute
   it." Risk-C handoffs are NEVER auto-dispatched, regardless of `Auto:`.
3. **Review + execute** — recipient reads the handoff, asks clarifying questions if
   needed, performs the steps, prepends an entry to `.ai/activity/log.md`.
4. **Report** — recipient reports back in chat with the "Report back with" section
   filled in. Optionally updates the handoff file's status to `DONE` inline, listing
   what was actually touched.
5. **Validate** — sender reads the recipient's touched files and confirms they match
   spec. If OK, sender (or user) moves the file from `open/` to `done/`. If not, the
   file stays in `open/` with a `BLOCKED` status + notes explaining what's wrong.

## Polling — who watches the queues (P4, 2026-07-09)

Three mechanisms, three scopes — they complement, never compete:

| Mechanism | Scope | How |
|---|---|---|
| **Session-end reminder** | every Claude session | `stop-reminder.sh` prints per-queue open counts at each turn end — zero setup, always on. |
| **In-session interval poll** | an active working session | `/loop 15m bash .ai/tools/dispatch-handoffs.sh --exec` — Claude re-runs the dispatcher every 15 min while you work. Stop the loop when done. |
| **Human glance** | daily 4AI-panes use | Selector badge (planned, P5): per-project open-handoff counts + framework-version state, so the human sees pending Risk-C work without opening files. |

A `schedule` cron routine (out-of-session cloud dispatch) is deliberately NOT
configured — cloud runs cost money (Tier C) and the dispatcher needs local CLI
binaries. Revisit only if the fleet outgrows in-session polling.

**Failure alerting:** a headless dispatch that exits non-zero writes
`.ai/reports/dispatch-failure-<UTC>-<cli>.md` (command, exit code, output
tail) and leaves the handoff OPEN for retry. Failed dispatches are never
silent.

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
