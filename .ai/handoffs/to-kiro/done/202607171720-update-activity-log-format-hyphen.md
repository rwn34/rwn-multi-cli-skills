# Update .kiro/steering/00-ai-contract.md activity-log format to ASCII hyphen + UTC+7
Status: DONE
Sender: kimi-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-18 00:20 (UTC+7)
Completed: 2026-07-18 00:21 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (grep -n "YYYY-MM-DD HH:MM" AGENTS.md -> "## YYYY-MM-DD HH:MM (UTC+7) - <cli-name>")

## Resolution
Replaced the em-dash activity-log template block in `.kiro/steering/00-ai-contract.md`
with the ASCII-hyphen format: `## YYYY-MM-DD HH:MM (UTC+7) - kiro-cli` plus
`Files: <paths, or "-">` / `Decisions: <non-obvious choices, or "-">`. Scope was
limited to the template block per the handoff's Target state — the surrounding
prose em-dashes (e.g. "Newest entries are at the top — scan...") were not part
of the ask and were left untouched.

## Goal
Bring Kiro's contract activity-log format in line with the new framework-wide ASCII-hyphen convention so em-dashes stop being written as cp1252 bytes (0x97) by Windows-hosted CLIs.

## Current state
- `AGENTS.md` and `.kimi/steering/00-ai-contract.md` already use the new format:
  `## YYYY-MM-DD HH:MM (UTC+7) - <cli-name>`
- `.kiro/steering/00-ai-contract.md` still uses the old em-dash format.

## Target state
- `.kiro/steering/00-ai-contract.md` activity-log entry examples use `## YYYY-MM-DD HH:MM (UTC+7) - kiro-cli`.
- Any "Files: —" / "Decisions: —" placeholders use ASCII `-` instead of em-dash.

## Steps
1. Grep the contract for em-dash activity-log lines: `grep -n "YYYY-MM-DD HH:MM" .kiro/steering/00-ai-contract.md`
2. Replace em-dash separators with ASCII hyphen.
3. Ensure the timestamp annotation reads `(UTC+7)`.

## Verification
- `grep -n "UTC+7" .kiro/steering/00-ai-contract.md` shows the updated format.
- `bash .ai/tools/check-encoding.sh .kiro/steering/00-ai-contract.md` passes.

## Next step / future note
After this and the sibling handoffs to claude/opencode land, the fleet will use one ASCII-safe format. The normalize-encoding.sh safety net remains in place for legacy entries and accidental non-UTF-8 writes.

## Activity log template
    ## YYYY-MM-DD HH:MM (UTC+7) - kiro-auto
    - Action: Updated .kiro/steering/00-ai-contract.md activity-log format to ASCII hyphen per handoff 202607171720-update-activity-log-format-hyphen
    - Files: .kiro/steering/00-ai-contract.md
    - Decisions: -

## Report back with
- Grep snippet showing the updated format line(s) in .kiro/steering/00-ai-contract.md.
- check-encoding.sh result.

## Evidence

    $ grep -n "UTC+7" .kiro/steering/00-ai-contract.md
    21:    ## YYYY-MM-DD HH:MM (UTC+7) - kiro-cli
    47:instant — do NOT put local time in the filename. A CLI in UTC+7 finishing at

    $ bash .ai/tools/check-encoding.sh .kiro/steering/00-ai-contract.md
    (exit 0, no output — passes)
