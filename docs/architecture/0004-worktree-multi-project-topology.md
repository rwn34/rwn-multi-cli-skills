# 4. Worktree + Multi-Project Topology for the Multi-CLI Framework

## Status

Accepted (2026-06-15)

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
