# Validate Kimi agent configs
Status: OPEN
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-04-17 17:30

## Goal
Validate the 13 Kimi CLI agent configs created per handoff 009 from kiro-cli.

## Files created

### Agent YAMLs (13)
- `.kimi/agents/orchestrator.yaml`
- `.kimi/agents/coder-executor.yaml`
- `.kimi/agents/reviewer.yaml`
- `.kimi/agents/tester.yaml`
- `.kimi/agents/debugger.yaml`
- `.kimi/agents/refactorer.yaml`
- `.kimi/agents/doc-writer.yaml`
- `.kimi/agents/security-auditor.yaml`
- `.kimi/agents/ui-engineer.yaml`
- `.kimi/agents/e2e-tester.yaml`
- `.kimi/agents/infra-engineer.yaml`
- `.kimi/agents/release-engineer.yaml`
- `.kimi/agents/data-migrator.yaml`

### System prompt files (13)
- `.kimi/agents/system/orchestrator.md`
- `.kimi/agents/system/coder-executor.md`
- `.kimi/agents/system/reviewer.md`
- `.kimi/agents/system/tester.md`
- `.kimi/agents/system/debugger.md`
- `.kimi/agents/system/refactorer.md`
- `.kimi/agents/system/doc-writer.md`
- `.kimi/agents/system/security-auditor.md`
- `.kimi/agents/system/ui-engineer.md`
- `.kimi/agents/system/e2e-tester.md`
- `.kimi/agents/system/infra-engineer.md`
- `.kimi/agents/system/release-engineer.md`
- `.kimi/agents/system/data-migrator.md`

## Deviations from spec

1. **Abstract tool name mapping:** The spec uses abstract tool names (`fs_read`, `fs_write`, `execute_bash`, `code`, `introspect`, `knowledge`). These were mapped to Kimi's native tool names:
   - `fs_read` → `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`
   - `fs_write` → `WriteFile`, `StrReplaceFile`
   - `execute_bash` → `Shell`
   - `web_search` → `SearchWeb`
   - `web_fetch` → `FetchURL`
   - `subagent` → `Agent`
   - `todo_list` → `SetTodoList`
   - `code` / `introspect` / `knowledge` → omitted as abstract concepts; code analysis is performed via `ReadFile`/`Grep`/`Glob`/`SearchWeb`/`FetchURL`

2. **No `AskUserQuestion` in subagents:** All subagents exclude `AskUserQuestion` to keep user interaction centralized in the orchestrator.

3. **Refactorer shell scope:** Spec says "Test runners only" for refactorer shell. Enforced via system prompt (Kimi has no native shell command filtering).

## Kimi-specific limitations

1. **No native path-level write restriction:** Kimi can only allow/deny tool classes (`WriteFile` yes/no), not restrict which paths can be written. Path restrictions (e.g., doc-writer only writing `*.md`) are enforced via system prompts and steering docs.
2. **No native shell command filtering:** Shell is all-or-nothing. "Scanners only" or "test runners only" restrictions are prompt-enforced.
3. **PostToolUse hooks possible but not configured:** We could add `~/.kimi/config.toml` hooks for path/command enforcement, but that requires global config changes. The current implementation relies on prompt discipline.
4. **Session restart required:** The new agent files won't be active until a fresh Kimi session starts with `kimi --agent-file .kimi/agents/orchestrator.yaml`.

## Verification checklist
- [ ] All 13 YAML files exist
- [ ] Each agent's tool list matches the spec (adapted to Kimi names)
- [ ] Orchestrator's `subagents:` block lists all 12 subagents
- [ ] System prompts encode the behavior rules from the spec
- [ ] No typos in file paths or tool names
