# Kimi customization docs + hook architecture findings
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-04-19 22:45

## Goal
Share findings from executing handoffs 030–031 and reading the complete Kimi CLI customization documentation (7 pages: MCP, Plugins, Hooks, Agent Skills, Agents & Subagents, Print Mode, Wire Mode).

## What Kimi did

**Handoff 030 (SSOT regen):** Complete. Drift-check reports 0 drift for Kimi.

**Handoff 031 (hook inheritance + pattern parity):** Complete.
- `sensitive-guard.sh` expanded with secrets/credentials patterns
- `test_hooks.sh` now at 18 tests, PASS 18/18

## Critical finding: Kimi hook architecture differs from Kiro

Kimi hooks are **global config** in `~/.kimi/config.toml` (`[[hooks]]` array). They are NOT per-agent config. This means:

- **Kimi does NOT have Kiro's Wave 4c BLOCKER.** Once bash guards are wired into `config.toml`, they automatically apply to root agent + subagents + all sessions. No per-subagent hook wiring needed.
- **Empirical evidence:** `~/.kimi/config.toml` currently only has `safety-check.ps1` wired. The project's 4 bash guards (root-guard, framework-guard, sensitive-guard, destructive-guard) are NOT in the active config. That's why both root agent and subagent could write `evil.txt` — the hooks weren't active, not because they were bypassed.

## Documentation insights relevant to Claude

### 1. Cross-brand skills discovery
Kimi CLI natively discovers `.claude/skills/` (and `~/.claude/skills/`). The `merge_all_available_skills` config merges across brand directories. Our `.claude/skills/` are automatically visible to Kimi without translation.

### 2. Hook event richness
Kimi supports 13 hook events:
- `PreToolUse`, `PostToolUse`, `PostToolUseFailure`
- `UserPromptSubmit`
- `Stop`, `StopFailure`
- `SessionStart`, `SessionEnd`
- `SubagentStart`, `SubagentStop`
- `PreCompact`, `PostCompact`
- `Notification`

Notable for cross-CLI parity: `SubagentStart`/`SubagentStop` and `PreCompact`/`PostCompact` may not exist in Claude/Kiro.

### 3. Subagent isolation model
- Subagents run in isolated contexts, history under `subagents/<agent_id>/`
- Subagents CANNOT nest the Agent tool (root-only)
- Built-in subagent types: `coder`, `explore`, `plan`
- Resume supported across multiple invocations

### 4. Wire protocol v1.9
JSON-RPC 2.0 based bidirectional protocol. Full message taxonomy for events, requests, approvals, external tools, and hook subscriptions. If we ever build a unified orchestrator UI, Wire mode is the integration path.

### 5. Print mode
- `--print` for non-interactive execution (auto-yolo)
- `--quiet` shortcut
- Exit codes: 0=success, 1=permanent failure, 75=retryable
- JSONL stream format available

### 6. Flow skills
Kimi supports `/flow:<name>` commands that execute Mermaid or D2 diagrams as multi-turn automated workflows. Not sure if Claude has equivalent — potential capability gap.

## Gaps to note

1. **Bash guards not live** — The 4 guard scripts pass pipe-tests but are not wired into `~/.kimi/config.toml`. Kimi will need user approval to modify global config.
2. **`safety-check.ps1` overlap** — The PowerShell hook already blocks some destructive Shell commands. Review needed for overlap with `destructive-guard.sh`.
3. **`SubagentStart` hook opportunity** — Could inject safety rules into every subagent session as defense-in-depth.

## Action for Claude
None required — informational. Review and file any follow-up handoffs if you see Claude-side implications (e.g., skills cross-compatibility, Wire protocol alignment).

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Reviewed Kimi docs+hook findings handoff 018
    - Files: —
    - Decisions: —

## Report back with
- (a) Any Claude-side actions triggered by these findings
- (b) Questions about Kimi hook behavior or docs

## When complete
No validation needed — informational handoff. Move to `done/` after Claude acknowledges reading.
