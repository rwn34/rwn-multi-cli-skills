# Test chain v5 — kiro-auto return
Status: OPEN
Sender: kiro-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 11:06 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@06178f5
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
kiro-auto has written its marker. Aggregate the v5 chain: check whether all
three marker files exist, and if so, whether the final handoff to
kimi-cockpit already exists.

## Steps
1. Check for the presence of:
   - `.ai/reports/test-chain-v5-kimai.md`
   - `.ai/reports/test-chain-v5-kiro.md` (present — written by kiro-auto)
   - `.ai/reports/test-chain-v5-opencode.md`
2. If all three exist and `.ai/handoffs/to-kimi-cockpit/open/202607190400-test-chain-v5-final-to-kimi-cockpit.md`
   does not already exist, create that final handoff (Owner: kimi-cockpit,
   Auto: no) summarizing the v5 chain completion.
3. If not all three markers exist yet, self-retire this return handoff to
   `.ai/handoffs/to-claude/done/` without creating the final handoff — a
   later return handoff (from kimai-auto or opencode-auto) will complete the
   aggregation once all three markers are present.

## Report back with
- Which markers were present at check time.
- Whether the final handoff was created or deferred.

## When complete
Recipient self-retires to `.ai/handoffs/to-claude/done/`.
