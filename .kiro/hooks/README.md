# `.kiro/hooks/` — Kiro lifecycle hook scripts

Bash scripts executed at agent lifecycle events. Wired in agent configs via the
`hooks` field (e.g., `.kiro/agents/orchestrator.json`).

## Scripts

| Script | Event | Matcher | Purpose |
|---|---|---|---|
| `activity-log-inject.sh` | `agentSpawn` | — | Inject activity log + git status + open handoffs at session start |
| `activity-log-remind.sh` | `stop` | — | Remind to log + remind about unpushed changes |
| `root-file-guard.sh` | `preToolUse` | `fs_write` | Block writes to root except ADR-approved files |
| `framework-dir-guard.sh` | `preToolUse` | `fs_write` | Block writes to `.kimi/`, `.claude/` (edit-boundary rule) |
| `sensitive-file-guard.sh` | `preToolUse` | `fs_write` | Block writes to `.env*`, `*.key`, `*.pem`, etc. |
| `destructive-cmd-guard.sh` | `preToolUse` | `execute_bash` | Block `rm -rf`, `git push --force`, `DROP TABLE`, etc. |

## How hooks work

- `preToolUse` hooks receive JSON via stdin with `tool_name` and `tool_input`
- Exit 0 = allow, exit 2 = block (stderr message returned to LLM)
- `agentSpawn` and `stop` hooks inject context via stdout
- All scripts use bash (Git Bash on Windows: `C:\Program Files\Git\bin\bash.exe`)

## Adding a new hook

1. Create a script in this directory
2. Wire it in the agent config's `hooks` section
3. Pipe-test before committing: `echo '{"tool_input":{"path":"test.txt"}}' | bash .kiro/hooks/your-script.sh`