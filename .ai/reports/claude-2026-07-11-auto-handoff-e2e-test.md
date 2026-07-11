# Auto-handoff delivery loop — end-to-end validation report

- **Author:** claude-code
- **Date:** 2026-07-11
- **Branch / worktree:** `claude/auto-handoff-e2e-report` (isolated agent worktree)
- **Method:** read + throwaway only. Real CLIs masked off `PATH` (`PATH=/usr/bin:/bin`)
  so `dispatch-handoffs.sh` prints its selection instead of launching. Where the
  claim-lock code path had to be reached (it sits *after* the `command -v <bin>`
  gate), a harmless **stub** `claude` was placed on PATH — it only echoes and
  exits 0, it is not the real CLI and spawns nothing.
- **Throwaways:** `999999999999-throwaway-valid.md` (Auto:yes Risk:B OPEN) and
  `999999999998-throwaway-done.md` (Status:DONE-in-open), plus claim sidecars and
  the debounce stamp. All removed; `grep -rl 999 .ai/handoffs/` returns nothing,
  `.claims/` is back to README-only, `to-claude/open/` (created for the test,
  absent at start) removed, `git status` clean.

Scripts under test (all on master, present in this worktree):
`.ai/tools/dispatch-own-queue.sh`, `.ai/tools/dispatch-handoffs.sh`,
`.ai/tools/reconcile-done-handoffs.sh`, plus the `.kimi/` and `.kiro/`
SessionStart wiring.

---

## Area 1 — `dispatch-own-queue.sh` (Claude's SessionStart auto-dispatcher)

**Tested:** recursion guard, empty-queue fast-exit, 5-min debounce, and that a
valid Auto:yes+OPEN+Risk-A/B to-claude handoff makes it invoke
`dispatch-handoffs.sh --exec --only claude`.

Observed:

```
### 1a RECURSION GUARD (AI_HANDOFF_DISPATCH=1) — expect silent no-op
exit=0  (empty output above == pass)

### 1d VALID HANDOFF PRESENT + PATH masked
[dispatch-own-queue] auto-dispatchable to-claude handoff found: .ai/handoffs/to-claude/open/999999999999-throwaway-valid.md
[dispatch-own-queue] running: dispatch-handoffs.sh --exec --only claude
SKIP  [claude] .ai/handoffs/to-claude/open/999999999999-throwaway-valid.md — 'claude' not on PATH
exit=0

### 1c DEBOUNCE — immediate second run
[dispatch-own-queue] debounced (ran <5min ago); skipping auto-dispatch.
exit=0

### 1b EMPTY-QUEUE FAST-EXIT — handoff moved aside
exit=0 (empty output == pass)
stamp written? NO-correct
```

- Recursion guard (`AI_HANDOFF_DISPATCH=1` → silent `exit 0`): **PASS**.
- Empty-queue fast-exit — exits *before* writing the debounce stamp, so an empty
  queue never burns the 5-min window: **PASS** (nice property — a debounce is only
  spent when there was real work to dispatch).
- Debounce — second immediate run short-circuits with the `debounced` message:
  **PASS**.
- Valid-candidate selection → invokes `dispatch-handoffs.sh --exec --only claude`,
  which (real CLI masked) correctly resolves to the throwaway and reports it would
  dispatch: **PASS**.

**Verdict: PASS.**

---

## Area 2 — `dispatch-handoffs.sh` (`--exec --only` scoping, claim-lock, recursion export, C3 reconcile-first)

**Tested:** `--only <cli>` scoping, per-handoff claim acquire/release, the
`AI_HANDOFF_DISPATCH=1` export into the spawned child, and that
`reconcile-done-handoffs.sh` runs *first*. Also the Risk gate and Auto:no.

Observed (reconcile-first + `--only claude`, with a DONE-in-open present):

```
--- open before: 999999999998-throwaway-done.md   999999999999-throwaway-valid.md
reconcile-done: moved .../to-claude/open/999999999998-throwaway-done.md -> done/ (Status:DONE was left in open/)
SKIP  [claude] .ai/handoffs/to-claude/open/999999999999-throwaway-valid.md — 'claude' not on PATH
--- open after: 999999999999-throwaway-valid.md
```

The `reconcile-done` line prints **before** the selection line — reconcile is the
first thing `--exec` does (C3): **PASS**.

`--only kimi` scoping (no to-claude output, only the empty to-kimi queue is
considered): **PASS**.

```
### 2b --only kimi scoping
No open handoffs marked 'Auto: yes'.
```

Claim acquire + release around a stubbed dispatch:

```
--- claims before: none
DISPATCH [claude] .../999999999999-throwaway-valid.md
[stub-claude] claim sidecars present during my run:
    .ai/handoffs/.claims/claude__999999999999-throwaway-valid.claim.json
---- [claude] finished (exit 0) ----
--- claims after (should be released/none): none
```

Sidecar exists *during* the child run and is deleted after — acquire→run→release
is correct: **PASS**.

Recursion-guard export into the child:

```
### 2c RECURSION-GUARD EXPORT
DISPATCH [claude] .../999999999999-throwaway-valid.md
[stub-claude] AI_HANDOFF_DISPATCH in my env = '1'
```

The spawned child inherits `AI_HANDOFF_DISPATCH=1`, so its own SessionStart hook
would no-op — no fork-bomb: **PASS**.

Risk gate + Auto flag (defense-in-depth):

```
### Risk-C HOLD
HOLD  [claude] .../999999999999-throwaway-valid.md — Risk C or no Risk field (human relays)
### Auto:no
No open handoffs marked 'Auto: yes'.
```

Risk:C is held for a human; Auto:no is not dispatched: **PASS**.

**Verdict: PASS.**

---

## Area 3 — `reconcile-done-handoffs.sh` (C3 self-heal)

**Tested:** a `Status: DONE` handoff left in `open/` gets moved to `done/`.

Observed (standalone):

```
reconcile-done: moved ./.ai/handoffs/to-claude/open/999999999998-throwaway-done.md -> done/ (Status:DONE was left in open/)
exit=0
open now: 999999999999-throwaway-valid.md
done has probe? 999999999998-throwaway-done.md
```

The DONE-in-open stray moves to `done/`; the OPEN handoff is untouched. Also
exercised inside the full chain (Area 5 run) — same result. Idempotent and
fail-open (exit 0 by contract): **PASS**.

**Verdict: PASS.**

---

## Area 4 — Kimi + Kiro SessionStart inbox+dispatch wiring

**Kiro — full loop, PASS.** `.kiro/hooks/guards.json` wires a SessionStart hook:

```
"name": "dispatch-own-queue",
"trigger": "SessionStart",
"action": { "type": "command", "command": "bash .kiro/hooks/dispatch-own-queue.sh" }
```

and `.kiro/hooks/dispatch-own-queue.sh` lists `to-kiro/open` *and* dispatches its
own queue: `bash .ai/tools/dispatch-handoffs.sh --exec --only kiro`. It carries
the same recursion guard (`AI_HANDOFF_DISPATCH` → no-op) and relies on the shared
claim-lock. Structurally identical to Claude's path. **Loop closed for Kiro.**

**Kimi — reminder only, does NOT dispatch. GAP.** `.kimi/config.toml` wires a
SessionStart hook, but to the *reminder* script, not a dispatcher:

```
[[hooks]]
event = "SessionStart"
command = "bash .kimi/hooks/handoffs-remind.sh"
```

`.kimi/hooks/handoffs-remind.sh` only *lists* qualifying handoffs and prints the
command as text (`Process with: bash .ai/tools/dispatch-handoffs.sh --exec --only
kimi`) — it never executes it. The Stop hook `handoff-queue-count.sh` likewise
only prints counts + the command string. A tree-wide grep confirms no Kimi hook
runs `dispatch-handoffs.sh --exec`:

```
.kimi/hooks/handoffs-remind.sh:40:    echo "Process with: bash .ai/tools/dispatch-handoffs.sh --exec --only kimi"
.kimi/hooks/handoff-queue-count.sh:30:        echo "  bash .ai/tools/dispatch-handoffs.sh --exec   # or --only kimi"
```

So Claude and Kiro have an always-on unattended auto-delivery path for their own
queue; **Kimi does not.** An Auto:yes Risk-A/B `to-kimi` handoff is auto-delivered
only if (a) a live 4AI pane-runner picks it up, (b) an operator runs the bare
dispatcher, or (c) an interactive Kimi session reads the reminder and runs the
printed command by hand. Headless/unattended, a `to-kimi` handoff can sit in
`open/` indefinitely. **This is the one place the loop is asymmetric.**

**Verdict: Kiro PASS, Kimi GAP.**

---

## Area 5 — Claim coordination (a live foreign claim blocks a second consumer)

**Tested:** a LIVE per-handoff claim by "another consumer" makes a second dispatch
skip; a STALE (dead-pid) claim is reclaimable.

Live foreign claim (owner `kimi-cli`, real live pid, same host):

```
### 5a LIVE FOREIGN CLAIM held by pid=661 host=E-NMP
SKIP  [claude] .../999999999999-throwaway-valid.md — live claim held by another consumer
--- foreign claim still present (not stolen)? YES-correct
```

Dispatch skipped the handoff and did **not** delete the foreign claim: **PASS**.

Same claim, pid rewritten to a dead pid → stale → reclaimable:

```
### 5a-followup: pid now DEAD -> claim is stale -> dispatch reclaims + runs stub
DISPATCH [claude] .../999999999999-throwaway-valid.md
[stub-claude] invoked (no real CLI spawned)
--- claim after (released): none
```

Stale claim reclaimed, child ran, claim released: **PASS**. The staleness model
(live = mtime < 15 min AND same-host pid alive) behaves as documented in
`.ai/handoffs/.claims/README.md`.

**Verdict: PASS.**

---

## Silent-drop analysis

Where could the loop silently lose a handoff?

1. **Kimi's own queue has no unattended dispatcher (Area 4).** This is the real
   silent-drop surface: a `to-kimi` Auto:yes Risk-A/B handoff is not auto-executed
   by any always-on path. It is not *lost* (it stays OPEN and is listed at the next
   Kimi SessionStart), but it is not *delivered* without a human, a live pane, or an
   interactive Kimi acting on the reminder. Claude and Kiro do not share this gap.
2. **Claim release is unconditional on child exit.** `dispatch-handoffs.sh` does
   `rm -f "$claim"` after the child returns regardless of exit code. That is correct
   for this design (a failed child leaves the handoff OPEN and a failure report is
   written, so the next `--exec` retries), but it means the claim never lingers to
   signal "in progress after crash." Acceptable given the retry-on-OPEN model — noted
   as a design choice, not a defect.
3. **Debounce is per-worktree, keyed to a single stamp file.** Two Claude sessions
   in *different* worktrees have independent stamps and `.claims/` dirs, so the
   cross-consumer guard is the claim-lock, not the debounce — which is exactly the
   division of labor intended. No drop, but worth remembering the debounce is a
   local rate-limiter, not a global one.

No path was found where a `to-claude` or `to-kiro` handoff is silently dropped: the
reconcile-first + OPEN-gate + claim-lock + retry-on-OPEN chain is coherent.

## Overall verdict

**The auto-handoff delivery loop is trustworthy for unattended operation for the
Claude and Kiro queues.** All guardrails behaved exactly as designed: recursion
guard, empty-queue fast-exit, debounce, `--only` scoping, reconcile-first (C3),
per-handoff claim acquire/skip/release, stale-claim reclaim, and the Risk/Auto
gates all PASS. The only material gap is that **Kimi's SessionStart reminds but
does not dispatch its own queue**, so `to-kimi` auto-handoffs lack an always-on
unattended delivery path that Claude and Kiro both have.

**Residual risks / recommendation:**
- Close the Kimi gap by giving `.kimi/` a `dispatch-own-queue.sh` equivalent (or
  swapping the SessionStart hook target from `handoffs-remind.sh` to a dispatcher
  that runs `dispatch-handoffs.sh --exec --only kimi`, guarded by
  `AI_HANDOFF_DISPATCH` exactly like Claude's and Kiro's). Until then, `to-kimi`
  auto-handoffs depend on a live pane-runner or a human.
- The headless invocation strings (`headless_cmd`) were **not** executed against
  real CLIs here (masked by design). Their flag correctness is asserted by comments,
  not exercised by this test — a CLI version bump that changes a flag (kiro's
  `--trust-all-tools`/`--agent`, kimi's `-p`) would break dispatch and is the first
  thing that breaks if a provider updates. Re-validate `headless_cmd` after any CLI
  upgrade.
