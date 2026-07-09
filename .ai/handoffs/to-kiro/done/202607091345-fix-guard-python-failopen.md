# Fix Kiro guards' python fail-open (same class as Claude's .claude/hooks fix)
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 13:45
Auto: yes
Risk: B

## Why
Your 13:20 guardfix report flagged (correctly, out of that handoff's scope)
that Kiro's guard scripts still use the python-only JSON extraction pattern
that Claude just fixed in `.claude/hooks/*` — it fails OPEN when python3
resolves to the Windows Store alias stub (empty stdout, exit 0), because the
`|| python` fallback keys on exit status, not empty output. On this machine
that means the guards can silently no-op even in the modes where they DO fire
(interactive). Reference the fixed pattern in `.claude/hooks/pretool-write-edit.sh`
(commit 588ed9c) — mirror it.

## Steps
1. In each `.kiro/hooks/*.sh` guard that parses stdin JSON via python, apply
   the SAME fix:
   - Empty-stdin gate first → exit 0 (allow, nothing to evaluate).
   - Extraction chained on EMPTY OUTPUT (not exit status): python3 → python →
     pure-`sed` fallback (`sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'`
     — use Kiro's actual field name, `path` or `file_path`, verify from a real
     payload).
   - FAIL-CLOSED: non-empty stdin but no path parsed → exit 2 ("could not parse
     tool input — refusing to fail open").
2. Add regression tests to `.kiro/hooks/test_hooks.sh` that run under
   `PATH="/usr/bin:/bin"` (python-less) and assert a `.claude/` write → exit 2
   and a benign `.ai/` write → exit 0. Prove both directions (fail pre-fix,
   pass post-fix).
3. Verify: `bash .kiro/hooks/test_hooks.sh` → paste count (0 failures);
   python-less repro exit codes pasted.

## Note (context — not this handoff's job)
Mechanical guards are inert in HEADLESS `--trust-all-tools` mode regardless of
this fix (your 13:20 finding). This fix restores INTERACTIVE-mode enforcement.
The universal headless net is the new git pre-commit backstop (ADR-0005,
claude-code building now) + prompt SAFETY RULES.

## Report back with
Set Status: DONE + move to `to-kiro/done/`; prepend activity entry (identity
`kiro-cli`). Leave commits to claude-code if no git lane. Report path:
`.ai/reports/kiro-cli-2026-07-09-guard-pythonfix.md`.

---

## COMPLETION (kiro-cli, 2026-07-09)

DONE. Applied the fail-closed extraction fix to all six `.kiro/hooks/*.sh`
guards that parse stdin JSON (5 fs_write file_path guards + 1 execute_bash
command guard). Report: `.ai/reports/kiro-cli-2026-07-09-guard-pythonfix.md`.

Verification (subagent, real run):
- `bash .kiro/hooks/test_hooks.sh` → **PASS: 52/52**, 0 failures (was 29 tests;
  added t30–t42).
- python-less repro (`PATH=/usr/bin:/bin`, python unavailable → sed fallback):
  - `.claude/agents/x.md` → `exit=2` (blocked)
  - `.ai/handoffs/x.md` → `exit=0` (allowed)
  - `rm -rf /` → `exit=2` (blocked)

Left for claude-code (no git lane on Kiro orchestrator): commit these changes,
and the physical `open/ → done/` move as the validation step.
