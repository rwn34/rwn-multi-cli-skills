# `.ai/` — shared context for multiple AI CLIs

This folder is the single source of truth for AI-CLI instructions and the shared
activity log in this project. It is CLI-agnostic: Claude Code, Kimi CLI, and Kiro CLI
all read from here via thin shim files inside their own native folders.

## Layout

    .ai/
    ├── README.md                  (this file)
    ├── sync.md                    (how to regenerate CLI-native shim files from here)
    ├── instructions/              (canonical instruction content)
    │   └── <skill-name>/
    │       ├── principles.md      (steering-class: always-loaded, concise rules)
    │       └── examples.md        (resource-class: on-demand, worked examples)
    ├── tools/                     (CI/test utilities: drift checks, handoff dispatch, etc.)
    └── activity/
        └── log.md                 (cross-CLI activity log, newest entries at top)

## How it works

Each CLI loads its own native steering file — Claude Code reads `CLAUDE.md` at project
root, Kimi CLI reads `.kimi/steering/*.md`, Kiro CLI reads `.kiro/steering/*.md`. Those
files contain the **AI contract**: a short instruction that points the CLI at
`.ai/instructions/` (canonical content) and `.ai/activity/log.md` (what other CLIs have
done recently).

When instructions change, edit them in `.ai/instructions/` and re-run the copy commands
in `sync.md`. Never edit the CLI-native replicas directly — they will drift.

## Adding a new instruction

1. Create `.ai/instructions/<name>/principles.md` (and optionally `examples.md`).
2. Decide which CLIs need it and as what class (steering vs resource).
3. Add a row to the map in `sync.md`.
4. Run the copy commands.

## Activity log

`.ai/activity/log.md` is an append-only cross-CLI ledger. Each CLI's AI contract tells
it to read recent entries at session start and prepend one entry after completing
substantive work. Keeps all three CLIs aware of each other's actions without
copy-pasting.

## Archive folders

Growing state under `.ai/` (activity log, research docs, and anything future) gets
archived over time so active files stay small and readable:

    .ai/activity/archive/   — older log entries, one file per month (YYYY-MM.md), grouped by day inside
    .ai/research/archive/   — superseded or landed research docs (<name>-YYYY-MM-DD.md)

**Read rule:** AI CLIs do NOT read archive folders during routine operations —
not in hooks, not in session-start scans, not in lookups for recent activity or
active research. Only consulted when the user explicitly references historical
content (e.g., "what did we decide in Q1?", "check the archive for the old
orchestrator design"). Each archive folder has its own `README.md` with the
archival protocol.

## Why this exists

Running Claude Code + Kimi CLI + Kiro CLI in the same project leads to three diverging
copies of every behavioural rule and zero shared memory of what each did. `.ai/` fixes
both: one place to edit, one place to scan for recent activity.

## Project-agnostic install

See the bottom of `sync.md` for the copy-to-another-project command.
