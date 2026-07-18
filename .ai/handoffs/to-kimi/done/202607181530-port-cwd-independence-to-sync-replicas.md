# Handoff: port cwd-independence onto current sync-replicas.sh

Status: DONE
Sender: kimi-cli
Recipient: kimi-auto
Created: 2026-07-18 15:30 (UTC+7)
Resolved: 2026-07-18 22:05 (UTC+7)
Auto: yes
Risk: B
Next: -
Observed-in: main@5999b82
Evidence: bash .ai/tests/test-sync-cwd-independence.sh → 16 passed, 0 failed. sync-replicas.sh now derives ROOT from $0, resolves SYNC_MD/sources/preamble reads against ROOT, and keeps --dest-root caller-relative.

## Goal

PR #72 (`exec/kiro/202607122030-drift-checker-cwd-false-pass`) was closed as superseded because `main` now has a different design:

- `check-ssot-drift.sh` is a thin shim that execs `.ai/tools/sync-replicas.sh --check`.
- `sync-replicas.sh` carries junction/reverse-write guards and a skip-worktree source guard.

However, **the cwd-independence fix from PR #72 is still correct and still missing**. The current `sync-replicas.sh` on `main` defaults to:

```bash
: "${SYNC_MD:=.ai/sync.md}"
DEST_ROOT="."
```

These are relative to the caller's current working directory. When the script is invoked by absolute path from a different worktree/directory, it regenerates/diffs against the CWD's tree, not the tree containing the script. This is the exact false-pass bug PR #72 fixed.

## Required change

Port the cwd-independence pattern from PR #72 into the current `sync-replicas.sh` **without removing the junction/skip-worktree guards**:

1. Derive `$ROOT` by pure string manipulation on `$0` (strip `/path/to/.ai/tools/sync-replicas.sh` → repo root). No `cd`, no `git rev-parse --show-toplevel`, no `pwd -P` — those resolve the `.ai` junction back to the primary checkout.
2. Default `SYNC_MD="$ROOT/.ai/sync.md"` and `DEST_ROOT="$ROOT"`.
3. Resolve every source/registry read against `$ROOT`.
4. Keep `--dest-root` as an explicit caller-relative output sink (it is intentionally not repo-rooted).
5. Preserve the existing `--check` drift report contract.
6. Preserve all existing guards: junction/refuse-to-write-through-link, skip-worktree source guard, `.ai/` destination refusal.

## Verification

- Existing tests must still pass:
  - `bash .ai/tests/test-reconcile-done-handoffs.sh` → 30 passed
  - `bash .kimi/hooks/test_hooks.sh` → 90 passed
  - `bash .claude/hooks/test_hooks.sh` → 66 passed
  - `bash .ai/tests/test-dispatch-worktree.sh` → all passed
- Add or extend a test that invokes `sync-replicas.sh --check` from a DIFFERENT directory by absolute path and proves it measures the script's own repo, not the CWD repo. PR #72's test approach is a good reference.

## Files

- `.ai/tools/sync-replicas.sh` — primary change
- `.ai/tools/check-ssot-drift.sh` — verify the shim still works and the false-pass is closed
- Optional new test under `.ai/tests/`

## Blocker

None. This is a bounded framework hardening task.

## Report back

- The exact diff of the `$ROOT` derivation and where it is used.
- Test output proving cwd-independence.
- Whether any guard behavior changed.
