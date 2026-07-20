# Smoke test: kimi cross-queue write

Status: DONE
Sender: claude-code
Recipient: kimi
Created: 2026-07-20 14:00 (UTC+7)
Auto: yes
Risk: A
Evidence: VERIFIED (dispatch-worktree suite 106/106 pass)
Observed-in: main@06b652a

## Goal
Verify that a headlessly dispatched Kimi auto pane can write a cross-queue
return handoff inside the worktree .ai/ and that it survives sync-back to the
canonical tree.

## Steps
1. Read this handoff.
2. Create `.ai/handoffs/to-claude/open/kimi-smoke-return.md` with:
   - Status: OPEN
   - Sender: kimi
   - Recipient: claude
   - Created: current UTC+7 wall-clock
   - Auto: yes
   - Risk: A
   - Evidence: VERIFIED (kimi can write cross-queue)
   - A brief note that the smoke test succeeded.
3. Move this handoff to `.ai/handoffs/to-kimi/done/202607201400-smoke-kimi-cross-queue.md`
   and set Status: DONE.
4. Prepend a terse entry to `.ai/activity/log.md`.
