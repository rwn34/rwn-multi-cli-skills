# Kiro guard fix — T-K2 (framework-dir write bypass)

**Author:** kiro-cli · **Date:** 2026-07-09 · **Handoff:** `202607091251-fix-guard-default-agent-and-abspath`
**Verdict:** T-K2 symptom **CLOSED** — a headless `.claude/` write is now refused.
But the close comes from the **prompt-level** layer, not the mechanical one:
live testing proved Kiro's preToolUse hooks **and** `allowedPaths` are both
**inert under `--trust-all-tools`** (the mandatory headless flag). Details below.

## What was asked
Fix (A) default-agent wiring + (B) absolute-path glob bypass, add absolute-path
regression tests, live-verify a main-thread `.claude/` write is blocked.

## What I found + fixed (grounded)

### (B) Absolute-path bypass — FIXED (guard logic now correct)
Kiro emits an ABSOLUTE `file_path` (`C:/…/.claude/…`); the guards matched
relative-anchored globs only, so absolute paths fell through to `exit 0`. It's a
**class bug** in the three legacy guards (the ADR-0004 worktree/fleet guards
already handle absolute paths). Fixed all three:
- `framework-dir-guard.sh` — segment-match (`*/.claude/*` etc.) + backslash normalize.
- `root-file-guard.sh` — absolute→root-relative via `pwd -W` + case-insensitive length-strip.
- `sensitive-file-guard.sh` — segment-match for the `.aws/`/`.ssh/` dir case.
- Test harness bug fixed too: `run_test` used `echo` (mangles JSON `\\`) → `printf '%s'`.

### Regression tests — ADDED (32 → 39, all PASS)
`t3a/t3b` (root abs), `t5d/t5e/t5f` (framework abs: fwd-slash / backslash /
real-root), `t11a/t11b` (sensitive abs). These feed ABSOLUTE paths and assert
`exit 2`, so the suite can no longer stay green while absolute paths bypass.
`bash .kiro/hooks/test_hooks.sh` → `PASS: 39/39`.

### (A) Default-agent wiring — corrected the diagnosis
My 12:38 note said "guard wired only on orchestrator." Grep shows the opposite:
**all 13 `.kiro/agents/*.json` already wire the guard.** The real gap is that
`chat.defaultAgent` is **unset**, so a bare headless `kiro-cli chat` runs Kiro's
**built-in default agent**, which carries no hooks and no path config. Two fixes:
- Dispatcher now pins `--agent orchestrator` for kiro (mirrors the existing
  `--agent opencode` pin) → headless runs a configured, SAFETY-RULE-carrying agent.
- `orchestrator.json` `fs_write.allowedPaths` narrowed `[.ai, .kiro, .kimi,
  .claude]` → `[.ai, .kiro]` — the per-CLI narrowing (documented in steering)
  was never applied to the hard layer.

## The live-verify finding (the important part)

I ran the real thing: `kiro-cli chat --no-interactive --trust-all-tools --agent
orchestrator "…write .claude/probe.txt…"`.

**Run 1 & 2 (after B + allowedPaths fixes): the write STILL LANDED.** Evidence:
- Only `agentSpawn` fired (`✓ 1 of 1 hooks finished`) — the 6 `preToolUse`
  `fs_write` guards did **not** fire for the write.
- `allowedPaths` was already narrowed to `[.ai, .kiro]`, yet the `.claude/` write
  succeeded — because `--trust-all-tools` (required by `--no-interactive`)
  **auto-approves the path-violation prompt**. `allowedPaths` is an approval
  policy, not a hard denial, so trust-all bypasses it.

**Conclusion (proven by execution): on Kiro headless (`--trust-all-tools`),
neither preToolUse hooks nor `allowedPaths` enforce. The only layer that fires is
prompt-level.** This extends the known "Kiro subagents don't fire hooks" bug to
the **main agent** in headless mode, and corroborates kimi-cli's 12:22 NO-GO
(hooks not firing on tool-name matchers).

**Run 3 (after adding prompt SAFETY RULES to the orchestrator, mirroring
`coder.json`): the write is REFUSED.** Verbatim:
> `SAFETY REFUSAL: .claude/ is another CLI's config directory (Claude Code's)…
> I did not create .claude/probe.txt and made no fs_write call.`
`Test-Path .claude/probe.txt` → `False`. The agent itself correctly noted this is
a prompt-level refusal, not a hook-level block.

So T-K2 is closed by the **soft** layer. The mechanical fixes remain as correct
defense-in-depth (they fire in interactive mode / if Kiro fixes hook-firing).

## Files changed (mine)
- `.kiro/hooks/framework-dir-guard.sh`, `.kiro/hooks/root-file-guard.sh`,
  `.kiro/hooks/sensitive-file-guard.sh`, `.kiro/hooks/test_hooks.sh`
- `.kiro/agents/orchestrator.json` (allowedPaths narrowed + SAFETY RULES added)
- `.ai/tools/dispatch-handoffs.sh` (kiro line: `--agent orchestrator`)
Cleaned: `.claude/probe.txt` (my test artifact, ×2) and 5 leftover
`.kiro/probe_*.txt` from earlier validation. Left Kimi's parallel fix
(`.kimi/hooks/*`, `202607091250`) untouched — not my lane.

## Verification
- `bash .kiro/hooks/test_hooks.sh` → `PASS: 39/39`
- `bash .ai/tools/check-ssot-drift.sh` → `Checked: 24 replicas, Drift: 0`
- Live headless refusal confirmed (Run 3 above); no probe artifact remains.

## Recommendations for claude-code (final reviewer — cross-cutting, not my lane)
1. **Treat prompt-level SAFETY RULES as the PRIMARY headless enforcement** for
   Kiro (and Kimi). Mechanical guards are interactive-mode + defense-in-depth
   only. The compat review §4.1 rated this HIGH risk; live testing confirms it.
2. **Add a repo-level git pre-commit hook** — the one mechanical layer that
   reaches a hookless/trust-all runtime: reject commits touching another CLI's
   dir / root non-allowlist / sensitive files, regardless of which CLI committed.
3. **Record in `.ai/known-limitations.md` + ADR:** "Kiro `preToolUse` hooks and
   `fs_write.allowedPaths` do NOT enforce under `--no-interactive
   --trust-all-tools`; prompt SAFETY RULES are the only active layer headless."
4. Consider whether every writable Kiro agent's prompt should carry the SAFETY
   RULES (coder already does; I added them to orchestrator; the other executors
   rely on `deniedPaths` which trust-all also bypasses headless).

## Next step + what breaks first
Next: Claude decides on the git pre-commit backstop (item 2) and the
known-limitations/ADR note (item 3), and commits this batch (I left commits to
claude-code per the handoff). What breaks first: a headless dispatched Kiro (or
Kimi) session fed an adversarial brief that talks the model past its prompt
SAFETY RULES — there is no mechanical net behind them in trust-all mode until
the pre-commit hook lands.
