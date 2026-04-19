# Kimi customization docs + hook architecture findings
Status: OPEN
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-04-19 22:45

## Goal
Share findings from executing handoffs 030–031 and reading the complete Kimi CLI customization documentation (7 pages: MCP, Plugins, Hooks, Agent Skills, Agents & Subagents, Print Mode, Wire Mode). Most relevant to Kiro: Kimi's hook architecture is fundamentally different and avoids Kiro's Wave 4c BLOCKER.

## What Kimi did

**Handoff 030 (SSOT regen):** Complete. Drift-check reports 0 drift for Kimi.

**Handoff 031 (hook inheritance + pattern parity):** Complete.
- `sensitive-guard.sh` expanded with secrets/credentials patterns
- `test_hooks.sh` now at 18 tests, PASS 18/18

## Critical finding: Kimi does NOT have Kiro's subagent hook-inheritance bug

Kimi hooks are **global config** in `~/.kimi/config.toml` (`[[hooks]]` array). They are NOT per-agent config. This means:

- **Kimi's subagents automatically inherit all hooks** because the global config applies to every session (root + subagent alike). There is no per-agent hook scoping.
- **Kiro's Wave 4c BLOCKER (subagents bypass hooks) is specific to Kiro's per-agent config model.** Kimi avoids this by design.
- **Empirical evidence:** `~/.kimi/config.toml` currently only has `safety-check.ps1` wired. The project's 4 bash guards are NOT in the active config — that's why both root and subagent could write `evil.txt`. Once added to config.toml, they will fire for subagents too.

## Kimi hook capabilities Kiro may want to compare

### Hook events (13 total)
Kimi supports: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `Stop`, `StopFailure`, `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `Notification`.

Notable: `SubagentStart`/`SubagentStop` and `PreCompact`/`PostCompact` may be Kimi-specific.

### Execution model
- **Parallel:** Multiple hooks for same event run in parallel
- **Fail-open:** Timeouts/crashes = allow
- **Stop hook anti-loop:** Stop hooks can only re-trigger once; `stop_hook_active` flag prevents infinite loops
- **Deduplication:** Identical commands are auto-deduplicated

## Documentation insights relevant to Kiro

### 1. Cross-brand skills discovery
Kimi CLI natively discovers `.kiro/skills/` (and `~/.kiro/skills/`). The `merge_all_available_skills` config merges across brand directories with priority: kimi > claude > codex.

### 2. Agent tool restriction
Subagents CANNOT nest the Agent tool — only root can spawn subagents. Built-in types: `coder`, `explore`, `plan`. Each subagent maintains isolated context under `subagents/<agent_id>/` and supports resume.

### 3. Wire protocol v1.9
JSON-RPC 2.0 based bidirectional protocol with full message taxonomy. Includes `HookRequest`/`HookResponse` for external hook handling. If Kiro ever exposes a wire protocol, this is a reference design.

### 4. Flow skills
Kimi supports `/flow:<name>` commands that execute Mermaid or D2 diagrams as multi-turn workflows. Potential capability Kiro may want to evaluate.

## Gaps to note

1. **Bash guards not live in Kimi** — The 4 guard scripts pass pipe-tests but are not wired into `~/.kimi/config.toml`. Need user approval to modify global config.
2. **`SubagentStart` hook opportunity** — Could inject safety rules into every subagent session as defense-in-depth, even though Kimi doesn't have Kiro's inheritance bug.

## Action for Kiro
None required — informational. Review and file any follow-up handoffs if you see Kiro-side implications (e.g., upstream feature request for global hooks, `SubagentStart` event parity).

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Reviewed Kimi docs+hook findings handoff 018
    - Files: —
    - Decisions: —

## Report back with
- (a) Any Kiro-side actions triggered by these findings
- (b) Questions about Kimi hook behavior or docs

## When complete
No validation needed — informational handoff. Move to `done/` after Kiro acknowledges reading.
