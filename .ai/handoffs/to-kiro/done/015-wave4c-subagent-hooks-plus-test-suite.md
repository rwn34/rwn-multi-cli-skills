# Wave 4c — wire hooks into all 12 subagent configs + formalize test_hooks.sh
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-19 17:30

## Goal
Close the Wave 4c BLOCKER: Kiro runtime does NOT inherit `orchestrator.json`
hooks into spawned subagents (confirmed empirically 2026-04-19 21:05 — the
`coder` subagent wrote `evil.txt` at repo root without `root-file-guard.sh`
firing). All 12 subagent configs must carry their own `hooks` section. Bundle
this with a standing `.kiro/hooks/test_hooks.sh` script so future hook changes
are instantly verifiable instead of requiring ad-hoc pipe-tests each time.

## Current state

- `.kiro/agents/orchestrator.json` — has full `hooks` section:
  - `agentSpawn`: `activity-log-inject.sh`
  - `preToolUse` (4 matchers): `root-file-guard`, `framework-dir-guard`,
    `sensitive-file-guard` (all matched on `fs_write`), `destructive-cmd-guard`
    (matched on `execute_bash`)
  - `stop`: `activity-log-remind.sh`
- 12 subagent configs in `.kiro/agents/`: `coder.json`, `reviewer.json`,
  `tester.json`, `debugger.json`, `refactorer.json`, `doc-writer.json`,
  `security-auditor.json`, `ui-engineer.json`, `e2e-tester.json`,
  `infra-engineer.json`, `release-engineer.json`, `data-migrator.json` —
  NONE have a `hooks` section.
- Pipe-tests are ad-hoc: every handoff asks for "6 tests" or "7 tests" and each
  author writes them from memory. No standing regression suite.

## Target state

**Part A — hook wiring (BLOCKER fix)**

Each of the 12 subagent configs gains a `hooks` section equivalent to the
orchestrator's, scoped appropriately:

- **All 12** get the 3 `fs_write` preToolUse guards (`root-file-guard`,
  `framework-dir-guard`, `sensitive-file-guard`). These enforce write boundaries
  — they must fire on every subagent write.
- **Any subagent with `execute_bash` in its `tools`** additionally gets the
  `destructive-cmd-guard` preToolUse hook on the `execute_bash` matcher.
  Subagents without `execute_bash` can skip this one.
- **All 12** get the `agentSpawn` activity-log-inject hook so every subagent
  session starts with cross-CLI context.
- **All 12** get the `stop` activity-log-remind hook.

Use the exact same command strings as `orchestrator.json` (the Git Bash path
and the relative hook script paths) so the matrix is uniform.

**Part B — standing test script**

New file: `.kiro/hooks/test_hooks.sh` — a bash script that pipes crafted JSON
payloads into each of the 4 hooks and asserts the expected exit codes.

Minimum coverage:

| Test | Hook | Payload | Expected exit |
|---|---|---|---|
| t1 | root-file-guard | fs_write to `evil.txt` (root, not in ADR allowlist) | 2 (block) |
| t2 | root-file-guard | fs_write to `.gitignore` (ADR category A) | 0 (allow) |
| t3 | root-file-guard | fs_write to `src/main.rs` (not root) | 0 (allow) |
| t4 | framework-dir-guard | fs_write to `.ai/handoffs/test.md` (allowed) | 0 |
| t5 | framework-dir-guard | fs_write to `.claude/agents/test.md` (denied, Kiro can't write Claude's dir) | 2 |
| t6 | sensitive-file-guard | fs_write to `.env` | 2 |
| t7 | sensitive-file-guard | fs_write to `id_ed25519` | 2 |
| t8 | sensitive-file-guard | fs_write to `id_rsa` | 2 |
| t9 | sensitive-file-guard | fs_write to `secrets.yaml` | 2 |
| t10 | destructive-cmd-guard | execute_bash with `rm -rf /` | 2 |
| t11 | destructive-cmd-guard | execute_bash with `DROP DATABASE foo` (uppercase) | 2 |
| t12 | destructive-cmd-guard | execute_bash with `Drop Database foo` (mixed-case, post-Wave-4 fix) | 2 |
| t13 | destructive-cmd-guard | execute_bash with `git status` | 0 |

Script layout — one `run_test <name> <hook-path> <payload-json> <expected-exit>`
helper, then 13 calls, then a summary line (`PASS: N/13` or `FAIL: listed`).
Exit 0 if all pass, 1 otherwise.

## Context (reference only, not binding)

Claude's equivalent will live at `.claude/hooks/test_hooks.sh` and Kimi's at
`.kimi/hooks/test_hooks.sh`. The attack matrix will be the same across all 3
— the hook script names and payload shapes differ per CLI. You define the
Kiro-side payload shape however it suits Kiro's hook-input contract.

One subtlety for Part A: the `activity-log-inject.sh` hook in orchestrator.json
expects `orchestrator` context. If replaying it for subagents surfaces issues
(e.g., it writes something inappropriate for a subagent context), flag it and
leave `agentSpawn` off for subagents — the BLOCKER fix is the 4 preToolUse
guards, those are non-negotiable. agentSpawn + stop are bonus.

## Steps

1. Edit all 12 subagent configs to add `hooks` section. Pattern per config:
   ```json
   "hooks": {
     "preToolUse": [
       { "matcher": "fs_write", "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" .kiro/hooks/root-file-guard.sh" },
       { "matcher": "fs_write", "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" .kiro/hooks/framework-dir-guard.sh" },
       { "matcher": "fs_write", "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" .kiro/hooks/sensitive-file-guard.sh" }
       // add destructive-cmd-guard entry IF this subagent has execute_bash in tools
     ],
     "agentSpawn": [ ... ],  // if safe
     "stop": [ ... ]          // if safe
   }
   ```
2. Validate all 12 JSON files with `python -m json.tool < file > /dev/null` —
   no syntax errors.
3. Create `.kiro/hooks/test_hooks.sh` with the 13-test matrix above.
4. `chmod +x .kiro/hooks/test_hooks.sh` and run it once. Expect all 13 pass.
5. Empirically re-verify the Wave 4c fix: spawn the `coder` subagent and ask
   it to write `evil.txt` at repo root. Expect `root-file-guard.sh` to fire
   and block the write (exit 2). This is the exact test that failed in the
   2026-04-19 21:05 run — it must now succeed.

## Verification
- (a) All 12 `.kiro/agents/*.json` validate as JSON.
- (b) `.kiro/hooks/test_hooks.sh` exists, is executable, and reports
  `PASS: 13/13` when run.
- (c) Re-run the Wave 4c empirical subagent test: coder-subagent write at
  root is now blocked.
- (d) Document which subagents received `destructive-cmd-guard` (those with
  `execute_bash`) and which did not — so I can verify the split matches
  each subagent's `tools` list.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Wave 4c hook wiring for 12 subagents + test_hooks.sh standing suite (per handoff 015)
    - Files: .kiro/agents/*.json (12 files), .kiro/hooks/test_hooks.sh (new)
    - Decisions: <agentSpawn/stop inclusion or omission; any subagent where hooks needed different shape>

## Report back with
- (a) List of 12 subagent configs touched, noting which got `destructive-cmd-guard` vs not.
- (b) `test_hooks.sh` pass/fail summary (exact output of the final PASS line).
- (c) Result of the empirical subagent-spawn test (coder writes evil.txt → blocked? yes/no + exit code).
- (d) Any deviation from the pattern (e.g., `agentSpawn` omitted for reviewer because it's read-only).

## When complete
Sender (claude-code) validates by reading 3 of the 12 touched configs +
test_hooks.sh. On success, move this file to `.ai/handoffs/to-kiro/done/`.
On failure, leave in `open/`, change Status to `BLOCKED`, append `## Blocker`.
