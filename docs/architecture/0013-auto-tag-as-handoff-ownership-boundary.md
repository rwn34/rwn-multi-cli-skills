# 13. The `Auto:` Tag Is the Handoff Ownership Boundary Between Cockpit and Auto Pane

## Status

Accepted (2026-07-13).

This ADR **extends ADR-0008** (the self-driving pane-runner and its claim-lock)
and **ADR-0009** (the operator-over-fleet topology that put a human cockpit and a
self-driving pane on the same queue). The tools that enforce the rule
(`.ai/tools/claim-handoff.sh`, `.ai/tools/release-handoff.sh`) are **live on
`main`** — they shipped in commit `8fb8bb3` *("feat(ai): make the `Auto:` tag
the cockpit-vs-pane handoff ownership boundary", kimi, handoff
`to-kimi/202607130250`)*, which also shipped `tools/4ai-panes/test-claim-handoff.ps1`
and the `.ai/handoffs/README.md` rule text. This ADR ratifies the rule and records
the doc/SSOT side of it.

## Context

A handoff is addressed to a **role** (`to-claude/`, `to-kimi/`), but since
ADR-0009 two live instances answer to that role: the **auto pane**
(`pane-runner.ps1`, headless, polling) and the **cockpit** (the interactive,
human-driven session). Both can read the same `open/` file.

The existing machinery protects pane-vs-pane, not cockpit-vs-pane:

- `tools/4ai-panes/pane-runner.ps1` `Get-QualifyingHandoff` (~:594-596) picks up a
  handoff only if `Auto: yes` AND `Status: OPEN` AND `Risk: A|B`.
- The per-project claim-lock and per-handoff claim sidecars (ADR-0008 guardrails,
  ADR-0009 §3) arbitrate between claim participants.

**The hole:** a cockpit is not a claim participant. It can simply start working a
handoff file without taking a claim, so the lock is bypassable by exactly the
actor most likely to bypass it — a human-driven session that "just does it."
Observed 2026-07-13: the Claude cockpit offered to take `to-claude/202607130206`
(`Auto: yes` / `Risk: B`) while the Claude auto pane was up and polling the same
queue. Two claimants, one item — duplicate work and racing commits.

## Decision

**The `Auto:` tag is the ownership boundary between cockpit and auto pane.**

1. `Auto: yes` + `Risk: A|B` → owned by the **auto pane**. A cockpit must not
   hand-take it.
2. `Auto: no`, or `Risk: C` → owned by the **cockpit** (human in the loop).
3. A cockpit that must take an `Auto: yes` handoff (pane down, quarantined, owner
   waiting live) takes it **only** by first running
   `bash .ai/tools/claim-handoff.sh <path>`, which atomically flips the file to
   `Auto: no` and writes a claim sidecar. `release-handoff.sh` reverts both. The
   override is thereby explicit, race-free, and visible in git history.
4. The rule is **symmetric across all four CLIs** — not a Claude special case. A
   kimi cockpit must not hand-take `Auto: yes` items out of `to-kimi/` while the
   kimi pane is up, and likewise for kiro and opencode.

**Explicit scope of the claim step (stated because the `Auto:` line alone reads
ambiguously to a skimmer):** `claim-handoff.sh` is required **only** for
`Auto: yes` + Risk A/B. **Risk C is cockpit-owned regardless of its `Auto:`
value and needs no claim** — the pane gate at `pane-runner.ps1:596` already
refuses any handoff that is not `Risk: A|B`, so a `Risk: C` + `Auto: yes` handoff
is never a pane candidate and there is nothing to claim it away from.

The rule also degrades correctly during an outage: panes down → claim (flip
`Auto: no`) → the cockpit owns it legitimately. That is precisely the path the
owner authorized ad-hoc during the 2026-07-12 quarantine storm; this decision
turns a verbal exception into a documented, enforced mechanism.

## Known limitation — owner-string collision (3 of 4 CLIs)

`pane-runner.ps1 Get-DefaultOwner` (:912-921) maps `claude`→`claude-auto`,
`kimi`→`kimi-cli`, `kiro`→`kiro-cli`, `opencode`→`opencode`. For kimi, kiro and
opencode those are **the same identity strings a human cockpit naturally uses**,
so a claim sidecar **cannot distinguish pane from cockpit** for three of the four
CLIs. Only Claude splits the identities (`claude-auto` pane vs `claude-code`
cockpit), per ADR-0009 §2.

Both tools accept `--owner`. The recommended convention is `<cli>-cockpit` for a
cockpit-initiated claim. Pinned here so a future change does not silently break
it: `claim-handoff.sh`'s idempotent no-op is keyed on **owner + host + `Auto:`
already `no`** — a re-run is a fresh process, so pid cannot serve as identity.
That is safe today only because a cockpit re-claiming its own handoff matches on
owner+host; if owner strings are ever made ambiguous *in the other direction*
(e.g. a pane and cockpit sharing a string on one host), idempotency and refusal
would both misjudge. Resolving the collision is a follow-up, not a blocker.

## Consequences

### Positive

- The double-claimant race is closed at its actual entry point — the cockpit —
  rather than only between claim participants.
- The outage path (pane down → cockpit takes over) is now a mechanism with an
  audit trail (`Auto:` flip in git history + claim sidecar) instead of a verbal
  exception.
- Symmetry: one rule, four CLIs, no per-CLI special cases to remember.

### Negative

- One extra step for a cockpit that legitimately needs an `Auto: yes` handoff.
  Accepted: the step is a single command and it is the thing that makes the
  override visible.
- The owner-string collision above means the sidecar's *provenance* signal is
  weaker than its *exclusion* signal for kimi/kiro/opencode until the
  `<cli>-cockpit` convention is adopted.

### Neutral

- The rule now lives in the SSOT `.ai/instructions/operating-prompt/principles.md`
  §7 and its three replicas (`.claude/skills/operating-prompt/SKILL.md`,
  `.kimi/steering/operating-prompt.md`, `.kiro/steering/operating-prompt.md`),
  and as a one-line contract statement in `CLAUDE.md` and `AGENTS.md`.
  `.ai/handoffs/README.md` carries it in the polling section and lifecycle table.
- No change to the pane gate itself — `Get-QualifyingHandoff` already implements
  the pane side of this boundary. The decision adds the cockpit side.

## Evidence (executed, not inspected)

- `tools/4ai-panes/test-claim-handoff.ps1` — **23 passed, 0 failed**. Drives the
  real `Get-QualifyingHandoff` gate (no re-implemented predicate); covers
  real-gate pickup, claim, real-gate skip, live-foreign-pid refuse, dead-pid
  reclaim, idempotent double-claim, release round-trip, DONE refused.
- `tools/4ai-panes/test-pane-runner.ps1` — **132 passed, 0 failed**, identical to
  the pre-change baseline: no regression.

## Verification notes

- The enforcement tools are on `main`, verified with git (authoritative,
  junction-independent): `git ls-tree --name-only origin/main .ai/tools/` lists
  both `.ai/tools/claim-handoff.sh` and `.ai/tools/release-handoff.sh`. The landing
  commit `8fb8bb3` is contained in both `main` and `origin/main`. Both scripts
  are present and executable on disk (10707 B / 4990 B) and byte-identical to the
  `origin/main` blobs.
- **Junction gotcha — read this before you "verify" any `.ai/**` claim.** In a
  worktree, `.ai/` is a *directory junction* into the primary worktree. Path-glob
  tools (Glob/Grep and anything walking the filesystem) **do not traverse it** and
  will report "no matches" for files that plainly exist. Verify `.ai/**` claims
  with git (`git ls-tree`, `git log`, `git cat-file`), never with a path glob. A
  glob miss under `.ai/` is a tool artifact, not evidence of absence.

## Follow-ups

- **Amend ADR-0009** to cross-reference this boundary: ADR-0009 §2 introduced the
  `claude` / `claude-cockpit` identity split and §3 the claim sidecars, but it
  predates the cockpit-side rule and still reads as though the claim-lock alone
  arbitrates the queue. It should point at this ADR for the cockpit half, and at
  the owner-string collision above (which affects kimi/kiro/opencode sidecar
  provenance).

## References

- `docs/architecture/0008-self-driving-fleet-pane-runner.md` — the pane-runner,
  the `Auto:`/`Risk:` dispatch gate, and the per-project claim-lock.
- `docs/architecture/0009-operator-over-fleet-topology.md` — the cockpit/auto-pane
  topology and the `claude` / `claude-cockpit` identity split; §3 claim sidecars.
- `.ai/instructions/operating-prompt/principles.md` §7 — the rule as written in
  the SSOT.
- `.ai/handoffs/README.md` — polling / who-watches-the-queues, lifecycle table.
- `.ai/handoffs/to-kimi/done/202607130250-cockpit-pane-handoff-ownership.md` — the
  implementation this ADR ratifies (transcripts, test counts).
- `tools/4ai-panes/pane-runner.ps1` — `Get-QualifyingHandoff` (~:594-596),
  `Get-DefaultOwner` (:912-921).
