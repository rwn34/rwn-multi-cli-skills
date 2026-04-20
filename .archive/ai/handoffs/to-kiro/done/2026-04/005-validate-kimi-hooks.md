# Validate Kimi CLI hooks implementation
Status: OPEN
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-04-17 21:45

## What was implemented

7 hooks implemented in Kimi CLI, matching Kiro's set:

| # | Hook | Kimi Event | Matcher | Script |
|---|---|---|---|---|
| 1 | Root file guard | `PreToolUse` | `WriteFile\|StrReplaceFile` | `.kimi/hooks/root-guard.sh` |
| 2 | Framework dir guard | `PreToolUse` | `WriteFile\|StrReplaceFile` | `.kimi/hooks/framework-guard.sh` |
| 3 | Sensitive file guard | `PreToolUse` | `WriteFile\|StrReplaceFile` | `.kimi/hooks/sensitive-guard.sh` |
| 4 | Destructive cmd guard | `PreToolUse` | `Shell` | `.kimi/hooks/destructive-guard.sh` |
| 5 | Git status at start | `SessionStart` | — | `.kimi/hooks/git-status.sh` |
| 6 | Open handoffs reminder | `SessionStart` | — | `.kimi/hooks/handoffs-remind.sh` |
| 7 | Unpushed changes reminder | `Stop` | — | `.kimi/hooks/git-dirty-remind.sh` |

## Files created / modified

**New scripts** (9 total in `.kimi/hooks/`):
- `root-guard.sh` — blocks root writes except AGENTS.md/README.md/CLAUDE.md
- `framework-guard.sh` — blocks writes to `.claude/` and `.kiro/`
- `sensitive-guard.sh` — blocks `.env*`, `*.key`, `*.pem`, `id_rsa*`, `.aws/`, `.ssh/`
- `destructive-guard.sh` — blocks `rm -rf /`, `git push --force`, `git reset --hard`, `DROP TABLE/DATABASE`
- `git-status.sh` — injects `git status --short` on session start
- `handoffs-remind.sh` — lists `.ai/handoffs/to-kimi/open/*.md` on session start
- `git-dirty-remind.sh` — reminds about uncommitted changes on stop
- `activity-log-inject.sh` — **fixed path bug** (was `.ai/activity/log.md` → now `.ai/activity-log.md`)
- `activity-log-remind.sh` — **fixed path bug** (same fix)

**Config modified**:
- `~/.kimi/config.toml` — replaced 2 inline hook commands with 9 script references

## Kimi-native deviations from Kiro

1. **Pre-flight vs post-hoc blocking:** Kimi's `PreToolUse` blocks *before* the tool executes (exit code 2). Kiro's `postToolUse` guard rejects after the fact. Kimi's approach is strictly safer — no rollback needed.

2. **Event differences:**
   - Kiro `agentSpawn` → Kimi `SessionStart` (functionally equivalent)
   - Kiro `stop` → Kimi `Stop` (same name, Kimi adds `stop_hook_active` anti-loop flag)

3. **Fail-open policy:** Kimi hooks that crash/timeout silently allow the operation. This is documented behavior but means guard scripts must be tested.

4. **JSON parsing dependency:** All guard scripts use `python3`/`python` to parse stdin JSON. If Python is unavailable, the hook parses nothing and fails open. This is acceptable for dev environments but should be noted.

5. **Parallel execution:** Multiple `SessionStart` and `Stop` hooks run in parallel. Their stdout outputs are all injected into context simultaneously.

## Validation needed

- [ ] Verify `PreToolUse` hooks actually block (try writing to root, `.claude/`, `.env`, etc.)
- [ ] Verify `SessionStart` hooks inject git status and handoff list
- [ ] Verify `Stop` hooks fire and remind about uncommitted changes
- [ ] Test that activity-log hooks still work after path fix

## Notes for consolidation

- Kimi has 13 hook events vs Kiro's fewer set. Unique Kimi events not used here: `SubagentStart`/`SubagentStop`, `PreCompact`/`PostCompact`, `PostToolUseFailure`, `Notification`.
- The `PreToolUse` blocking mechanism (exit 2 / `permissionDecision: deny`) is Kimi's strongest advantage over Kiro's post-hoc guards.
