# Make `gates` a required check + stop it masking real test results
Status: BLOCKED
Sender: claude-code
Recipient: opencode
Created: 2026-07-12 00:21
Auto: yes
Risk: B
Base: origin/master

<!-- RE-OPENED 2026-07-12 14:15 by claude-code. Your previous BLOCKED reason —
     "framework-guard blocks .github/workflows/gates.yml" — is RESOLVED: PR #45
     (merged f1a4d59) granted your lane `.github/**`. Re-cut your branch from the
     CURRENT origin/master (which has #45), and the guard will now allow the
     workflow edit. Everything below still stands. This is your genuine first
     round-trip — take it end to end: consume, do the work, commit, open the PR,
     self-retire to done/. Note: opening the PR is in your lane; MERGING it is
     not (Tier C, owner-gated). Leave it OPEN for the owner. -->

## Goal
Two defects in the CI gate, both proven tonight on real PRs:

1. **`gates` is not a REQUIRED check.** PR #40 went red on `gates` and GitHub
   still offered the merge button (`mergeStateStatus: UNSTABLE`, not `BLOCKED`).
   A gate you can walk past is decoration. Had it been merged red, the framework
   version would not have bumped, every onboarded project would still match the
   template version, the drift warning would never fire — and the release would
   have shipped to nobody, silently.
2. **The version-bump step runs FIRST in the `gates` job, so a bookkeeping miss
   masks every real test behind it.** On PR #42, `check-version-bump.sh` exited 1
   at `.github/workflows/gates.yml:36` and CI therefore NEVER RAN: the SSOT drift
   check, the four hook suites, the pre-commit backstop, or the installer tests.
   The next agent reads `gates: FAILURE` and reasonably assumes the code is
   broken when only the changelog bookkeeping was. This WILL recur — most
   framework work touches versioned paths.

## Target state
1. **`gates` (and `framework-check`) are REQUIRED status checks on `master`** via
   branch protection, so a red gate BLOCKS the merge button rather than
   suggesting caution. Use the `gh` CLI / GitHub API. Keep the rest of the
   existing protection settings intact — read them first, change only what this
   handoff names, and paste the before/after settings.
2. **Reorder the `gates` job so the version-bump check runs LAST** (or lives in
   its own separate job — your call, justify it). The substantive tests must run
   and report even when the version bump is missing. A missing bump must still
   FAIL the job — it just must not SUPPRESS the other results.

## Constraints
- **Do NOT touch source code.** This is `.github/workflows/gates.yml` + repo
  settings only. If the fix appears to require a source change, STOP and report.
- Branch protection changes: read the current config, make the minimal change,
  and paste both states. If a setting looks risky or ambiguous, STOP and report —
  do not improvise on repo settings.
- Do NOT merge anything to master (Tier C — the owner gates merges).
- `gates` requires a version bump when versioned framework content changes.
  `.github/**` may or may not be versioned — RUN `bash scripts/check-version-bump.sh
  origin/master` and obey its verdict. Do not bump if it says no bump is needed;
  do not skip if it says one is.
- Read first: `.ai/instructions/operating-prompt/principles.md` §14 (why this is
  your lane), `.opencode/contract.md`, `.ai/instructions/delivery-integrity/principles.md`.
- Branch `exec/opencode/gates-required-and-order` cut from `origin/master`. Open a
  PR; do not merge it.

## Verification (EXECUTE — inspection is not evidence)
- (a) Paste the branch-protection settings BEFORE and AFTER (`gh api` output).
      Show that `gates` is now in `required_status_checks`.
- (b) Prove the reordering works: the job must run and REPORT the hook suites /
      drift / backstop results even on a commit with a deliberately missing
      version bump, while still failing overall. Paste the CI run showing both
      facts. (A local dry-run of the reordered steps is acceptable evidence if you
      cannot force a red CI run without polluting the branch — say which you did.)
- (c) Paste `bash scripts/check-version-bump.sh origin/master` verdict for your
      own PR.

## Blocker

NEW BLOCKER (2026-07-12): Although PR #45 (f1a4d59) resolved the original blocker by adding `.github/**` to OpenCode's writable lane, the framework guard is still blocking edits to `.github/workflows/gates.yml`. The guard reports:

```
BLOCKED by framework-guard: edit of '.github/workflows/gates.yml' is outside the lane. OpenCode's writable lane is .ai/activity/log.md, .ai/reports/**, .ai/handoffs/** (see .opencode/contract.md).
```

However, the source file `.opencode/plugin/framework-guard.js` shows `.github/**` in WRITABLE_LANE at line 55. This suggests the guard is using a cached or stale configuration despite the source file being updated.

**Root cause:** The framework guard appears to be caching the old WRITABLE_LANE configuration. This needs to be debugged to understand why the runtime guard doesn't match the source configuration.

**Full report:** See `.ai/reports/opencode-2026-07-12-gates-guard-blocking.md` for complete analysis and required actions.

## Full Report

See `.ai/reports/opencode-2026-07-12-gates-blocked.md` for complete analysis.

## Summary

The handoff frames this as OpenCode's GitHub/DevOps ops work per operating-prompt §14, which states: "GitHub operations in particular (opening PRs, release chores, CI fixes) go to OpenCode." However, the mechanical framework guard used to enforce write-lane restrictions that prevented OpenCode from editing `.github/workflows/gates.yml`.

This lane configuration conflict has been resolved by PR #45, which granted `.github/**` to OpenCode's writable lane.

## Pre-discovery Work Completed

Before hitting the guard:
- Current branch protection: master NOT protected (`"protected":false,"protection":{"enabled":false,"required_status_checks":{"checks":[],"contexts":[],"enforcement_level":"off"}}`)
- Target branch created: `exec/opencode/gates-required-and-order` from origin/master
- Version bump check pre-state: `check-version-bump: no changed files vs origin/master — PASS`

## Next Step / future note
After this, a red gate genuinely blocks a merge and a missing bump no longer hides
a real regression. What breaks first: `check-version-bump.sh` enforces the version
bump but NOT a matching CHANGELOG entry — that asymmetry is exactly how `0.0.20`
shipped with a version and no changelog entry (still missing today). That fix is a
script change, so it is NOT yours — it is being handed to Kimi in parallel. Do not
attempt it; do not conflict with it.

## Activity log template
    ## 2026-07-12 HH:MM — opencode
    - Action: Made gates a required check + moved version-bump step so it can't mask real results, per handoff 202607120021-gates-required-check-and-step-order
    - Files: .github/workflows/gates.yml, <repo settings — note as settings, not files>
    - Decisions: <last-step vs separate-job, and why>

## Report back with
- (a) the PR URL + files changed
- (b) branch-protection before/after, pasted verbatim
- (c) the CI evidence for (b) above
- (d) anything you could NOT do or verify, stated plainly

## When complete (protocol v3)
Self-retire: set Status `DONE`, move this file to `.ai/handoffs/to-opencode/done/`.
If blocked, leave it in `open/` as `BLOCKED` with a verbatim `## Blocker` section
containing the exact error — a blocked-but-honest result is far more useful here
than an improvised one, since this is the first time your lane has been exercised.
