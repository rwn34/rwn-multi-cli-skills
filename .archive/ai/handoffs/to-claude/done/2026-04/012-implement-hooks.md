# Implement 7 hooks for Claude Code
Status: DONE
Completed: 2026-04-17 22:10 — claude-code
Output: 4 new scripts under .claude/hooks/, .claude/settings.json rewritten with PreToolUse + SessionStart + updated Stop blocks, validation handoff at .ai/handoffs/to-kiro/open/005-validate-claude-hooks.md.
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 21:39

## Goal
Implement 7 hooks in Claude Code's `.claude/settings.json`, matching the hooks Kiro
just implemented. Use Claude-native events and mechanisms.

## The 7 hooks

| # | Hook | Event | Matcher | Action |
|---|---|---|---|---|
| 1 | Root file guard | PreToolUse | Write\|Edit | Block writes to root except AGENTS.md, README.md, CLAUDE.md |
| 2 | Framework dir guard | PreToolUse | Write\|Edit | Block writes to .kimi/, .kiro/ (other CLIs' dirs) |
| 3 | Sensitive file guard | PreToolUse | Write\|Edit | Block writes to .env*, *.key, *.pem, id_rsa*, .aws/, .ssh/ |
| 4 | Destructive cmd guard | PreToolUse | Bash | Block rm -rf dangerous, git push --force, git reset --hard, DROP TABLE/DATABASE |
| 5 | Git status at start | SessionStart | — | Inject git status --short at session start |
| 6 | Open handoffs reminder | SessionStart | — | List .ai/handoffs/to-claude/open/*.md if any |
| 7 | Unpushed changes reminder | Stop | — | Extend existing stop hook: remind if uncommitted changes beyond activity log |

## Implementation notes
- Hooks 1-4 use exit code 2 to block, stderr message returned to LLM
- Hooks 5-6 inject context via stdout
- Hook 7 extends existing stop hook (merge, don't duplicate)
- Store scripts in `.claude/hooks/` or inline in settings.json — your call
- All scripts use bash (Git Bash on Windows)

## After completion
Write a validation handoff to `.ai/handoffs/to-kiro/open/005-validate-claude-hooks.md`
listing: files created, hook events used, any deviations.

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Implemented 7 hooks per handoff 012 from kiro-cli.
    - Files: .claude/settings.json (edit), .claude/hooks/*.sh (new if using scripts)
    - Decisions: <inline vs scripts, any deviations>