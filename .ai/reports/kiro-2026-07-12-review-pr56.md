# Review: PR #56 — version-at-merge (ADR-0012)

**Reviewer:** kiro-cli · **Author:** claude-code (Plan-designed, coder-implemented)
**PR:** #56 `claude/version-at-merge` @ `74339bb` → `master` (base `b555d47`)
**Verdict: APPROVE**

## Method

Reviewed via a disposable git worktree at the PR head commit (did not disturb
the shared `kiro` worktree, which carries live uncommitted `.ai/` edits from
other CLIs mid-session). Fetched fresh refs, ran every verification step in
the handoff, read the full diff.

## The load-bearing check — adopter drift-detection preserved

```
$ git diff origin/master..HEAD --stat
 .claude/agents/release-engineer.md                 |  21 +++
 .github/workflows/gates.yml                        |  16 +-
 CHANGELOG.md                                       |  36 ++++
 docs/architecture/0012-version-assigned-at-merge.md | 183 +++++++++++++++++++++
 docs/specs/framework-install-drift-check.md        |  15 +-
 scripts/check-version-bump.sh                      |  41 ++++-
 scripts/test-check-version-bump.sh                 |  80 +++++++++
 tools/multi-cli-install/package.json               |   2 +-
 8 files changed, 375 insertions(+), 19 deletions(-)
```

**Confirmed: no drift-detection reader touched.** `Selector.ps1`,
`tools/multi-cli-install/{bin/multi-cli-install.ts,src/upgrade/version.ts}`, and
`.github/workflows/release.yml` all absent from the diff — the coder's claimed
identical-blob-hashes holds by independent stat-diff, not just by their word.
`.version` field shape unchanged (still a bare `"version": "x.y.z"` string in
`tools/multi-cli-install/package.json`, now `0.0.30`). This is exactly what
Candidate 1 needed to preserve and it does.

## Verification executed

```
$ bash scripts/test-check-version-bump.sh   (Git Bash, PR head)
...
RESULT: 38 passed, 0 failed
```

Confirmed Part 3/4 genuinely exercise the new master-push path, not just the
old PR-time logic: correct-bump PASS, no-bump FAIL, downgrade FAIL, the
`0.0.9`→`0.0.10` lex-trap PASS (field-wise numeric compare, not string sort),
unresolvable-base-ref exit-2 (fail closed), and the PR-carve-out (feature
branches pass without a bump). All present, all passing.

```
$ bash scripts/check-version-bump.sh origin/master   (PR head)
Versioned framework content changed:
  - .claude/agents/release-engineer.md
  - .github/workflows/gates.yml
package.json .version: base='0.0.28' head='0.0.30'
check-version-bump: version bumped 0.0.28 -> 0.0.30 with CHANGELOG entry — PASS
```

Correct base/head detected, CHANGELOG heading `## [0.0.30]` confirmed present
(read directly, see below).

```
$ bash .ai/tools/check-ssot-drift.sh   (PR head)
Checked: 24 replicas, Drift: 0
```

No SSOT drift introduced.

## Scrutiny items (per handoff)

1. **Detective-gate flip.** Confirmed in `.github/workflows/gates.yml`: the
   version-bump step is `if: github.event_name == 'push'`, positioned as the
   **last** step, after SSOT drift / four hook suites / OpenCode guard / git
   pre-commit backstop / installer asset-drift / installer typecheck+tests.
   PR runs never execute it (`grep` for `check-version-bump` in the workflow
   file returns exactly one hit, guarded to push) — the substantive suites
   carry no event guard, so they still run unchanged on every PR. The
   fail-closed unresolvable-`github.event.before` path is real: `check-version-bump.sh`
   does `git rev-parse --verify --quiet "$BASE_REF^{commit}"` before any diff
   and exits 2 with an explicit "cannot diff (env error)" message if it fails
   — matches an all-zero/force-push edge correctly refusing rather than
   waving through.
2. **Transition edge.** This PR itself bumps `0.0.28` → `0.0.30` in
   `tools/multi-cli-install/package.json` and adds the matching `## [0.0.30]`
   CHANGELOG heading — i.e. it satisfies the **old** PR-time rule (still in
   force for this PR's own merge) while shipping the **new** rule for every
   PR after it. Read `CHANGELOG.md` directly: `## [0.0.30] - 2026-07-12` is
   present with real, non-TODO release notes describing exactly this change,
   followed by `## [0.0.28]` (the prior entry) below it — coherent, no gap,
   no wedge for the next PR (which will add bullets under a fresh
   `## [Unreleased]` per the new convention documented inline in the
   CHANGELOG header comment).
3. **gates.yml step ordering.** Confirmed above — last step, push-only,
   substantive steps unaffected.
4. **ADR-0012 soundness.** Read in full. The residual risk section states the
   detective-vs-preventive weakening honestly: names exactly what's exposed
   (tip-of-master installs, bounded window), and gives a concrete reason the
   blast radius is small — `release.yml`'s auto-cut derives its tag from the
   same `.version` SSOT and won't publish until it moves, so the *released*
   artifact stream is never affected, only an unlucky tip-of-master adopt
   during the window between a bad merge and the resulting red `gates` run.
   Not hand-waved — it names the mechanism, not just an assurance.
5. **Test coverage.** 38/0, and independently confirmed (not just trusted)
   that Part 3/4 cover the specific cases the handoff called out — see above.

## Other findings

- `.claude/agents/release-engineer.md` gains a new "Version assignment at
  merge (ADR-0012)" section giving the release-engineer the exact 3-step
  merge-time discipline (assign one version strictly greater than master's,
  promote `## [Unreleased]` bullets, bump `package.json`). Consistent with
  the ADR and the CHANGELOG header comment — three places describe the same
  convention identically, no drift between them.
- `docs/specs/framework-install-drift-check.md`'s open question on
  version-bump-discipline enforcement is resolved by reference to ADR-0012 —
  confirmed the diff there is a pointer update, not a design change.
- No unrelated files touched. Diff is scoped exactly to the release-governance
  change described.

## Verdict

**APPROVE.** The one thing this change must not break — adopter
drift-detection — is independently verified untouched (no reader file in the
diff, unchanged field shape, and the ADR's own consequences section names the
readers explicitly). The detective-vs-preventive trade is real but bounded
and honestly stated, not hand-waved. Test coverage matches the claimed 38/0
and actually exercises the new code paths. Step ordering fix is real and
verified in the workflow file, not just described in prose.

Ready for the owner's Tier-C ADR merge gate.
