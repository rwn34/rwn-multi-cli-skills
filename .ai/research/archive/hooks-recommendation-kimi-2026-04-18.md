# Hooks Recommendation — Kimi CLI

**Scope:** Which hooks Kimi should add beyond the existing activity-log hooks. Companion to Kiro's `hooks-recommendation-kiro.md`.

---

## 1. Kiro's 4 Proposed Hooks — Kimi Verdict

| # | Hook | Kiro Event | Kimi Equivalent | Verdict |
|---|------|------------|-----------------|---------|
| 1 | **Root file guard** | `postToolUse` on fs_write | `PreToolUse` matcher=`WriteFile\|StrReplaceFile` | ✅ **Yes — implement.** `PreToolUse` blocks *before* the write, which is strictly better than Kiro's post-hoc guard. Check `tool_input.file_path` against root; block with exit 2 if path has no `/`. |
| 2 | **Framework dir guard** | `preToolUse` on fs_write | `PreToolUse` matcher=`WriteFile\|StrReplaceFile` | ⚠️ **Yes — as safety net only.** Primary enforcement is agent-level `exclude_tools` + system prompt. The hook catches edge cases (MCP tool writes, subagent misconfiguration) but should not be the main gate. |
| 3 | **Git dirty check** | `agentSpawn` | `SessionStart` | ✅ **Yes — implement.** `SessionStart` receives `{source: "startup" \| "resume"}`. Run `git status --short` on startup and prepend to context via stdout. Skip on resume to avoid noise. |
| 4 | **Unpushed changes reminder** | `stop` | `Stop` | ✅ **Yes — reminder-only.** Check `git status --short`. If dirty, inject reminder to commit (delegate to `infra-engineer`). **Never auto-push** — hooks cannot safely decide push timing. |

---

## 2. Additional Hooks Kimi Should Have

### 2a. Auto-format on save
- **Event:** `PostToolUse` matcher=`WriteFile\|StrReplaceFile`
- **Action:** Run `prettier --write`, `black`, `rustfmt`, etc. based on file extension.
- **Why:** Zero-friction formatting. Kimi docs already use this as the canonical example.

### 2b. Sensitive file protection
- **Event:** `PreToolUse` matcher=`WriteFile\|StrReplaceFile`
- **Action:** Block writes to `.env*`, `*.key`, `*.pem`, `id_rsa*`, `.aws/credentials`.
- **Why:** Security baseline. Also shown in Kimi docs as canonical example.

### 2c. Subagent audit trail
- **Events:** `SubagentStart` + `SubagentStop`
- **Action:** Append `{timestamp, agent_name, prompt_hash, duration}` to `.ai/logs/subagent-activity.md`.
- **Why:** Kimi's `SubagentStart`/`SubagentStop` events are unique — Kiro has no equivalent. Use them for delegation telemetry and debugging orchestrator loops.

### 2d. Context compaction warning
- **Event:** `PreCompact`
- **Action:** If `trigger` is `token_limit` and `token_count` > 200k, inject a reminder: "Context compaction imminent — save any critical state."
- **Why:** Kimi's `PreCompact`/`PostCompact` events let agents react to compaction. Kiro has no equivalent.

### 2e. Failed tool pattern detection
- **Event:** `PostToolUseFailure`
- **Action:** Track repeated failures (e.g., 3+ `Grep` failures in one turn). Inject: "Multiple tool failures detected — consider using `Glob` to discover files first."
- **Why:** Catches the "grep loop" antipattern before it spirals.

---

## 3. Kimi-Specific Implementation Details

### Hook mechanics
- **13 events** available (full list in [Kimi hooks docs](https://moonshotai.github.io/kimi-cli/en/customization/hooks.md)).
- **Context via stdin JSON:** `{session_id, cwd, hook_event_name, tool_name, tool_input, ...}`.
- **Blocking:** Exit 0 = allow; Exit 2 = block (stderr → LLM correction); Exit 0 + `{"hookSpecificOutput": {"permissionDecision": "deny"}}` = also block.
- **Fail-open:** Crashes/timeouts silently allow the operation. Log monitoring required.
- **Parallel execution:** Multiple hooks for same event run in parallel; identical commands deduplicated.
- **Stop anti-loop:** `Stop` can re-trigger once; `stop_hook_active` field set on second call.

### Recommended hook script pattern
Store scripts in `.kimi/hooks/*.sh` (cross-platform via bash/Git Bash). Reference them in `config.toml`:

```toml
[[hooks]]
event = "PreToolUse"
matcher = "WriteFile|StrReplaceFile"
command = "bash .kimi/hooks/root-guard.sh"
timeout = 5

[[hooks]]
event = "SessionStart"
command = "bash .kimi/hooks/git-status.sh"
timeout = 5

[[hooks]]
event = "Stop"
command = "bash .kimi/hooks/git-dirty-remind.sh"
timeout = 5
```

### Key: do NOT inline complex bash in `command`
Inline bash in TOML strings is error-prone (quote-escaping hell, especially on Windows). Always shell out to scripts.

---

## 4. Auto-Push vs Reminder-Only

**Reminder-only.**

Reasons:
- Hooks have no access to branch protection rules, PR requirements, or CI status.
- A `Stop` hook cannot distinguish "I'm done for the day" from "pausing for coffee."
- The `infra-engineer` subagent already has git ops in its scope; the hook should *suggest* delegation, not act.

Recommended `Stop` hook behavior:
```bash
if git status --short | grep -q .; then
    echo "Uncommitted changes detected. Consider: git add -A && git commit -m '...' && git push"
    echo "Or delegate to infra-engineer subagent."
fi
```

---

## 5. Impossible or Impractical in Kimi CLI

| Hook Idea | Why Not |
|-----------|---------|
| **Dynamic tool list modification** | Tool lists are static YAML (`allowed_tools`/`exclude_tools`). Changing them requires session restart. |
| **Per-subagent hook scoping** | Hooks run in the root runtime context; there's no built-in way to say "only for subagent X." Workaround: check `agent_name` in `SubagentStart`/`SubagentStop` events. |
| **LLM reasoning introspection** | Hooks see tool inputs/outputs, not the LLM's internal chain-of-thought. |
| **Hook-to-hook communication** | No shared state between hooks. Each hook is an isolated shell invocation. |
| **Windows-native hooks without bash** | Hooks are shell commands. On Windows, this requires Git Bash/WSL. No native PowerShell/CMD hook execution. |

---

## 6. Kimi vs Kiro Hook System Comparison

| Dimension | Kimi CLI | Kiro CLI |
|-----------|----------|----------|
| **Event count** | 13 events | Fewer (exact count TBD) |
| **Pre-flight blocking** | ✅ `PreToolUse` — block before tool executes | ⚠️ `preToolUse` — depends on implementation |
| **Post-flight automation** | ✅ `PostToolUse` — format, lint, etc. | ✅ `postToolUse` |
| **Session lifecycle** | ✅ `SessionStart` / `SessionEnd` | ⚠️ `agentSpawn` only |
| **Subagent lifecycle** | ✅ `SubagentStart` / `SubagentStop` | ❌ No equivalent |
| **Context compaction** | ✅ `PreCompact` / `PostCompact` | ❌ No equivalent |
| **Blocking mechanism** | Exit code 2 or JSON `permissionDecision: deny` | Varies by CLI |
| **Context access** | JSON via stdin | Varies |
| **Fail policy** | Fail-open (broken hook = allow) | Unknown |
| **Parallelism** | Parallel per event, deduped | Unknown |
| **Anti-loop** | `stop_hook_active` flag | Unknown |

**Key advantage for Kimi:** `PreToolUse` blocking is a genuine safety feature. Kiro's `postToolUse` guard can only reject after the fact (requiring rollback). Kimi stops the write before it touches disk.

**Key limitation for Kimi:** No per-subagent hook scoping. A `PreToolUse` hook runs for the orchestrator AND all subagents. For framework-dir guard, this is actually fine (nobody should write there). For root-file guard, also fine. But for hooks that should only apply to certain agents, you need to encode agent-awareness in the hook script itself (e.g., skip if `cwd` is under `.kimi/` — though that's fragile).

---

## 7. Recommended Priority Order

1. **P0 — Implement now:**
   - `PreToolUse` root file guard
   - `SessionStart` git status
   - `Stop` git dirty reminder

2. **P1 — Implement next:**
   - `PreToolUse` sensitive file protection
   - `PostToolUse` auto-format
   - `SubagentStart`/`SubagentStop` audit trail

3. **P2 — Nice to have:**
   - `PreCompact` compaction warning
   - `PostToolUseFailure` pattern detection
   - `Notification` desktop alert (if using GUI notifications)
