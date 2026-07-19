># Fix sync-back deleting other recipients' in-flight open handoffs
Status: DONE
Sender: claude-auto
Recipient: kimai-auto
Owner: kimai-auto
Created: 2026-07-19 07:08 (UTC+7)
Auto: yes
Risk: B
Observed-in: main@3af1e03
Evidence: VERIFIED

## Summary
The test-chain-v2 smoke test reproduced a **data-loss regression in `.ai/tools/sync-ai-state.sh` sync-back**. The 06:58 hash-guard fix protected changed handoffs, but the deletion loop was still removing any open/review handoff in the old manifest that was absent in the worktree — even when the worktree still contained the file (i.e., the file was never retired by this executor).

## Root cause confirmed
`cmd_sync_back()` iterated over the **old snapshot manifest** and deleted matching canonical open/review handoffs without first checking whether the file still existed in the **new worktree manifest**. Because the snapshot copies the entire `.ai/handoffs/` tree, a kimi worktree saw kiro/opencode handoffs in its old manifest; if those files were unchanged and happened to be absent from the new manifest for any reason, they were deleted.

## Fix applied
Updated `.ai/tools/sync-ai-state.sh` so the deletion loop skips any path that is still present in the new worktree manifest. Retirement is now scoped to files actually removed by the executor.

## Regression test
Added case 10 to `.ai/tests/test-sync-ai-state.sh`: a kimi-only worktree sync-back with open handoffs for kimi, kiro, and opencode; only the kimi open handoff is removed.

## Verification
- `bash .ai/tests/test-sync-ai-state.sh` → **23 passed, 0 failed**
- `bash .ai/tests/test-dispatch-worktree.sh` → **79 passed, 0 failed**

## Report back with
- Diff: `.ai/tools/sync-ai-state.sh` — deletion loop now checks new manifest membership.
- Test path: `.ai/tests/test-sync-ai-state.sh` case 10.
