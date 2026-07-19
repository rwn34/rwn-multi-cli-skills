# Fix sync-back deleting other recipients' in-flight open handoffs
Status: OPEN
Sender: claude-auto
Recipient: kimai-auto
Owner: kimai-auto
Created: 2026-07-19 07:08 (UTC+7)
Auto: yes
Risk: B
Observed-in: main@3af1e03
Evidence: VERIFIED

## Summary
The test-chain-v2 smoke test (root handoff 202607182359, your own) reproduced a
**data-loss regression in `.ai/tools/sync-ai-state.sh` sync-back**. Your 06:58 fix
(hash-guard: only delete a canonical handoff when its sha256 matches the snapshot
manifest, so handoffs that CHANGED since the snapshot survive) does not cover the
case that actually bit here: **unchanged open handoffs addressed to a different
recipient than the one whose worktree is syncing back.**

## What was verified (live tree, main@3af1e03)
1. claude-auto created three sibling echo handoffs at ts=202607190001:
   - `.ai/handoffs/to-kimi/open/202607190001-test-chain-v2-kimai-echo.md`
   - `.ai/handoffs/to-kiro/open/202607190001-test-chain-v2-kiro-echo.md`
   - `.ai/handoffs/to-opencode/open/202607190001-test-chain-v2-opencode-echo.md`
2. `dispatch-handoffs.sh --exec` bootstrapped a worktree for **kimi only**
   (`[wt-bootstrap] Executors: kimi`). The kimi child ran correctly: wrote its
   marker, filed its return, self-retired its own echo.
3. On the kimi worktree sync-back the log emitted:
   ```
   [sync-ai-state] sync-back removed: handoffs/to-kimi/open/...kimai-echo.md (handoff retirement)   # legitimate
   [sync-ai-state] sync-back removed: handoffs/to-kiro/open/...kiro-echo.md (handoff retirement)    # BUG — never dispatched
   [sync-ai-state] sync-back removed: handoffs/to-opencode/open/...opencode-echo.md (handoff retirement)  # BUG — never dispatched
   ```
4. **Confirmed against the filesystem** (not just the log): the kiro and opencode
   echo handoffs are gone from `open/`, while `to-claude/open/...kimai-return.md`
   and `.ai/reports/test-chain-v2-kimai.md` survived. Those two handoffs were
   silently destroyed before their recipients ever ran.

## Root-cause hypothesis (please confirm before fixing)
The snapshot copied into the kimi worktree likely does not contain (or the
sync-back diff does not scope to) handoffs addressed to other recipients, so at
sync-back they read as "present in master, absent in worktree ⇒ retired." The
hash-guard permits the delete because master still matches the snapshot hash
(nobody changed them) — precisely the wrong signal. Retirement must be scoped to
the recipient the worktree actually dispatched: a `to-kiro/` or `to-opencode/`
open handoff is never retirable by a `kimi` worktree's sync-back.

## Asks
1. Diagnose and confirm the exact mechanism (snapshot scope vs. diff scope).
2. Fix sync-back so an executor worktree can only retire open/review handoffs
   **addressed to that executor** (its own `to-<self>/` queues) plus shared files
   it actually wrote. Never delete an open handoff belonging to a different
   recipient.
3. Add a regression test asserting: given open handoffs for kimi + kiro + opencode
   and a kimi-only worktree sync-back, the kiro and opencode open handoffs survive.
4. Note the secondary observation for the owner/dispatcher discussion: `--exec`
   only bootstrapped a kimi worktree though the dry-run listed all three
   recipients — sequential multi-recipient dispatch may be interacting badly with
   the per-run sync-back. Not necessarily in scope for this fix, but flag if related.

## Report back with
- The confirmed root cause, the diff to `sync-ai-state.sh`, and the new regression
  test path + a paste of it passing.
