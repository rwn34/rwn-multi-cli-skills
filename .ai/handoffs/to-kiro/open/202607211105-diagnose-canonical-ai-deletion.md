# Root-cause the canonical .ai/ deletion during dispatch-handoffs.sh --exec
Status: OPEN
Sender: claude-cockpit
Recipient: kiro
Owner: kiro
Created: 2026-07-21 18:05 (UTC+7)
Auto: no
Risk: B
Observed-in: main@9797a1f16f70eff2edc9b714945db6ff31f20218
Evidence: VERIFIED (bash .ai/tools/dispatch-handoffs.sh --exec in the claude worktree -> canonical .ai/ reduced from 464 files/3.8M to 2 entries/1.0K; git status showed 438 tracked deletions; restored from the executor worktree snapshot)

> **Auto: no is deliberate.** Do NOT dispatch this handoff by running
> `dispatch-handoffs.sh --exec` — that is the very command under investigation and
> it destroys the coordination plane. The owner launches this one manually.

## Goal

Find why `bash .ai/tools/dispatch-handoffs.sh --exec`, run from the `claude`
executor worktree, deleted the **canonical** `.ai/` tree mid-run, and why it then
exited 0 with no dispatch-failure report. Until this is understood, the fleet has
no safe auto-dispatch path.

## Current state — what was observed

Run context: cwd `C:\Users\rwn34\Code\.wt\rwn-multi-cli-skills\claude`, HEAD
`9797a1f`, four handoffs queued (claude/kimi/kiro/opencode).

Dry run correctly listed 4 dispatches. The `--exec` run then produced:

    [wt-bootstrap] Project:    /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude
    [wt-bootstrap] Container:  /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/.wt/claude
    [wt-bootstrap] Executors:  claude
    Preparing worktree (checking out 'exec/claude/init')
    [wt-bootstrap] create claude — worktree at /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/.wt/claude/claude on exec/claude/init
    [sync-ai-state] snapshot copied to /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/.wt/claude/claude/.ai
    DISPATCH [claude] .ai/handoffs/to-claude/open/20260721T085700Z-test-chain-v7-aggregate.md — worktree: …/.wt/claude/claude branch: exec/claude/20260721T085700Z-test-chain-v7-aggregate (base: origin/main)
    ---- [claude] finished (exit 0) ----
    bash: /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude/.ai/tools/sync-ai-state.sh: No such file or directory
    EXIT=0

Immediately after: canonical `.ai/` contained only
`.ai/handoffs/.claims/.fleet-notify-throttle.json` and an empty `.ai/tools/`.
**kimi, kiro and opencode were never launched** — the loop found nothing to
iterate because the queue directories no longer existed, and still exited 0.

Notable: there was **no `.ai.stale-*` rename directory**, so this was a real
delete, not the Windows-lock rename fallback in `safe_rm_rf`.

## Leading hypotheses (not verified — your job)

1. **Nested-worktree path arithmetic.** `wt-bootstrap` treated the *executor
   worktree* as the project root and cut a nested container at
   `.wt/rwn-multi-cli-skills/.wt/claude/claude`. A `.wt` inside a `.wt` checkout
   is the most likely source of a canonical-vs-snapshot path confusion, where a
   cleanup meant for the snapshot resolves onto the canonical tree.
2. **`sync_back_ai` is fail-open (`|| true`).** It deleted before it synced, or it
   deleted and then could not run the script it had just removed. Either way the
   failure was swallowed.
3. **Loop cannot distinguish "queue empty" from "queue directory deleted"** —
   which is why the run reported success on 1-of-4.

`dispatch-handoffs.sh`'s own header comment (~line 53) already names the
**2026-07-16 canonical `.ai/` deletion incident**. A guard was added then and it
did not hold. Treat "the existing guard is sufficient" as disproven.

## Files

- `.ai/tools/dispatch-handoffs.sh` — the fail-open `sync_back_ai`, the queue loop, the 2026-07-16 guard
- `.ai/tools/sync-ai-state.sh` — holds the only `rm -rf` paths in play, plus `safe_rm_rf`
- `scripts/wt-bootstrap.sh` — nested-container path arithmetic
- `docs/architecture/0016-snapshot-copy.md` and `docs/specs/ai-snapshot-sync.md` — the intended sync contract; read these before proposing a fix
- **Forensic evidence, do not delete:** `C:\Users\rwn34\Code\.wt\rwn-multi-cli-skills\.wt\claude\claude\.ai` (464 files, 3.8M) — the executor snapshot the canonical tree was restored from

## Steps

1. Reproduce in a throwaway location — **never** against the canonical `.ai/`.
   Instrument `sync-ai-state.sh` / `dispatch-handoffs.sh` with `set -x` or an
   echo of every path passed to `safe_rm_rf`, and capture which call resolves onto
   the canonical tree.
2. Establish precisely which command deleted the tree and what the path variables
   held at that moment. A hypothesis without the resolved path is not a diagnosis.
3. Propose the fix. Required properties, at minimum:
   - a hard refusal to `rm -rf` any path that is (or contains) the canonical
     project `.ai/` — asserted by comparing resolved realpaths, not string prefix;
   - `sync_back_ai` must NOT be fail-open on a missing script — that is the signal,
     not noise;
   - the dispatcher must exit non-zero and write
     `.ai/reports/dispatch-failure-<UTC>-<cli>.md` when the queue directory it
     expects has vanished.
4. Add a regression test under `.ai/tests/` that fails on the current code and
   passes after the fix. Follow the existing `.ai/tests/test-*.sh` conventions.
5. Do not merge to main and do not run the real dispatcher to close this out.

## Verification

- (a) Paste the instrumented trace showing the exact `rm`/`rm -rf` invocation and its fully resolved argument.
- (b) `bash .ai/tests/<your-new-test>.sh` — paste output failing on current code, then passing after the fix.
- (c) `bash .ai/tools/lint-handoff.sh` → `OK` after your changes.
- (d) Confirm by `ls` that the canonical `.ai/` is fully intact after your reproduction run.

## Next step / future note

Once fixed, chain-v7 can be re-dispatched — the three child handoffs
(`to-kimi/open/…-kimai-echo.md`, `to-kiro/open/…-kiro-echo.md`,
`to-opencode/open/…-opencode-echo.md`) and the aggregator
(`to-claude/open/…-aggregate.md`) are all intact and lint-clean, so the chain test
doubles as the post-fix integration check.

**What breaks first if nobody fixes this:** the wipe presents as ordinary unstaged
working-tree changes. A routine `git add -A && git commit` would land a 438-file
deletion of the entire coordination plane, and recovery then depends on an
executor worktree that this same dispatcher is designed to clean up.

## Recurrence #2 — 2026-07-21 23:30 (UTC+7), partial wipe, added by claude-cockpit

A second, **partial** occurrence was observed on branch
`exec/claude/202607211616-delegate-adr0010-freeze-to-claude` (HEAD `f3d37e9` at
the time). This one is more diagnostically useful than the first because it
deleted only 3 tracked files instead of 438 — the failure is not all-or-nothing.

    $ git status --short
     D .ai/handoffs/to-claude-cockpit/open/20260721T111600Z-kimi-cockpit-framework-finalization-report.md
     M .ai/handoffs/to-claude/open/202607211616-delegate-adr0010-freeze-to-claude.md
     D .ai/handoffs/to-kimi-cockpit/open/20260721T143000Z-post-merge-followups-and-freeze-preconditions.md
     D .ai/handoffs/to-kiro/open/202607211616-delegate-canonical-ai-deletion-to-kiro.md

None of the three has a commit that retires it — every commit touching those
paths is an add/modify:

    $ git log --oneline -2 -- .ai/handoffs/to-kiro/open/202607211616-delegate-canonical-ai-deletion-to-kiro.md
    f3d37e9 chore(ai): delegate ADR-0010 freeze and canonical .ai/ deletion root cause to auto panes

**The strongest signal:** that path was *created by `f3d37e9` itself* — the
commit immediately preceding the observation — and was already gone from the
working tree. A handoff written one commit ago and never claimed cannot have
been legitimately retired. Note also the irony worth keeping: the file the bug
deleted was the handoff delegating *this very diagnosis*.

Restored with `git restore` (byte-identical to HEAD, no content authored);
restoration is a mitigation, not a fix — the next snapshot/sync cycle can
re-delete them.

### What this adds to the hypotheses above

- A **partial** deletion set argues against a single `rm -rf` of the whole
  canonical `.ai/` and toward a **per-file sync-back reconciliation** that
  decides some files are absent-in-snapshot and therefore should be removed
  from canonical. Hypothesis 1 (path arithmetic) alone does not explain why
  exactly these 3 of ~464 files were chosen.
- All three deleted files are **recent** relative to the snapshot. The obvious
  candidate mechanism: they were created in canonical *after* the snapshot copy
  was taken, so sync-back — treating the stale snapshot as authoritative rather
  than as a one-way source — deleted them as "no longer present". If that is the
  mechanism, the bug is a **lost-update / stale-snapshot** class problem, and the
  438-file wipe is the degenerate case where the snapshot was empty or misrooted.
- Worth checking against `docs/specs/ai-snapshot-sync.md`: does the contract
  permit sync-back to **delete** canonical files at all, or only to add/update?
  If deletion is not in the contract, the fix is narrow.

Please fold this into step 2 — reproducing the 3-file case is likely far cheaper
than reproducing the full wipe, and a fix that explains both is the real
diagnosis.

## Report back with
- (a) the resolved deleting command + path (verbatim trace)
- (b) the failing-then-passing regression test output
- (c) the diff of your fix, and whether ADR-0016 / `docs/specs/ai-snapshot-sync.md` need amending
- (d) explicit confirmation the canonical `.ai/` survived your testing
