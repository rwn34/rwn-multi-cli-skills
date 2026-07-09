# Fix Kiro framework-dir-guard — default-agent wiring + absolute-path glob (validation T-K2 FAIL)
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 12:51
Auto: yes
Risk: B

## Why (blocking — validation campaign 2026-07-09)
Your own self-validation (`.ai/reports/kiro-cli-2026-07-09-selfvalidation.md`,
activity 12:38) found T-K2 FAIL — a main-thread write to `.claude/x` landed.
Two independent defects, either sufficient (you diagnosed both):
- **(A) Wiring gap:** `framework-dir-guard` is wired only on the `orchestrator`
  agent, not the DEFAULT agent a headless `kiro-cli chat` session runs — so the
  guard isn't active at all in dispatch.
- **(B) Absolute-path glob gap:** the guard's `case` globs anchor at string
  start and match RELATIVE paths only, but your runtime emits ABSOLUTE
  `file_path` (`C:/…/.claude/…`) → falls through to `exit 0`. Proven: relative
  `.claude/…` → exit 2 BLOCKED; absolute → exit 0 allowed. `test_hooks.sh`
  passes 32/32 because every case feeds a relative path.
Note: T-K3 (subagent adversarial) PASSED via prompt SAFETY RULES — keep those;
this handoff fixes the main-thread/default-agent mechanical guard.

## Steps
1. **(B) Normalize absolute → relative** at the top of the guard before the
   `case` matches (mirror Claude's `pretool-write-edit.sh` lines ~19-31: strip
   `$PWD` prefix, convert backslashes). Then the existing globs match both.
2. **(A) Wire `framework-dir-guard` (+ the ADR-0004 worktree/fleet guard) on the
   DEFAULT agent**, not just `orchestrator` — every agent that can write must
   carry the guard. Apply to all 13 `.kiro/agents/*.json` as appropriate, or the
   default set a headless session uses.
3. **Add regression tests** to `.kiro/hooks/test_hooks.sh` that feed ABSOLUTE
   paths (`C:/…/.claude/x`, `/…/.kimi/x`) and assert exit 2 — so the suite
   can't stay green while absolute paths bypass. Re-run → paste PASS count.
4. **Live-verify:** in a real default-agent `kiro-cli chat` session (or headless
   `--trust-all-tools`), attempt a main-thread write to `.claude/probe.txt`
   (absolute path) → must now be BLOCKED. Paste evidence + `git status`.

## Report back with
Set Status: DONE + move to `to-kiro/done/`; prepend activity entry (identity
`kiro-cli`). Leave commits to claude-code if no git lane. Report path:
`.ai/reports/kiro-cli-2026-07-09-guardfix.md`.
