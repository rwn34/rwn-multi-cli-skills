# Snapshot-copy sync model for `.ai/` shared state

**Status:** design + implementation in progress  
**Owner:** kimi-cli  
**Related:** ADR-0004 worktree topology, S1-4 field-report finding, saja-qr deletion incident (2026-07-16/17)

## Problem

The shared coordination plane `.ai/` was exposed inside every executor worktree as a Windows junction / POSIX symlink to the primary checkout's `.ai/`. This created a severe reverse-write hazard:

- `git clean -fd`, `git reset --hard`, `git worktree remove`, and `git checkout -- .ai` inside a worktree followed the junction and deleted or rewrote canonical `.ai/` state.
- On 2026-07-17 this fired twice in `saja-qr`, destroying uncommitted handoffs, activity-log entries, and a findings report.
- Phase 1 mitigations (guard scripts, safe `wt-bootstrap.sh --remove`) closed the deletion path but did not remove the underlying hazard.

## Decision

Replace the junction with an **explicit dispatcher-owned copy/sync model**.

## Model

```text
Primary checkout          Dispatcher                Executor worktree
  .ai/ (canonical)  <----- copy snapshot ----->  .ai/ (ordinary files)
       ^                                            |
       |                                            | executor reads/writes
       |                                            v
       <---- sync back (new/changed/moved) ---- .ai/
```

### Lifecycle

1. **Branch cut / dispatch.** The dispatcher copies the current canonical `.ai/` snapshot from the primary checkout into the executor worktree as ordinary files. No junction, no symlink.
2. **Execution.** The executor reads `.ai/` locally and writes outputs locally. It does not see live canonical changes that arrive after the snapshot.
3. **Completion.** The dispatcher:
   - copies changed/new files back to canonical `.ai/`,
   - replays moves/renames inside `.ai/handoffs/` (so handoff retirement `open/` → `done/` still works),
   - never propagates other deletions from the worktree,
   - commits the canonical `.ai/` changes,
   - removes `worktree/.ai/` completely.
4. **Next dispatch.** A fresh snapshot is copied again.

### Why this is safe

- The canonical `.ai/` is never reachable through a link from inside a worktree, so destructive git verbs in a worktree cannot touch it.
- Because `.ai/` is removed after sync-back, a stale worktree cannot drift behind trunk and then stage the entire shared dir as its own work.
- Sync-back is scoped: it replays only what the executor changed, plus handoff moves.

## Manifest-based sync-back

To replay handoff moves correctly, the dispatcher records a manifest of the snapshot at copy time:

```text
.ai/.snapshot-manifest
```

The manifest is a sorted list of relative paths and SHA-256 hashes of every file in `.ai/` at snapshot time. It is written inside the worktree `.ai/` and is therefore removed with `.ai/` after sync-back.

Sync-back rules:

| Worktree state | Canonical state | Action |
|---|---|---|
| File exists, not in manifest, or differs from manifest | — | Copy worktree file to canonical |
| File not in worktree, but was in manifest | — | Delete from canonical (this replays a handoff move or intentional deletion) |
| File in worktree, in manifest, unchanged | — | No action |
| File in canonical but not in manifest and not in worktree | — | No action (concurrent canonical addition, do not delete) |

Only files inside `.ai/handoffs/` are deleted when missing from worktree; files outside `handoffs/` are never deleted, only added/overwritten. This prevents an executor from accidentally wiping shared reports, logs, or other coordination state.

## Files touched

- `scripts/wt-bootstrap.sh` — replace `link_ai()` with `copy_ai()`; remove junction helpers; simplify `--remove`.
- `.ai/tools/sync-ai-state.sh` — new tool: snapshot, sync-back, commit, remove.
- `.ai/tools/dispatch-handoffs.sh` — snapshot before launch, sync-back after completion.
- `tools/4ai-panes/pane-runner.ps1` — snapshot before launch, sync-back after completion (parity with dispatcher).
- Tests: `.ai/tests/test-sync-ai-state.sh`, updates to `test-dispatch-worktree.sh` and `test-pane-runner.ps1`.

## Migration

Existing worktrees with junctions:

1. Run `bash scripts/wt-bootstrap.sh --remove <project-dir> <executor>...` to safely unmount the junction and remove the worktree.
2. Re-run `bash scripts/wt-bootstrap.sh <project-dir> <executor>...` to create fresh worktrees using snapshot-copy.

No project source changes are required.

## Open questions / future work

- Periodic checkpoint commits of canonical `.ai/` (every N minutes or per handoff) are deferred to a later change.
- Conflict resolution when canonical `.ai/` changes during executor runtime: currently worktree wins for files it touched; canonical wins for untouched files. A future ADR may define a merge strategy.
