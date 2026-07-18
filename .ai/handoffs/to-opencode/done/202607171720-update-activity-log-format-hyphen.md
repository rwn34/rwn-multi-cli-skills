# Update .opencode/contract.md activity-log format to ASCII hyphen + UTC+7
Status: BLOCKED

## Blocker
Edit of '.opencode/contract.md' is outside the lane. OpenCode's writable lane is .ai/activity/log.md, .ai/activity/entries/**, .ai/reports/**, .ai/handoffs/**, .github/** (see .opencode/plugin/framework-guard.js). The contract is Claude's custodian file — this handoff should have been routed to to-claude/open/ instead of to-opencode/open/.
Sender: kimi-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-18 00:20 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (grep -n "YYYY-MM-DD HH:MM" AGENTS.md -> "## YYYY-MM-DD HH:MM (UTC+7) - <cli-name>")

## Goal
Bring OpenCode's contract activity-log format in line with the new framework-wide ASCII-hyphen convention so em-dashes stop being written as cp1252 bytes (0x97) by Windows-hosted CLIs.

## Current state
- `AGENTS.md` and `.kimi/steering/00-ai-contract.md` already use the new format:
  `## YYYY-MM-DD HH:MM (UTC+7) - <cli-name>`
- `.opencode/contract.md` still uses the old em-dash format.

## Target state
- `.opencode/contract.md` activity-log entry examples use `## YYYY-MM-DD HH:MM (UTC+7) - opencode`.
- Any "Files: —" / "Decisions: —" placeholders use ASCII `-` instead of em-dash.

## Steps
1. Grep the contract for em-dash activity-log lines: `grep -n "YYYY-MM-DD HH:MM" .opencode/contract.md`
2. Replace em-dash separators with ASCII hyphen.
3. Ensure the timestamp annotation reads `(UTC+7)`.

## Verification
- `grep -n "UTC+7" .opencode/contract.md` shows the updated format.
- `bash .ai/tools/check-encoding.sh .opencode/contract.md` passes.

## Next step / future note
After this and the sibling handoffs to claude/kiro land, the fleet will use one ASCII-safe format. The normalize-encoding.sh safety net remains in place for legacy entries and accidental non-UTF-8 writes.

## Activity log template
    ## YYYY-MM-DD HH:MM (UTC+7) - opencode-auto
    - Action: Updated .opencode/contract.md activity-log format to ASCII hyphen per handoff 202607171720-update-activity-log-format-hyphen
    - Files: .opencode/contract.md
    - Decisions: -

## Report back with
- Grep snippet showing the updated format line(s) in .opencode/contract.md.
- check-encoding.sh result.

## Blocker
Edit of '.opencode/contract.md' is outside the lane. OpenCode's writable lane is .ai/activity/log.md, .ai/activity/entries/**, .ai/reports/**, .ai/handoffs/**, .github/** (see .opencode/plugin/framework-guard.js). The contract is Claude's custodian file — this handoff should have been routed to to-claude/open/ instead of to-opencode/open/.
