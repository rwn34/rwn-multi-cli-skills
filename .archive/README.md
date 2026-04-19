# `.archive/` — framework cold storage

## Purpose

Historical content that has rolled out of the live framework view
(`.ai/`, `.claude/`, `.kimi/`, `.kiro/`). Keeps the working tree scannable
without losing history.

**AI CLIs must not read this folder during routine operations.** Only consult
when the user explicitly references archived content ("what did Kimi's Q1
audit say?", "pull up the old orchestrator design").

## Layout

```
.archive/
├── README.md                        # this file
└── ai/
    ├── activity/
    │   └── YYYY-MM.md               # monthly rollup (formerly .ai/activity/archive/)
    ├── reports/
    │   └── YYYY-MM-DD/              # date-grouped audit / review outputs
    │       ├── claude-audit.md
    │       ├── kimi-audit.md
    │       ├── kiro-audit.md
    │       └── consolidated.md
    └── handoffs/
        ├── to-claude/done/YYYY-MM/  # archived by resolution-month
        ├── to-kimi/done/YYYY-MM/
        └── to-kiro/done/YYYY-MM/
```

Mirrors `.ai/` structure one level deep so the provenance of any archived
file is obvious from its path. When Kimi or Kiro eventually get their own
archivable outputs, add `.archive/kimi/`, `.archive/kiro/` peers.

## When to archive

| Content | Trigger | Destination |
|---|---|---|
| Audit / review reports in `.ai/reports/` | Older than 30 days **or** superseded by newer same-subject report | `.archive/ai/reports/YYYY-MM-DD/` (date = report's original creation date) |
| Resolved handoffs in `.ai/handoffs/to-*/done/` | Older than 30 days **or** when `done/` exceeds 20 files in the dir | `.archive/ai/handoffs/to-*/done/YYYY-MM/` (month = handoff resolution month) |
| Monthly activity-log rollups currently at `.ai/activity/archive/YYYY-MM.md` | On creation (rollups are born archive-ready) | `.archive/ai/activity/YYYY-MM.md` |
| Research scratch at `.ai/research/archive/` | Whenever research is marked archive | `.archive/ai/research/` |

Trigger-based, not time-based — running 20 audits in a week and then none for
a year shouldn't bloat `.ai/reports/` for that year.

## Who archives

- **Any orchestrator CLI** can propose an archive pass. Surface which files
  qualify, ask the user to approve, then execute.
- The actual file move is a `git mv` — preserves history. Delegate to
  `infra-engineer` (Claude-side) since orchestrator has no shell.
- Archive moves are logged in `.ai/activity/log.md` as any other substantive
  action.

## How to archive

### Bash / Git Bash (from repo root)

```bash
# Example: archive all reports from 2026-04-18
mkdir -p .archive/ai/reports/2026-04-18
git mv .ai/reports/kimi-audit-2026-04-18.md  .archive/ai/reports/2026-04-18/kimi-audit.md
git mv .ai/reports/kiro-audit-2026-04-18.md  .archive/ai/reports/2026-04-18/kiro-audit.md
git mv .ai/reports/claude-audit-2026-04-18.md .archive/ai/reports/2026-04-18/claude-audit.md

# Example: archive done/ handoffs resolved in 2026-03
mkdir -p .archive/ai/handoffs/to-kimi/done/2026-03
git mv .ai/handoffs/to-kimi/done/014-recommend-hooks.md .archive/ai/handoffs/to-kimi/done/2026-03/
# ... etc
```

### PowerShell

```powershell
# Example: archive a single report
New-Item -ItemType Directory -Force -Path .archive/ai/reports/2026-04-18
git mv .ai/reports/kimi-audit-2026-04-18.md .archive/ai/reports/2026-04-18/kimi-audit.md
```

Always `git mv` — never bare `mv` — so history sticks with the file.

## What NOT to put here

- Live state: `.ai/instructions/**`, `.claude/agents/**`, `.kimi/steering/**`,
  `.kiro/steering/**`. These are authoritative, not archived.
- Handoffs still in `open/`. An open handoff is an unpaid debt, not history.
- The current `.ai/activity/log.md`. Only monthly rollups go here.
- Secrets, keys, credentials. The `.gitignore` + sensitive-file hooks still
  apply — `.archive/` is not a bypass.

## Cross-CLI behavior

- Claude's `.claude/hooks/pretool-write-edit.sh` allows `.archive/*` writes
  (dotfolder, path has `/`, no sensitive pattern).
- Kimi's and Kiro's equivalent guards should also allow `.archive/*` —
  flag in a handoff if they block.
- None of the CLIs should load `.archive/**/*.md` as context resources. Agent
  configs that glob `.ai/**/*.md` or `docs/**/*.md` are unaffected (`.archive/`
  is not under either).

## Eventual-consistency note

If the repo lives on a network share (Dropbox, OneDrive) and `.archive/` grows
large, sync lag on cold files can mask recent writes. No current mitigation —
treat this as a known limitation if you ever run the framework off such a
share.

## References

- ADR-0001 `docs/architecture/0001-root-file-exceptions.md` Category E —
  `.archive/` is recognized framework territory (amendment pending in
  handoff to doc-writer).
- Archive protocol exercised first: see activity-log entry dated
  2026-04-XX for the initial archive pass of the 2026-04-18 audit cycle
  reports (when it happens).
