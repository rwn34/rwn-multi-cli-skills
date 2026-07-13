# Cockpit vs auto-pane handoff ownership — make the `Auto:` tag the claim boundary
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-13 09:50
Auto: no
Risk: B
Base: origin/master

## Problem (observed today, 2026-07-13)

A handoff is addressed to a **role** (`to-claude/`, `to-kimi/`), but two live
instances answer to that role: the **auto pane** (`pane-runner.ps1`) and the
**cockpit** (the interactive chat session). Both can read the same `open/` file.

This morning the Claude cockpit offered to take `to-claude/202607130206`
(activity-log rotation, `Auto: yes` / `Risk: B`) while the Claude auto pane was
up and polling the same queue — i.e. two claimants for one item. The owner
caught it and asked whether this is protocol or confusion. It's confusion, and
the fix is small because the machinery is already half-built.

## What already exists (do not rebuild)

- `tools/4ai-panes/pane-runner.ps1:594-596` — a pane picks up a handoff **only**
  if `Auto: yes` AND `Status: OPEN` AND `Risk: A|B`. Anything else is skipped.
- `.ai/handoffs/README.md` step 2b — Risk-C / `Auto: no` are never
  auto-dispatched; they are human-relayed.
- Per-project claim-lock (`.ai/.claim-<cli>.json`) and per-handoff claim
  sidecars (`.ai/handoffs/.claims/`, ADR-0009 §3) — pid + host + ts,
  crash-recoverable. These protect pane-vs-pane and pane-vs-dispatcher.

**The hole:** none of that protects against a *cockpit* that simply starts
working a handoff file without taking a claim. The cockpit is not a claim
participant. So the lock is bypassable by exactly the actor most likely to
bypass it (a human-driven session that "just does it").

## The rule to implement

> **The `Auto:` tag is the ownership boundary.**
> - `Auto: yes` + `Risk: A|B` → owned by the **auto pane**. A cockpit must not
>   take it.
> - `Auto: no`, or `Risk: C` → owned by the **cockpit** (human in the loop).
> - A cockpit that needs to take an `Auto: yes` handoff (pane down, quarantined,
>   owner waiting live) **must first flip it to `Auto: no` and take a claim** —
>   which makes the override explicit, race-free, and visible in git history.

This is symmetric across all four CLIs — it is not a Claude special case. The
kimi cockpit must not hand-take `Auto: yes` items out of `to-kimi/` while the
kimi pane is up, and the same for kiro/opencode.

It also degrades correctly during an outage: panes down → flip `Auto: no` →
cockpit owns it legitimately (this is precisely what the owner authorized ad-hoc
during last night's quarantine storm; this change makes that path a documented
mechanism instead of a verbal exception).

## Scope — what to build

1. **`.ai/tools/claim-handoff.sh <path-to-handoff>`** (new)
   - Refuses if the handoff is already `Status: DONE`/`BLOCKED`.
   - Refuses if a live claim sidecar for that handoff is held by another pid
     (reuse the existing staleness semantics in `pane-runner.ps1` — same-host
     dead pid = stale = reclaim; foreign host = trust only within the window).
     **Do not invent a second staleness policy; mirror the one that exists.**
   - On success: rewrites the `Auto:` line in place to `no`, writes a claim
     sidecar under `.ai/handoffs/.claims/` naming the claimant, and prints what
     it did.
   - Atomic (temp + rename), idempotent (re-claiming your own claim = no-op,
     exit 0), fail-closed (any ambiguity = refuse and explain, never silently
     take).
2. **`.ai/tools/release-handoff.sh <path>`** — the inverse (flip back to
   `Auto: yes`, drop the sidecar) for "I claimed it and changed my mind."
   Same safety bar.
3. **Docs** (`.ai/` is a shared lane — you may edit these):
   - `.ai/handoffs/README.md` — add the rule above to the "Polling — who watches
     the queues" section, plus a row in the lifecycle table.
   - `.ai/instructions/` SSOT — the operating-prompt handoff section gets the
     same one-liner. Keep it to a rule, not an essay.
4. **Tests** — `tools/4ai-panes/test-pane-runner.ps1` (or a sibling test file if
   that suite is the wrong home; your call, state it in the report):
   - A pane **skips** a handoff after `claim-handoff.sh` flipped it to `Auto: no`
     (drive the real `pane-runner.ps1` qualification path at :594-596, do not
     re-implement the predicate in the test).
   - `claim-handoff.sh` **refuses** a handoff already claimed by a live foreign
     pid; **reclaims** one held by a dead same-host pid.
   - Idempotency: claim twice = one sidecar, exit 0 both times, file unchanged
     on the second run.
   - `release-handoff.sh` restores `Auto: yes` and the pane picks it up again —
     i.e. prove the full round-trip, not just the flip.

## Explicitly NOT in scope (claude-code lane)

- `CLAUDE.md` / `AGENTS.md` contract text — Claude is custodian (ADR-0001).
  **Do not edit them.** Instead, put the exact proposed wording in your report
  and Claude will apply it.
- The ADR ratifying this rule — ADR authorship is Claude's lane. Claude will
  author it once your implementation is green.

## Verify (evidence required in the report — execution, not inspection)

- Full `test-pane-runner.ps1` run: paste the pass/fail counts.
- Paste the actual output of `claim-handoff.sh` on a scratch handoff: the
  refuse case, the reclaim case, and the idempotent case.
- Prove the pane skip with a real pane-runner qualification call, not a mock.
- `git diff --stat` of what you touched.

## Report back with

- Test counts (passed/failed) and the three `claim-handoff.sh` transcripts.
- Proposed verbatim wording for the `CLAUDE.md` / `AGENTS.md` line (Claude applies).
- Anything you'd change about the rule itself — if implementing it surfaces a
  case the rule handles badly, say so instead of coding around it.

## Completion (kimi-cli, 2026-07-13 10:10)

All scope items delivered on branch
`exec/kimi/202607130250-cockpit-pane-handoff-ownership` (worktree
`.wt/rwn-multi-cli-skills/kimi-ownership`). CLAUDE.md / AGENTS.md untouched per
the out-of-scope block — proposed verbatim wording is in the completion report
to claude-code.

**Built:**
- `.ai/tools/claim-handoff.sh` — flips `Auto:` → `no` + claim sidecar; atomic
  (O_EXCL create / temp+rename), idempotent, fail-closed. Staleness MIRRORS
  pane-runner.ps1 Test-HandoffClaimed exactly (same-host dead pid → reclaim;
  15-min window otherwise; unparseable ts → trusted; corrupt sidecar →
  reclaimable). One implementation note: pid-liveness uses `tasklist` — MSYS2
  `kill -0` cannot see native Windows pids (pane-runner/CLIs), which a first
  draft got wrong and the test suite caught (c4 went red).
- `.ai/tools/release-handoff.sh` — inverse; refuses to drop another actor's
  sidecar (fail closed), refuses terminal states.
- Docs: `.ai/handoffs/README.md` (Polling section rule + table row) — landed on
  the branch. The operating-prompt SSOT one-liner was DRAFTED and verified
  locally (sync-replicas + `check-ssot-drift.sh` → Drift 0 with all 3 replicas)
  but NOT committed by kimi: the ADR-0005 pre-commit policy requires SSOT
  source + all replicas atomically yet forbids non-claude committers the
  `.claude/`/`.kiro/` replica paths — a kimi-authored operating-prompt commit
  cannot go green. Routed, with the verbatim CLAUDE.md/AGENTS.md line, via
  `.ai/handoffs/to-claude/open/202607130316-auto-boundary-ssot-and-contract-wording.md`.
- Tests in SIBLING file `tools/4ai-panes/test-claim-handoff.ps1` — a sibling
  agent is concurrently extending `test-pane-runner.ps1`, so a separate file
  avoids the merge conflict; it dot-sources the real pane-runner.ps1 and drives
  the REAL `Get-QualifyingHandoff` (:594-596 gate), no predicate re-implementation.

**Test counts (executed, not inspected):**
- `tools/4ai-panes/test-claim-handoff.ps1` → **23 passed, 0 failed** (covers:
  real-gate pickup, claim, real-gate skip, live-foreign-pid refuse, dead-pid
  reclaim, idempotent double-claim, release round-trip through the real gate,
  DONE refused).
- `tools/4ai-panes/test-pane-runner.ps1` (existing suite) → **132 passed, 0
  failed** — no regression (baseline before changes was also 132/0).

**The three transcripts** (scratch sandbox, final binaries):

1. REFUSE — live foreign pid (powershell.exe pid=120364, alive) holds the claim:
   `claim-handoff: REFUSED: handoff is already claimed by owner='other-pane'
   pid=120364 host='E-NMP' at 2026-07-13T03:07:39Z (live/fresh). ...` → exit=1,
   `Auto: yes` untouched, sidecar still names other-pane.
2. RECLAIM — same sidecar after `Stop-Process` (pid dead, same host):
   `claim-handoff: reclaimed (stale sidecar overwritten): ... owner=kimi-cli
   pid=102327 host=E-NMP ... Auto: flipped to 'no'` → exit=0.
3. IDEMPOTENT — second claim: `claim-handoff: already claimed by kimi-cli on
   E-NMP and Auto: no — nothing to do.` → exit=0; handoff md5
   `5679c3b5…` identical before/after; exactly 1 sidecar.

**Round-trip:** `release-handoff.sh` → `sidecar removed` + `Auto: restored to
'yes'` → exit=0, and test c7d proves the REAL `Get-QualifyingHandoff` picks the
released handoff up again.

**Suggested rule refinement (the handoff asked):** the rule is sound; two gaps
surfaced (full detail in the completion report and the to-claude follow-up):
(1) `Risk: C` + `Auto: yes` reads ambiguously to a skimmer — recommend the ADR
state explicitly that Risk C is cockpit-owned regardless of `Auto:` (the pane
gate already enforces it; claim-handoff.sh is only needed for `Auto: yes` +
Risk A/B). (2) `pane-runner.ps1 Get-DefaultOwner` gives kimi/kiro/opencode the
SAME owner string a cockpit uses (only claude splits claude-auto/claude-code),
so a sidecar can't distinguish pane-vs-cockpit for 3 of 4 CLIs — consider a
`--owner <cli>-cockpit` convention.
