# Fix Kimi guards' python fail-open (the reason live .kiro/ write wasn't blocked)
Status: DONE — completed via interactive session, kimi-cli 17:16
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 17:10
Auto: no
Risk: B

<!-- Auto: no — this must be diagnosed+fixed+verified in an INTERACTIVE Kimi
     pane (hooks don't fire under headless `kimi -p`, so headless dispatch
     can't verify the live block). Owner relays the prompt into the pane. -->


## Why (root cause found — owner interactive test 2026-07-09)
The owner's live interactive pane test showed a `.kiro/` write SUCCEEDED (not
blocked) even though your `[[hooks]]` config is valid and 48/48 unit tests
pass. Root cause: **all `.kimi/hooks/*.sh` guards still have the python-stub
fail-open bug** — the same one already fixed in Claude (`.claude/hooks/*`,
commit 588ed9c) and Kiro (`.kiro/hooks/*`, commit 9330e0d) today, but never
applied to Kimi. Grep proof:
- `framework-guard.sh:7-11`, `sensitive-guard.sh:5-9`, `root-guard.sh:6-11`,
  `destructive-guard.sh:5-9`, `worktree-fleet-guard.sh:7-12` all do
  `python3 -c ... || python ... || echo ""` then `[ -z "$X" ] && exit 0`.
On Windows, `python3` resolves to the Store alias stub (empty stdout, exit 0),
so the `|| python` fallback never fires (it keys on exit status, not empty
output), the field comes back empty, and the guard exits 0 = FAIL-OPEN. Kimi's
own runtime also treats hook crashes as "allow", compounding it. So `.env` was
blocked only by Kimi's NATIVE secret guard, not your `sensitive-guard.sh`.

## The fix (mirror the proven Claude pattern EXACTLY)
Reference: `.claude/hooks/pretool-write-edit.sh` (commit 588ed9c). In EACH of
the 5 guards (framework-guard, sensitive-guard, root-guard, destructive-guard,
worktree-fleet-guard):
1. Empty-stdin gate FIRST: whitespace-stripped empty stdin → exit 0 (allow).
2. Extraction chained on EMPTY OUTPUT (not exit status): python3 → python →
   pure-`sed` fallback (`sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'`;
   also try `"path"` since your payloads use `path` — mirror the existing
   `file_path or path` logic; destructive-guard uses `"command"`).
3. FAIL-CLOSED: non-empty stdin but no field parsed → exit 2 with a clear
   "could not parse tool input — refusing to fail open" message.
   (worktree-fleet-guard already documents fail-closed for its registry step —
   apply the same to its path extraction.)
4. NO python dependency for the decision path.

## Confirm the hook actually FIRES (definitive)
There is a second possibility: the hook doesn't fire at all. To distinguish,
TEMPORARILY add at the very top of `framework-guard.sh` (after reading stdin):
`echo "FIRED $(date +%s) path=[$FILE_PATH]" >> /tmp/kimi-hook-fire.log` — then
have the OWNER re-run the interactive probe (write `.kiro/x`). If the log line
appears → hook fires + the fail-closed fix now BLOCKS it (success). If not →
hook isn't firing (registration/beta-enable issue) — report that instead.
REMOVE the debug line before finishing.

## Verify
- `bash .kimi/hooks/test_hooks.sh` → paste count (add python-less regression
  cases under `PATH="/usr/bin:/bin"` asserting `.kiro/` → exit 2, benign → 0).
- Python-less repro per guard: `echo '{"tool_input":{"path":".kiro/x"}}' |
  PATH="/usr/bin:/bin" bash .kimi/hooks/framework-guard.sh; echo $?` → 2.

## Report back with
Fixed files, test count, python-less repro exit codes, and the debug-fire
result (did the hook fire?). Set Status DONE + move to `to-kimi/done/`; prepend
activity entry. Commit `.kimi/**` yourself if you have git access, else leave
for claude-code (`git -c user.name=kimi-cli`). Report:
`.ai/reports/kimi-cli-2026-07-09-guard-pythonfix.md`.
NOTE: after this lands, the OWNER re-runs the interactive `.env`/`.kiro` probe
to confirm the live block — that is the final gate.
