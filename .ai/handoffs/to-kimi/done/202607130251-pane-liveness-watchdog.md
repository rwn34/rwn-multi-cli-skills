# Fleet pane liveness — a stalled pane's queue is silently unwatched
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-13 09:51
Auto: no
Risk: B
Base: origin/master

## Completion (kimi-cli, 2026-07-13 ~10:45) — DONE

Shipped as **PR #77** (branch `exec/kimi/202607130251-pane-liveness-watchdog`,
base master, NOT merged — review/merge per ADR-0011).

- **Heartbeat**: `pane-runner.ps1` writes `.ai/.heartbeat-<cli>.json` once per
  poll cycle (cli/pid/host/ts + current handoff or `idle`), atomic temp+rename
  per `Write-Claim`, fail-open in the loop. Only runner change (+43 lines).
- **Watchdog**: `.ai/tools/fleet-health.sh` — 4-row verdict table (OK / STALL /
  WEDGED / DOWN (idle)), exit 1 on STALL/WEDGED, fail-open on internal errors.
  Staleness MIRRORS the pane-runner claim policy (15-min window, same-host dead
  pid = stale, foreign host = time window only); qualifying gate mirrors
  `Get-QualifyingHandoff` incl. the 60-min quarantine skip.
- **Surfacing**: Selector badge `stall:<cli>` marker (cheap: Test-Path+Get-Item
  per recipient with handoffs, only when `[H:n]` non-zero). The
  `stop-reminder.sh` block (STALL/WEDGED loud, DOWN-idle silent) is written +
  smoke-tested but **routed to claude-code** — ADR-0005's pre-commit gate bars
  kimi-cli from `.claude/**`: `to-claude/202607130332-surface-fleet-health-in-stop-reminder`
  carries the exact tested patch.
- **Verification**: STALL sim (stale hb + open Auto:yes B → STALL, exit 1) ✓;
  DOWN-idle sim (stale hb + empty queue → DOWN (idle), exit 0) ✓; live-repo run
  flags all four panes STALL incl. opencode on this handoff's subject
  (`202607121900-gates-required-check.md`) — expected pre-relaunch state
  (deployed runner has no heartbeat code yet) ✓; pane-runner suite **145/0**
  (132 + 13 heartbeat asserts), `test-fleet-health.sh` **9/9**, selector-e2e
  **90/0** ✓.
- **OpenCode pane diagnosis: WEDGED, not dead.** Pane-runner PID 59232 alive
  since 08:52:17; claimed the handoff, spawned `opencode.exe` PID 14584 at
  08:52:22; worktree cut `exec/opencode/202607121900-gates-required-check`.
  opencode.log shows run 966924d2 (zhipu-coding/glm-4.7-flash — the key
  AUTHENTICATED; "invalid key" does not match) working steps 10→14 until
  01:57:51 UTC, then total silence; PID 14584 still exists with 59.2s cumulative
  CPU. Hung LLM stream, no client-side timeout, blocking the poll loop inside
  one invocation. Also an orphaned pair from 07:13 (PIDs 80192/80256, parent
  dead) hung on a handoff since moved to done/. Bring-back: kill the hung
  children — the pane's `finally` releases claims and it re-polls. Restart/kill
  stays with owner/claude per this handoff.
- **Side effect**: the post-commit `sync-4ai-panes-install` hook auto-deployed
  this branch's `pane-runner.ps1`/`Selector.ps1` to `~/.rwn-auto/rwn-4AI-panes`
  (`verify=ok`) — running panes pick the heartbeat up on next respawn.
- **Incident found while delivering** (reported, not fixed — out of lane): the
  two ad-hoc kimi handoff-worktrees cut today (`kimi-watchdog`, `kimi-ownership`)
  have `.ai` as a REAL DIRECTORY, not the junction (Attributes=Directory, no
  ReparsePoint; the standing pane worktrees all have ReparsePoint). My worktree
  reflected live `.ai` state at ~09:58 and stopped by ~10:13; untracked live
  files (this handoff) are absent from the copy — consistent with a git op
  materializing tracked `.ai` content over the junction. Routed to the existing
  junction-reverse-write-guard thread (`to-kiro/202607130150`). All shared-plane
  writes for this completion (this retirement, the to-claude handoff, the
  activity-log entry) were made directly at the junction target.

## Problem (measured, 2026-07-13 ~09:50 local)

`.ai/handoffs/to-opencode/open/202607121900-gates-required-check.md` is
`Status: OPEN`, `Auto: yes`, `Risk: B`, `Created: 2026-07-12 19:00` — **~15 hours
unclaimed**. `.ai/handoffs/.quarantine/` contains only `README.md`, so it was
never quarantined: it is **not failing, it is unattended**. The owner noticed
before any tooling did ("opencode kind of stalling and nobody tries to up it").

**Root cause (structural):** the poll loop lives *inside* each pane. Pane dead,
wedged, or never relaunched → nobody polls that pane's queue. The existing
safety nets all assume a live poller:

- Per-project / per-handoff claim-locks reclaim a **dead pid** — but only when
  something polls to notice. A dead pane doesn't poll on its own behalf.
- Quarantine counts **failed attempts** — a pane that never attempts never
  quarantines, so an unattended queue looks identical to an idle-and-healthy one.
- `stop-reminder.sh` prints open counts to a **Claude session** — invisible if
  nobody is sitting in Claude.

So the fleet has no liveness signal and no dead-man's-switch. A pane can be down
for a day and the only detector is the owner's eyeball. That's the bug.

## Scope — what to build

**1. Pane heartbeat.** `pane-runner.ps1` writes a heartbeat sidecar each poll
cycle (`.ai/.heartbeat-<cli>.json`: cli, pid, host, ts, current handoff or
`idle`). Atomic temp+rename, same as `Write-Claim`. This is the only change to
the runner — keep it small; that file just came through a fleet outage and
should not be churned.

**2. `.ai/tools/fleet-health.sh`** (new). For each of the four CLIs, cross-check
heartbeat freshness against queue state and classify:

| Heartbeat | Open Auto:yes A/B handoffs | Verdict |
|---|---|---|
| fresh | any | `OK` |
| stale / missing | **0** | `DOWN (idle)` — informational, not an alarm |
| stale / missing | **≥1** | `STALL` — a queue with nobody watching it |
| fresh | ≥1, unclaimed, age > threshold | `WEDGED` — polling but not picking up |

Reuse the existing pid/host staleness semantics from `pane-runner.ps1` — do not
invent a second policy. Exit non-zero on `STALL`/`WEDGED` so CI/hooks can gate
on it. Fail-open on its own internal errors (never take the fleet down because
the health checker threw).

**3. Surface it where a human actually looks.**
- `stop-reminder.sh` — one line per non-OK pane at turn end. `STALL`/`WEDGED`
  must be loud; `DOWN (idle)` should not nag.
- The 4AI-panes selector badge already renders per-project open-handoff counts
  (`.ai/handoffs/README.md`, P5) — add pane health to that badge if it's cheap.
  If it isn't cheap, say so and skip it; do not gold-plate.

**4. Do NOT auto-restart panes.** Detection and alerting only, this round.
Auto-respawn touches process lifecycle and Windows Terminal, and last night
proved what a self-healing loop does when its base assumption is wrong (three
panes quarantined every handoff they touched). Alert first; earn the restart
later.

## Verify (evidence required — execution, not inspection)

- Simulate a stalled pane: stale heartbeat + ≥1 open `Auto: yes` Risk-B handoff
  → `fleet-health.sh` reports `STALL` and exits non-zero. Paste the output.
- Simulate down-but-idle: stale heartbeat + empty queue → `DOWN (idle)`, exit 0.
- Run it against the **real repo right now**: it should flag OpenCode as `STALL`
  on the live 15h-old `202607121900-gates-required-check.md`. **Paste that
  output** — that is the acceptance test that this would have caught the thing
  the owner caught by hand.
- Heartbeat write is atomic and does not perturb the existing pane-runner tests:
  run `tools/4ai-panes/test-pane-runner.ps1` in full and paste pass/fail counts
  (it was 132/0 after PR #70 — it must not regress).

## Report back with

- The four transcripts above (STALL, DOWN-idle, live-repo OpenCode STALL, test counts).
- `git diff --stat`.
- Your read on whether OpenCode's pane is dead vs wedged, and what it would take
  to bring it back up — the actual restart stays with the owner/Claude, but your
  diagnosis should say which it is.
