# 4AI-panes comprehensive integration test (positive + negative)

- **Author:** claude-code
- **Date:** 2026-07-11
- **Scope:** End-to-end integration test of the self-driving pane system
  (`tools/4ai-panes/`): pane-runner loop, supervisor crash/respawn/cap, Telegram
  notify fail-open, unit suites, multi-select WT string, C3 reconcile + stranded
  badge.
- **Process safety:** Every spawned process was launched with a captured handle
  (`Start-Process -PassThru $p`) and stopped ONLY by its exact PID
  (`Stop-Process -Id $p.Id`). No name/regex/wildcard kill was used anywhere. No
  pre-existing process (owner's live panes, `~/.rwn-auto/`) was touched. All test
  data lived in fresh temp dirs and was cleaned up.

## Result summary

| Test | Kind | What I did | Observed result | Verdict |
|---|---|---|---|---|
| **A** | positive, integrated | Dot-sourced `pane-runner.ps1 -NoRun`, stubbed `$script:InvokeCli` to copy the claim mid-flight + move the throwaway handoff open→done + return 0, wrapped `Send-FleetNotification` to record the real API result, ran `Start-PaneRunner -Cli claude -MaxContinues 2 -PollSeconds 1` in a captured-PID console process against a temp project with one Auto:yes/OPEN/Risk:B handoff. Polled ≤30s for done/, then `Stop-Process -Id $p.Id`. | Claim `.ai/.claim-claude.json` written with `host` field + no BOM; loop-fired Telegram **picked** `ok:true` (msg 731) and **done** `ok:true` (msg 732); handoff reached done/ (open emptied). | **PASS** |
| **B** | negative, integrated | Ran `test-pane-supervisor.ps1` (stub runner exits 1→respawn w/ backoff→cap→give-up; exit 0→no respawn; healthy-run counter reset; backoff schedule). | `==== pane-supervisor tests: 9 passed, 0 failed ====` | **PASS** |
| **C** | negative | Dot-sourced `notify.ps1`. C1: bad token `0:bad` + valid chat_id → `Send-FleetNotification`. C2: cleared env + redirected `$HOME` to an empty dir so `~/.rwn-auto/notify.json` isn't found. Env changes isolated in a child process. | C1: did NOT throw, returned `$null` (fail-open). C2: `Resolve-FleetNotifyConfig` → `$null`, send did NOT throw, returned `$null` (silent no-op). | **PASS** |
| **D** | positive + negative | Ran `test-pane-runner.ps1` (37 asserts: claim host/staleness, quarantine age-out, invoke-core stderr-no-crash, reconcile of exit-code contract, per-handoff claim race). | `==== pane-runner tests: 37 passed, 0 failed ====` | **PASS** |
| **E** | positive, no launch | Extracted `Build-FleetTabCmd` from `Selector.ps1` via AST (menu never runs), reproduced 6pane/all-available state, built the multi-select string for 2 fake dirs and the single string for 1. Counted `new-tab`; never executed `wt`. | Multi = **2** `new-tab` groups (10 `split-pane`), single = **1** `new-tab`. | **PASS** |
| **F** | positive | F1: ran `.ai/tools/reconcile-done-handoffs.sh` against a temp tree holding a `Status: DONE` handoff still in `to-kimi/open/`. F2: extracted `Get-ProjectBadges` via AST, temp project with a `to-opencode/open` handoff and OpenCode marked unavailable. | F1: moved to `done/`, exit 0, open emptied. F2: badge `[v OK] [H:1 stranded:opencode]`; control (OpenCode available) `[v OK] [H:1]` (no stranded). | **PASS** |

## Key evidence

### A — claim (host field, no BOM), Telegram picked+done from the loop
```
BOM_PRESENT: False
RAW: {"project":"zztest-pane-int-a5d2fec4","cli":"claude","pid":81008,"host":"E-NMP","ts":"2026-07-11T03:40:48Z"}
host field: E-NMP

notify-capture (loop-fired, real Telegram API result):
{"kind":"picked","ok":true,"message_id":731,"owner":"claude-auto","handoff":"202607111200-zztestmarker-a5d2fec4",...}
{"kind":"done","ok":true,"message_id":732,"owner":"claude-auto","handoff":"202607111200-zztestmarker-a5d2fec4",...}

driver.log (loop trace):
| pane-runner  project=zztest-pane-int-a5d2fec4  cli=claude
NOTIFY kind=picked ok=True mid=731
== RUN  [claude] .ai\handoffs\to-claude\open\202607111200-zztestmarker-a5d2fec4.md ==
STUB InvokeCli fired for claude
  claim copied
  moved 202607111200-zztestmarker-a5d2fec4.md -> done/
== DONE [claude] ... (moved to done/, 0 continue(s)) ==
NOTIFY kind=done ok=True mid=732
```
Two real `[test]` Telegram messages (msg 731 picked, 732 done) were delivered to
the owner's topic — expected and pre-approved for this run.

### B — supervisor
```
PASS  A: 1,1,0 -> supervisor spawns the runner 3 times
PASS  B: always-crash, cap 3 -> exactly 3 spawns then give up
PASS  B: cap reached -> loud GIVING UP message
PASS  C: a healthy run mid-loop resets the crash counter (5 spawns, not 3)
PASS  D: backoff doubles then caps (0.02,0.04,0.08,0.1,0.1)
==== pane-supervisor tests: 9 passed, 0 failed ====
```

### C — notify fail-open / unconfigured
```
C1_THREW: False        (bad token, chat_id present -> no throw)
C1_RETURN_NULL: True
C2_RESOLVE_NULL: True   (env cleared + HOME redirected)
C2_THREW: False
C2_RETURN_NULL: True
```

### D — pane-runner unit suite
```
PASS  p: real InvokeCli (stderr+nonzero) does NOT throw under EAP=Stop
PASS  p: real InvokeCli returns the child exit code (3)
PASS  q: foreign-host claim past window -> Test-ClaimBlocks false (reclaim)
PASS  r: same-host live-pid fresh claim -> Test-ClaimBlocks true (block)
==== pane-runner tests: 37 passed, 0 failed ====
```

### E — multi-select WT string (2-tab), never executed
```
MULTI new-tab count: 2   (expect 2)
SINGLE new-tab count: 1   (expect 1)
MULTI split-pane count: 10
```
Multi string shape (truncated): `-w rwn4ai new-tab -d "…alpha" powershell … "claude …" ; split-pane -H … run-pane-supervised.ps1 -Cli claude … ; … ; new-tab -d "…beta" powershell … "claude …" ; split-pane -H … -Cli claude … ; …`

### F — reconcile + stranded badge
```
reconcile-done: moved …/to-kimi/open/202607111201-…-recon.md -> done/ (Status:DONE was left in open/)   exit=0
BADGE: [v OK] [H:1 stranded:opencode]
CONTROL BADGE (opencode available): [v OK] [H:1]
```

## Finding (mechanism, not a product bug)

`Start-PaneRunner`'s loop calls `[Console]::KeyAvailable` at the top of every
iteration (the p/q/Ctrl-C escape hatch). In a context with **no interactive
console** (verified: PowerShell `Start-Job`, and any run whose console **input**
is redirected), that call throws `InvalidOperationException`, which the loop's
generic recovery `catch` swallows — so it never reaches the handoff poll and the
pane silently idles/error-spams instead of working.

- **Impact in production: none.** Real panes launch as
  `powershell -NoExit -File pane-runner.ps1` inside a Windows Terminal pane, which
  always has a real console, so `KeyAvailable` works. This is why the live fleet
  runs fine and why the unit suites (which drive helpers, not the loop) pass.
- **Impact on testing:** the loop is not drivable under `Start-Job`. This test
  therefore ran the loop in a captured-PID `Start-Process` console (allowed by the
  safety rules) rather than `Start-Job` — the same faithful integrated path, with
  a real console. Flagged so future harnesses don't try `Start-Job` and conclude
  the loop is broken.
- Not filing a code change: guarding `KeyAvailable` (e.g. skip when
  `[Console]::IsInputRedirected`) would be a small hardening, but it is out of
  scope for a test report and the production path is unaffected. Left as an
  observation for the owner.

## Harness note (self-inflicted, fixed)

First attempt dot-sourced `pane-runner.ps1` and named a driver param `$ProjectDir`;
pane-runner's own `param()` block ran in that scope and clobbered it with its
default `(Get-Location).Path`, so the loop polled the current worktree instead of
the temp project. Caught immediately (banner showed `project=agent-…worktree`),
verified no real mutation occurred (worktree `to-claude/open` had only `.gitkeep`;
no claim file created; clean git status), and fixed by renaming the driver params
so the dot-source cannot overwrite them. Re-run passed cleanly.

## Verdict on integrated readiness

The self-driving pane system is **integration-ready**. The full IDLE→CLAIM→RUN→
DECIDE loop works end-to-end against a stubbed CLI: it writes a crash-recoverable
per-project claim (with `host`, BOM-less), fires fail-open Telegram picked/done
notifications that reach the real API (`ok:true`), and releases on the durable
done-signal (handoff moved to done/). The supervisor's crash→respawn→backoff→cap
and the notify fail-open/unconfigured paths behave exactly as specified. Unit
coverage is green (37 + 9). The multi-select launcher composes a correct N-tab
`wt` batch, and the C3 self-heal (reconcile) + stranded-recipient badge both work.

The only real observation is the `KeyAvailable`-needs-a-console coupling, which
does not affect the production WT-pane path. Live WT render remains the owner's
acceptance test.

## Cleanup

All temp dirs, throwaway handoffs, and capture files removed.
`grep -rl zztestmarker-a5d2fec4` returns nothing in the repo tree or temp. No
stray claim/quarantine sidecars; worktree git status clean.
