# Formalize test_hooks.sh standing suite
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-19 17:35

## Goal
Turn the ad-hoc pipe-tests used in Wave 1 and Wave 4 into a standing
`.kimi/hooks/test_hooks.sh` script. Intent: any future hook change (including
subtle stdin-draining regressions like the F-4 `read JSON` bug you just fixed)
is caught instantly by running one script, not recomposed from memory each
time. This is part of a 3-CLI parity effort — Kiro is building
`.kiro/hooks/test_hooks.sh` (handoff to-kiro/015) and Claude will add
`.claude/hooks/test_hooks.sh` in parallel.

## Current state

- `.kimi/hooks/` has 4 guard scripts fixed in Wave 4 (Option A — `read JSON`
  removed, python reads stdin directly): `root-guard.sh`, `framework-guard.sh`,
  `destructive-guard.sh`, `sensitive-guard.sh`.
- Wave 4 required 7 manual pipe-tests; all passed per your 2026-04-19 19:47
  activity-log entry.
- No standing script — next time someone edits a hook, they'd either skip
  the pipe-tests or recompose them from memory.

## Target state

New file: `.kimi/hooks/test_hooks.sh` — a bash script that pipes crafted JSON
payloads into each of the 4 hooks and asserts expected exit codes. Exit 0 on
all-pass, 1 on any fail.

Minimum coverage (mirrors what Kiro is building, so behavior parity is
testable across CLIs):

| Test | Hook | Payload | Expected exit |
|---|---|---|---|
| t1 | root-guard | fs_write to `evil.txt` | 2 |
| t2 | root-guard | fs_write to `.gitignore` | 0 |
| t3 | root-guard | fs_write to `src/main.rs` | 0 |
| t4 | framework-guard | fs_write to `.ai/handoffs/test.md` | 0 |
| t5 | framework-guard | fs_write to `.claude/agents/test.md` | 2 (Kimi cannot write Claude's dir) |
| t6 | framework-guard | fs_write to `.kiro/agents/test.json` | 2 |
| t7 | sensitive-guard | fs_write to `.env` | 2 |
| t8 | sensitive-guard | fs_write to `id_rsa` | 2 |
| t9 | sensitive-guard | fs_write to `id_ed25519` | 2 |
| t10 | sensitive-guard | fs_write to `server.key` | 2 |
| t11 | sensitive-guard | fs_write to `cert.pem` | 2 |
| t12 | destructive-guard | execute_bash with `rm -rf /` | 2 |
| t13 | destructive-guard | execute_bash with `DROP DATABASE foo` | 2 |
| t14 | destructive-guard | execute_bash with `Drop Database foo` (mixed-case — relies on your lowercase normalization) | 2 |
| t15 | destructive-guard | execute_bash with `git status` | 0 |

Include a **stdin-drain regression test**:
| t16 | any guard | pipe empty stdin; hook must NOT hang and should exit 0 (fail-open on unparseable input, same as current behavior) |

This is the test that, if you'd had it in place, would have caught the F-4
`read JSON` bug the day it was introduced: the hook's exit code was 0 on a
malformed/drained stdin and you assumed that meant "payload allowed" when it
actually meant "hook couldn't parse".

Script layout:
```bash
#!/bin/bash
# test_hooks.sh — regression suite for .kimi/hooks/*
# Exits 0 if all pass, 1 if any fail.

pass=0
fail=0
fails=()

run_test() {
  local name="$1" hook="$2" payload="$3" expected="$4"
  local actual
  actual=$(echo "$payload" | bash "$hook" > /dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$name (expected $expected, got $actual)")
  fi
}

# 16 run_test calls here ...

total=$((pass+fail))
if [ $fail -eq 0 ]; then
  echo "PASS: $pass/$total"
  exit 0
else
  echo "FAIL: $fail/$total"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
```

## Context (reference only, not binding)

Kiro's parallel handoff (to-kiro/015) asks for a 13-test matrix. Kimi's matrix
is slightly larger (16) because Kimi's `sensitive-guard.sh` has broader
pattern coverage and because the stdin-drain regression test is particularly
relevant for Kimi given F-4 history.

Script location: `.kimi/hooks/test_hooks.sh` at the hook-dir level, not nested.
Mirror the pattern Kiro will use.

## Steps

1. Create `.kimi/hooks/test_hooks.sh` per the layout above.
2. `chmod +x .kimi/hooks/test_hooks.sh`.
3. Run it once. Expect `PASS: 16/16`. If any fail, fix the script or identify
   a real hook gap (and surface it — don't silently adjust the expected exit).
4. Update `.kimi/hooks/README.md` to document the script (2-line addition —
   "run `bash test_hooks.sh` after any hook edit").

## Verification
- (a) `.kimi/hooks/test_hooks.sh` exists, is executable.
- (b) Running it prints `PASS: 16/16` and exits 0.
- (c) `.kimi/hooks/README.md` references the test script.
- (d) Payload-for-empty-stdin test (t16) behaves as expected — hook does not
  hang waiting for input.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Formalized test_hooks.sh standing suite (per handoff 029)
    - Files: .kimi/hooks/test_hooks.sh (new), .kimi/hooks/README.md (edit)
    - Decisions: <anything non-obvious>

## Report back with
- (a) Final PASS/FAIL line from the script.
- (b) Exact path(s) touched.
- (c) Any test that's expected to fail AND why — if you discover a real hook
  gap while writing the suite, flag it rather than patching silently.

## When complete
Sender (claude-code) validates by reading the script + running it in a fresh
shell. On success, move to `.ai/handoffs/to-kimi/done/`. On failure, leave
in `open/`, Status → `BLOCKED`, append `## Blocker`.
