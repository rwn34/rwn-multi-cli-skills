# Post-freeze cleanup of Kiro-native activity-log wording
Status: OPEN
Sender: kimi
Recipient: kiro
Owner: kiro
Created: 2026-07-21 18:17 (UTC+7)
Auto: yes
Risk: B
Observed-in: exec/kimi/20260721-framework-finalization@297de1a
Evidence: VERIFIED (grep -n "prepend" .kiro/steering/00-ai-contract.md .kiro/hooks/guards.json -> 4 hits; grep -n "protocol v3" .kiro/steering/00-ai-contract.md -> 1 hit; bash .ai/tools/sync-replicas.sh --check -> DRIFT: .ai/instructions/self-grep-verify/principles.md -> .kimi/steering/self-grep-verify.md)

## Goal

Finish the ADR-0010 Wave-3 freeze for Kiro-native files. The shared `.ai/` state and Kimi-native files are already updated; `.kiro/steering/00-ai-contract.md` and `.kiro/hooks/guards.json` still describe the old prepend-to-`log.md` model. Update them to the entry-spool model.

## Current state

- `.ai/activity/log.md` is still tracked (pre-freeze), but the freeze finish is being routed to claude-cockpit in `.ai/handoffs/to-claude-cockpit/open/20260721-adr0010-freeze-execution.md`.
- `.kimi/steering/00-ai-contract.md` and `.kimi/steering/self-grep-verify.md` are already updated to the spool model (commit 297de1a).
- `.kiro/steering/self-grep-verify.md` and `.kiro/steering/operating-prompt.md` are replicas generated from `.ai/instructions/`; claude-cockpit will regenerate them as part of the SSOT + replica atomic commit.
- `.kiro/steering/00-ai-contract.md` and `.kiro/hooks/guards.json` are **Kiro-native, non-replica files** and must be edited by Kiro.

## Files to change

1. `.kiro/steering/00-ai-contract.md`
   - Line ~10: "activity-log entries you prepend here." → "activity-log entry files you write here."
   - Line ~84: "prepend an activity-log entry," → "write an activity-log entry file,"
   - Line ~94: "Recipient self-retires (protocol v3)." → "Recipient self-retires (protocol v4)."
   - Review the "Fallback (transitional, until the freeze lands)" paragraph (~lines 68-76). If claude-cockpit has already archived `log.md` by the time you act, replace the fallback with a clean post-freeze statement; if `log.md` is still tracked, leave the fallback intact. Either way, the default action must be "write an entry file under `.ai/activity/entries/`".

2. `.kiro/hooks/guards.json`
   - Line ~74: "Reminds to prepend an activity-log entry at session end." → "Reminds to write an activity-log entry file at session end."

## Steps

1. Pull the latest `exec/kimi/20260721-framework-finalization` branch.
2. Make the edits above.
3. Run `bash .ai/tools/sync-replicas.sh --check`. If it reports drift only in `.kiro/steering/self-grep-verify.md` or `.kiro/steering/operating-prompt.md`, wait for claude-cockpit's SSOT + replica commit, then re-run. Do NOT edit replicas by hand.
4. Run the verification commands below.
5. Commit as kiro with a message like `chore(kiro): post-freeze activity-log wording cleanup`.
6. Self-retire this handoff to `.ai/handoffs/to-kiro/done/`.

## Verification

```bash
bash .kiro/hooks/test_hooks.sh              # should pass (currently 70/70 baseline)
bash .ai/tools/lint-handoff.sh              # OK
bash .ai/tools/sync-replicas.sh --check     # 0 drift after claude-cockpit's replica commit
grep -n "prepend" .kiro/steering/00-ai-contract.md .kiro/hooks/guards.json || echo "no stale prepend references"
grep -n "protocol v3" .kiro/steering/00-ai-contract.md && echo "FAIL: still v3" || echo "OK: v4"
```

## Report back with

- The exact line changes made.
- Test output showing green.
- Confirmation whether `log.md` was already archived by claude-cockpit when you acted.
