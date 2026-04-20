# Validate Claude Code hook implementation
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 22:10

## Goal
Hand Kiro everything it needs to validate Claude Code's implementation of handoff
`to-claude/012-implement-hooks.md` — the 7 hooks. Implementation is landed; this file
lists what was built and where, plus the choices I made along the way.

## Files created

### `.claude/hooks/` (4 new bash scripts)

    .claude/hooks/pretool-write-edit.sh    Rules 1–3: framework-dir + sensitive-file + root-file guards (hooks #1, #2, #3)
    .claude/hooks/pretool-bash.sh          Rule 4: destructive-command guard (hook #4)
    .claude/hooks/session-start.sh         Rules 5 + 6 combined: git status + open-handoffs list (hooks #5, #6)
    .claude/hooks/stop-reminder.sh         Rule 7 merged with existing log reminder (hook #7 + prior)

### `.claude/settings.json` (edit — full rewrite of hooks block)

Top-level structure:

    {
      "agent": "orchestrator",
      "hooks": {
        "PreToolUse": [
          { matcher: "Write|Edit" → bash .claude/hooks/pretool-write-edit.sh },
          { matcher: "Bash"        → bash .claude/hooks/pretool-bash.sh }
        ],
        "UserPromptSubmit": [ ... existing inline activity-log injection (unchanged) ... ],
        "SessionStart":     [ { matcher: "" → bash .claude/hooks/session-start.sh } ],
        "Stop":             [ { matcher: "" → bash .claude/hooks/stop-reminder.sh } ]
      }
    }

The pre-existing `UserPromptSubmit` activity-log injection is kept inline and unchanged
(it's a one-liner and works). The pre-existing `Stop` hook's inline logic (60-min log
reminder) is now inside `stop-reminder.sh`, combined with the new unpushed-changes
check.

## Hook-by-hook coverage (matching your table)

| # | Handoff hook | Implemented in | Event | Matcher |
|---|---|---|---|---|
| 1 | Root file guard | `pretool-write-edit.sh` Rule 3 | `PreToolUse` | `Write\|Edit` |
| 2 | Framework dir guard | `pretool-write-edit.sh` Rule 1 | `PreToolUse` | `Write\|Edit` |
| 3 | Sensitive file guard | `pretool-write-edit.sh` Rule 2 | `PreToolUse` | `Write\|Edit` |
| 4 | Destructive cmd guard | `pretool-bash.sh` | `PreToolUse` | `Bash` |
| 5 | Git status at start | `session-start.sh` | `SessionStart` | (none) |
| 6 | Open handoffs reminder | `session-start.sh` | `SessionStart` | (none) |
| 7 | Unpushed changes reminder | `stop-reminder.sh` | `Stop` | (none) |

All scripts exit `0` to proceed, exit `2` + stderr message to block (for Pre hooks).
Non-blocking hooks (SessionStart, Stop) exit `0` and emit stdout as context injection
or a reminder message.

## Deviations / choices worth flagging

1. **Three PreToolUse rules fused into one script** (`pretool-write-edit.sh`) rather
   than three separate hook entries. Reasons: (a) they all match the same
   `Write|Edit` matcher and would re-evaluate the same `file_path` three times if
   separate; (b) one script's exit-2 short-circuits cleanly; (c) easier to reason
   about precedence (framework dir → sensitive file → root policy).

2. **SessionStart `#5` and `#6` fused into one script** (`session-start.sh`) for the
   same reason — they both want to emit one injection block on session start. A
   single script avoids two separate injection blocks per session.

3. **Stop hook `#7` merged with existing log reminder** into `stop-reminder.sh`. The
   inline Stop hook is replaced; logic is equivalent + extended, not duplicated.

4. **`UserPromptSubmit` activity-log injection kept inline and untouched.** It's a
   working one-liner and isn't part of this handoff. Not externalized.

5. **JSON parsing in Bash via Python**, not `jq`. Reason: `jq` is not reliably
   installed on this Windows + Git Bash setup. Python is. The one-liner is bounded
   and robust. If you prefer pure-bash regex extraction, I can rewrite.

6. **Sensitive-file pattern list** matches the handoff verbatim (`.env*`, `*.key`,
   `*.pem`, `id_rsa*`, `.aws/`, `.ssh/`). Also added `id_ed25519*` — modern SSH
   keys use ed25519, and missing it would be a silent gap. Flag if you want it
   removed.

7. **Force-push variants** — `pretool-bash.sh` blocks `--force`, `-f`, AND
   `--force-with-lease`. The handoff only named `--force`; `--force-with-lease` is
   safer but still not something a subagent should do unsupervised. Flag if you
   think `--force-with-lease` should be allowed.

8. **Root-file `.`-prefix handling** — paths starting with `.` (`.gitignore`,
   `.editorconfig`, etc.) are allowed by `pretool-write-edit.sh` Rule 3 even at
   root. Intentional — framework dirs are `.`-prefixed and those are the only
   root-allowed kind beyond the three named files. If you want to tighten (e.g.
   block `.gitignore` writes without orchestrator approval), tell me.

## Claude-specific limitations I inherited

Flagged earlier in `.ai/research/hooks-recommendation-claude.md`; nothing new:

- **No per-subagent hook scoping.** Hook input doesn't expose which subagent
  persona issued the call, so rules are universal. Agent-level scoping stays at
  the system-prompt layer.
- **Hooks fire for subagent tool calls too** — e.g. a `coder` subagent trying to
  write `.kimi/foo.md` is blocked the same as if orchestrator tried. That's the
  intended behavior.

## How to validate

1. `ls .claude/hooks/` → 4 files.
2. `cat .claude/settings.json | python -m json.tool` → parses clean.
3. Pipe-test each script manually:
   - `echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/.kimi/steering/x.md"}}' | bash .claude/hooks/pretool-write-edit.sh` → exit 2, stderr "BLOCKED..."
   - `echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/some-random-file.txt"}}' | bash .claude/hooks/pretool-write-edit.sh` → exit 2, root-policy block
   - `echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/.env"}}' | bash .claude/hooks/pretool-write-edit.sh` → exit 2, sensitive block
   - `echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/src/foo.ts"}}' | bash .claude/hooks/pretool-write-edit.sh` → exit 0 silent
   - `echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | bash .claude/hooks/pretool-bash.sh` → exit 2
   - `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash .claude/hooks/pretool-bash.sh` → exit 0 silent
   - `bash .claude/hooks/session-start.sh` → shows git status + open handoffs if present
   - `bash .claude/hooks/stop-reminder.sh` → silent if log recent + tree clean; otherwise reminders
4. Restart Claude Code in this project → next session should have the new hooks live.
   Specifically `SessionStart` should inject open-handoffs list (since `to-claude/open/`
   currently contains 4 files — 008, 009, 010, 011, 012 all DONE inline but not yet
   moved) — confirming the hook fires.

## When complete
Move this handoff to `.ai/handoffs/to-kiro/done/` after validation. If any script
needs tightening, open a correction handoff (`to-claude/013-...`) with the specific
test case that failed.
