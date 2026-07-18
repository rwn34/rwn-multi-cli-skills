# 16. `.ai/` durability contract — snapshot-copy plus per-handoff sync-back commits

## Status

Accepted (2026-07-18).

## Context

The shared `.ai/` coordination plane is the fleet's single source of truth for:

- handoff queues (`.ai/handoffs/`)
- the append-only activity log (`.ai/activity/log.md`)
- claim sidecars and quarantine records (`.ai/handoffs/.claims/`, `.ai/handoffs/.quarantine/`)
- per-CLI steering and hooks (`.claude/`, `.kimi/`, `.kiro/`, `.opencode/`)

Until 2026-07-16 this plane was exposed inside every executor worktree as a
Windows junction / POSIX symlink pointing back at the primary checkout. A
junction makes the shared state appear as ordinary tracked files inside the
worktree, so normal git verbs such as `git clean -fd`, `git reset --hard`,
`git worktree remove`, and `git checkout -- .ai` followed the link and deleted
or rewrote canonical `.ai/` state. On 2026-07-17 this fired twice in a live
project, destroying uncommitted handoffs, activity-log entries, and a findings
report.

## Decision

1. **Snapshot-copy model.** Executor worktrees no longer junction-mount `.ai/`.
   The dispatcher copies the current canonical `.ai/` snapshot into the worktree
   as ordinary files before launching the CLI, and syncs changed/new files back
   to the canonical tree after the CLI exits.
2. **Per-handoff sync-back commit.** When the dispatcher syncs an executor's
   `.ai/` changes back to the primary checkout, it commits the canonical `.ai/`
   changes with an automatic commit message. This makes handoff retirements,
   activity-log appends, and report writes durable in git history.
3. **Deletion policy.** The sync-back propagates only two classes of deletions:
   - handoff files moving out of `open/` or `review/` (retirement moves)
   - files the executor explicitly removed and that were present in the snapshot
     manifest
   Arbitrary deletions of `done/` history, reports, logs, steering, or SSOT
   files are NOT propagated from the worktree snapshot.
4. **Worktree `.ai/` removal.** After a successful sync-back the dispatcher
   removes the worktree's `.ai/` directory completely, so the next dispatch
   starts from a clean snapshot of canonical state.
5. **No manual destructive cleanup.** `git clean -fd`, `git reset --hard`,
   `git worktree remove`, and `git checkout -- .ai` inside a worktree are no
   longer meaningful ways to "fix" a worktree because `.ai/` is ordinary files,
   not a junction. `scripts/wt-bootstrap.sh --remove` unmounts/removes `.ai/`
   before invoking `git worktree remove`.

## Consequences

- Canonical `.ai/` state is durable via git commits, not merely the working tree.
- A worktree can still diverge from trunk, but a destructive git verb inside it
  can no longer delete the shared coordination plane in one command.
- The activity-log prepend race (two concurrent appends interleaving in the same
  file) remains until ADR-0010's entry-spool model replaces direct `log.md`
  appends. The snapshot-copy model reduces the blast radius of a corruption but
  does not serialize writers.
- Checkpoint commits are per-handoff, not periodic. If a long-running headless
  session crashes before sync-back, its in-flight `.ai/` changes are lost.

## Implementation

- `.ai/tools/sync-ai-state.sh` — `snapshot` and `sync-back` commands.
- `.ai/tools/dispatch-handoffs.sh` — calls `snapshot_ai()` before launch and
  `sync_back_ai()` after the CLI exits.
- `scripts/wt-bootstrap.sh` — creates worktrees without a `.ai/` junction;
  `--remove` unmounts `.ai/` before worktree removal.

## References

- ADR-0004 (worktree-per-CLI topology)
- ADR-0010 (activity-log entry-spool model, not yet fully deployed)
- `docs/specs/junction-reverse-write-guard.md`
