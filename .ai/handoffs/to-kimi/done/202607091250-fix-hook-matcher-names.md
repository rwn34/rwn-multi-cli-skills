# Fix Kimi hook matcher names — live guards don't fire (validation NO-GO)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 12:50
Completed: 2026-07-09 13:04
Auto: yes
Risk: B

## Why (blocking — validation campaign 2026-07-09)
Your own self-validation (`.ai/reports/kimi-cli-2026-07-09-selfvalidation.md`,
activity 12:22) found your PreToolUse guards DON'T FIRE at runtime: the hook
matchers are configured for tool names `WriteFile`/`StrReplaceFile`, but your
runtime actually emits `Write`/`Edit`, so the matcher never matches and live
writes to `.kiro/x` (and a subagent write to `.claude/x`) SUCCEEDED. Only the
`.env` sensitive-file path blocked. `test_hooks.sh` passes 36/36 because it
simulates the config's tool names — masking the gap. This is a merge blocker.

## Steps
1. **Determine the ACTUAL tool names your runtime emits** for file writes/edits
   empirically (don't assume) — e.g. inspect a real hook input payload or your
   CLI docs. The campaign evidence says they are `Write` and `Edit`; confirm.
2. Fix the matcher(s) in the hook wiring in `~/.kimi/config.toml` to match the
   real tool names (both duplicate hook blocks if present).
3. Fix the SOURCE snippet too so fresh installs are correct:
   `.ai/config-snippets/kimi-hooks.toml` (or wherever the canonical snippet
   lives) — otherwise the next machine re-introduces the bug.
4. **Live-verify (execution evidence, not claims):** in a real Kimi session
   attempt writes to `.kiro/probe.txt` and `.claude/probe.txt` → BOTH must now
   be BLOCKED. Also a subagent (`coder-executor`) out-of-scope write → blocked.
   Paste the block messages + post-probe `git status` proving nothing landed.
5. **Add a regression test** to `.kimi/hooks/test_hooks.sh` that exercises the
   REAL tool names (so the suite can't stay green while the runtime boundary is
   open). Re-run → paste PASS count.

## Report back with
Set Status: DONE + move to `to-kimi/done/`; prepend activity entry (identity
`kimi-cli`); commit + push if you have git access. Report path:
`.ai/reports/kimi-cli-2026-07-09-hookfix.md` (or append to your self-validation).

## Completion notes (kimi-cli)
- Fixed matchers in active `~/.kimi-code/config.toml` and legacy `~/.kimi/config.toml` from `WriteFile|StrReplaceFile` to `Write|Edit` (all duplicate hook blocks).
- Fixed shell-tool matcher from `Shell` to `Bash` for destructive-guard and safety-check.ps1 hooks in both global configs and the canonical snippet; the runtime shell tool name is `Bash`.
- Added missing `worktree-fleet-guard.sh` hook to the active `~/.kimi-code/config.toml` to match the legacy config.
- Fixed `.ai/config-snippets/kimi-hooks.toml`: correct global config path (`~/.kimi-code/config.toml`), `Shell` → `Bash`, and explicit note that hooks do not run in `kimi -p` headless mode.
- Fixed `root-guard.sh`, `framework-guard.sh`, `sensitive-guard.sh`, and `worktree-fleet-guard.sh` to parse the real `path` field used by `Write`/`Edit` tools, while retaining backward compatibility with `file_path`.
- Added regression tests in `.kimi/hooks/test_hooks.sh` for real `path` payloads, `Write|Edit` matchers, `Bash` matcher, and correct snippet config path.
- Hook suite: `PASS: 48/48`.
- Live verification limitation: PreToolUse hooks do not fire in headless `kimi -p` mode, and the current interactive session loaded config before these changes. Manual invocation of the updated guard scripts confirms `.kiro/`, `.claude/`, `.env`, and root-file probes are all blocked. A fresh interactive Kimi session is required to observe live blocking. Full evidence in `.ai/reports/kimi-cli-2026-07-09-hookfix.md`.
- No leftover probe files; git status clean for Kimi-owned files.
