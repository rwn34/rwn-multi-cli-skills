# Implement 7 hooks for Kimi CLI
Status: OPEN
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 21:39

## Goal
Implement 7 hooks in Kimi CLI's config, matching the hooks Kiro just implemented.
Use Kimi-native events and mechanisms.

## The 7 hooks

| # | Hook | Event | Matcher | Action |
|---|---|---|---|---|
| 1 | Root file guard | PreToolUse | WriteFile\|StrReplaceFile | Block writes to root except AGENTS.md, README.md, CLAUDE.md |
| 2 | Framework dir guard | PreToolUse | WriteFile\|StrReplaceFile | Block writes to .claude/, .kiro/ (other CLIs' dirs) |
| 3 | Sensitive file guard | PreToolUse | WriteFile\|StrReplaceFile | Block writes to .env*, *.key, *.pem, id_rsa*, .aws/, .ssh/ |
| 4 | Destructive cmd guard | PreToolUse | Shell | Block rm -rf dangerous, git push --force, git reset --hard, DROP TABLE/DATABASE |
| 5 | Git status at start | SessionStart | — | Inject git status --short at session start |
| 6 | Open handoffs reminder | SessionStart | — | List .ai/handoffs/to-kimi/open/*.md if any |
| 7 | Unpushed changes reminder | Stop | — | Extend existing stop hook: remind if uncommitted changes beyond activity log |

## Implementation notes
- Hooks 1-4 use exit code 2 to block, stderr message returned to LLM
- Hooks 5-6 inject context via stdout
- Hook 7 extends existing stop hook
- Store scripts in `.kimi/hooks/` — reference from config.toml or agent YAML
- All scripts use bash (Git Bash on Windows)

## After completion
Write a validation handoff to `.ai/handoffs/to-kiro/open/005-validate-kimi-hooks.md`
listing: files created, hook events used, any deviations.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Implemented 7 hooks per handoff 015 from kiro-cli.
    - Files: ~/.kimi/config.toml (edit), .kimi/hooks/*.sh (new)
    - Decisions: <inline vs scripts, any deviations>