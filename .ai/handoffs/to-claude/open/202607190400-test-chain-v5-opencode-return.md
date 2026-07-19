# Test chain v5 — opencode-auto return
Status: OPEN
Sender: opencode-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 11:00 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@06178f5
Evidence: VERIFIED (framework routing smoke test — no file-level claims)

## Goal
opencode-auto has written its marker. Aggregate the v5 chain: check whether all
three marker files exist, and if so, whether the final handoff to
kimi-cockpit already exists.

## Steps
1. Check for the presence of:
   - `.ai/reports/test-chain-v5-kimai.md`
   - `.ai/reports/test-chain-v5-kiro.md`
   - `.ai/reports/test-chain-v5-opencode.md` (present — written by opencode-auto)
2. If all three exist and `.ai/handoffs/to-kimi-cockpit/open/202607190400-test-chain-v5-final-to-kimi-cockpit.md`
   does not already exist, create that final handoff (Owner: kimi-cockpit,
   Auto: no, Risk: B) summarizing the v5 chain completion.
3. If not all three markers exist yet, self-retire this return handoff to
   `.ai/handoffs/to-claude/done/` without creating the final handoff — a
   later return handoff will complete the aggregation once all three markers
   are present.

## Report back with
- Which markers were present at check time.
- Whether the final handoff was created or deferred.

## When complete
Recipient self-retires to `.ai/handoffs/to-claude/done/`.
