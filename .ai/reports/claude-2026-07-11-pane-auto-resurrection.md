# Pane Auto-Resurrection — Design Report (2026-07-11)

Author: claude-code. Scope: a read-only investigation of the 4AI-panes
`pane-runner.ps1` self-heal boundary + a concrete design for auto-resurrecting a
fully-exited runner without the owner. Sources: `tools/4ai-panes/pane-runner.ps1`,
`Selector.ps1`, `restart-pane.ps1`, `test-pane-runner.ps1`, ADR-0008/0009, and
the 2026-07-11 framework/panes gap analysis (item B6: "runner crashed → handoff
sits with no actor and no alert"). Status: design only — nothing modified.

---

## 0. One-paragraph summary

The per-iteration try/catch added to `Start-PaneRunner`'s `while($true)` loop
makes the runner survive almost any in-iteration fault (bad handoff, CLI error,
stderr storm) — it logs `ALERT ... recovering, still polling` and keeps going.
Only four things still take the runner fully offline: (a) Ctrl-C / intentional
stop, (b) the two rethrown cancel exceptions (`PipelineStopped` /
`OperationCanceled`) or any exception that escapes the inner try, (c) a
PowerShell parse/bind/load error (the try never even starts), and (d) the
process being killed. Today none of these respawn — the `-NoExit` on the launch
keeps the pane shell alive at a dead prompt, and recovery is the manual
`restart-pane.ps1`. The design below inserts a thin supervisor at the Selector
launch layer (`run-pane-supervised.ps1`) that re-launches the runner as an
isolated child, distinguishes intentional stop (exit 0) from crash (non-zero)
via a new exit-code contract in the runner's `finally`, and respawns only on
crash with exponential backoff + a rolling-window cap before giving up loudly.

---

## 1. Failure taxonomy — what still causes a FULL exit vs self-heal

The self-heal boundary is the inner `try { ... } catch {...}` inside the loop
(`pane-runner.ps1` ~L537-L618). The generic `catch` (L603) swallows and
re-polls; the two typed catches (L594, L599) rethrow; the outer `finally` (L620)
releases the claim and prints `pane-runner stopped`. Enumerated:

| # | Cause | Full exit? | Path | Respawn-worthy? |
|---|-------|-----------|------|-----------------|
| (a) | Ctrl-C / intentional stop | Yes | Console raises `PipelineStoppedException` → typed catch L594 → `throw` → outer `finally` → process ends | No — the owner meant to stop it |
| (b1) | Rethrown cancel not from Ctrl-C (rare) | Yes | Same as (a) | Ambiguous — treated as intentional (indistinguishable from Ctrl-C at runtime) |
| (b2) | Exception that escapes the inner try — thrown from inside the recovery `catch` itself (its trailing `Start-Sleep`/`Write-Host`) or from the `finally`'s `Remove-Claim` | Yes | Escapes loop → outer `finally` → ends | Yes — unexpected |
| (c) | Parse / bind / load error — syntax error, `ValidateSet` rejects `-Cli`, `Get-DefaultOwner` throws (L446), a load-time throw before the loop | Yes | `Start-PaneRunner` (and its try/finally) never runs → powershell.exe exits non-zero naturally | Yes, but re-crashes identically → the cap must catch it |
| (d) | Process killed — `Stop-Process`, `taskkill`, WT pane closed, OS/OOM | Yes | No `finally`, hard termination; claim lingers until staleness ages it out | Yes (if the pane/console still exists) |
| — | Any other in-iteration error (bad handoff, CLI non-zero, native stderr under EAP=Stop, throwing handoff) | No — self-heals | Generic catch L603: logs ALERT, counts a quarantine attempt, releases claim, re-polls | n/a |
| — | `'p'` pause → interactive CLI → exit CLI | No | Loop `continue`s (L546) — pause/resume, never an exit | n/a |

Key consequence for the design: the runner almost never crash-exits on its own
(that is the entire point of the per-iteration self-heal). The realistic
crash-exit population is (c) parse/bind errors and (d) kills — plus the rare
(b2). Intentional stop (a) is the only wanted exit, and at runtime it is
indistinguishable from (b1). Therefore the supervisor cannot infer intent from
the exception type — the runner must declare intent via its exit code.

Note (caveat, not new): the runner has no clean quit other than Ctrl-C. There is
no `'q'` key; `'p'` only pauses. So today "intentional stop" == Ctrl-C. A
deliberate pause-then-stop is: press `p`, exit the CLI (loop resumes), then
Ctrl-C.

---

## 2. Exit-code contract (the change that makes intent legible)

Today `pane-runner.ps1` never sets an explicit exit code. We define a contract
the supervisor keys off:

| Exit code | Meaning | Supervisor action |
|-----------|---------|-------------------|
| 0 | Intentional / clean stop — Ctrl-C (`PipelineStopped`/`OperationCanceled` caught) or a future `'q'` quit key | Do not respawn. Fall through to a live prompt. |
| non-zero (proposal: 1) | Crash / escaped exception / parse-bind error / killed | Respawn subject to backoff + cap. |

### Mechanics (PowerShell specifics that make this work)

- The runner is launched as `powershell -File pane-runner.ps1 ...`, so
  powershell.exe's process exit code = whatever the script `exit`s with, or 1 if
  a terminating error escapes, or 0 on clean fall-through.
- An `exit N` inside the `finally` terminates the process with code N and
  suppresses the propagating terminating error — this is how we force the code
  even though Ctrl-C arrives as a rethrown exception.
- A parse/bind error (c) means the `finally` never runs → powershell.exe exits
  non-zero on its own → correctly read as a crash (and the cap stops the hot-loop).

### Required pane-runner.ps1 edits (plan, not code)

1. Declare an intent flag near the top of `Start-PaneRunner` (before the outer
   `try`): `$stopIntent = $false`.
2. In the two rethrow catches (L594 `PipelineStoppedException`, L599
   `OperationCanceledException`): set `$stopIntent = $true` before `throw`.
3. (Optional but recommended) Add a `'q'` branch to the `[Console]::KeyAvailable`
   block (beside `'p'`, ~L539): set `$stopIntent = $true` and break/return out of
   the loop — a clean intentional stop that is not a Ctrl-C.
4. In the outer `finally` (L620-L624), after `Remove-Claim` and the
   `pane-runner stopped` message, add: `if ($stopIntent) { exit 0 } else { exit 1 }`.
   Define the codes as named constants at file top (`$script:ExitIntentional = 0`,
   `$script:ExitCrash = 1`).
5. Guard: the `exit` path lives inside `Start-PaneRunner`, which only runs when
   `-not $NoRun` (L627). Tests dot-source with `-NoRun` and never call the loop,
   so they never hit `exit` — do not move the `exit` to file scope.
6. Document the exit-code contract in the header block so the Selector/supervisor
   coupling is discoverable.

Testability note: the loop itself is not unit-testable (infinite). Extract the
trivial decision into a pure helper `Get-StopExitCode([bool]$Intent)` → 0 or 1
and unit-test it in `test-pane-runner.ps1` (add asserts u/v). End-to-end code
behavior (Ctrl-C → 0, thrown → 1) is covered by the supervisor integration test
in section 7.

---

## 3. Supervisor design — run-pane-supervised.ps1

Where: a dedicated script the Selector launches instead of `pane-runner.ps1` for
each self-driving pane. Chosen over an inline bash/pwsh one-liner because (i) it
is testable, (ii) it keeps the Selector launch strings readable, and (iii) it
lives beside the runner and shares `$PSScriptRoot`.

Isolation model — run the runner as a CHILD PROCESS, not dot-sourced. The
supervisor does `& powershell -NoProfile -File pane-runner.ps1 ...` and reads
`$LASTEXITCODE`. Child-process isolation is deliberate: a parse/bind error (c)
crashes only the child (non-zero code) instead of taking the supervisor down too
— exactly the fault a same-process dot-source could not survive. It also makes
kill (d) legible as a non-zero child exit.

### Parameters

    -Cli               claude|kimi|kiro|opencode   (passed through)
    -ProjectDir        (passed through)
    -Owner             (passed through, default '')
    -MaxContinues 5    (passed through)
    -PollSeconds 10    (passed through)
    -MaxRetries 5             # crashes allowed within the rolling window before giving up
    -RetryWindowMinutes 10    # rolling window length
    -BackoffBaseSeconds 2     # first backoff
    -BackoffMaxSeconds 60     # backoff ceiling
    -HealthyRunSeconds 120    # a run lasting >= this is "healthy" -> resets the crash counter

### Control flow

    $env:RWN_PANE_CLI = $Cli          # so restart-pane.ps1 still works from this pane
    $crashes = <list of recent crash timestamps>
    try {
      while ($true) {
        $start = Get-Date
        & powershell -NoProfile -ExecutionPolicy Bypass -File <pane-runner.ps1> `
            -Cli $Cli -ProjectDir $ProjectDir -Owner $Owner `
            -MaxContinues $MaxContinues -PollSeconds $PollSeconds
        $code = $LASTEXITCODE
        $ranSeconds = ((Get-Date) - $start).TotalSeconds

        if ($code -eq 0) {            # intentional stop (Ctrl-C / q)
          Write-Host "supervisor: runner exited cleanly - not respawning"
          break
        }
        # --- crash path ---
        prune $crashes older than $RetryWindowMinutes
        if ($ranSeconds -ge $HealthyRunSeconds) { $crashes.Clear() }  # long run = transient blip
        $crashes.Add(Get-Date)
        if ($crashes.Count -ge $MaxRetries) {
          Write-Host "supervisor: runner crashed N times - GIVING UP. run restart-pane.ps1." -Red
          break
        }
        $delay = min($BackoffMaxSeconds, $BackoffBaseSeconds * 2^($crashes.Count-1))
        Write-Host "supervisor: runner crashed (code $code) - respawn in ${delay}s" -Yellow
        Start-Sleep -Seconds $delay
      }
    }
    catch [System.Management.Automation.PipelineStoppedException] { break }  # Ctrl-C during backoff = stop
    # fall off the end -> pane drops to a live prompt (supervisor launched -NoExit)

Rolling window (not "consecutive") is intentional: a runner that survives
`HealthyRunSeconds` between crashes resets the counter, so a genuinely-transient
blip never permanently kills the pane, while a fast crash-loop (parse error,
poison environment) trips the cap within seconds and stops.

---

## 4. Backoff + cap parameters (recommended defaults)

- Backoff: exponential, 2s, 4s, 8s, 16s, 32s, capped at 60s (`BackoffMaxSeconds`).
  Base 2s so a legitimately transient crash recovers fast; the cap prevents
  unbounded waits.
- Cap: 5 crashes within a 10-minute rolling window (`MaxRetries=5`,
  `RetryWindowMinutes=10`) → give up loudly with a red message naming
  `restart-pane.ps1`. This bounds a parse-error hot-loop to ~5 attempts over
  <1 min of wall time.
- Healthy reset: a single run lasting >=120s (`HealthyRunSeconds`) clears the
  counter. The runner normally runs for hours; any crash after a long healthy run
  is treated as fresh, not accumulated toward the cap.
- Loud give-up is the safety valve the gap analysis (B6) asked for: instead of a
  silently-dead poller, the pane shows a persistent red banner and the exact
  recovery command.

---

## 5. Interaction with -NoExit

Change the layering, don't remove `-NoExit`:

- Selector launches the SUPERVISOR with `-NoExit` (as it launches the runner
  today). After the supervisor breaks — clean stop or cap exhausted — control
  falls off the end and `-NoExit` keeps the pane at a live prompt, preserving
  today's post-stop behavior (owner can inspect, run `restart-pane.ps1`, etc.).
- The supervisor launches the RUNNER child WITHOUT `-NoExit`, so the child
  returns control (and its exit code) to the supervisor on every exit. `-NoExit`
  on the child would hang the supervisor forever at the child's prompt.
- Net: the pane stays alive via the supervisor (auto-respawn while crashing), and
  only drops to a bare prompt after an intentional stop or after the retry cap —
  a strict improvement over "dead prompt on first exit."

Verification item (could not run — read-only): confirm on this machine that
`exit 0` in the runner's `finally` under `powershell -File` returns 0 to the
parent's `$LASTEXITCODE` (expected), and that `-NoExit` on the supervisor keeps
the pane open after the supervisor script ends without an explicit `exit`. An
explicit `exit` in the supervisor would override `-NoExit`, so the supervisor
must NOT call `exit` on its terminal paths — it should break/return and idle at
the prompt.

---

## 6. Interaction with the claim-lock (why respawn is safe)

A respawned runner re-acquires the per-project claim with no special handling:

- Clean/crash exit with `finally` reached: `Remove-Claim` already ran
  (pane-runner.ps1 L622), so the claim is gone before respawn.
- Hard kill (d): the claim file lingers, but `Test-ClaimBlocks` (L161-L185)
  returns `$false` for a same-host dead pid (immediate reclaim via
  `$script:TestPidAlive`) and otherwise ages the claim out after
  `$script:ProjectClaimStaleMinutes = 15`. The respawned child is same-host with
  a fresh pid → it reclaims immediately.
- The per-handoff claim sidecars behave identically (`Test-HandoffClaimed` L253,
  15-min staleness + dead-pid reclaim); a mid-run kill leaves at most one stale
  sidecar that ages out or is reclaimed on the next poll.

So the C2 staleness hardening already in place is exactly what makes
auto-resurrection race-free — no new locking is needed. Sidecars are already
gitignored (`.ai/.claim-*.json`, `.ai/handoffs/.claims/*`), so no respawn-era pid
leaks into VCS.

---

## 7. Concrete change plan

### New file — tools/4ai-panes/run-pane-supervised.ps1
Implements section 3 (child-process respawn loop, backoff, cap, healthy-reset,
Ctrl-C-clean-break, -NoExit-friendly fall-through). Mirrors `restart-pane.ps1`
param style; resolves the runner via `Join-Path $PSScriptRoot 'pane-runner.ps1'`;
sets `$env:RWN_PANE_CLI` (so `restart-pane.ps1` still infers the CLI in this pane).

### tools/4ai-panes/pane-runner.ps1
- Add `$stopIntent = $false` before the outer `try` in `Start-PaneRunner`.
- Set `$stopIntent = $true` before `throw` in the `PipelineStoppedException`
  (L594) and `OperationCanceledException` (L599) catches.
- (Optional) `'q'` key handler in the KeyAvailable block → `$stopIntent=$true` + break.
- Outer `finally`: append `if ($stopIntent) { exit 0 } else { exit 1 }`.
- Header comment: document the 0=intentional / 1=crash contract.
- Extract `Get-StopExitCode([bool]$Intent)` for unit testing.

### tools/4ai-panes/Selector.ps1
- Add `$paneSupervisor = Join-Path $scriptDir 'run-pane-supervised.ps1'`.
- Replace the runner launch target in all four places that spawn a runner,
  swapping `-File "$paneRunner"` → `-File "$paneSupervisor"` (same -Cli/-ProjectDir
  args, keeping the pane's -NoExit):
  - 6-pane: `$runner0` (L1031) and the loop `$runner` (L1039);
  - 5-pane: `$runner0` (L1080) and the loop `$runner` (L1088);
  - 4-grid: `Get-PaneLaunch` (L1109) and the first-pane `& $paneRunner` (L1142) —
    the first-pane call currently runs the runner in-process; route it through the
    supervisor too, or accept that the first pane is unsupervised.
- Extend the `$layoutSupported` gate (L987) to also require
  `(Test-Path $paneSupervisor)`; if the supervisor script is missing, fall back to
  launching `pane-runner.ps1` directly (graceful degrade — never a broken pane).
  Same fallback in `Get-PaneLaunch`.

### tools/4ai-panes/restart-pane.ps1 (optional)
- Prefer `run-pane-supervised.ps1` when present (so a manual restart is also
  auto-resurrecting), falling back to `pane-runner.ps1`. Add a `-Supervised`
  switch (default true). Low priority — manual restart already works.

### Tests
- test-pane-runner.ps1: add asserts (u) `Get-StopExitCode $true -eq 0`,
  (v) `Get-StopExitCode $false -eq 1`.
- New test-pane-supervisor.ps1: point the supervisor at a stub runner script that
  `exit`s a chosen code, and assert:
  - stub `exit 0` → supervisor loops once, does not respawn;
  - stub `exit 1` → supervisor respawns until the cap, then gives up;
  - a stub that sleeps > HealthyRunSeconds then `exit 1` → counter resets;
  - backoff delays follow the exponential schedule (use sub-second params to keep
    the test fast).
  Use a supervisor param (e.g. -RunnerPath) or an env override so the test injects
  the stub without launching a real CLI.

---

## 8. Caveats & open risks

- Ctrl-C during an active child CLI (RUN state) may not yield exit 0. When the
  runner is mid-`Invoke-Expression` of a headless CLI, a console Ctrl-C hits the
  whole process group; it typically kills the grandchild CLI and returns control
  to the loop (self-heal, no exit) rather than raising `PipelineStopped` in the
  runner. So a reliable exit-0 intentional stop is cleanest while IDLE-polling.
  Pre-existing behavior, not introduced here, but it means a Ctrl-C landed during
  a run could occasionally read as a crash and trigger one respawn. The `'q'` quit
  key (fires only from the KeyAvailable check between iterations) is the
  deterministic intentional-stop path if this matters.
- The supervisor itself is not resurrected. If the supervisor process or the WT
  pane is killed, nothing brings it back — auto-resurrection covers the runner,
  not the pane. This matches scope; re-opening panes remains a Selector action.
- exit semantics need a live confirm (section 5 verification item) — the contract
  rests on exit 0/1 in the runner finally propagating to the supervisor's
  `$LASTEXITCODE`, and on the supervisor's -NoExit fall-through. Both are expected
  PowerShell behavior but were not executed (read-only task).
- Cap give-up is terminal per pane. After the cap, the pane sits at a prompt until
  a human runs `restart-pane.ps1`. Deliberate (don't hot-loop a persistently-broken
  runner) and aligned with the gap analysis's ask for a loud signal rather than
  silent death — but a persistently-crashing recipient still needs one human touch.
  Surfacing "gave-up" panes in the Selector badge (a natural extension of B6) would
  close that loop.
