# Rule: confirmed-stale auto-CLI kills are fleet-executed, not owner-gated
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 11:47
Auto: yes
Risk: B
Base: origin/master

## Owner directive (2026-07-13, verbatim intent)
"Killing a stale auto CLI — if it is confirmed stale — should be done by the AI,
not me. Otherwise it takes too much time while other important stuff could be
delivered. This should be a rule that the claude orchestrator knows and
understands."

## Why now
Today's OpenCode wedge (diagnosed in the retired `to-kimi/202607130251`
handoff): opencode.exe PID 14584 hung on an LLM HTTP stream for ~8.5h holding a
claim, plus an orphaned pair (80192/80256) from a dead pre-restart runner. The
handoff's "restart stays with owner/claude" line meant the kill waited on the
owner — exactly the delay the owner is now removing. (Resolution in the end: a
full pane relaunch at 11:45 local cleared everything; the relaunched opencode
pane claimed the handoff at 11:45:39 and is working.)

## Proposed rule (for operating-prompt SSOT §8 autonomy tiers + contracts)
**Confirmed-stale kill = Tier B** (fleet-executed, no owner gate), with these
guards:

1. **"Confirmed stale" requires at least two independent signals**, e.g.:
   heartbeat/claim stale beyond the mirrored 15-min window AND the CLI child
   process shows no CPU progress and no log-file growth over a comparable
   window; or the process's parent runner is dead (orphan). A single signal
   (e.g. "orphaned but 1 minute old") is NOT enough — exactly the discipline
   `fleet-health.sh` applies.
2. **Kill the stale CLI child only — never the pane-runner or supervisor.**
   The runner's `finally` releases the claim and re-polls; that is the designed
   recovery path. Killing a runner/supervisor stays owner/claude-gated.
3. **Cross-CLI is allowed**: any fleet member (pane or cockpit) may kill a
   confirmed-stale CLI child of any pane — process lifecycle is not file-lane
   governed, and waiting for the "owning" CLI recreates the delay.
4. **Evidence at kill time**: the actor prepends an activity-log entry with the
   staleness evidence (pids, CPU/log timestamps, claim age) and the action
   taken. If confirmation is ambiguous, escalate to the owner instead — do not
   guess.
5. Detection tooling (`fleet-health.sh`, heartbeat) stays as-is; this rule only
   removes the human gate on the *act* once confirmation exists.

## Scope ask
- Ratify + place in the SSOT §8 tiers and the four contracts (your custodianship,
  ADR-0001). One line in each contract's kill/process section should suffice.
- Optional follow-up (not required here): a `.ai/tools/kill-stale-cli.sh` that
  encodes the two-signal check so actors don't hand-roll it — could fold into
  the watchdog work already merged via PR #77.

## Notes
- kimi cockpit did NOT perform any kill today — the 11:45 relaunch (actor
  unknown to me) resolved the wedge first. No action to unwind.
- Related open threads: `to-kimi/202607130150` (pin sync deploys), junction
  reverse-write guard (`to-kiro/202607130150`), ADR-0005 territory friction
  (two blocks today, reported in PR #75/#77 retirement notes).
