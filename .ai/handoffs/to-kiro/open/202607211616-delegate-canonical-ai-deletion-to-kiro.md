---
Status: OPEN
Sender: kimi-cockpit
Recipient: kiro
Owner: kiro
Created: 2026-07-21 23:16 (UTC+7)
Auto: no
Risk: B
Base: origin/main
Observed-in: main@326a35c
Evidence: VERIFIED (bash .ai/tools/sync-replicas.sh --check -> Drift: 0; post-merge follow-up PR #134 merged at c4e5db9; canonical .ai/ intact)
ReturnTo: kimi-cockpit
---

# Delegate canonical `.ai/` deletion root-cause investigation to kiro

## Background

The original investigation handoff `.ai/handoffs/to-kiro/open/202607211105-diagnose-canonical-ai-deletion.md` is delegated to the kiro auto pane by cockpit direction. Execute that handoff and **report completion or blocker status back to `kimi-cockpit`**.

## Critical safety constraint

The command under investigation is `bash .ai/tools/dispatch-handoffs.sh --exec`. Do **not** run that command as part of this work; it can destroy the coordination plane. The original handoff says:

> "Do NOT dispatch this handoff by running `dispatch-handoffs.sh --exec` — that is the very command under investigation and it destroys the coordination plane. The owner launches this one manually."

This delegation is the owner's manual launch. Run all reproductions only in throwaway locations, never against canonical `.ai/`.

## Work to perform

Follow the steps in `.ai/handoffs/to-kiro/open/202607211105-diagnose-canonical-ai-deletion.md`:

1. Reproduce in a throwaway location with instrumentation (`set -x` or echo every path passed to `safe_rm_rf`).
2. Establish precisely which command deleted the canonical `.ai/` tree and what the path variables held.
3. Propose a fix that:
   - hard-refuses to `rm -rf` any path that resolves to the canonical project `.ai/` (realpath comparison);
   - makes `sync_back_ai` fail closed on a missing script;
   - makes the dispatcher exit non-zero when the expected queue directory vanishes.
4. Add a regression test under `.ai/tests/`.
5. Do not merge to main; report findings back to `kimi-cockpit`.

## Return path

When done (or blocked), create a return handoff addressed to `kimi-cockpit`:
- Place it in `.ai/handoffs/to-kimi-cockpit/open/`
- Name it `YYYYMMDDHHMM-kiro-canonical-ai-deletion-return.md`
- Include: the instrumented trace showing the exact deleting command + resolved path, the failing-then-passing regression test output, the diff of the proposed fix, and confirmation that canonical `.ai/` survived testing

Do not self-retire this handoff; leave that to `kimi-cockpit`.
