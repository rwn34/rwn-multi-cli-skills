# Kiro guards — python fail-open fix (handoff 202607091345)

**Author:** kiro-cli · **Date:** 2026-07-09 · **Handoff:** `202607091345-fix-guard-python-failopen`
**Verdict:** Code fix **LANDED** across all guards (grep-grounded below).
Runtime verification (test suite + python-less repro) **BLOCKED this session** —
no process could be spawned (shell `STATUS_DLL_INIT_FAILED`). Written,
**UNVERIFIED at runtime**; a working-shell re-run is the remaining gate before
commit. See §Verification.

## What was asked
Apply the Claude python-independent, fail-CLOSED extraction pattern
(`.claude/hooks/pretool-write-edit.sh` 588ed9c / `pretool-bash.sh` c5afd79) to
every `.kiro/hooks/*.sh` guard that parses stdin JSON via python: empty-stdin
gate → python3 → python → pure-sed fallback keyed on EMPTY output → fail-CLOSED
(exit 2) when a non-empty payload yields no parseable field. Add python-less
regression tests. Verify by execution.

## State found + delivered (grounded)

The three `fs_write` guards and the test suite already carried the fix on entry
(applied by an earlier session in this multi-CLI workspace). The one remaining
fail-open guard was `destructive-cmd-guard.sh`, which still used
`python3 || python || echo ""` keyed on exit status with `[ -z "$CMD" ] && exit 0`.
During this session that guard was also brought to the fixed pattern (concurrent
edit in the live workspace observed; final state re-read and confirmed). All four
legacy guards plus the two ADR-0004 guards now share the fail-CLOSED extractor.

### Grep evidence (fail-CLOSED marker present in every guard)

    $ rg -n "refusing to fail open" .kiro/hooks/*.sh
    destructive-cmd-guard.sh:21:  echo "BLOCKED: could not parse tool input (no command found) — refusing to fail open." >&2
    framework-dir-guard.sh:22:    echo "BLOCKED: could not parse tool input (no file_path found) — refusing to fail open." >&2
    root-file-guard.sh:17:        echo "BLOCKED: could not parse tool input (no file_path found) — refusing to fail open." >&2
    sensitive-file-guard.sh:17:   echo "BLOCKED: could not parse tool input (no file_path found) — refusing to fail open." >&2
    fleet-whitelist-guard.sh:22:  echo "BLOCKED: could not parse tool input (no file_path found) — refusing to fail open." >&2
    worktree-confinement-guard.sh:20: echo "BLOCKED: could not parse tool input (no file_path found) — refusing to fail open." >&2

### destructive-cmd-guard.sh — the guard fixed this session

    16  CMD=$(printf '%s' "$INPUT" | python3 -c "...get('command','')" 2>/dev/null)
    17  [ -z "$CMD" ] && CMD=$(printf '%s' "$INPUT" | python -c "...get('command','')" 2>/dev/null)
    18  [ -z "$CMD" ] && CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    19  # Non-empty stdin but no command parsed → refuse to fail open.
    20  if [ -z "$CMD" ]; then
    21      echo "BLOCKED: could not parse tool input (no command found) — refusing to fail open." >&2
    22      exit 2
    23  fi

Empty-stdin gate precedes extraction (lines 12–15): whitespace-only stdin → exit 0.

### Regression tests present in `.kiro/hooks/test_hooks.sh`

- **python-less fallback (PATH=/usr/bin:/bin)** — t30–t36, incl.
  `t35 pyless destructive rm -rf / blocked` (expect 2) and
  `t36 pyless destructive git status allowed` (expect 0).
- **fail-CLOSED on unparseable input** — t37–t42, incl.
  `t40 destructive unparseable → block` (expect 2) and
  `t42 destructive empty stdin → allow` (expect 0).

These tests already encode the destructive-guard expectations; before this
session's destructive-guard fix they would have failed (t35, t40).

## Verification — BLOCKED (honest state)

Delegated the test run to a `tester` subagent. It reported that **every** shell
invocation in this session (bash / cmd.exe / powershell) returns Windows exit
code `0xc0000142` (`STATUS_DLL_INIT_FAILED`) with no stdout/stderr — no child
process can spawn. This is an environment/session failure, external to the
project. The orchestrator has no shell either.

Consequently, NONE of the following were executed:

- `bash .kiro/hooks/test_hooks.sh` — expected `PASS: 42/42`, **NOT RUN**.
- The four python-less `destructive-cmd-guard.sh` repros — **NOT RUN**.
- `bash .ai/tools/check-ssot-drift.sh` — **NOT RUN**.

Verified by inspection + grep only (presence, not behavior). Per
delivery-integrity, presence ≠ behavior — this is **not** a runtime-verified
"done".

## Follow-up (the remaining gate)

Re-run in a working shell (Git Bash directly, or after resolving the DLL-init
failure) and paste evidence:

    bash .kiro/hooks/test_hooks.sh                 # expect PASS: 42/42
    printf '%s' '{"tool_input":{"command":"rm -rf /"}}'  | PATH="/usr/bin:/bin" bash .kiro/hooks/destructive-cmd-guard.sh; echo "exit=$?"  # expect 2
    printf '%s' '{"tool_input":{"command":"git status"}}' | PATH="/usr/bin:/bin" bash .kiro/hooks/destructive-cmd-guard.sh; echo "exit=$?"  # expect 0
    printf '%s' '{"garbage":true}'                       | PATH="/usr/bin:/bin" bash .kiro/hooks/destructive-cmd-guard.sh; echo "exit=$?"  # expect 2
    printf '%s' ''                                       | PATH="/usr/bin:/bin" bash .kiro/hooks/destructive-cmd-guard.sh; echo "exit=$?"  # expect 0

Commits left to claude-code (no Kiro git lane). The uncommitted
`.kiro/hooks/*.sh` + `test_hooks.sh` changes are ready for that verification +
commit.

## Next step + what breaks first
Next: claude-code (or a working shell) runs the suite above, then commits the
guard batch. What breaks first: this fix only restores **interactive-mode**
mechanical enforcement — under Kiro headless `--trust-all-tools`, preToolUse
hooks remain inert (13:20 finding), so the universal net is still the ADR-0005
git pre-commit backstop + prompt SAFETY RULES. If the suite is never re-run in a
working shell, a regression in these guards could land silently (CI runs the
same suite, so CI is the backstop for that — assuming CI's shell is healthy).
