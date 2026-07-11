# Kimi CLI Hooks

Lifecycle hooks for the Kimi CLI in this project. All hooks are bash scripts
invoked by `~/.kimi-code/config.toml`.

## Hook inventory

| Hook | Event | Matcher | Script | Status | Purpose |
|------|-------|---------|--------|--------|---------|
| Root file guard | `PreToolUse` | `WriteFile\|StrReplaceFile` | `root-guard.sh` | ✅ **WIRED** | Block writes to project root except ADR-0001 allowlist: Category A (AGENTS.md, README.md, CLAUDE.md, LICENSE*, CHANGELOG*, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md) + Category B (.gitignore, .gitattributes) + Category C (.editorconfig) + Category D (.dockerignore, .gitlab-ci.yml) + Category E (.mcp.json, .mcp.json.example). See `docs/architecture/0001-root-file-exceptions.md` for the full allowlist. |
| Framework dir guard | `PreToolUse` | `WriteFile\|StrReplaceFile` | `framework-guard.sh` | ✅ **WIRED** | Block writes to `.claude/` and `.kiro/` (other CLIs' dirs) |
| Sensitive file guard | `PreToolUse` | `WriteFile\|StrReplaceFile` | `sensitive-guard.sh` | ✅ **WIRED** | Block writes to `.env*`, `*.key`, `*.pem`, `id_rsa*`, `.aws/`, `.ssh/` |
| Destructive cmd guard | `PreToolUse` | `Shell` | `destructive-guard.sh` | ✅ **WIRED** | Block `rm -rf /`, `git push --force`, `git reset --hard`, `DROP TABLE/DATABASE` |
| safety-check.ps1 | `PreToolUse` | `Shell` | `safety-check.ps1` | ✅ **WIRED** | Broad PowerShell safety net (blocks dangerous patterns) |
| Git status at start | `SessionStart` | — | `git-status.sh` | ⚠️ **NOT WIRED** | Inject `git status --short` into context at session start |
| Open handoffs reminder | `SessionStart` | — | `handoffs-remind.sh` | ✅ **WIRED** | List qualifying (Status: OPEN, Auto: yes, Risk A\|B) handoffs in `.ai/handoffs/to-kimi/open/` at session start |
| Auto-dispatch own queue | `SessionStart` | — | `dispatch-own-queue.sh` | ✅ **WIRED** | Run `dispatch-handoffs.sh --exec --only kimi` for qualifying to-kimi handoffs at session start (recursion-guarded + 5-min debounce; closes the e2e-test non-delivery gap) |
| Open handoff queue-counts | `Stop` | — | `handoff-queue-count.sh` | ✅ **WIRED** | Print per-queue open counts across all `to-*/open` queues at each turn end (gap B4 poll point) |
| Activity log inject | `UserPromptSubmit` | — | `activity-log-inject.sh` | ⚠️ **NOT WIRED** | Inject top 40 lines of `.ai/activity/log.md` into context |
| Activity log remind | `Stop` | — | `activity-log-remind.sh` | ⚠️ **NOT WIRED** | Remind to update activity log if not touched in 60 min |
| Git dirty reminder | `Stop` | — | `git-dirty-remind.sh` | ⚠️ **NOT WIRED** | Remind about uncommitted changes beyond activity log |

## How hooks work

Kimi CLI passes a JSON context object to each hook via **stdin**.

```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "hook_event_name": "PreToolUse",
  "tool_name": "WriteFile",
  "tool_input": {"file_path": "src/app.ts", "content": "..."}
}
```

Scripts parse this JSON (using Python as a fallback since `jq` is not guaranteed
on all systems) and decide:

- **Exit 0** → allow the operation. stdout is injected into the agent's context.
- **Exit 2** → **block** the operation. stderr is fed back to the LLM as a
correction message.
- **Exit 0 + structured JSON** → can also block via
`{"hookSpecificOutput": {"permissionDecision": "deny", ...}}`.

**Fail-open:** If a hook crashes, times out, or can't parse stdin, Kimi allows
the operation. This means hooks must be correct — test them.

## Testing a hook manually

```bash
# Simulate a root-file write being blocked
echo '{"tool_input": {"file_path": "badfile.txt"}}' | bash .kimi/hooks/root-guard.sh
# → exits 2, stderr: "BLOCKED: Writing 'badfile.txt' to project root..."

# Simulate an allowed write
echo '{"tool_input": {"file_path": "src/app.ts"}}' | bash .kimi/hooks/root-guard.sh
# → exits 0

# Simulate a destructive shell command
echo '{"tool_input": {"command": "rm -rf /"}}' | bash .kimi/hooks/destructive-guard.sh
# → exits 2, stderr: "BLOCKED: rm -rf /..."
```

## Adding a new hook

1. Write a script in this directory following the stdin-JSON → exit-code
   pattern.
2. Add a `[[hooks]]` entry in `~/.kimi-code/config.toml`.
3. Test manually with piped JSON before relying on it.
4. Run the standing regression suite: `bash test_hooks.sh` (expect `PASS: N/N`
   — all green; the exact count grows as hooks are added).
5. Update the table above.

## Wiring status

The 4 guard scripts (`root-guard.sh`, `framework-guard.sh`, `sensitive-guard.sh`,
`destructive-guard.sh`) were wired into `~/.kimi-code/config.toml` on 2026-04-20.
They are now active alongside the existing `safety-check.ps1` hook.

The handoff-delivery hooks were wired on 2026-07-11 (handoff
`.ai/handoffs/to-kimi/open/202607101900-wire-kimi-handoff-reminder.md`):
`handoffs-remind.sh` (SessionStart — lists qualifying to-kimi handoffs) and
`handoff-queue-count.sh` (Stop — per-queue open counts, gap B4). The always-on
auto-dispatcher `dispatch-own-queue.sh` (SessionStart — runs
`dispatch-handoffs.sh --exec --only kimi` for qualifying handoffs; recursion-
guarded + 5-min debounce) was added the same day (handoff
`.ai/handoffs/to-kimi/open/202607110218-kimi-auto-dispatch-own-queue.md`),
closing the e2e-test non-delivery gap. The listing hook is kept as the
human-visible view; the dispatch hook acts on it.

**To finish activation:** restart Kimi Code CLI or start a fresh session.

The remaining convenience hooks (`git-status.sh`, `activity-log-inject.sh`,
`activity-log-remind.sh`, `git-dirty-remind.sh`) remain on disk but are
**not yet wired**. Add `[[hooks]]` entries to `~/.kimi-code/config.toml`
manually if you want them.

## Windows note

All scripts use bash (tested with Git Bash). On Windows, ensure Git Bash is
installed at `C:\Program Files\Git\bin\bash.exe` or available in PATH.
