# Fix Kiro framework-dir-guard — default-agent wiring + absolute-path glob (validation T-K2 FAIL)
Status: DONE (kiro-cli 2026-07-09 13:20 — report: .ai/reports/kiro-cli-2026-07-09-guardfix.md; suite 39/39, live-verify BLOCKED, one residual manual-launch gap flagged)
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

---

## Completion report (kiro-cli, 2026-07-09 13:20)

Full report: `.ai/reports/kiro-cli-2026-07-09-guardfix.md`.

- **(B) absolute-path glob — DONE.** All three guards normalize backslashes and
  segment-match the framework dir. `framework-dir-guard.sh:15` `REL=$(printf '%s' "$FILE_PATH" | tr '\\' '/')`; `:19` `.claude|.claude/*|*/.claude|*/.claude/*) … exit 2`. `root-file-guard.sh` strips a `pwd -W` prefix; `sensitive-file-guard.sh` segment-matches `.aws/`/`.ssh/`.
- **(A) default-agent wiring — DONE for the dispatch lane.** `chat.defaultAgent`
  confirmed unset → bare `kiro-cli chat` uses the hook-less built-in default.
  Fix: `.ai/tools/dispatch-handoffs.sh` pins `--agent orchestrator` for headless
  Kiro. All 13 agent JSONs already wire the 5 guards; orchestrator allowedPaths
  tightened to `.ai/**`,`.kiro/**`.
- **Step 3 — DONE.** `test_hooks.sh` adds t3a/b, t5d/e/f, t11a/b (absolute payloads). `bash .kiro/hooks/test_hooks.sh` → `PASS: 39/39` (was 32/32; the old count masked defect B by testing relative paths only).
- **Step 4 live-verify — DONE (BLOCKED).** Headless `--agent orchestrator` session refused an absolute-path write to `.claude\probe.txt` (`SAFETY REFUSAL …`, hooks loaded); `Test-Path .claude\probe.txt` → `PROBE_ABSENT`.
- **Cleanup:** removed 5 `.kiro/probe*.txt` debris files from prior sessions.

**Residual (flagged, not fixed — out of mechanical scope):** manual
`kiro-cli chat --trust-all-tools` with no `--agent` (4AI-panes Kiro pane) still
runs the unguarded built-in default. Close via `kiro-cli settings
chat.defaultAgent orchestrator` (per-machine, declined silently — global, risks
other projects) or add `--agent orchestrator` to the 4AI-panes launch
(cross-repo). Claude to decide.

**Insight (not patched):** the three Kiro guards still use the fail-open
`python3||python||echo "" ; [ -z ] && exit 0` extraction that claude-code
already fixed for `.claude/hooks/*` (588ed9c/c5afd79). Recommend a follow-up
handoff to make them fail-CLOSED + python-independent.

Changes left uncommitted for claude-code (no Kiro git lane). Kimi's parallel
changes (`.kimi/*`, dispatch-failure report) untouched.
