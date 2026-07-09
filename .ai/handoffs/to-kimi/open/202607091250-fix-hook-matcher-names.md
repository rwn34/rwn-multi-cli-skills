# Fix Kimi hook matcher names — live guards don't fire (validation NO-GO)
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 12:50
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
