# Peer-review PR #93 — sync-4ai-panes-install.ps1 ancestor guard
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-07-14 01:34
Completed: 2026-07-14 01:26
Auto: yes
Risk: B
Touched: `.ai/reports/kimi-2026-07-14-review-pr93.md`, `.ai/activity/log.md`

## Goal
Peer-review PR #93 (branch `exec/kiro/sync-provenance-check`) per handoff
`to-kiro/open/202607122200-sync-provenance-and-verify-live-launcher.md`, which
explicitly routes review to Kimi (author != reviewer, ADR-0002). Do NOT merge —
report back, then the fleet merges (Tier B) after your review.

## Current state
PR: https://github.com/rwn34/rwn-multi-cli-skills/pull/93

Adds a third provenance property ("ancestor guard") to
`scripts/sync-4ai-panes-install.ps1`, on top of the existing primary-checkout +
master-branch guard (hole 1, 2026-07-13): HEAD must be an ancestor of
`origin/master` (`git merge-base --is-ancestor HEAD origin/master`, best-effort
fetch first, fails closed if unresolvable). Escape hatch:
`RWN_4AI_ALLOW_UNMERGED=1` (separate from `-Force`/`SYNC_FORCE`).

`scripts/test-sync-4ai-panes-install.ps1` extended 24 -> 52 assertions.

## Target state
Your review report in `.ai/reports/` (or inline in your self-retire report),
covering:
- Does the ancestor-guard logic actually close the gap it claims to (a local
  `master` that is ahead of/diverged from `origin/master`)?
- Is the escape-hatch design (option b: master-only default + opt-in env var)
  the right call, or would you have picked (a) strict or a different (c)?
- Any gap in the new test scenarios (i/j/k/l)?
- Does this conflict with anything in your fleet-supervisor work (#78)? (I did
  not touch `tools/4ai-panes/pane-runner.ps1` — only `scripts/`.)

## Context (reference only)
Task 1 of the source handoff (byte-compare live launcher vs `origin/master`)
found the hazard live: the primary checkout's local `master` was 3 commits
ahead of `origin/master` (unpushed) when its git hooks last deployed to
`~/.rwn-auto/rwn-4AI-panes/` — `4e743c7` is NOT an ancestor of `origin/master`.
The primary checkout's own copy of the sync script still lacks this guard
(commit `9b04eda`) until this PR merges and it's re-pulled there — flagging in
case you want to fix that separately; it's out of scope for this PR (worktree
can't reach the primary checkout).

## Steps
1. Read the PR diff.
2. Run `scripts/test-sync-4ai-panes-install.ps1` yourself if you want to verify
   independently (52/52 expected).
3. Report approval, requested changes, or concerns.

## Verification
- (a) You ran the test suite yourself, or explain why you relied on the pasted
  output in the PR body instead.

## Next step / future note
After your review, the fleet merges (Tier B, no owner pre-approval per
ADR-0011). Follow-up not in scope here: someone with access to the primary
checkout (`C:\Users\rwn34\Code\rwn-multi-cli-skills`) needs to re-sync/re-pull
so the live-deploying git hooks actually get this guard.

## Report back with
- (a) approve / request-changes verdict on PR #93
- (b) any issues found, with file:line references
- (c) whether you ran the tests yourself and the result

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kimi/done/`.
