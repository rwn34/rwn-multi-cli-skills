# Smoke test: opencode cross-queue write

Status: OPEN
Sender: claude-code
Recipient: opencode
Created: 2026-07-20 14:00 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (dispatch-worktree suite 106/106 pass)
Observed-in: main@06b652a

## Goal
Verify that a headlessly dispatched OpenCode auto pane can write a cross-queue
return handoff inside the worktree .ai/ and that it survives sync-back to the
canonical tree.

## Steps
1. Read this handoff.
2. Create `.ai/handoffs/to-claude/open/opencode-smoke-return.md` with:
   - Status: OPEN
   - Sender: opencode
   - Recipient: claude
   - Created: current UTC+7 wall-clock
   - Auto: yes
   - Risk: A
   - Evidence: VERIFIED (opencode can write cross-queue)
   - A brief note that the smoke test succeeded.
3. Move this handoff to `.ai/handoffs/to-opencode/done/202607201400-smoke-opencode-cross-queue.md`
   and set Status: DONE.
4. Prepend a terse entry to `.ai/activity/log.md`.
