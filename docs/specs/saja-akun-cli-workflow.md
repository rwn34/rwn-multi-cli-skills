# Cockpit / Auto Handoff Workflow

**Status:** design pattern for the rwn-multi-cli-skills framework  
**First adopter:** saja-akun (and the rest of the saja fleet)  
**Replaces / extends:** protocol v3 in `.ai/handoffs/README.md`

This document fixes the ambiguity that a cockpit sees when it writes a handoff
and wants to know whether `<recipient>-auto` picked it up, whether the handoff
belongs to the auto pane or to the cockpit, and how a feature chains through
multiple auto panes before returning to a cockpit for final state read.

## 1. The six actors

A project using this framework has six logical actors. Four of them are headless
auto panes; two are interactive cockpits.

| Actor | Identity in handoffs / activity log | Role | Headless? |
|---|---|---|---|
| `claude-cockpit` | `claude-cockpit` | Architecture, orchestration, final review, human relay | no |
| `kimai-cockpit` | `kimai-cockpit` | Executor/tester, dispatcher to auto, human relay | no |
| `claude-auto` | `claude-auto` | Spec/plan design, final review | yes |
| `kimai-auto` | `kimai-auto` | Backend + shell-package implementation | yes |
| `kiro-auto` | `kiro-auto` | Frontend implementation | yes |
| `opencode-auto` | `opencode-auto` | Deploy, GitHub ops | yes |

The **cockpits** are the interactive chat sessions the owner talks to. They do
not poll `open/` queues on their own; they read handoffs on explicit user
instruction.

The **auto panes** run `tools/4ai-panes/pane-runner.ps1` and poll their own
`to-<cli>/open/` and `to-<cli>/review/` queues every `PollSeconds`.

## 2. Routing table

| Task type | From | To | Auto / Risk | Notes |
|---|---|---|---|---|
| Feature request, architecture decision, spec | owner / any cockpit | `claude-cockpit` or `claude-auto` | `Auto: no`, Risk C if irreversible, B otherwise | Cockpit-level thinking stays in a cockpit. |
| Backend implementation | `claude-auto` (spec) | `kimai-auto` | `Auto: yes`, Risk B | Executor lane. |
| Frontend implementation | `claude-auto` (spec) | `kiro-auto` | `Auto: yes`, Risk B | Executor lane; can run in parallel with kimai-auto. |
| Peer review of backend | `kimai-auto` (on done) | `kiro-auto` via `ReviewBy: kiro` | `Auto: yes`, Risk B | Emitted to `to-kiro/review/`. |
| Peer review of frontend | `kiro-auto` (on done) | `kimai-auto` via `ReviewBy: kimi` | `Auto: yes`, Risk B | Emitted to `to-kimi/review/`. |
| Final review | peer reviewer | `claude-auto` via `FinalReview: claude` | `Auto: yes`, Risk B | Emitted to `to-claude/review/`. |
| Deploy / GitHub ops | `claude-auto` (final review) | `opencode-auto` via `Deploy: yes` | `Auto: yes`, Risk B | Emitted to `to-opencode/open/`. |
| Human-gated production deploy | `opencode-auto` | `claude-cockpit` or `kimai-cockpit` | `Auto: no`, Risk C | Explicit owner confirmation required. |
| Urgent override / pane down | any cockpit | `<recipient>-cockpit` via `claim-handoff.sh` | `Auto: no`, Risk B/C | Cockpit claims an `Auto: yes` handoff atomically. |

## 3. Status-block conventions

A handoff status block now carries four routing fields. `Auto:` and `Risk:` are
required; `Owner:` and `Next:` are optional but strongly recommended for
visibility.

```markdown
Status: OPEN
Sender: claude-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-15 22:00
Auto: yes
Risk: B
Next: kimai-auto
```

### 3.1 `Auto:` — the ownership boundary (unchanged from protocol v3)

- `Auto: yes` + Risk A/B → owned by the **auto pane**. The dispatcher
  (`dispatch-handoffs.sh`) and the pane-runner will pick it up headlessly.
- `Auto: no` or Risk C → owned by a **cockpit**. It is never auto-dispatched.

`Auto:` is the **single source of truth** for the mechanical dispatch decision.
No new `Mode:` field is required; `Auto: yes` already means "mode = auto".

### 3.2 `Risk:` — autonomy tier (unchanged)

- `Risk: A` — reversible routine (reports, tests, docs, small edits).
- `Risk: B` — act-then-notify (multi-file refactors, config, PRs, deploy to
  staging, peer review).
- `Risk: C` — hard gate (production deploy, destructive ops, ADR changes,
  secrets).

Risk C is **never** auto-dispatched, regardless of `Auto:`.

### 3.3 `Owner:` — recommended visibility field

`Owner:` names the actor that currently owns the handoff. It is redundant with
`to-<cli>/` + `Auto:`, but it removes ambiguity for humans reading the file:

- `Owner: kimai-auto` means the kimai auto pane should pick it up.
- `Owner: claude-cockpit` means a human or the claude cockpit must handle it.

The dispatcher **ignores** `Owner:`; it uses `to-<cli>/` and `Auto:`.

### 3.4 `Sender:` / `Recipient:` — include mode

Use the six-actor identities:

- `Sender: claude-cockpit`
- `Recipient: kimai-auto`
- `Sender: kimai-auto`
- `Recipient: kiro-auto`

Do **not** use bare `kimi-cli` or `claude-code`; those names do not say whether
the sender/recipient is the cockpit or the auto pane.

### 3.5 `Next:` — encode the next actor in a chain

When an auto pane finishes and must hand off to another actor, the original
handoff carries a `Next:` field. The pane-runner's `Emit-NextStageHandoff`
reads `Next:` (in addition to the existing `ReviewBy:`, `FinalReview:`, and
`Deploy:` fields) and emits the follow-up handoff to the correct queue.

`Next:` is a general escape hatch for any chain that does not fit the
review/final-review/deploy pattern.

### 3.6 Why no `Mode:` field

`Mode: auto|cockpit` would duplicate `Auto: yes/no`. Two fields with the same
meaning create drift: a handoff could say `Auto: yes` and `Mode: cockpit`, and
nobody would know which wins. Keep one mechanical field (`Auto:`) and one human
visibility field (`Owner:`).

## 4. How the dispatcher knows to send to `<recipient>-auto`

The dispatcher does not need to know about cockpits. It only dispatches to auto
panes. The rules are:

1. Look in `to-<cli>/open/` and `to-<cli>/review/`.
2. Select handoffs with `Status: OPEN` + `Auto: yes` + `Risk: A|B`.
3. Skip handoffs with a live claim sidecar under `.ai/handoffs/.claims/`.
4. Launch the recipient CLI headless in its own worktree.

A cockpit never receives a dispatch. Cockpits read handoffs when:

- The owner tells the cockpit to read a specific file.
- `stop-reminder.sh` prints open counts at session end.
- `fleet-health.sh` reports STALL/WEDGED and the cockpit decides to claim the
  handoff.

## 5. Visibility model

A cockpit that writes a handoff can check progress with four canonical reads:

| Question | Command / file |
|---|---|
| Was the handoff picked up by auto? | `bash .ai/tools/dispatch-handoffs.sh` (dry-run shows "WOULD DISPATCH" if still queued) |
| Is the pane alive? | `bash .ai/tools/fleet-health.sh` |
| Who holds the claim? | `.ai/handoffs/.claims/<cli>__<slug>.claim.json` |
| Did the pane finish? | `ls .ai/handoffs/to-<cli>/done/<slug>.md` |
| What is the pane's last state? | `.ai/.heartbeat-<cli>.json` |

The **canonical progress check** for a cockpit is:

```bash
bash .ai/tools/fleet-health.sh
bash .ai/tools/dispatch-handoffs.sh
```

`fleet-health.sh` prints one line per CLI:

```
CLI       | heartbeat                      | queue | verdict
----------+--------------------------------+-------+--------
kimi      | ts 1m ago, pid 12345 live      | 1     | OK
kiro      | missing                        | 1     | STALL — 1 qualifying handoff(s), nobody watching
```

- `OK` → pane is polling. If the handoff is still in `open/`, it is queued or
  claimed by another consumer.
- `STALL` → pane is down and has open work. The cockpit should investigate or
  claim the handoff.
- `WEDGED` → pane is alive but has not picked up an old unclaimed handoff.

## 6. Multi-stage handoff chain

Lifecycle for a feature that flows from cockpit → auto planning → parallel
implementation → review → deploy → cockpit final read:

1. **Cockpit dispatch.** `claude-cockpit` writes:
   `.ai/handoffs/to-claude/open/202607152200-plan-checkout-flow.md`
   - `Sender: claude-cockpit`, `Recipient: claude-auto`, `Owner: claude-auto`
   - `Auto: yes`, `Risk: B`, `Next: kimai-auto,kiro-auto`

2. **Auto planning.** `claude-auto` picks it up, writes a spec/ADR, self-retires
   to `to-claude/done/`, and emits two implementation handoffs:
   - `.ai/handoffs/to-kimi/open/202607152300-implement-checkout-api.md`
   - `.ai/handoffs/to-kiro/open/202607152300-implement-checkout-ui.md`

3. **Parallel implementation.** `kimai-auto` and `kiro-auto` work in parallel.
   Each self-retires to its own `done/`.

4. **Peer review.** `kimai-auto`'s handoff has `ReviewBy: kiro`, so on done it
   emits `.ai/handoffs/to-kiro/review/202607160100-review-checkout-api.md`.
   `kiro-auto` does the same for `kimai`.

5. **Final review.** Each review handoff has `FinalReview: claude`, so on
   approval it emits `.ai/handoffs/to-claude/review/202607160200-final-review-checkout.md`.

6. **Deploy.** `claude-auto` final-reviews and, because the original handoff had
   `Deploy: yes`, emits `.ai/handoffs/to-opencode/open/202607160300-deploy-checkout.md`.

7. **Back to cockpit.** `opencode-auto` deploys and self-retires. The original
   cockpit (`claude-cockpit`) reads `to-opencode/done/` and the activity log to
   confirm the chain is complete.

## 7. Failure, retry, and escalation

### 7.1 Auto does not pick up a handoff

- `fleet-health.sh` flags `STALL` (pane down) or `WEDGED` (pane alive but not
  picking up).
- A `dispatch-failure-<UTC>-<cli>-<slug>.md` report is written if the headless
  dispatch exits non-zero.
- The originating cockpit is notified via the fleet Telegram notification if
  configured.
- Escalation: the cockpit runs `bash .ai/tools/claim-handoff.sh <path>` to take
  ownership, flips `Auto: no`, and either does the work or diagnoses the pane.

### 7.2 Stale claim sidecar

A claim sidecar (`.ai/handoffs/.claims/<cli>__<slug>.claim.json`) is stale when:

- Same host + pid is dead, **or**
- `claimed_at` is older than 15 minutes.

Stale claims are reclaimed automatically by:
- `pane-runner.ps1` on its next poll (`Test-HandoffClaimed`).
- `dispatch-handoffs.sh` before dispatch.
- `claim-handoff.sh` when a cockpit wants to take the handoff.

A cockpit may remove a stale claim only by claiming the handoff itself (which
replaces the sidecar atomically). A cockpit must **never** delete a claim
sidecar by hand — that bypasses the audit trail.

### 7.3 Handoff is BLOCKED

The recipient leaves the handoff in `open/`, sets `Status: BLOCKED`, and appends
a `## Blocker` section with verbatim errors.

- The owner cockpit (the one named in `Owner:` or `Recipient:`) reads the
  blocker and decides:
  - Fix the blocker and move the handoff back to `OPEN`.
  - Re-route to another actor with a new handoff.
  - Claim it and do it manually.

### 7.4 Pane outage

If an auto pane is persistently down:

1. `fleet-health.sh` reports `STALL`.
2. The owner or cockpit claims the urgent handoff (`claim-handoff.sh`).
3. The cockpit executes it.
4. The cockpit prepends an activity-log entry explaining the override.
5. The cockpit may restart the pane via `restart-pane.ps1` or the Windows
   Terminal UI.

## 8. Activity-log identity

Activity-log entry headers use the six-actor identity:

```markdown
## 2026-07-15 22:00 — kimai-auto
- Action: Implemented checkout API per handoff 202607152300-implement-checkout-api.md.
- Files: src/routes/checkout.ts
- Decisions: —
```

For machine-readable sidecars (heartbeat, claim), the existing CLI-type field
(`claude`, `kimi`, `kiro`, `opencode`) remains sufficient. Human-facing logs and
handoffs should use the actor name.

## 9. Tooling changes required

This pattern is mostly a convention change. The mechanical dispatch decision
stays on `Auto:` + `Risk:` + `to-<cli>/`, so `dispatch-handoffs.sh` and
`pane-runner.ps1` do not need to change.

Recommended tooling updates:

1. `.ai/handoffs/template.md` — add `Owner:` and `Next:` optional fields; update
   `Sender:` / `Recipient:` examples to use actor names.
2. `.ai/handoffs/README.md` — document the cockpit/auto distinction and the
   six-actor identity convention.
3. `.ai/tools/claim-handoff.sh` and `.ai/tools/release-handoff.sh` — change
   default `--owner` values from `claude-auto` / `kimi-cli` / `kiro-cli` /
   `opencode` to `claude-cockpit` / `kimai-cockpit` / `kiro-cockpit` /
   `opencode-cockpit`, because these scripts are cockpit-only.
4. `.ai/instructions/operating-prompt/principles.md` §7 and §8 — note that the
   `Auto:` boundary separates auto panes from cockpits, and that activity-log
   identity uses the six-actor names.

No change is required to `dispatch-handoffs.sh`, `fleet-health.sh`, heartbeat
sidecars, or the claim-lock mechanics.

## 10. Migration from four-actor to six-actor naming

Existing handoffs and log entries use names like `kimi-cli` and `claude-code`.
They are grandfathered. New handoffs and new log entries should use the six
actor names. The dispatcher does not read `Sender:` / `Recipient:` / `Owner:`
for routing, so mixed naming does not break the fleet.
