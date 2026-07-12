# Make `gates` + `framework-check` REQUIRED status checks on master
Status: OPEN
Sender: claude-code
Recipient: opencode
Created: 2026-07-12 19:00
Auto: yes
Risk: B
Base: origin/master

<!-- RETRY of 202607120021, which you correctly BLOCKED twice. Root cause found:
     your pane process had loaded framework-guard.js into memory BEFORE PR #45
     widened WRITABLE_LANE to include `.github/**`, and never reloaded it — so the
     runtime enforced a stale lane while the on-disk source was already correct.
     Your own report was the evidence that cracked it (you quoted line 55 showing
     `.github/**` AND line 52 showing `.ai/activity/entries/**` from PR #48 — proving
     the SOURCE was current while the RUNTIME was not). The owner has now restarted
     the PowerShell terminal, so your process has a fresh guard. Retry.

     SCOPE SHRANK: the step-reorder half of the old handoff is ALREADY DONE by PR #56
     (version-bump step now runs LAST and only on `push`). Do NOT redo it. Only the
     branch-protection half remains. -->

## Goal
`gates` is not a required check — it is decoration. Proven on PR #40: the check went
RED and GitHub still offered the merge button (`mergeStateStatus: UNSTABLE`, not
`BLOCKED`). You confirmed the deeper truth yourself: master has **no branch protection
at all** (`gh api .../branches/master/protection` -> 404 "Branch not protected").

Under the owner's new policy the FLEET merges to main (Tier B, no owner pre-approval).
That autonomy is only safe if a red gate genuinely blocks the merge. Right now nothing
does. Close that.

## Target state
Branch protection on `master` with **`gates`** and **`framework-check`** as REQUIRED
status checks, so a red check BLOCKS the merge rather than suggesting caution.

## Constraints
- **Repo settings + `gh` API only.** No source code. If the task appears to need a
  source change, STOP and report.
- **Read the CURRENT protection config first, change only what this handoff names,
  and paste BEFORE and AFTER.** If any existing setting looks risky to alter or the
  API forces you to set something not named here, STOP and report rather than
  improvise on repo settings.
- Do NOT require a PR-review approval as part of protection (the fleet's peer review
  is a process rule, not a GitHub rule — forcing it mechanically could deadlock the
  merge-train). Only the two status checks.
- Do NOT enable "dismiss stale reviews", "require linear history", or "enforce for
  admins" unless you must to make the checks required — if you must, SAY SO and
  explain.
- Do NOT merge anything (owner gates ADR merges; the fleet merges code PRs).
- Verify `bash scripts/check-version-bump.sh origin/master` behavior is unaffected.

## Watch out — open PRs exist
PRs #55 and #56 are open and green. Making the checks required must not wedge them.
Confirm after the change that both still show as mergeable (green checks satisfy the
new requirement). If either becomes blocked, report immediately.

## Verification (EXECUTE — inspection is not evidence)
- (a) `gh api repos/rwn34/rwn-multi-cli-skills/branches/master/protection` BEFORE
      (expect 404) and AFTER (expect the two checks in `required_status_checks`).
      Paste both verbatim.
- (b) Confirm open PRs #55/#56 still report mergeable with green checks.
- (c) State plainly whether the framework-guard blocked you anywhere this time. If it
      did NOT, say so explicitly — that is the proof the stale-cache diagnosis was
      right and that your lane now works end to end.

## Why this matters to you specifically
This is your **round-trip proof**: handoff -> your auto pane consumes it unattended ->
real work -> you self-retire it to `done/`. Kimi and Kiro have proven their lanes;
Claude-auto has proven its. Yours is the last one unproven, and ADR-0011's
sequencing precondition holds OpenCode-as-merge-executor until this round-trips
clean. Take it end to end.

## Activity log template
    ## 2026-07-12 HH:MM — opencode
    - Action: Made gates + framework-check REQUIRED status checks on master per handoff 202607121900-gates-required-check
    - Files: — (repo settings, not files)
    - Decisions: <any protection setting you had to touch beyond the two checks, and why>

## Report back with
- (a) branch-protection BEFORE/AFTER, verbatim
- (b) PR #55/#56 mergeability after the change
- (c) whether the guard blocked you at any point (the stale-cache proof)
- (d) anything you could NOT do, stated plainly

## When complete (protocol v3)
Self-retire: set Status `DONE`, move this file to `.ai/handoffs/to-opencode/done/`.
If blocked AGAIN, leave it `OPEN` as `BLOCKED` with the verbatim error — a third
block would mean the stale-cache diagnosis is wrong and something else is going on,
which is itself the most valuable thing you could tell me.
