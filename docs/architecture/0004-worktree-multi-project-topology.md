# 4. Worktree + Multi-Project Topology for the Multi-CLI Framework

## Status

Accepted (2026-06-15)

Amended 2026-07-11 (owner-approved): worktree-per-CLI is **REQUIRED** for
dispatched handoff execution — no two CLIs may concurrently share a working tree
/ HEAD. See Amendment (2026-07-11) at the end of this file. The 2026-06-15
decision below described the worktree topology as the model for *executor*
parallelism but never bound the **dispatcher** to it; the amendment closes that
gap after a live near-miss.

## Context

- Each project is now worked by **≥4 CLIs concurrently** — Claude (architect/orchestrator) plus Kiro, Kimi, and Crush (executors).
- Executors need **independent working trees** so parallel edits never collide.
- We will not **fragment the source** — copying the source N times into per-CLI sandboxes is rejected up front.
- Claude must **hold the actual main** and be the sole integration authority.
- There are **multiple connected projects**, each running its own Claude orchestrator instance (separate working dir + process), which must **coordinate across a whitelist** without reaching directly into each other's trees.
- `.ai/tests/concurrency-test-protocol.md` (lines 204-206) already flagged the core hazard: with git worktrees, SSOT/coordination state lives in one worktree and the others see **stale copies** until pull/rebase. This ADR's coordination plane resolves that.

Full design rationale: `.ai/research/worktree-multi-project-topology.md`.

## Decision

Separate **where code is edited** from **where AIs coordinate** — a two-plane model.

| Plane | What | Mechanism |
|---|---|---|
| **Code plane** | Source edited by executors | Git **worktrees**, one per executor, on `exec/<name>/*` branches. A single shared `.git` object store gives independent trees with zero fragmentation. |
| **Coordination plane** | `.ai/` runtime state (activity log, handoffs, reports) + SSOTs | One **canonical `.ai/`** in the primary checkout; every worktree reaches it through a directory **junction**. One log, one queue, no per-branch divergence. |

**Layout (single project):**

```
~/Code/
  project-a/                  PRIMARY checkout. Branch: main. Claude orchestrator.
    .git/                     the one real object store (shared by all worktrees)
    .ai/                      CANONICAL coordination plane
    src/ ...
  .wt/project-a/              worktree container — SIBLING, outside the main tree
    kiro/   .ai -> junction   git worktree, branch exec/kiro/<task>
    kimi/   .ai -> junction   git worktree, branch exec/kimi/<task>
    crush/  .ai -> junction   git worktree, branch exec/crush/<task>
```

**Branch & merge flow — Claude holds main.** Claude writes a handoff to `.ai/handoffs/to-<exec>/open/`; the executor works only inside its own worktree on `exec/<name>/NNN-slug`, writes a completion handoff, and appends to the shared activity log via the junction. Claude reviews `git diff main..exec/<name>/NNN-slug` and is the **only** merger to main. Post-merge, executors `git rebase main` before the next task. Collision-free by construction: distinct working directory + distinct branch namespace per executor.

**Cross-orchestrator coordination — `.fleet/` tier.** A third plane one level up (`~/Code/.fleet/`) mirrors `.ai/` across projects: `registry.json` (the project whitelist + `talks_to` relationships), `handoffs/to-<project>/open/`, and a fleet-level `activity/log.md`. An orchestrator reads only `.fleet/handoffs/to-<self>/open/` and accepts a handoff **only if the sender is in its `talks_to` list**. Cross-project work is always a handoff, never a direct write into another project's tree. `.fleet/` is maintained as **its own small git repository** (for auditability), scaffolded idempotently by `scripts/fleet-init.sh`.

**Enforcement (hooks).** `pretool-write-edit.sh` (and Kiro/Kimi equivalents) gain two guards: **worktree confinement** (an executor may write only under its own worktree path plus the shared `.ai/`) and **fleet whitelist** (block writes to `.fleet/handoffs/to-X/` unless the current project's `talks_to` includes X).

### User-decided choices (with rejected alternatives)

1. **Pure junction of the whole `.ai/`** to the canonical copy.
   - *Rejected:* a `merge=union` git driver; and the hybrid variant (junction the runtime, track the SSOTs).
   - *Why:* one canonical `.ai/` means executors always read main's current SSOTs and write to one shared log/queue. Trade-off accepted — an executor mid-task sees SSOT changes from main immediately, which is desirable, not harmful.

2. **Sibling worktree location** at `~/Code/.wt/<project>/`.
   - *Rejected:* nested `<project>/.worktrees/`.
   - *Why:* nesting would be indexed 4× by CodeGraph/KiroGraph/KimiGraph, risk accidental commits, and confuse `pretool-write-edit.sh`. Sibling keeps the main tree clean.

## Consequences

- **Positive:** parallel executors never collide (distinct trees + branch namespaces).
- **Positive:** no source fragmentation — one shared `.git` object store.
- **Positive:** a single coordination log/queue across all executors of a project; no stale-SSOT divergence.
- **Positive:** clear integration authority — Claude is the sole merger to main, with one whitelist as the cross-project security boundary.
- **Negative / risk:** junctions must be re-established idempotently after `git worktree prune` or branch deletion (a bootstrap-script concern).
- **Negative / risk:** depends on Windows directory junctions (`mklink /J`); portability to other platforms is unaddressed here.
- **Negative / risk:** executors see SSOT changes from main mid-task (accepted trade-off, but a behavioral surprise to document for executor authors).
- **Negative / risk:** installer wiring and Kiro/Kimi hook parity for the new guards are still TODO (see Follow-ups).

## Follow-ups

From §7 of `.ai/research/worktree-multi-project-topology.md`:

- Reflect the worktree/fleet bootstrap in the installer (`tools/multi-cli-install/`) so adopters get it for free.
- Achieve Kiro/Kimi hook parity for the two new guards (via `.ai/handoffs/to-kiro|to-kimi/`).
- Add `.fleet/registry.json` schema validation plus a `fleet-status` helper. (The `.fleet/` scaffold itself is now provided by `scripts/fleet-init.sh`.)

## Open questions

Mirrors §8 of the research note:

- Junction durability across `git worktree prune` / branch deletion — the bootstrap script must re-establish junctions idempotently.

## References

- `.ai/research/worktree-multi-project-topology.md` — full design and rationale (source of truth)
- `.ai/tests/concurrency-test-protocol.md` § "Open questions" (lines 204-206) — the stale-worktree-SSOT hazard this ADR resolves
- `docs/architecture/0001-root-file-exceptions.md` — root-file policy, enforced by the same hook family
- `CLAUDE.md`, `AGENTS.md`, per-CLI steering files — single-project `.ai/` coordination model this topology extends
- `.claude/hooks/pretool-write-edit.sh` — enforcement point for the new worktree/fleet guards

## Amendment (2026-07-11): worktree-per-CLI is mandatory for dispatched execution

Owner-approved 2026-07-11. The original decision defined the worktree topology
and shipped a bootstrap for it (`scripts/wt-bootstrap.sh`), but left it optional
in practice: `.ai/tools/dispatch-handoffs.sh` launches every recipient CLI with
`( cd "$root" && ... )` — the **primary checkout**. Parallel dispatch therefore
runs N CLIs in **one working tree, on one git HEAD**. This amendment makes the
worktree a precondition of dispatch rather than a convention for executors.

### Context — the 2026-07-11 near-miss

Two Risk-A handoffs were dispatched in parallel (Kimi + Kiro, each syncing its
own steering replica of the operating-prompt SSOT §14). Both ran in the same
working tree. Reconstructed from the reflog:

1. Kiro branched `kiro/sync-operating-prompt-s14` off PR #39's tip and committed
   its replica (`07d97dc`).
2. Kimi branched `kimi/sync-operating-prompt-s14` **off Kiro's branch** — not off
   master — and committed its replica (`4c924ec`).
3. A `git checkout` moved HEAD back to Kiro's branch, which **reverted Kimi's
   file on disk**: Kimi's change existed only in a commit that was no longer
   checked out.
4. Kimi's handoff self-retired as `DONE` and its completion claim was *literally
   true* (its committed blob was byte-identical to the SSOT) while the working
   tree contradicted it. It briefly looked like a CLI had lied.

**Nothing was lost** — the work was recovered by cherry-picking onto a clean
master branch. It survived only because the three commits happened to be
**file-disjoint**. `git checkout` is a **process-global mutation** of the shared
tree: had two CLIs touched the same file, the loss would have been real, silent,
and — unlike a commit — **not in the reflog**. `.ai/activity/log.md` is the
obvious candidate: multiple CLIs prepend to it.

The only thing that detected the inconsistency was the SSOT drift gate
(`.ai/tools/check-ssot-drift.sh`), which fires **after** the fact and covers
**replicas only**. This is a smoke alarm, not a fire door.

This matters more now, not less: operating-prompt SSOT **§14 (delegation
economics)** makes parallel cross-CLI handoffs the *normal* case, raising
collision probability from "occasional" to "expected".

### Decision

**One git worktree per CLI is REQUIRED for dispatched handoff execution. No two
CLIs may concurrently share a working tree / HEAD.**

1. **The dispatcher owns the worktree lifecycle.**
   `.ai/tools/dispatch-handoffs.sh` MUST run each recipient CLI inside a worktree
   dedicated to that CLI, never in the primary checkout. It creates the worktree
   on demand (idempotently — an existing healthy worktree is reused, never
   destroyed) and is responsible for teardown policy. The primary checkout is
   reserved for the human-driven Claude orchestrator seat.
2. **Location: the existing `.wt/` container from this ADR's original decision** —
   `<parent>/.wt/<project>/<cli>/`, sibling to the repo, one directory per CLI,
   already implemented by `scripts/wt-bootstrap.sh` (worktree on `exec/<cli>/*`
   plus the `.ai/` junction). No new path convention is introduced and nothing
   is added to the repo root, so `docs/architecture/0001-root-file-exceptions.md`
   is unaffected.
   *Prior art considered and NOT reused:* `.claude/worktrees/agent-*` (gitignored,
   `.gitignore` line 110) — worktrees the Claude Agent tool creates for its own
   subagents. That path stays exactly as it is for Claude-internal subagent use.
   It is **not** adopted for cross-CLI dispatch: it is nested inside the repo,
   which §"User-decided choices" item 2 of this ADR explicitly rejected for
   shared-executor worktrees (4× graph indexing, accidental commits, hook-path
   confusion).
3. **Branches must be cut from a declared base.** Every dispatched CLI cuts its
   branch from an explicit base ref — `origin/master` unless the handoff names a
   different one — and never from "whatever HEAD happens to be". The incident's
   Kimi-off-Kiro's-branch cut is a **second, independent defect**: it is possible
   even *with* worktrees, and it silently entangles two unrelated handoffs'
   histories. A worktree fixes the shared-HEAD problem; only a declared base
   fixes this one.
4. **Scope.** This binds *dispatched* (headless, Auto+Risk-A/B) execution — the
   path that runs CLIs in parallel without a human watching. Interactive
   single-CLI work in the primary checkout is unchanged.

### Consequences

- **Dispatcher (`.ai/tools/dispatch-handoffs.sh`).** The `( cd "$root" && ... )`
  invocation becomes `cd <worktree-for-$cli>`. It gains worktree
  ensure/reuse/teardown logic and must fail the dispatch — loudly, with the
  handoff left `OPEN` — if the worktree cannot be established. Dispatching into
  the primary checkout is no longer an acceptable fallback: a silent degrade to
  shared-HEAD reintroduces exactly the failure this amendment exists to prevent.
- **Each CLI's `infra-engineer`.** Branch, commit, and push happen **inside that
  CLI's own worktree**, from the declared base. `git checkout` inside a worktree
  moves only that worktree's HEAD, so it can no longer revert another CLI's files
  on disk. Push-to-feature-branch remains Tier A; merge to main remains Tier C
  with Claude.
- **Branch topology.** `exec/<cli>/*` (or the handoff's named branch) cut from
  `origin/master`. Sibling-cut branches are a defect to be caught in review, not
  a style preference.
- **`.ai/activity/log.md` — the honest limit of this decision.** Worktrees are
  **not** a total fix, and this ADR does not claim they are.
  - For **code-plane** files (tracked, materialized per worktree), a worktree
    converts a *silent clobber* into an *honest merge conflict* at integration
    time. Two CLIs can still write conflicting versions of the same tracked file
    in separate trees — the win is that git now tells us, instead of one tree's
    checkout quietly discarding the other's work.
  - For the **coordination plane**, worktrees give **zero** isolation by design:
    this ADR junctions every worktree's `.ai/` to the one canonical `.ai/`, so
    `.ai/activity/log.md` is the *same file on disk* for all CLIs. Concurrent
    prepends remain a last-writer-wins race, exactly as before — see
    `.ai/known-limitations.md` § "Concurrent activity-log writes" (still
    uncharacterized; `.ai/tests/concurrency-test-protocol.md` is the open test).
    That race is **out of scope here and unmitigated by this amendment.** It is
    the highest-risk shared file in the framework and needs its own fix
    (append-only lease, per-CLI log shards, or a serialized writer).
- **Cost.** Each worktree is a full checkout of the tree (the `.git` object store
  is shared, so the marginal cost is working-tree size, not history). Bounded and
  accepted.
- **Positive.** Parallel cross-CLI dispatch — which §14 now mandates — becomes
  safe by construction for source files, rather than safe by luck of
  file-disjointness.

### Alternatives considered

- **(A) Serialized checkout lock in the dispatcher** — a mutex around the shared
  tree so only one CLI holds HEAD at a time. **Rejected:** it removes the
  cross-CLI parallelism that operating-prompt §14 just mandated, converting the
  fleet back into a queue. It also fails to solve anything worktrees don't solve
  better.
- **(B) Status quo + the drift gate as the safety net.** **Rejected:**
  `check-ssot-drift.sh` detects *after* the fire and only for SSOT replicas. The
  incident's own timeline is the argument — the gate found the inconsistency, but
  a same-file collision would have been invisible to it and absent from the
  reflog.
- **(C) Nested per-CLI worktrees under the repo (`.claude/worktrees/`-style).**
  **Rejected** on the grounds already recorded in this ADR (item 2 of
  "User-decided choices"): graph re-indexing, accidental-commit risk, hook-path
  confusion.

### Follow-ups

- **Implementation of the dispatcher change is a separate task, handed to Kiro.**
  This amendment is the decision only; `.ai/tools/dispatch-handoffs.sh` is
  unchanged as of this ADR landing (it still runs `cd "$root"`). Until that task
  lands, **parallel dispatch remains unsafe** and the orchestrator should serialize
  same-file-risk handoffs by hand.
- The activity-log write race (above) needs its own decision. Track it against
  `.ai/known-limitations.md` § "Concurrent activity-log writes".
- `tools/4ai-panes/pane-runner.ps1` runs the same headless invocations as the
  dispatcher and must be brought to parity, or it reintroduces the shared-HEAD
  path from the pane side.
