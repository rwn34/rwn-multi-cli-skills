# `.claude/hooks/`

Bash scripts invoked by Claude Code's lifecycle hooks. Registration lives in `.claude/settings.json → hooks`; the scripts here are the bodies.

## Current hooks

| Script | Event | Matcher | Purpose |
|---|---|---|---|
| `pretool-write-edit.sh` | `PreToolUse` | `Write\|Edit` | Fused rules. **Rule 0** (prerequisite): lexically normalize `file_path` to a project-relative path — the tools emit Windows-absolute (`C:\Users\...`) while `pwd` under Git Bash is MSYS (`/c/Users/...`); without this every later pattern silently misses. Fails **closed** on a path it cannot canonicalize. **Rule 1**: block writes to `.kimi/**` or `.kiro/**` (other CLIs' territory — use handoffs instead). **Rule 2**: block sensitive-file patterns (`.env*`, `*.key`, `*.pem`, `id_rsa*`, `id_ed25519*`, `.aws/`, `.ssh/`). **Rule 3**: block root-file writes not on the allowlist from `docs/architecture/0001-root-file-exceptions.md`. |
| `pretool-bash.sh` | `PreToolUse` | `Bash` | Block destructive commands: `rm -rf` with broad targets (`/`, `~`, `*`, `.`), force-push variants (`--force`, `-f`, `--force-with-lease`), `git reset --hard`, `DROP DATABASE/TABLE/SCHEMA`, `TRUNCATE TABLE`. **Does NOT path-check.** See "Known gap" below. |
| `session-start.sh` | `SessionStart` | — | Inject `git status --short` (if dirty) and list of open handoffs in `.ai/handoffs/to-claude/open/` (if any). Both only emit when non-empty, so clean sessions stay silent. |
| `stop-reminder.sh` | `Stop` | — | Two reminders, non-blocking. (a) `.ai/activity/log.md` not updated in the last 60 min → remind to prepend an entry. (b) Uncommitted changes beyond the activity log → remind to delegate a commit to `infra-engineer` (orchestrator has no shell). |

All scripts exit **0** to proceed, exit **2** + stderr message to block (applicable to `PreToolUse` rules only).

## Known gap — the Bash side-door

`pretool-write-edit.sh` guards the **Write/Edit tools only**. `pretool-bash.sh`
screens for *destructive command shapes*, but performs **no path checking** — so
`cp`, `mv`, `sed -i`, `tee`, `>` redirection etc. can still write any protected
path (`.kimi/**`, `.env`, root files) via the Bash tool.

The Write/Edit guard therefore raises the wall; the door beside it is still open.
Treat the territorial rules as a guardrail against *accident*, not as a boundary
against a determined or careless agent. Closing the Bash path is tracked
separately — do not assume protected paths are unreachable.

## Behavior semantics

- **Block hooks** (`pretool-*`): a single `exit 2` short-circuits; tool call never runs. The stderr message is returned to Claude as context so the model can explain the block to the user.
- **Context-injection hooks** (`session-start.sh`, the `UserPromptSubmit` inline activity-log hook): stdout is injected into the model's context before the turn proceeds.
- **Reminder hooks** (`stop-reminder.sh`): stdout is shown before the session ends; Claude decides whether to log / delegate / continue.

## Testing a hook

Simulate the hook input from the shell. Claude Code passes tool-call context as JSON on stdin:

    # PreToolUse: Write|Edit — test a would-be write
    echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/src/foo.ts"}}' \
      | bash .claude/hooks/pretool-write-edit.sh
    # Exit 0, silent → allowed

    echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/.env"}}' \
      | bash .claude/hooks/pretool-write-edit.sh
    # Exit 2, stderr "BLOCKED by hook: Sensitive file pattern..."

    # PreToolUse: Bash — test a would-be destructive command
    echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
      | bash .claude/hooks/pretool-bash.sh
    # Exit 2, stderr "BLOCKED by hook: 'rm -rf' with broad target..."

    # Session-start — just run it
    bash .claude/hooks/session-start.sh

    # Stop — just run it
    bash .claude/hooks/stop-reminder.sh

Check exit codes (`$?`) to verify block-vs-allow.

For a full regression run, use `test_hooks.sh` — pipes curated JSON payloads through both pre-tool hooks and asserts the expected exit code. Run from repo root: `bash .claude/hooks/test_hooks.sh` (expects `PASS: 98/98`).

**Fixtures must cover every path shape the runtime can receive.** The Write/Edit
tools emit Windows-absolute paths (`C:\Users\...`); a suite that only feeds
*relative* fixtures will certify a hook that never fires at runtime. That is not
hypothetical — it is exactly how the absolute-path territorial bypass survived a
green suite. When touching a path-matching hook, assert on: relative,
Windows-absolute (both slash directions), MSYS (`/c/...`), and mixed case.

On Windows, two drive-letter-form ALLOW cases (t89/t90) are **skipped** when the
shell's cwd has no `/<drive>/` prefix (e.g. a Linux CI sandbox rooted at `/tmp`),
because the Windows form of the project root cannot be constructed there. They
are skipped *loudly*, never silently. Their BLOCK-direction twins run everywhere.

## JSON parsing

Python is used for robust stdin JSON extraction since `jq` isn't reliably installed on Windows + Git Bash. The pattern is:

    input=$(cat)
    path=$(echo "$input" | python -c "import sys, json
    try:
        d = json.load(sys.stdin)
        print(d.get('tool_input', {}).get('file_path', ''))
    except Exception:
        print('')" 2>/dev/null)

Keep the try/except — malformed JSON shouldn't take the hook down.

## Adding a new hook

1. Write the script in this directory. Choose the failure direction deliberately:
   - **Enforcement hooks** (anything whose job is to *block* — territory, secrets,
     root-file, confinement) must **fail CLOSED**: if the input cannot be parsed or
     a path cannot be canonicalized, `exit 2`. A guard that cannot understand its
     input must deny. `pretool-write-edit.sh` blocks on an un-normalizable
     `file_path` for exactly this reason.
   - **Advisory hooks** (context injection, reminders) may **fail open** (`exit 0`)
     — they are not a security boundary, and a broken strict hook can silently
     disable neighbouring hooks in the same event.

   The old blanket "prefer fail-open" advice is what allowed a territorial guard to
   pass every input it did not understand. Do not reintroduce it.
2. Register in `.claude/settings.json → hooks` under the appropriate event key (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart`, etc.) with the right matcher.
3. **Pipe-test** from the shell before committing (examples above).
4. Document the new script in the table above.
5. If the behavior should be mirrored in Kimi/Kiro, send a handoff with the semantics — each CLI maps to its native event names.

## Relationship to the `update-config` skill

Editing `.claude/settings.json` directly is fine for experienced operators. For anything non-trivial (new permissions, new hook events, merging with existing config), use the `update-config` skill — it enforces the Read-before-Edit rule, JSON-schema validation, and pipe-testing workflow.

## Watcher caveat

Claude Code's settings watcher only picks up `.claude/settings.json` changes at session start (for projects that had no `settings.json` at the previous session's start) or when `/hooks` is manually opened. After adding or editing a hook, run `/hooks` once or restart the CLI to see it fire.
