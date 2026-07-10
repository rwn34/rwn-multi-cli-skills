# 8. Self-Driving Fleet — The Pane-Runner (P1 Keystone)

## Status

Accepted (owner-approved 2026-07-09)

Extended by ADR-0009 (operator-over-fleet — 5-pane topology, auto-Claude
reviewer, and Claude-to-Claude claim-lock coordination).

This ADR realizes ADR-0007's **P1** — "Visible per-pane dispatch (Approach A),
cwd / multi-tab-scoped, with a per-project claim-lock" — and elevates it from
"nice UX" to the framework's operating spine. It sits on top of ADR-0004 (the
worktree / `.fleet/` multi-project tier) and reuses the headless dispatch logic
already proven in `.ai/tools/dispatch-handoffs.sh` (ADR handoff protocol v2). It
bundles three items from `.ai/research/framework-improvement-backlog.md`:
§5 (auto-continuation + auto-handoff-execution), §1 (handoff claim-lock), and
§7 (concurrency safety of shared `.ai/` files).

## Context

The single largest daily friction the owner reported after ~3 months running
the fleet across ~7 concurrent projects is that **the human is the relay**. Two
manual actions dominate the loop:

- Typing **"continue"** to push a CLI past a step/tool cap — Kimi is the acute
  case, pausing at its ~100-step multi-step limit mid-task.
- Typing **"check and execute handoff"** to make the next CLI pick up work the
  previous one queued for it.

This directly contradicts the framework's own principle — *"the human is a gate,
not a relay"* (operating-prompt SSOT §8 autonomy tiers). The 4-pane launcher
(`tools/4ai-panes/Selector.ps1`) today opens each pane as a **bare interactive
CLI** the owner types into. Nothing drives the panes; the owner does.

Two facts constrain any fix:

- **Windows Terminal has no send-keys / input-injection API.** You cannot type
  "continue" into a live pane programmatically. `dispatch-handoffs.sh` already
  documents this and works around it by launching **one-shot headless
  instances** rather than driving the interactive session (see its Design
  notes header).
- **State lives in files, not sessions.** Handoffs (`Status:` + `open/`→`done/`
  moves), the activity log, and the repo itself are the durable memory. A fresh
  headless process reconstructs full context by reading them — no live session
  needs to survive.

Two latent bugs observed on 2026-07-09 make the guardrails non-optional:

- **Double-processing race (backlog §1):** two Kiro instances grabbed the same
  `open/` handoff at 13:58 and 14:02 — an `open/` handoff being actively worked
  is indistinguishable from an untouched one.
- **Activity-log clobber (backlog §7):** two CLIs wrote the activity-log header
  concurrently and one overwrote the other's entry.
  `.ai/tests/concurrency-test-protocol.md` exists but has **never been run**.

A self-driving fleet writing to shared `.ai/` state across ~28 sessions
(~7 tabs × 4 CLIs) amplifies both. They must be fixed *inside* this build, not
after it.

## Decision — the pane-runner

Each pane launches a **supervisor loop**, not a bare CLI:

```
tools/4ai-panes/pane-runner.ps1 <cli> <projectDir>
```

`Selector.ps1` is rewired so each pane's launch command becomes the runner for
its CLI instead of the raw `$cliDefs[...].cmd`. The runner is a visible,
per-pane state machine:

### IDLE

Poll `<projectDir>/.ai/handoffs/to-<cli>/open/` every ~10s for handoffs marked
`Auto: yes` **and** `Risk: A|B`. **The poll is a filesystem check — zero tokens,
no CLI invocation.** Risk-C (or a missing Risk line) never auto-runs; it waits
for the human gate. This mirrors `dispatch-handoffs.sh`'s existing status-block
gate (`Auto: yes` + `Status: OPEN` + `Risk: [AB]`).

### RUNNING

On a new qualifying handoff:

1. Write a **claim marker** (see Guardrails — claim-lock).
2. Print a visible banner naming project + CLI + handoff.
3. Run the CLI **headless as a blocking child**, streaming output to the pane so
   the owner sees the work happen. The per-CLI headless invocation is the one
   already mapped in `dispatch-handoffs.sh`'s `headless_cmd`:
   - `kimi -p "<prompt>"`
   - `kiro-cli chat --no-interactive --trust-all-tools --agent orchestrator "<prompt>"`
   - `opencode run --auto --agent opencode "<prompt>"`
   - `claude -p "<prompt>" --permission-mode acceptEdits`

The loop is **blocked on the child** for the duration — no polling, no
re-sending, no second dispatch while work is in flight.

### DECIDE (on child exit)

Inspect the durable done-signal: **did the handoff move to `done/`?**

- **YES** → the CLI reported completion (Status: DONE + move to `done/`, per the
  handoff protocol). Release the claim, return to IDLE.
- **NO** → the handoff is still `OPEN`, meaning the CLI hit its step/tool cap
  before finishing. **AUTO-CONTINUE:** re-invoke the CLI headless with a
  "continue processing handoff X" prompt, increment a per-handoff continue
  counter, up to **MAX** (default 5). At MAX, print an **ALERT** banner, stop,
  and wait for the human.

**Step-cap detection needs no output-scraping** — "handoff still `OPEN` after
the run" is the signal. This is the same inference `dispatch-handoffs.sh` relies
on when it notes re-runs "skip them once they leave OPEN state."

### Chaining is emergent

When a CLI finishes and writes a **follow-up handoff** to another CLI's queue,
*that* CLI's pane-runner picks it up on its next IDLE poll. Work flows
**Claude → Kimi → Kiro → OpenCode** automatically and visibly, each pane
watching only its own inbox. No central conductor — the queues are the wiring.

## Why it works (state lives in files, not sessions)

- **"Continue" = re-invoke headless** with the handoff as context. The CLI reads
  the handoff, the activity log, and the repo fresh on each run — there is no
  live session to keep alive and no input to inject. This is *why* the design
  uses fresh headless processes rather than fighting Windows Terminal's missing
  send-keys API.
- **Done-signal = the existing handoff protocol** (Status: DONE + move to
  `done/`). No new completion mechanism.
- **Step-cap detection = "handoff still OPEN after the run"** — no fragile
  output pattern-matching.

## Guardrails (load-bearing)

- **MAX-continues cap** (default 5) + **real done-signal** — together they
  prevent both runaway credit burn and infinite loops. The cap is a cost
  control, not a nicety (backlog §5, §6).
- **Per-project CLAIM-LOCK (backlog §1):** before RUNNING, write a marker file
  under *that project's* `.ai/` carrying `project + cli + pid + timestamp`. Skip
  the handoff if a **fresh claim by a LIVE pid** already exists; **reclaim** if
  the recorded pid is dead (crash recovery). This closes the double-processing
  race two Kiro instances hit at 13:58/14:02. It is the same claim-lock backlog
  §1 Option B recommends — built once, serving both this ADR and the future
  handoff-protocol-v3 work.
- **Risk-C gate honored** — deploys, merges, publishes, and destructive or
  ADR-touching handoffs never auto-run (operating-prompt SSOT §8 Tier C). The
  runner only ever dispatches Risk-A|B, exactly like `dispatch-handoffs.sh`.
- **Visible + interruptible:** a banner shows `auto-continuing (n/MAX)`; a
  keypress **pauses the loop and drops to the interactive CLI** (manual
  override / escape hatch); Ctrl-C stops the runner.
- **Token-cost model:** idle poll is **free** (disk only). Tokens are spent only
  on real handoff runs — the same spend as manual dispatch — plus at most MAX
  auto-continues, which is the *only* new cost and is capped.

## Multi-tab / multi-project scoping

The owner runs ~7 tabs = ~28 sessions. Scoping rules:

- Each runner keys off **its own pane's cwd** (the project) and polls **only that
  project's relative `.ai/`** — never a global or hard-coded path.
- The **claim-lock is per-project** (marker under that project's `.ai/`), so two
  projects never contend.
- **No single-global-project assumption.** Cross-project coordination stays in
  the ADR-0004 `.fleet/` tier; the pane-runner is strictly intra-project.
- The banner names **project + CLI** so ~28 concurrent panes stay legible.
- A **gentle poll interval** (~10s) keeps ~28 filesystem-only loops cheap.

## Concurrency safety (backlog §7 — REQUIRED)

Because self-driving amplifies the two observed 2026-07-09 races, this build
**MUST** ship, not defer:

- An **atomic prepend-only activity-log write** (lockfile or atomic
  temp-file + rename) so concurrent CLIs cannot clobber the header or each
  other's entries.
- The **per-project claim-lock** above for handoff pickup.
- An actual **run of `.ai/tests/concurrency-test-protocol.md`** — the protocol
  exists but has never been executed; shipping self-driving without exercising
  it would knowingly risk corrupting shared state.

## Consequences

- **Each pane becomes a supervised worker.** You give work by writing handoffs,
  not by typing into panes — with a keypress manual-override escape hatch
  preserved.
- **Reuse, not reinvention.** The per-CLI headless command mapping, the
  Auto/Risk status-block gate, and the "OPEN after run = incomplete" inference
  all come straight from `dispatch-handoffs.sh`. The runner is that logic moved
  from a one-shot dispatcher into a persistent per-pane loop.
- **Three backlog items land together:** §5 (auto-continue + auto-handoff), §1
  (claim-lock), §7 (concurrency safety). Backlog §3 (session restore /
  multi-select) is a *separate* launcher enhancement but shares the same
  `Selector.ps1` surface, so it bundles naturally with this work.
- **Installer + launcher wiring required.** The framework installer must ship
  `pane-runner.ps1`, and `Selector.ps1` must be updated so each pane launches
  the runner rather than the bare CLI. Until both land, the fleet is not
  self-driving.
- **New cost surface, capped.** Auto-continue introduces the framework's first
  unattended token spend. The MAX cap and the Risk-C gate are the two controls;
  backlog §6 (cost/usage observability) becomes the natural next risk to close.
- **ADR-0007 P1 is realized** — the launcher moves from panes-you-type-into to a
  self-driving fleet, which the owner identified as "what makes the framework
  feel finished."

## References

- `docs/architecture/0004-worktree-multi-project-topology.md` — the `.fleet/`
  cross-project tier this ADR stays inside of (per-project scoping).
- `docs/architecture/0007-target-architecture-and-roadmap.md` — P1 that this ADR
  realizes; headless-by-default posture the runner depends on.
- `.ai/research/framework-improvement-backlog.md` — §1 (claim-lock), §3 (session
  restore, bundled), §5 (auto-continuation / auto-handoff — the keystone),
  §7 (concurrency safety).
- `.ai/tools/dispatch-handoffs.sh` — the existing headless dispatch logic
  (per-CLI `headless_cmd`, Auto/Risk status gate, "OPEN after run" inference)
  the runner reuses.
- `tools/4ai-panes/Selector.ps1` — the launcher whose pane command becomes the
  runner.
- `.ai/tests/concurrency-test-protocol.md` — the never-run protocol this build
  must execute.

## Note (2026-07-09): handoff protocol v3 alignment

The cross-CLI handoff protocol was bumped from v2 to v3 today. Under v3 the
**recipient self-retires** its own handoff — it sets the file's status to
`DONE` and moves it from `.ai/handoffs/to-<recipient>/open/` to `.../done/`
itself (lifecycle step 4, "Report + self-retire") — and the **sender validates
post-hoc** (step 5), whereas in v2 the sender moved the file only after
validating. Recipient-self-retire is therefore now the standard handoff-close
mechanism across all four CLIs. This is consistent with this ADR's DECIDE /
auto-continuation directive, where the done-signal is precisely "the handoff
moved to `done/`" — the recipient closing its own loop is exactly the behavior
the self-driving pane-runner already depends on to distinguish a completed run
from a step-capped one. See `.ai/handoffs/README.md` "Protocol v3 (lifecycle of
a single handoff) — 2026-07-09", steps 4–5.
