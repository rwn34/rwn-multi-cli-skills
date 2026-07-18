# Fleet supervisor: detect a dead fleet, alert the owner, relaunch it
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-12 21:30
Auto: yes
Risk: B
Base: origin/master

## Why this exists (the failure, from tonight)
The owner restarted PowerShell. That killed the pane-runners. **Four handoffs sat
`OPEN` and unconsumed for over an hour, and nothing anywhere said so** — the
orchestrator kept reporting "in flight" while the fleet was dead.

**A queue with no consumer looks exactly like a queue being worked.** That is the
whole bug. `run-pane-supervised.ps1` already respawns a *runner* that crashes inside
a live terminal — but when the **terminal itself** dies, nothing survives to notice.

Owner decision (2026-07-12): build **alert + auto-relaunch**. Explicitly NOT a
headless drain — the supervisor restores the fleet exactly as it was and tells the
owner. **It grants no new autonomy**: the revived fleet operates under the same tiers
as always. Do not exceed that scope.

## Target
An **OS-level supervisor** (Windows Task Scheduler — survives terminal death AND
reboot, needs no terminal open) that periodically:
1. Determines whether the fleet's pane-runners are **alive**.
2. If DOWN **and** there are open handoffs → **alert the owner** (Telegram) **and
   relaunch the fleet**.
3. If DOWN with an empty queue → alert is optional (your call; justify it). Don't spam.

## Pieces that already exist — REUSE, do not rebuild
- `tools/4ai-panes/notify.ps1` (+ `.ai/tools/notify.sh`) — Telegram to the owner.
  **Proven working** (the owner visually confirmed emoji + timestamp render). Use it.
- `tools/4ai-panes/run-pane-supervised.ps1` — respawns a crashed runner *within* a
  live terminal. Your supervisor is the layer ABOVE this, not a replacement.
- `tools/4ai-panes/Launch4Panes.ps1` / `Selector.ps1` — how the fleet is launched.
  Reuse the existing launch path; do not invent a second one.
- The `[H:n stranded:<cli>]` badge logic in `Selector.ps1` — already computes
  "handoffs exist whose CLI is unavailable". Same question your supervisor asks.
- `pane-runner.ps1` — has an idle heartbeat (PR #43), but it writes to the **console
  only**. That proves a live pane is alive; it says nothing when the pane is GONE.
  **You need a persistent heartbeat.**

## ⚠️ AMENDMENT (2026-07-12 22:30) — LIVENESS IS NOT ENOUGH. READ THIS FIRST.

**A live process that cannot call its LLM is indistinguishable from a healthy one,
and this is not hypothetical — it is happening RIGHT NOW.**

The owner just discovered **OpenCode's LLM API key is invalid.** Its pane-runner is
alive. It is polling. It is printing idle heartbeats. And it is **completely unable to
do any work.** A supervisor that only asks *"is the process alive?"* would have
reported the fleet 100% GREEN all night while a quarter of it was brain-dead.

Note the shape of it: OpenCode produced real work earlier today (read files, cut
branches, ran `gh api`, wrote reports), so this is not a config error — the key broke
*later*. **Any CLI can lose its credentials, hit a quota, or have its provider go down
mid-session, and the symptom is identical: silence.**

**Therefore your health model MUST have TWO levels, not one:**

- **L1 — LIVENESS:** is the pane-runner process alive and polling? (heartbeat file,
  recent mtime)
- **L2 — CAPABILITY:** can the CLI actually reach its model and do work?

**L2 is the one that matters and the one that is missing.** Design a **canary**: a
cheap, periodic proof that each CLI can actually invoke its LLM (e.g. a trivial
headless invocation whose success/failure is recorded; or have the pane-runner record
the outcome of its LAST real invocation — auth failure / quota error / non-zero exit —
into its heartbeat file). Auth and quota failures must be **distinguishable from "idle
with an empty queue"**, because today they look identical.

Required behavior:
- **ALIVE + CAPABLE + idle** -> healthy, no alert.
- **ALIVE but NOT CAPABLE** (auth failure, quota exhausted, provider down) ->
  **ALERT THE OWNER**, name the CLI and the reason. **Do NOT relaunch** — relaunching a
  process whose API key is dead just spins. Relaunch fixes a dead *process*, not dead
  *credentials*. Getting this wrong turns a broken key into an infinite relaunch loop.
- **DEAD process** -> alert + relaunch (the original brief).

The alert must say WHICH failure it is. "OpenCode is down" and "OpenCode is up but its
API key is invalid" require completely different responses from the owner, and only one
of them is fixed by a relaunch.

Design the canary cheaply — do not burn tokens pinging every model every minute. Piggy-
backing on the outcome of real invocations is likely better than synthetic pings; if a
CLI has had no invocation in a long while, an occasional cheap canary is justified.
State your design and its cost.

---

## The adversarial gaps — I have thought these through; your design must handle each
1. **False-positive relaunch is the worst outcome.** If the supervisor wrongly
   concludes a *live* fleet is dead and relaunches it, you get **two fleets, two sets
   of runners, two consumers racing the same handoff queue** — and the claim sidecar
   has a known 15-minute staleness with no heartbeat renewal. That is strictly worse
   than the bug being fixed. **Liveness detection must be robust**: a heartbeat FILE
   with a recent mtime, written by each runner on every poll — not "is a window
   titled rwn4ai open".
2. **Heartbeat file location.** Do NOT put it in `.ai/` — that tree is junctioned
   across every worktree and shared by every pane; adding per-poll churn there
   pollutes the coordination plane and git. Put it outside the repo (e.g. under
   `%LOCALAPPDATA%`) or in a gitignored path. State where and why.
3. **Relaunch loop.** If the fleet crashes immediately on launch, a naive supervisor
   relaunches forever, burning the machine (and possibly tokens) with nobody watching.
   **Required: exponential backoff, a max-attempts circuit breaker, and an alert when
   it gives up.** A supervisor that can loop unattended is a liability, not a fix.
4. **Task Scheduler + GUI.** Launching Windows Terminal from a scheduled task hits
   session-isolation: a task running in session 0 (or "run whether user is logged on
   or not") **cannot open an interactive window**. You will likely need "run only when
   the user is logged on" + interactive. **Verify this actually works — do not assume.**
   If it cannot reliably relaunch the GUI panes, SAY SO and report what it CAN do
   (e.g. alert-only + a headless fallback) rather than shipping something that
   silently never works. That negative result would be a completely acceptable outcome.
5. **Don't alert-spam.** A down fleet at 3am should not fire a Telegram every minute.
   Rate-limit / dedupe (alert on state *transition*, not on every poll).
6. **Registration must be scripted + reversible.** A `scripts/` (or `tools/4ai-panes/`)
   install script that registers the scheduled task, and an uninstall that removes it.
   Never a hand-clicked task that exists only on one machine.

## ALSO — record the boundary (owner-decided, do not fix)
Add to `.ai/known-limitations.md`, honestly:

> **The fleet cannot self-heal when the machine is off or asleep.** A Windows scheduled
> task cannot run on a powered-off box — it cannot relaunch the fleet, and it cannot
> even send the alert. Every local supervision mechanism shares this hard boundary.
> True always-available operation would require an always-on host (VPS / cloud runner /
> home server), which drags in secrets handling, cost, and remote-tree topology.
> **Owner decision 2026-07-12: accept this limit for now; record it, do not solve it.**

## Constraints
- **Do NOT build a headless drain.** The owner explicitly chose relaunch-only. A
  scheduled `dispatch-handoffs.sh --exec` that consumes handoffs with no terminal is a
  DIFFERENT decision with real autonomy implications, and it was declined tonight.
  If you think the relaunch path is unworkable and headless is the only option, STOP
  and report — do not substitute it.
- **Version:** ADR-0012 is live — the version is assigned **at merge**, not on the
  branch. **Do NOT bump `package.json`.** Bullets under `## [Unreleased]`. Confirm by
  grepping `.github/workflows/gates.yml` for `if: github.event_name == 'push'`.
- PowerShell 5.1 compatible; a pre-commit hook parse-gates every staged `.ps1`.
- **Commit any `.ai/` artifact before your worktree goes away.** A design doc was
  destroyed twice tonight by living uncommitted in a removed worktree.
- Read first: `docs/architecture/0008-self-driving-fleet-pane-runner.md` (the
  pane-runner architecture — this supervisor sits above it; consider whether it needs an
  amendment and say so), `.ai/instructions/delivery-integrity/principles.md`.

## Tests (the deliverable — this thing runs unattended, so it must be provably safe)
- Liveness: fresh heartbeat -> ALIVE; stale heartbeat -> DOWN; missing -> DOWN.
- **A live fleet is NEVER relaunched** (the false-positive case — assert it hard).
- Down + open handoffs -> alert fires AND relaunch is attempted.
- Down + empty queue -> whatever you chose, asserted.
- Backoff + circuit breaker: repeated launch failure backs off and eventually gives up
  **with an alert**, rather than looping.
- Alert dedupe: a fleet down for N polls fires ONE alert, not N.
- Install/uninstall script registers and removes the task cleanly.

## Verify (EXECUTE — inspection is not evidence)
- Paste the full test output.
- **Paste a real end-to-end proof:** kill the pane-runners, show the supervisor detect
  it, show the alert fire (a real Telegram send, or the exact payload it would send),
  and show the relaunch succeed. This is the acceptance test; a green unit suite
  without it is not done.
- State plainly whether Task Scheduler can actually relaunch the interactive panes on
  this machine. If it cannot, that negative finding IS the deliverable — report it.

## Deliverable
Branch `exec/kimi/fleet-supervisor` off `origin/master`. Push, open a PR, route peer
review to **KIRO**. Do NOT merge (Kiro reviews; then the fleet merges — merge-to-main
is Tier B now, the owner does not gate it).

## Report back with
- the liveness mechanism you chose and why it can't false-positive
- the end-to-end kill→detect→alert→relaunch proof, verbatim
- whether Task Scheduler can relaunch the GUI panes (yes/no, with evidence)
- the backoff/circuit-breaker design
- what this still does NOT cover, stated plainly
- PR URL

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kimi/done/`.
