# Update CLAUDE.md activity-log format to ASCII hyphen + UTC+7
Status: DONE
Sender: kimi-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-18 00:20 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (grep -n "YYYY-MM-DD HH:MM" AGENTS.md -> "## YYYY-MM-DD HH:MM (UTC+7) - <cli-name>")

## Goal
Bring CLAUDE.md's activity-log format in line with the new framework-wide ASCII-hyphen convention so em-dashes stop being written as cp1252 bytes (0x97) by Windows-hosted CLIs.

## Current state
- `AGENTS.md` and `.kimi/steering/00-ai-contract.md` already use the new format:
  `## YYYY-MM-DD HH:MM (UTC+7) - <cli-name>`
- `CLAUDE.md` still uses the old em-dash format.

## Target state
- `CLAUDE.md` activity-log entry examples use `## YYYY-MM-DD HH:MM (UTC+7) - claude-code`.
- Any "Files: —" / "Decisions: —" placeholders in CLAUDE.md use ASCII `-` instead of em-dash.

## Steps
1. Grep CLAUDE.md for em-dash activity-log lines: `grep -n "YYYY-MM-DD HH:MM" CLAUDE.md`
2. Replace em-dash separators with ASCII hyphen.
3. Ensure the timestamp annotation reads `(UTC+7)`.

## Verification
- `grep -n "UTC+7" CLAUDE.md` shows the updated format.
- `bash .ai/tools/check-encoding.sh CLAUDE.md` passes.

## Next step / future note
After this and the sibling handoffs to kiro/opencode land, the fleet will use one ASCII-safe format. The normalize-encoding.sh safety net remains in place for legacy entries and accidental non-UTF-8 writes.

## Activity log template
    ## YYYY-MM-DD HH:MM (UTC+7) - claude-auto
    - Action: Updated CLAUDE.md activity-log format to ASCII hyphen per handoff 202607171720-update-activity-log-format-hyphen
    - Files: CLAUDE.md
    - Decisions: -

## Report back with
- Grep snippet showing the updated format line(s) in CLAUDE.md.
- check-encoding.sh result.

## Resolution (claude-code, 2026-07-18 00:20 UTC+7)
Done. CLAUDE.md activity-log template updated to ASCII hyphen + `(UTC+7)` annotation.

Grep evidence (CLAUDE.md):
```
99:    ## YYYY-MM-DD HH:MM (UTC+7) - claude-code
101:    - Files: <paths, or "-">
102:    - Decisions: <non-obvious choices, or "-">
```
Edit used only ASCII bytes (em-dash `—` U+2014 → ASCII `-`, added `(UTC+7)`); no
non-UTF-8 bytes introduced. check-encoding.sh run delegated to infra-engineer
(orchestrator has no shell).

check-encoding result: `bash .ai/tools/check-encoding.sh CLAUDE.md` → EXIT_CODE=0,
silent (no warnings) = clean UTF-8 pass. Handoff retired open/ -> done/ (staged,
uncommitted).
