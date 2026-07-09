# Kimi CLI Hook Fix Report — 2026-07-09

Identity: **Kimi CLI**  
Handoff: `.ai/handoffs/to-kimi/done/202607091250-fix-hook-matcher-names.md`

---

## Executive Summary

The self-validation campaign (`.ai/reports/kimi-cli-2026-07-09-selfvalidation.md`) diagnosed live PreToolUse guards not firing because hook matchers allegedly used legacy tool names `WriteFile|StrReplaceFile`. This follow-up investigation found that diagnosis was only partially correct:

1. **The active global config already used `Write|Edit` matchers**, not `WriteFile|StrReplaceFile`.
2. **A second mismatch existed**: the destructive/safety hooks matched on `Shell`, but the runtime shell tool is named `Bash`.
3. **The canonical snippet pointed to the wrong global config path**: `~/.kimi/config.toml` instead of the active `~/.kimi-code/config.toml` used by Kimi 0.23.3.
4. **The root cause for headless validation failures**: `kimi -p` (non-interactive prompt mode) does **not** execute hooks at all — neither `PreToolUse` nor `SessionStart` events fire. Live blocking can only be observed in a fresh interactive Kimi session.

All configs, the canonical snippet, and the regression suite have been updated. The hook suite passes 48/48.

---

## Runtime Tool Names (empirical)

Extracted from a live `kimi -p` wire log (`~/.kimi-code/sessions/wd_rwn-multi-cli-skills_5ddd1416afd3/session_fe11311e-.../agents/main/wire.jsonl`):

```json
{"type":"tools.set_active_tools","names":["Read","Write","Edit","Grep","Glob","Bash",...]}
{"type":"...tool.call...","name":"Write","args":{"path":".kiro/probe_runtime.txt",...}}
```

- File write tool: `Write`
- File edit tool: `Edit`
- Shell tool: `Bash`

Therefore hook matchers must be:

- `Write|Edit` for root/framework/sensitive/worktree-fleet guards
- `Bash` for destructive-command and safety-check guards

---

## Fixes Applied

### 1. Active global config — `~/.kimi-code/config.toml`

- Deduplicated repeated hook blocks.
- Changed destructive/safety matchers from `Shell` to `Bash`.
- Removed temporary debug/probe hooks left over from investigation.
- Preserved the `Stop` activity-log enforcement hook.

Verified:

```text
$ kimi doctor
OK config.toml  C:/Users/rwn34/.kimi-code/config.toml
OK tui.toml     C:\Users\rwn34\.kimi-code\tui.toml
```

### 2. Legacy mirror config — `~/.kimi/config.toml`

Same cleanups applied so the legacy file does not re-introduce `Shell` matchers if ever loaded.

### 3. Canonical snippet — `.ai/config-snippets/kimi-hooks.toml`

- Updated instruction path from `~/.kimi/config.toml` to `~/.kimi-code/config.toml`.
- Added explicit note that hooks do **not** run in `kimi -p` headless mode.
- Changed destructive guard matcher from `Shell` to `Bash` and updated comments.
- Updated safety-check.ps1 coexistence note to reference `Bash`.

### 4. Regression suite — `.kimi/hooks/test_hooks.sh`

Added tests:

- `t46-snippet-uses-bash-tool-name` — snippet must not contain `matcher = "Shell"`.
- `t47-active-config-uses-bash-tool-name` — both global configs must not contain `matcher = "Shell"`.
- `t48-snippet-points-to-active-config` — snippet must reference `~/.kimi-code/config.toml`.

Existing tests `t39-t45` already cover real `path`-based payloads and `Write|Edit` matchers.

Result:

```text
$ bash .kimi/hooks/test_hooks.sh
PASS: 48/48
```

---

## Live Verification Status

### What was attempted

1. `kimi -p` with a debug `PreToolUse` hook (`matcher = ".*"`) that appends to `/tmp/kimi-hooks-fired.log`.
   - Result: write succeeded; debug log was **not** written.
2. `kimi -p` with a `SessionStart` probe hook.
   - Result: session started; probe log was **not** written.
3. Piped interactive `kimi --yolo` (no real TTY).
   - Result: TUI hung on MCP failures before reaching a tool call.
4. `winpty bash -c '... | kimi --yolo'`.
   - Result: `stdin is not a tty`; no tool call.

### Conclusion

`kimi -p` does not execute hooks in Kimi 0.23.3. This explains why the original validation campaign saw writes "succeed" despite correct `Write|Edit` matchers. The guard scripts themselves are correct: manual invocation with the runtime `path` payload blocks the intended paths.

Manual evidence (run from project root):

```text
$ echo '{"tool_input":{"path":".kiro/probe.txt"}}' | bash .kimi/hooks/framework-guard.sh; echo exit=$?
BLOCKED: Writing to '.kiro/probe.txt' is not allowed. That path is owned by another CLI. Use .ai/ or .kimi/ for framework-level files.
exit=2

$ echo '{"tool_input":{"path":".claude/probe.txt"}}' | bash .kimi/hooks/framework-guard.sh; echo exit=$?
BLOCKED: Writing to '.claude/probe.txt' is not allowed. That path is owned by another CLI. Use .ai/ or .kimi/ for framework-level files.
exit=2

$ echo '{"tool_input":{"path":".env"}}' | bash .kimi/hooks/sensitive-guard.sh; echo exit=$?
BLOCKED: Direct modification of .env files is not allowed. Use .env.example for templates.
exit=2
```

A fresh interactive Kimi session (started after these config changes) is required to observe live automatic blocking.

---

## Remaining Risk / Follow-up

- **Headless dispatch path**: any cross-CLI handoff that relies on `kimi -p` to enforce project guards will **not** be protected by PreToolUse hooks. This is a Kimi CLI runtime limitation, not a config bug.
- **Recommendation**: for unattended/headless execution, enforce boundaries before invoking Kimi (e.g., pre-flight checks, restricted working directories, or subagent policies), or require interactive sessions for guard-dependent work.
- **Verification gap**: live automatic blocking was not observed because the current session predates the config changes and `kimi -p` does not load hooks. The next human-driven interactive Kimi session should manually confirm a `.kiro/probe.txt` write is blocked.

---

## Files Changed

- `~/.kimi-code/config.toml` — cleaned, deduplicated, `Shell` → `Bash`.
- `~/.kimi/config.toml` — mirrored cleanup.
- `.ai/config-snippets/kimi-hooks.toml` — correct path, `Shell` → `Bash`, `kimi -p` note.
- `.kimi/hooks/test_hooks.sh` — added t46-t48 regressions.
- `.ai/reports/kimi-cli-2026-07-09-hookfix.md` — this report.
