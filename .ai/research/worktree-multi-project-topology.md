# Worktree + multi-project topology for the multi-CLI framework

**Status:** design, accepted (user decisions captured 2026-06-15) — pre-implementation
**Author:** claude-code orchestrator
**Supersedes/extends:** the single-project `.ai/` coordination model in `CLAUDE.md`,
`AGENTS.md`, and the per-CLI steering files. Companion ADR:
`docs/architecture/0004-worktree-multi-project-topology.md` (renumbered from 0002
on 2026-07-08 — the 0002 slot was already taken by `0002-cli-role-topology.md`).

## 1. Problem

Each project is now worked by ≥4 CLIs concurrently — Claude (architect/orchestrator),
Kiro, Kimi, Crush (executors). Requirements:

1. Executors must run in **independent working trees** so parallel edits never collide.
2. No **fragmentation** — we will not copy the source N times into per-CLI sandboxes.
3. Claude must **hold the actual main** (sole integration authority).
4. There are **multiple connected projects**, each with its own Claude orchestrator
   instance (separate working dir + process).
5. Orchestrators must **coordinate across whitelisted projects** without reaching
   directly into each other's trees.

`.ai/tests/concurrency-test-protocol.md` (lines 204-206) already flagged the core
hazard: with git worktrees, SSOT/coordination state lives in one worktree and the
others see stale copies until pull/rebase. The design below resolves that.

## 2. Core principle — two planes

Stop conflating "where code is edited" with "where AIs coordinate."

| Plane | What | Mechanism |
|---|---|---|
| **Code plane** | Source edited by executors | Git **worktrees** — one per executor, on `exec/<name>/*` branches. Shared `.git` object store ⇒ independent trees, zero fragmentation. |
| **Coordination plane** | `.ai/` runtime state (activity log, handoffs, reports) + SSOTs | **Single canonical `.ai/`** in the primary checkout; every worktree reaches it via a directory **junction**. One log, one queue, no per-branch divergence, no merge conflicts. |

## 3. Single-project layout

```
~/Code/
  project-a/                  PRIMARY checkout. Branch: main. Claude orchestrator instance.
    .git/                     the one real object store (shared by all worktrees)
    .ai/                      CANONICAL coordination plane
    src/ ...

  .wt/project-a/              worktree container — SIBLING, outside the main tree
    kiro/   .ai -> junction   git worktree, branch exec/kiro/<task>
    kimi/   .ai -> junction   git worktree, branch exec/kimi/<task>
    crush/  .ai -> junction   git worktree, branch exec/crush/<task>
```

Setup:
```sh
git -C project-a worktree add ../.wt/project-a/kiro  -b exec/kiro/init
git -C project-a worktree add ../.wt/project-a/kimi  -b exec/kimi/init
git -C project-a worktree add ../.wt/project-a/crush -b exec/crush/init
# in each worktree, replace tracked .ai with a junction to the canonical one:
mklink /J ".wt\project-a\kiro\.ai"  "..\..\..\project-a\.ai"   # Windows, no admin needed
# and exclude the junction from the worktree's index:
echo ".ai" >> .wt/project-a/kiro/.git/info/exclude
```

**Decision — worktrees live OUTSIDE the project (`~/Code/.wt/<project>/`), not nested.**
Nested `.worktrees/` would be indexed 4× by CodeGraph/KiroGraph/KimiGraph, risk
accidental commits, and confuse `pretool-write-edit.sh`. Sibling keeps the main tree
clean.

**Decision — pure junction of the whole `.ai/` to the canonical copy.** Chosen over a
`merge=union` git driver and over the hybrid (junction runtime, track SSOTs). One
canonical `.ai/` means executors always read main's current SSOTs and write to one
shared log/queue. Trade-off accepted: an executor mid-task sees SSOT changes from main
immediately — desirable, not harmful.

## 4. Branch & merge flow — Claude holds main

1. Claude (on `main`) writes a handoff → `.ai/handoffs/to-kiro/open/NNN.md`.
2. Kiro works **only in `.wt/project-a/kiro/`** on `exec/kiro/NNN-slug`. Never touches
   main or another worktree.
3. Kiro writes a completion handoff + appends to the shared activity log (via junction).
4. Claude reviews `git diff main..exec/kiro/NNN-slug` and is the **only** merger to main.
5. Post-merge, executors `git rebase main` their worktrees before the next task.

Collision-free by construction: distinct working directory + distinct branch namespace
(`exec/<name>/*`) per executor.

## 5. Multi-project / cross-orchestrator tier — `.fleet/`

A third plane spanning projects, mirroring `.ai/` one level up.

```
~/Code/
  .fleet/                         meta-coordination root (its own small git repo)
    registry.json                 project whitelist + who-may-talk-to-whom
    handoffs/
      to-project-a/open/          cross-orchestrator handoffs
      to-project-b/open/
    activity/log.md               fleet-level log

  project-a/   (Claude orchestrator A, main)
  project-b/   (Claude orchestrator B, main)
  .wt/project-a/{kiro,kimi,crush}/
  .wt/project-b/{kiro,kimi,crush}/
```

`registry.json` — the whitelist is the security boundary:
```json
{
  "projects": {
    "project-a": { "path": "~/Code/project-a", "talks_to": ["project-b"] },
    "project-b": { "path": "~/Code/project-b", "talks_to": ["project-a"] },
    "project-c": { "path": "~/Code/project-c", "talks_to": [] }
  }
}
```

Rules per orchestrator:
- Reads only `.fleet/handoffs/to-<self>/open/`; accepts a handoff **only if the sender
  is in its `talks_to` list**.
- Cross-project work is **always** a handoff — never a direct write into another
  project's tree (the per-CLI folder-ownership rule, lifted one level).
- Two queues, two scopes: intra-project Claude↔executors in `project-x/.ai/handoffs/`;
  inter-orchestrator Claude-A↔Claude-B in `.fleet/handoffs/`.

## 6. Enforcement (hooks)

Extend `pretool-write-edit.sh` (and Kiro/Kimi equivalents via handoff) with:
1. **Worktree confinement** — an executor may write only under its own worktree path +
   the shared `.ai/`. Block escapes into sibling worktrees or other projects.
2. **Fleet whitelist** — block writes to `.fleet/handoffs/to-X/` unless the current
   project's `talks_to` includes X.

## 7. Follow-ups (not in this pass)

- Reflect the worktree/fleet bootstrap in the installer (`tools/multi-cli-install/`) so
  adopters get it for free.
- Kiro/Kimi hook parity for the two new guards (via `.ai/handoffs/to-kiro|to-kimi/`).
- `.fleet/registry.json` schema validation + a `fleet-status` helper.

## 8. Resolved decisions & open questions

**Resolved (2026-06-15, user):** `.fleet/` is its **own small git repo** (not an
untracked local-only dir) — for auditability of cross-orchestrator coordination.
Scaffolded by `scripts/fleet-init.sh`.

**Open:**
- Junction durability across `git worktree prune` / branch deletion — bootstrap script
  must re-establish junctions idempotently (handled in `scripts/wt-bootstrap.sh`).
