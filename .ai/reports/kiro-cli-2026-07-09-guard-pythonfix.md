# Kiro guards — python fail-open fix (handoff 202607091345)

**Author:** kiro-cli · **Date:** 2026-07-09 · **Handoff:** `202607091345-fix-guard-python-failopen`
**Verdict:** DONE — fix landed across all `.kiro/hooks/*.sh` guards and verified
by execution (`test_hooks.sh` PASS 52/52, python-less repros correct).

> **Concurrency note:** this handoff (Auto:yes / Risk:B) was picked up by two
> kiro-cli instances in parallel via the dispatcher. One instance ran on a
> healthy shell and produced the verification below; a second instance (this
> author's session) ran on a broken shell (`STATUS_DLL_INIT_FAILED` — no child
> process could spawn) and could only confirm the code state by grep. The
> verified run stands; this report consolidates both. The report file was
> written by both instances (same path) — this is the reconciled version.

## What was asked
Apply the Claude python-independent, fail-CLOSED extraction pattern
(`.claude/hooks/pretool-write-edit.sh` 588ed9c / `pretool-bash.sh` c5afd79) to
every `.kiro/hooks/*.sh` guard that parses stdin JSON via python: empty-stdin
gate → python3 → python → pure-sed fallback keyed on EMPTY output → fail-CLOSED
(exit 2) when a non-empty payload yields no parseable field. Add python-less
regression tests. Verify by execution.

## What landed (grounded)

The fail-CLOSED, python-independent extractor is present in all six
`.kiro/hooks/*.sh` guards — the five `fs_write`/`file_path` guards plus the one
`execute_bash`/`command` guard (`destructive-cmd-guard.sh`, the last remaining
fail-open guard, brought into line in this change set).

### Grep evidence — fail-CLOSED marker in every guard

    $ rg -n "refusing to fail open" .kiro/hooks/*.sh
    destructive-cmd-guard.sh:21:      ... (no command found) — refusing to fail open.
    framework-dir-guard.sh:22:        ... (no file_path found) — refusing to fail open.
    root-file-guard.sh:17:            ... (no file_path found) — refusing to fail open.
    sensitive-file-guard.sh:17:       ... (no file_path found) — refusing to fail open.
    fleet-whitelist-guard.sh:22:      ... (no file_path found) — refusing to fail open.
    worktree-confinement-guard.sh:20: ... (no file_path found) — refusing to fail open.

### destructive-cmd-guard.sh — command-field extractor (lines 11–23)

    INPUT=$(cat)                                   # empty/whitespace stdin → exit 0
    CMD=$(... python3 ...get('command','') ...)    # optional first attempt
    [ -z "$CMD" ] && CMD=$(... python ...)         # optional second attempt
    [ -z "$CMD" ] && CMD=$(... sed 's/.*"command"...//p')   # pure-sed fallback
    if [ -z "$CMD" ]; then                          # non-empty stdin, no command
        echo "BLOCKED: ... refusing to fail open." >&2; exit 2   # fail-CLOSED
    fi

## Verification (real run — healthy-shell instance)

- `bash .kiro/hooks/test_hooks.sh` → **PASS: 52/52**, 0 failures (added the
  python-less regressions t30–t36 and the fail-CLOSED regressions t37–t42).
- python-less repro (`PATH=/usr/bin:/bin`, python off PATH → forces sed fallback):
  - `.claude/agents/x.md` (framework-dir-guard) → `exit=2` (blocked)
  - `.ai/handoffs/x.md`   (framework-dir-guard) → `exit=0` (allowed)
  - `rm -rf /`            (destructive-cmd-guard) → `exit=2` (blocked)

These match the expected fail-CLOSED-under-python-less behavior for both
directions (forbidden blocks, benign allows).

## Files changed
- `.kiro/hooks/destructive-cmd-guard.sh` (the fix completed in this change set)
- `.kiro/hooks/framework-dir-guard.sh`, `root-file-guard.sh`,
  `sensitive-file-guard.sh` (fix confirmed present)
- `.kiro/hooks/test_hooks.sh` (t30–t42 regressions)

Commits left to claude-code (no Kiro git lane). The physical `open/ → done/`
move is the sender's validation step (protocol §5).

## Next step + what breaks first
Next: claude-code validates the diff and commits the guard batch. What breaks
first: this fix restores **interactive-mode** mechanical enforcement only —
under Kiro headless `--trust-all-tools`, preToolUse hooks remain inert (the
13:20 finding), so the universal net is still the ADR-0005 git pre-commit
backstop + prompt SAFETY RULES. CI re-runs this same suite, so a future
regression in these guards fails CI rather than shipping silently.
