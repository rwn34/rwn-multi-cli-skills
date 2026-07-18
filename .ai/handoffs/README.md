# Cross-CLI Handoff Directory

When one CLI needs another to execute changes in its own folder, the sender writes a
paste-ready instruction file here. The recipient reviews and executes. The sender
validates afterward by reading the resulting files.

## Why this exists

Cross-CLI convention assumptions can be silently wrong (e.g. "Kiro auto-scans
`.kiro/skills/`" was wrong — it actually loads skills via `skill://` URIs in agent
config). Each CLI owns changes to its own folder. This handoff queue keeps cross-CLI
work explicit, reviewable, and traceable instead of one CLI guessing at another's
conventions.

## Who can edit what (reminder)

- **Claude Code** edits: `.claude/`, `.ai/`, `CLAUDE.md`, `AGENTS.md`, any non-CLI path. Also custodian of OpenCode's files (`AGENTS.md` OpenCode-facing content, `opencode.json`, `.opencode/`) per ADR-0001 (amended 2026-07-09).
- **Kimi CLI** edits: `.kimi/` (project), `~/.kimi/` (global), any non-CLI path.
- **Kiro CLI** edits: `.kiro/` (project), `~/.kiro/` (global), any non-CLI path.
- **OpenCode** edits: `.ai/` only (activity log, reports, handoffs). Its own config is Claude-maintained — OpenCode requests changes via `to-claude/`.

Any CLI can edit `.ai/` (shared SSOT + docs + handoffs queue + activity log). When a
CLI needs a change in another CLI's folder, it writes a handoff to
`.ai/handoffs/to-<owner>/open/` — including to `to-claude/` when Kimi or Kiro needs
Claude to update something in `.claude/` or in Claude's portion of the shared docs.

## Layout

    .ai/handoffs/
    ├── README.md                    this file
    ├── template.md                  copy-paste starting shape for new handoffs
    ├── to-claude/
    │   ├── open/                    handoffs for Claude Code to process
    │   ├── review/                  verification handoffs routed to Claude Code
    │   └── done/                    handoffs Claude has completed + sender has validated
    ├── to-kimi/
    │   ├── open/
    │   ├── review/
    │   └── done/
    ├── to-kiro/
    │   ├── open/
    │   ├── review/
    │   └── done/
    └── to-opencode/            (renamed from to-crush/ 2026-07-09; done/ history preserved)
        ├── open/
        ├── review/
        └── done/

`open/` and `review/` are both polled by the auto panes. `review/` holds
verification work produced by an executor after it finishes a task — for example,
a Kiro task may result in a `to-kimi/review/` handoff so Kimi checks Kiro's work.

## Filename convention

    YYYYMMDDHHMM-short-task-slug.md

- `YYYYMMDDHHMM` — **UTC** timestamp of handoff creation, minute precision. Example:
  `202604201530-wave5-cleanup.md` (2026-04-20 15:30 UTC). Collisions across CLIs
  at the same minute are vanishingly rare; if one happens, the second writer
  appends a `-a` / `-b` suffix.
- `short-task-slug` — kebab-case, ≤ 5 words, describes the change.

**⚠️ Filename basis = UTC, `Created:`/log basis = UTC+7 — do not mix them.**
A CLI finishing at 22:17 UTC+7 writes the filename with the **UTC** time
(15:17), but the `Created:` line and its activity-log entry with the **UTC+7**
time, annotated `(UTC+7)`:

    Filename:  202607091517-test-count-reply.md      ← 15:17 UTC
    Created:   2026-07-09 22:17 (UTC+7)              ← 22:17 UTC+7

Both refer to the same instant. Using local time in the filename (e.g.
`202607092217-…`) is the common mistake — it desynchronizes sort order across
CLIs on different clocks. When in doubt, derive the filename from UTC (`date -u
+%Y%m%d%H%M`).

**Why timestamp-based (not `NNN-slug`):** the old `NNN` scheme required each
CLI to compute `max(existing) + 1`, creating a race condition when two CLIs
dispatched handoffs to the same recipient within seconds of each other. We
observed 3 such collisions during the 2026-04-18/19 audit cycle. Timestamps
are monotonic per-CLI-clock and carry useful metadata (when was this filed?)
for free.

**Legacy handoffs** (created before 2026-04-20) use the old `NNN-slug` format.
Do not rename — they are grandfathered. New handoffs use the timestamp format.
Sorting `ls .ai/handoffs/to-<cli>/open/` still shows oldest-first with both
formats present.

## Six-actor cockpit / auto model — 2026-07-18

The queue directories are still named after the four CLIs (`to-claude/`,
`to-kimi/`, `to-kiro/`, `to-opencode/`), but a handoff's `Sender:`,
`Recipient:`, and `Owner:` lines use the six-actor identity that includes the
mode:

| Identity | Mode | Role |
|----------|------|------|
| `claude-cockpit` | interactive cockpit | architecture, orchestration, final review, human relay |
| `kimai-cockpit` | interactive cockpit | executor/tester, dispatcher to auto |
| `claude-auto` | headless auto pane | spec/plan design, final review |
| `kimai-auto` | headless auto pane | backend + shell package implementation |
| `kiro-auto` | headless auto pane | frontend implementation |
| `opencode-auto` | headless auto pane | deploy, GitHub ops |

- `Auto: yes` + `Risk: A/B` routes to the recipient's `-auto` pane.
- `Auto: no`, hard-gate `Risk: C`, or a `Next:` pointing at a cockpit routes to
the recipient's `-cockpit` interactive session.

See `docs/specs/saja-akun-cli-workflow.md` for the routing table, multi-stage
chains, visibility model, and escalation rules, and
`docs/guides/example-handoff-chain.md` for a concrete end-to-end example.

## Protocol v4 (lifecycle of a single handoff) — 2026-07-16

Every handoff carries routing fields in its status block:
`Auto:` (default **yes**), `Risk:` (**A**/**B**/**C** per the autonomy tiers
in `.ai/instructions/operating-prompt/principles.md` §8), and sender-side
evidence fields introduced in v4. A missing `Risk:` line is treated as C —
conservative by default.

1. **Create** — sender writes `to-<recipient>/open/YYYYMMDDHHMM-<slug>.md`. Status
   line inside the file reads `OPEN`. Set `Auto:`, `Risk:`, `Evidence:`, and
   `Observed-in:` honestly. A Risk-C task labeled B to sneak past the gate is a
   delivery-integrity violation.
2. **Lint (sender-side gate)** — before dispatch, `bash .ai/tools/lint-handoff.sh`
   checks for protocol-v4 discipline errors: `Status: DONE` without evidence,
   `Evidence: HYPOTHESIS` with a priority label or `Risk: C`, and file-level
   claims missing `Observed-in:`. Run it locally before filing; CI also runs it.
3. **Dispatch (auto, default for Risk A/B)** — run
   `bash .ai/tools/dispatch-handoffs.sh --exec` (dry-run without `--exec`): it
   launches the recipient CLI headless (one-shot) for every `Auto: yes` +
   Risk A/B handoff. Any idle CLI, a polling loop, or the user can trigger the
   dispatcher — it is safe to run repeatedly. Windows Terminal panes can't be
   driven programmatically, so this spawns fresh instances — see
   `.ai/research/4ai-panes-integration-notes.md`.
3b. **Dispatch (manual — Risk C, `Auto: no`, or hard-gate)** — the user tells the
   recipient CLI: "read `.ai/handoffs/to-<cli>/open/YYYYMMDDHHMM-<slug>.md` and
   execute it." Hard-gate Risk-C handoffs are NEVER auto-dispatched, regardless
   of `Gate-satisfied-by:`.
4. **Review + execute** — recipient reads the handoff, asks clarifying questions if
   needed, performs the steps, prepends an entry to `.ai/activity/log.md`.
5. **Report + self-retire** — recipient reports back in chat with the "Report
   back with" section filled in, sets the handoff file's status to a terminal
   value inline (`DONE`, `IMPOSSIBLE`, or `NOT-A-BUG`), **and moves the file from
   `open/` to `done/` itself.** The recipient closing its own loop is now the
   standard — it keeps the `open/` queue an accurate picture of outstanding work
   without waiting on a sender round-trip.
   - `Status: DONE` — work completed; include a non-empty `Evidence`/`Report`/
     `Verification`/`Output` section.
   - `Status: IMPOSSIBLE` — sender's premise was disproven; include a `## Why`
     section with the disproof and evidence. Recipient moves to `done/`.
   - `Status: NOT-A-BUG` — reported behavior is correct or intended; include a
     `## Why` section with evidence. Recipient moves to `done/`.
   - Exception: if the recipient is **blocked**, it leaves the file in `open/`,
     sets status `BLOCKED`, and appends a `## Blocker` section with the verbatim
     error — never a paraphrase.
6. **Validate (post-hoc)** — sender reads the recipient's touched files and confirms
   they match spec. Validation now happens *after* the file is already in `done/`.
   If the work is wrong, the sender moves it back to `open/`, sets status `BLOCKED`
   with notes, and (for Auto handoffs) it re-dispatches on the next poll.

> **v3 → v4 change (2026-07-16):** v4 adds `Observed-in:`, `Evidence:`, and
> `Gate:`/`Gate-satisfied-by:`/`Relay:` to the status block, and a lint step to
> catch sender-side evidence errors before they burn executor budget. The
> recipient self-retire rule from v3 is unchanged. See
> `docs/specs/handoff-protocol-v4.md` and `docs/architecture/0015-handoff-protocol-v4.md`
> for the full rationale and ADR-0015 decisions.

> **Auto-reconcile (belt-and-suspenders, gap C3):** if a recipient sets a
> terminal status (`Status: DONE`, `Status: IMPOSSIBLE`, or
> `Status: NOT-A-BUG`) inline but forgets to move the file out of `open/`,
> `.ai/tools/reconcile-done-handoffs.sh` moves any such stray into its sibling
> `done/` dir. It runs at the start of every `dispatch-handoffs.sh --exec` cycle
> (so every auto-dispatch across all CLIs self-heals a forgotten step-4
> self-retire), and can also be run standalone. It is idempotent and fail-open
> (always exits 0). On filename collision it renames the incoming file to
> `<basename>-superseded-<UTC>.md` rather than overwriting. Terminal handoffs
> that fail the v4 lint are left in place so the recipient can fix them.

### Read `Status:` before you act on a resume instruction (v3 amendment, 2026-07-17)

**A `BLOCKED` handoff is not an interrupted handoff, and the two need opposite
responses.** Generic resume scaffolds assert a cause ("you hit a step or tool cap;
finish the remaining steps, set Status `DONE`, move to `done/`") that the file
itself frequently refutes. A session that complies without checking closes a
legitimately-open block, and the record drifts from the tree — worse than the open
block, because it stops the next session from looking.

Before obeying any instruction to close, resume, or continue a handoff:

1. **Read `Status:` first.** `BLOCKED` + a `## Blocker` section means the prior
   session ran to a deliberate reasoned stop, not a cap-out. There are no
   "remaining steps" to finish. Re-verify the blocker against the live tree; if it
   still holds, the handoff **stays put** and refusing to close it is the
   deliverable. Say so explicitly rather than silently doing nothing.
2. **Re-pin `Commit:` before trusting it.** A `Commit:` line is recorded once at
   review start and never revalidated, so a branch that moves underneath a review
   leaves every downstream reader inheriting a stale premise. The next actor runs
   `git rev-parse <branch>` and compares. One command; it catches tip drift at the
   handoff boundary instead of at the merge gate.
3. **A review scope statement describes a commit, not a branch.** "Diff scoped to
   N files" is typically true of `base..<reviewed-commit>` while the branch has
   moved on. Check `git diff --name-only base..<branch>` — that is what would
   actually merge.

Rationale: this shape recurred four times (logged 2026-07-17 16:20, 23:05, 23:20,
and the resume attempt that prompted this amendment). Each instance was diagnosed
correctly and the protocol was left unchanged, so it recurred. The common
mechanism is that **the scaffold's premise is never checked against reality before
it is obeyed.**

## Status-block fields (v4)

Status-block parsing is key-based and case-insensitive; extra header lines
(`Owner:`, `Reopened:`, `Rescoped:`, `Gate:`, …) and a `## Blocker` above the
sender block are valid. See `docs/specs/handoff-protocol-v4.md` for the full
spec and `docs/architecture/0015-handoff-protocol-v4.md` for the ADR.

- `Observed-in: <branch>@<sha>` — required when the handoff asserts file-level
  facts. The `<branch>` part is advisory; the `<sha>` part is authoritative. The
  dispatcher resolves abbreviated SHAs and accepts the observed commit if it is
  the dispatch base or an ancestor of it. Divergence produces a first-class
  `evidence-base mismatch` dispatch failure, routed back to the sender.
- `Evidence: VERIFIED | HYPOTHESIS` — epistemic status. Absent or `VERIFIED`
  dispatches under normal Risk rules. `HYPOTHESIS` at `Risk: A/B` dispatches a
  verify-first pass; the recipient upgrades to `VERIFIED` or retires as
  `NOT-A-BUG`/`BLOCKED`. `HYPOTHESIS` is capped at `Risk: A/B` and may not carry
  a priority label.
- `Gate: <what>` — for `Risk: C` handoffs, names the action that needs
  authorization. Hard gates (production deploy, publish to a public registry,
  tag/release cut, force-push / destructive ops on shared history,
  `git reset --hard` on shared state, secrets, production data) always HOLD for a
  cockpit, even with `Gate-satisfied-by:` present.
- `Gate-satisfied-by: <who> @ <when>` — records who authorized a non-hard gate.
  Once present, the orchestrator may relay the launch and the dispatcher may
  auto-dispatch a non-hard-gate `Risk: C` handoff.
- `Relay: <actor>` — optional; clarifies who physically launches the action when
  it differs from the `Recipient`. If omitted, the recipient is the relay.

## Cockpit / auto distinction (six-actor model)

A project using this framework has six logical actors, not four CLI binaries:

| Actor | Role | Headless? |
|---|---|---|
| `claude-cockpit` | Interactive Claude Code chat — architecture, orchestration, final review, human relay | no |
| `kimai-cockpit` | Interactive Kimi CLI chat — executor/tester, dispatcher to auto, human relay | no |
| `claude-auto` | Headless Claude pane-runner — spec/plan design, final review | yes |
| `kimai-auto` | Headless Kimi pane-runner — backend + shell package implementation | yes |
| `kiro-auto` | Headless Kiro pane-runner — frontend implementation | yes |
| `opencode-auto` | Headless OpenCode pane-runner — deploy, GitHub ops | yes |

The dispatcher and the pane-runner only ever talk to the **auto** actors. A
cockpit reads handoffs when the owner asks it to, when `stop-reminder.sh`
surfaces counts, or when `fleet-health.sh` reports a STALL/WEDGED pane.

In handoff status blocks:

- `Sender:` / `Recipient:` / `Owner:` should use the six-actor identity (e.g.
  `kimai-auto`, `claude-cockpit`). Bare `kimi-cli` or `claude-code` are
  ambiguous — they do not say whether the actor is the cockpit or the auto pane.
- `Auto:` remains the single mechanical ownership boundary:
  - `Auto: yes` + Risk A/B → owned by the auto pane.
  - `Auto: no` or Risk C → owned by a cockpit.
- `Evidence:`, `Observed-in:`, `Gate:`/`Gate-satisfied-by:`/`Relay:` are required
  or forbidden based on the rules above.
- `Owner:` and `Next:` are optional but recommended for human readability; the
  dispatcher ignores them.

Full routing table, visibility model, and multi-stage chain examples:
`docs/specs/saja-akun-cli-workflow.md`.

## Review pipeline (peer review before release)

The `review/` queue is a separate lane for verification work. It lets executors
(Kimi/Kiro) review each other's output and lets Claude give final approval before
OpenCode deploys.

Typical flow:

1. Task handoff: `to-kimi/open/202607151200-fix-foo.md` (ReviewBy: kiro)
2. Kimi executes the task and self-retires to `to-kimi/done/`.
3. Kimi also emits a review handoff: `to-kiro/review/202607151300-review-kimi-fix-foo.md`.
4. Kiro reviews. If approved, Kiro emits `to-claude/review/202607151400-final-review-fix-foo.md`.
5. Claude final-reviews. If approved and the task needs release, Claude emits
   `to-opencode/open/202607151500-deploy-fix-foo.md`.
6. OpenCode deploys and self-retires to `to-opencode/done/`.

A reviewer may reject by moving the handoff back to the original executor's
`open/` queue with `Status: BLOCKED` and a `## Blocker` section explaining what
must be fixed.

Review handoffs use the same status block as regular handoffs (`Auto:`, `Risk:`,
`Status:`). Optional routing fields in the status block:

- `ReviewBy: <cli>` — the executor that completed the original task should emit
  a review handoff to `to-<cli>/review/` on completion.
- `FinalReview: <cli>` — the reviewer should emit a final-review handoff to
  `to-<cli>/review/` after approving.
- `Deploy: yes` — the final reviewer should emit a deploy handoff to
  `to-opencode/open/` after approving.

## Polling — who watches the queues (P4, 2026-07-09)

Three mechanisms, three scopes — they complement, never compete:

| Mechanism | Scope | How |
|---|---|---|
| **Session-end reminder** | every Claude session | `stop-reminder.sh` prints per-queue open counts at each turn end — zero setup, always on. |
| **In-session interval poll** | an active working session | `/loop 15m bash .ai/tools/dispatch-handoffs.sh --exec` — Claude re-runs the dispatcher every 15 min while you work. Stop the loop when done. |
| **Human glance** | daily 4AI-panes use | Selector badge (planned, P5): per-project open-handoff counts + framework-version state, so the human sees pending Risk-C work without opening files. The badge also carries a `stall:<cli>` marker when a recipient with open handoffs has a missing/stale pane heartbeat — the glance-level twin of `fleet-health.sh`'s STALL verdict. |
| **Cockpit claim override** | a cockpit taking an `Auto: yes` handoff (pane down, quarantined, owner waiting live) | `bash .ai/tools/claim-handoff.sh <path>` — flips `Auto:` to `no` and takes a claim sidecar atomically, so the auto pane skips the item on its next poll; `release-handoff.sh` reverts ("claimed it, changed my mind"). |

**The `Auto:` tag is the ownership boundary (2026-07-13).** Two live instances
answer to every role — the auto pane (`pane-runner.ps1`) and the cockpit
(interactive chat) — and both can read the same `open/` file. `Auto: yes` +
Risk A/B is owned by the **auto pane**: a cockpit must not hand-take it.
`Auto: no`, or Risk C, is owned by the **cockpit** (human in the loop). The
claim override above is the ONLY legitimate way for a cockpit to take an
`Auto: yes` item — never just start working one, and never hand-edit `Auto:`
without a claim. Symmetric across all four CLIs; it degrades correctly during
a pane outage (panes down → claim → cockpit owns it legitimately).

A fourth mechanism watches the watchers (P6, 2026-07-13): `bash .ai/tools/fleet-health.sh`
cross-checks each pane's heartbeat sidecar (`.ai/.heartbeat-<cli>.json`, written
once per poll cycle by `pane-runner.ps1`) against its open queue and flags
`STALL` (queue with nobody watching) / `WEDGED` (polling but not picking up) /
`DOWN (idle)` (informational). Exit 1 on STALL/WEDGED so CI and hooks can gate;
fail-open on its own errors. Detection and alerting only — it never restarts a
pane. `stop-reminder.sh` surfaces STALL/WEDGED lines at every session end.

A `schedule` cron routine (out-of-session cloud dispatch) is deliberately NOT
configured — cloud runs cost money (Tier C) and the dispatcher needs local CLI
binaries. Revisit only if the fleet outgrows in-session polling.

**Failure alerting:** a headless dispatch that exits non-zero writes
`.ai/reports/dispatch-failure-<UTC>-<cli>.md` (command, exit code, output
tail) and leaves the handoff OPEN for retry. Failed dispatches are never
silent.

## Handoff file shape

Every handoff opens with a status block and follows the skeleton in `template.md`.
See `to-kimi/open/001-clarify-timestamp-semantics.md` or
`to-kiro/open/001-clarify-timestamp-semantics.md` for a live example.

## Timestamp convention

Timestamps in this framework — both in handoff `Created:` lines and in
`.ai/activity/log.md` entry headers — are **UTC+7 wall-clock time at the moment of
writing**, annotated `(UTC+7)`. For log entries this means *after the work is done*
(prepend time = finish time). Since CLIs may have different local clocks, timestamps
are annotations; **prepend order is the authoritative sequencing**.

On this Windows + Git Bash/MSYS host the local system clock is kept at UTC+7, so
use plain `date +'%Y-%m-%d %H:%M'` to produce a UTC+7 timestamp. Do **not** use
`TZ=Asia/Bangkok date` — MSYS interprets that override as UTC and will emit a
timestamp seven hours behind the wall clock.
