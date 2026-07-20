# Claude auto pane is crash-looping; orphaned claims mask it as healthy

- **Filed:** 2026-07-20 21:10 (UTC+7) by `claude-cockpit`
- **Trigger:** owner asked the cockpit to process `to-claude/open/202607201300-auto-echo-test.md`
- **Outcome:** handoff deliberately NOT processed and left `OPEN` / `Auto: yes`
- **Severity:** high — every dashboard reports the claude pane healthy while it completes zero work

## Why the handoff was not processed

`202607201300-auto-echo-test.md` states its own purpose:

    Task: Confirm this auto pane is alive and processing handoffs.

It is `Auto: yes` + `Risk: B`, so per `.ai/handoffs/README.md` it is owned by the
**auto pane**, not the cockpit. Had the cockpit executed it, the handoff would
have retired `DONE` and the fleet record would assert "claude auto pane is alive
and processing handoffs" — which is false. The test would have been marked
passed by the one actor whose participation invalidates it.

Per the README's v3 amendment (2026-07-17), refusing to close is the deliverable
here, stated explicitly rather than silently skipped.

The cockpit did take a claim during investigation (`claim-handoff.sh` in the
worktree). That claim was void — wrong tree, see finding 2 — and has been
released. Worktree file re-verified at `Auto: yes`, sidecar removed. Canonical
was never modified.

## Finding 1 — the pane-runner is alive; its children die before retiring work

The claim sidecar for this handoff was rewritten three times in ~90 seconds,
each time by a different pid, each of which then exited:

| Time (UTC) | pid | Liveness at check |
|---|---|---|
| 14:02:41 | 34452 | **alive** — `powershell`, started 14:02:39, the long-lived pane-runner |
| 14:03:50 | 973148 | **dead** |
| 14:04:41 | 976430 | **dead** (worktree sidecar) |

Heartbeat `.ai/.heartbeat-claude.json` reports `pid 34452` — the pane-runner,
which is genuinely alive. The claim sidecar reports `pid 973148` — a child,
which is dead. **The heartbeat and the claim disagree about who holds the work.**

Shape of the failure: each poll cycle spawns a child; the child writes a
heartbeat and a claim, then exits before retiring the handoff. The parent
survives, so the heartbeat stays fresh. The handoff is never completed.

Corroborating: `to-claude/done/202607201300-auto-echo-test.md` does not exist,
and the file is still in `open/` with `Status: OPEN` — after ~70 minutes and
repeated pickups.

## Finding 2 — `.ai/` is NOT a junction in the worktrees, so claims are advisory

`CLAUDE.md` states `.ai/` is a Windows junction (`mklink /J`). In
`C:\Users\rwn34\Code\.wt\rwn-multi-cli-skills\claude` it is not:

- `LinkType` empty, `Attributes: Directory`, `IsReparse: False`
- `cmd /c dir /al` finds zero reparse points at every level of the path
- NTFS file IDs differ for the same relative path (worktree `9851624186135341`
  vs canonical `6192449489876963`), link count 1 each

The two trees are coupled by `sync-ai-state.sh` copying, not by the filesystem.
`claim-handoff.sh`'s exclusive-create atomicity is therefore **per-directory**,
and `.ai/handoffs/.claims/` is not one shared namespace. Two actors in two trees
can both "win" the same claim — which is what happened here.

This is the likely mechanism behind the existing
`.duplicate-20260720135736` files in `to-kiro/done/` and `to-opencode/done/`.

Note the confinement hook's own wording — "may write only inside it (+ the
junctioned .ai/)" — encodes the same assumption. This report had to be
redirected into the worktree for exactly that reason, and reaches canonical only
when `sync-ai-state.sh` next runs.

## Finding 3 — `fleet-health.sh` cannot detect this class of failure

`fleet-health.sh` liveness-checks the **heartbeat** pid and never the **claim
sidecar** pid. Against a crash-looping pane it reports:

    claude | ts 1m ago, pid 34452 live | 3 | WEDGED — polling but not picking up

"Polling but not picking up" is wrong. The pane *is* picking up — it picks up,
claims, and dies. The distinction matters because it points at the pane-runner
child lifecycle, not at the queue.

Worse, a dead-pid claim with a fresh `claimed_at` is indistinguishable from
healthy work-in-progress until the 15-minute wall-clock window expires. Because
each crash refreshes the timestamp, the window never expires while the loop runs.

`fleet-health.sh` also reported all four worktrees behind `origin/main`.

## Scaling behaviour

With one handoff this looks like a stall. With N queued handoffs it compounds:
each crashed child burns a fresh 15-minute orphaned-claim window on a *different*
handoff, so throughput collapses toward zero while every dashboard still reports
the pane live and polling. The claude queue currently holds **3 open handoffs**
(`202607201300-auto-echo-test.md`, `202607201500-auto-echo-v2.md`,
`kimi-smoke-return.md` — the last unclaimed for 143 minutes).

## Recommended next steps

1. **Diagnose the child exit** — the pane-runner log, not the claim system, is
   where the cause is. `tools/4ai-panes/pane-runner.ps1` child invocation +
   whatever it writes on child exit. The claim churn is a symptom.
2. **Liveness-check the sidecar pid** in both `fleet-health.sh` and the pane's
   own claim gate. A claim whose pid is dead on the same host is already defined
   as reclaimable by `.ai/handoffs/.claims/README.md` — the check just is not
   being applied to the sidecar.
3. **Make `.ai/` an actual junction in each worktree**, which is what ADR-0016
   already assumes. Sync-by-copy cannot provide mutual exclusion no matter how
   `claim-handoff.sh` is hardened.
4. **Refresh the four stale worktrees** before the next dispatch.

Items 1 and 2 are the ones that stop the bleeding; item 3 is the structural fix.

## Verification evidence

    $ grep -n "^Auto:" .ai/handoffs/to-claude/open/202607201300-auto-echo-test.md
    5:Auto: yes                          # worktree, after release — restored

    $ cat .ai/handoffs/.claims/claude__202607201300-auto-echo-test.claim.json   # canonical
    {"handoff":"202607201300-auto-echo-test","recipient":"claude","owner":"claude",
     "pid":973148,"host":"E-NMP","claimed_at":"2026-07-20T14:03:50Z"}

    PID 34452:  ALIVE  powershell  StartTime=7/20/2026 9:02:39 PM
    PID 973148: DEAD
    PID 976430: DEAD

    $ ls .ai/handoffs/to-claude/done/202607201300-auto-echo-test.md
    ls: No such file or directory
