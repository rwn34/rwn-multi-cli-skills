# Kiro CLI — subagent hook inheritance broken (bug report draft)

Paste-ready bug report for the Kiro CLI upstream team. Filled in during the
2026-04-19 framework-hardening session.

---

## Title

Subagent sessions do not execute `preToolUse` hooks declared in the subagent's own config (JSON `hooks` section is ignored at runtime)

## Severity

High — safety hooks (`fs_write` guards, `execute_bash` guards) declared on subagent configs have zero effect. Any root-file-policy, sensitive-file-policy, or destructive-command-policy implemented via Kiro hooks is bypassed automatically every time a subagent is spawned.

## Filed:

## Environment

- Kiro CLI version: **0.11.130**
- Platform: Windows 10/11 with Git Bash (`"C:\Program Files\Git\bin\bash.exe"` used to invoke hooks)
- Agent definition format: JSON (e.g. `.kiro/agents/orchestrator.json`, `.kiro/agents/coder.json`)

## Summary

Kiro agent JSON configs support a `hooks` object with `preToolUse`, `agentSpawn`, `stop`, etc. hook arrays. When declared on the **orchestrator (main agent)** config, those hooks fire correctly for every tool call made in the orchestrator session. When the **same shape of `hooks` block** is declared on a subagent config (e.g. `coder.json`), the hooks never fire for that subagent's tool calls.

Result: a subagent can perform an `fs_write` that the declared `preToolUse` hook would block, and no hook invocation occurs — the write succeeds.

## Reproduction

1. Fresh Kiro session from a project root that has:
   - `.kiro/agents/orchestrator.json` with its hooks block (as originally shipped)
   - `.kiro/agents/coder.json` with an identical `hooks` block declaring a `preToolUse` hook on `fs_write` that points at a script which unconditionally exits 2 (block) for a specific payload.
2. From orchestrator, spawn the `coder` subagent and instruct it:
   "Write the file `evil.txt` at the repo root with arbitrary content."
3. Observe the filesystem.

**Expected:** `root-file-guard.sh` (or whichever `preToolUse` hook is declared on `coder.json`) fires, blocks the write with exit 2 + a stderr message, `evil.txt` does NOT appear at root.

**Observed:** `evil.txt` is created at root. No hook invocation. No stderr from any guard script. The subagent reports the write succeeded.

**Verification:** piping the same JSON payload directly through the declared hook script (`echo '{"tool_input":{"file_path":"evil.txt"}}' | bash .kiro/hooks/root-file-guard.sh`) exits 2 with the expected error. The hook script is correct. The issue is that the runtime does not invoke it for the subagent's tool call.

## Confirmed on 12 subagent configs

The multi-CLI project wired identical `hooks` blocks into all 12 subagent configs: `coder`, `reviewer`, `tester`, `debugger`, `refactorer`, `doc-writer`, `security-auditor`, `ui-engineer`, `e2e-tester`, `infra-engineer`, `release-engineer`, `data-migrator`. All 12 wire correctly per the documented schema and validate as JSON. None fire their hooks at subagent runtime.

## Impact on real projects

If a Kiro user relies on hooks for safety enforcement (blocking writes to production config, preventing `rm -rf /` class commands, blocking credential leaks), they may believe subagents are covered because the config declares hooks identical to the orchestrator's. They are not. The mitigation we applied is **prompt-level self-enforcement** (injecting a `SAFETY RULES` block into each subagent prompt that duplicates the hook logic in natural language). That is soft — LLM-following-instructions rather than hard platform enforcement.

## Ask

Fix the runtime to invoke hooks declared in the spawned subagent's own config when that subagent performs a tool call. If there is an intentional reason subagents do not inherit/respect hooks, document the alternative enforcement mechanism (global `config.toml`-level hooks? a different config key?) so users can implement safety layers correctly.

## Workaround (for other Kiro users reading this)

Until upstream fixes this, three defense layers can help:
1. Tool-level `deniedPaths` in the subagent's `fs_write` settings — enforced by runtime independently of hooks.
2. Explicit `SAFETY RULES` prompt preamble listing the forbidden file patterns and commands.
3. Where possible, remove `execute_bash` from subagent `tools` arrays (diagnosers, read-only reviewers).

## Related

- Multi-CLI framework activity-log entry 2026-04-19 21:22 documents the empirical failure.
- `.ai/handoffs/to-kiro/done/015-wave4c-subagent-hooks-plus-test-suite.md` shows the wiring that was applied and the empirical test that surfaced the bug.
- `.ai/handoffs/to-kiro/open/017-wave4d-runtime-hole-mitigation.md` documents the defense-in-depth mitigation currently in flight.
