# Review PR #56 — version-at-merge (ADR-0012)
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-12 18:00
Completed: 2026-07-12 18:55
Auto: yes
Risk: A
Base: origin/master

## Result

**Verdict: APPROVE.** Full review report:
`.ai/reports/kiro-2026-07-12-review-pr56.md`. Posted as PR comment:
https://github.com/rwn34/rwn-multi-cli-skills/pull/56#issuecomment-4950498060

Verified independently (not just trusted): no drift-detection reader
(`Selector.ps1`, installer `version.ts`/`multi-cli-install.ts`, `release.yml`)
appears in `git diff origin/master..HEAD --stat`; `.version` field shape
unchanged; `test-check-version-bump.sh` 38/0 on PR head (Git Bash);
`check-version-bump.sh origin/master` PASS (0.0.28 -> 0.0.30, CHANGELOG
heading present); `check-ssot-drift.sh` Drift 0 (24 replicas); `gates.yml`
version-bump step confirmed `if: github.event_name == 'push'` and last in the
job; no residual PR-time invocation of the check anywhere in the workflow
tree. Did not merge — Tier C, owner-gated per protocol.

## Goal
Peer-review **PR #56** (`claude/version-at-merge`, commit `74339bb`, ADR-0012).
Release-governance change: stop bumping the framework version on feature branches;
the release-engineer assigns it at merge; `check-version-bump.sh` becomes a
master-push DETECTIVE gate. Designed by the Plan agent, implemented by a coder — so
YOU review (author != reviewer; you did neither). This review gates the merge (the
ADR merge is also owner-gated — Tier C — but your review must clear first).

## The load-bearing thing to verify above all else
**Adopter drift-detection must still work.** Onboarded projects compare their
`.ai/.framework-version` against the template `package.json .version` via
`tools/4ai-panes/Selector.ps1` `Test-FrameworkDrift` and the installer
(`tools/multi-cli-install/{bin/multi-cli-install.ts,src/upgrade/version.ts}`). This
only holds if the version still increments once per content-change. Candidate 1
preserves that (one bump per merge). CONFIRM:
1. The PR does NOT modify `Selector.ps1`, the installer, or `release.yml` (the coder
   claims identical blob hashes — verify independently: `git diff origin/master..claude/version-at-merge --stat` should show none of them).
2. `.version` is still the field those readers read, unchanged in shape.
If the PR touched any drift-detection reader, REQUEST CHANGES — that's the one thing
this change must not break.

## Also scrutinize
1. **The detective-gate flip.** `check-version-bump.sh` now evaluates the master
   push (`github.event.before..after`) instead of a PR base..HEAD. Confirm: PR#44
   hardening intact (semver-increase, reject equal+downgrade, CHANGELOG-heading
   requirement, fail-closed on unparseable); the new fail-closed guard on an
   all-zero/unresolvable `github.event.before` (first-push edge) is correct; and it
   is a genuine no-op on PR events (feature branches pass without a bump).
2. **The transition edge.** This PR itself bumps 0.0.28 -> 0.0.30 under the OLD rule
   (so CI is green on merge), while introducing the new rule for FUTURE PRs. Confirm
   that's coherent and won't wedge the next PR.
3. **gates.yml step ordering.** The version-bump step now runs LAST and only on push,
   so a missing bump no longer masks real test failures. Confirm the substantive
   steps (drift/hooks/backstop) still run on PRs unchanged.
4. **ADR-0012 soundness.** It amends the ADR-0007 P2 gate discipline and resolves the
   `docs/specs/framework-install-drift-check.md` open question. Confirm the residual
   (detective-not-preventive; exposure = tip-of-master installs only; bounded by
   fleet reaction to a red master) is stated honestly, not hand-waved.
5. **Test coverage.** `scripts/test-check-version-bump.sh` (38 tests) — verify the
   master-push-mode cases actually exercise the new path (correct-bump PASS,
   no-bump FAIL, downgrade FAIL, 0.0.9->0.0.10 PASS, unresolvable-ref exit-2,
   PR-passes-without-bump).

## Verify (execute)
- Check out PR #56's head; run `bash scripts/test-check-version-bump.sh` -> paste (expect 38/0).
- `bash scripts/check-version-bump.sh origin/master` on the branch -> paste verdict.
- `git diff origin/master..HEAD --stat` -> confirm no drift-detection reader appears.
- `bash .ai/tools/check-ssot-drift.sh` -> Drift 0.

## Deliverable
Review report `.ai/reports/kiro-2026-07-12-review-pr56.md` + PR comment with verdict:
**APPROVE / APPROVE-WITH-NOTES / REQUEST-CHANGES**, evidence-backed. A drift-detection
regression is the highest-value find. On APPROVE it goes to the owner for the ADR merge.

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kiro/done/`. Do NOT merge.
