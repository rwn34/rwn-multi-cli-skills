# Handoff: fix `rm -rf /` false-positive in destructive-cmd guard

**From:** claude-code
**To:** kimi
**Date:** 2026-04-21
**Priority:** medium (safety hook correctness — not a security regression, but blocks legitimate commands)

## Background

Consistency audit turned up a false-positive in all three CLIs' destructive-cmd
guards. The guards block legitimate commands like `rm -rf /tmp/foo` because
their patterns match `rm -rf /` as a substring without boundary checking.

Claude's hook has been fixed (see commit on `master`) and test coverage added.
Kiro has a parallel handoff. You need to apply the same fix to Kimi's guard
and add equivalent test coverage.

## The bug

`.kimi/hooks/destructive-guard.sh` lines 15–16:

```bash
case "$CMD_LOWER" in
    *"rm -rf /"*|*"rm -rf /*"*)
        echo "BLOCKED: rm -rf / or rm -rf /* is extremely dangerous and not allowed." >&2
        exit 2
        ;;
```

The pattern `*"rm -rf /"*` matches any command containing that substring —
including `rm -rf /tmp/foo` (substring match, no word boundary). The `~`, `*`,
`.` cases on lines 20–31 have the same issue.

**Intent:** block `rm -rf /` where `/` is the *target*, not `/tmp/...`.

## Suggested fix

Replace the five `case` arms (lines 15–32) with a single bash-regex check that
requires the target to be followed by a shell separator (space, `;`, `&`, `|`)
or end-of-string. This is the approach Claude took:

```bash
# Normalize whitespace (like Claude's hook does)
NORM=$(echo "$CMD_LOWER" | tr -s ' \t' '  ')

rm_flags='(-[rf]+|-r[[:space:]]+-f|-f[[:space:]]+-r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
rm_target='(/|~|\*|\.)'
rm_tail='([[:space:]]|[;|&]|$)'
if [[ " $NORM " =~ [[:space:]]rm[[:space:]]+${rm_flags}[[:space:]]+${rm_target}${rm_tail} ]]; then
    echo "BLOCKED: rm -rf with a dangerous target (/, ~, *, .) is not allowed." >&2
    exit 2
fi
```

(Note: flags are lowercase-only here since Kimi already lowercased the command
on line 12. Claude's version keeps `[rRfF]` because it doesn't lowercase.)

If you prefer to keep the `case` style, the expanded pattern list would be
4× longer (per-target × trailing-delimiter combinations). Regex is cleaner.
Git Bash on Windows supports `[[ =~ ]]` — confirmed working in Claude's test run.

## Test cases to add

If Kimi has a test harness for hooks, add these four. If not, at minimum
smoke-test manually:

| # | Payload | Expected exit |
|---|---|---|
| 1 | `{"tool_input":{"command":"rm -rf /"}}` | 2 (still blocked) |
| 2 | `{"tool_input":{"command":"rm -rf /tmp/foo"}}` | 0 (NEW — previously falsely blocked) |
| 3 | `{"tool_input":{"command":"rm -rf / "}}` (trailing space) | 2 (blocked) |
| 4 | `{"tool_input":{"command":"rm -rf /;echo ok"}}` | 2 (blocked via `;` separator boundary) |

Bonus verifications that should already work and shouldn't regress:

- `rm -rf /usr` → 0 (legitimate absolute-path target)
- `rm -rf ~/foo` → 0 (legitimate home-relative target)
- `rm -rf *.log` → 0 (legitimate glob)
- `rm -rf ./build` → 0 (legitimate dot-prefixed target)

## Deliverables

1. Edit `.kimi/hooks/destructive-guard.sh` with the boundary-aware matcher.
2. Confirm the four test cases above behave as expected (manually or via harness).
3. Log one activity entry to `.ai/activity/log.md`.
4. Move this handoff file to `.ai/handoffs/to-kimi/done/` when complete.

## Reference

- Claude's fix: see `.claude/hooks/pretool-bash.sh` (boundary regex + comments).
- Claude's tests: see `.claude/hooks/test_hooks.sh` tests t18–t21.
