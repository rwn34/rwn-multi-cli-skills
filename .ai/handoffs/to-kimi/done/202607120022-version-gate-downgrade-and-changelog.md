# Version gate: reject downgrades + require a CHANGELOG entry
Status: DONE (kimi-cli, 2026-07-12)
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-12 00:22
Auto: yes
Risk: B
Base: origin/master

## Goal
`scripts/check-version-bump.sh` has two holes, both proven tonight:

1. **A version DOWNGRADE passes the gate.** It only asserts `old != new`. A bad
   rebase, a botched merge order, or a careless edit can hand master a version
   LOWER than what adopters already hold. Every onboarded project compares its
   `.ai/.framework-version` against the template's version to decide whether to
   warn about drift — so a downgrade doesn't just fail to warn, it **inverts the
   warning for every adopter simultaneously.**
2. **The gate requires a version bump but NOT a matching CHANGELOG entry.**
   `CHANGELOG.md` falls through `is_versioned()` to the `*)` catch-all
   (`scripts/check-version-bump.sh:58`). This is exactly how **`0.0.20` shipped
   with a version and no changelog entry — it is still missing today**, and the
   changelog visibly skips from `[0.0.19]` to `[0.0.21]`.

## Target state
1. **Semver ordering, not inequality.** The gate must require `new > old` by
   semantic-version comparison, and FAIL on equal-or-lower. `sort -V` is the
   obvious portable primitive; if you use it, be careful that it is a *version*
   sort, and prove the comparison is correct for the cases below — don't assume.
   Required behavior:
   - `0.0.20 -> 0.0.21` PASS
   - `0.0.21 -> 0.0.21` FAIL (unchanged, versioned content changed)
   - `0.0.21 -> 0.0.20` **FAIL (downgrade — this is the new hole being closed)**
   - `0.0.9  -> 0.0.10` PASS (must NOT be treated as a downgrade — this is the
     classic lexicographic-vs-semver trap; test it explicitly)
   - `0.9.0  -> 0.10.0` PASS (same trap, minor position)
   - `1.0.0 -> 0.9.9` FAIL
   - Malformed/missing version on either side → FAIL CLOSED (a gate that cannot
     parse its input must refuse, never wave through).
2. **Require a matching CHANGELOG entry.** When a version bump is required, the
   PR must also add a `## [<new-version>]` heading to `CHANGELOG.md`. Fail with a
   clear, actionable message naming the exact heading expected. This closes the
   asymmetry that produced the missing 0.0.20 entry.
3. **Do NOT back-fill the missing `[0.0.20]` entry.** Nobody knows what shipped in
   it, and inventing history is worse than a visible gap. Report it as an open item
   for the owner to reconstruct or explicitly declare unreleased.

## Constraints
- Scope: `scripts/check-version-bump.sh` + its tests + (if needed) the CHANGELOG
  requirement's docs. Do **NOT** touch `.github/workflows/gates.yml` — OpenCode is
  editing that file in parallel (reordering the steps so a missing bump stops
  masking real test results). You WILL conflict. If your change *needs* a workflow
  edit, STOP and report rather than reaching into it.
- POSIX-sh/bash compatible; must run in CI (Linux) and locally under Git Bash.
- Read first: `.ai/instructions/delivery-integrity/principles.md`,
  `.ai/instructions/karpathy-guidelines/principles.md`. Keep it small — this is a
  gate, and a gate with a clever implementation is a gate nobody trusts.
- Branch `exec/kimi/version-gate-ordering` cut from `origin/master`.
- The gate will demand a version bump for your own PR if you touch versioned
  content — run it against yourself and obey its own verdict. Bump + CHANGELOG as
  required (note the ordering: you may be the first PR that must satisfy your own
  new CHANGELOG rule — that is a feature, not a problem; if it is awkward, say so).

## Tests (the delivery bar — real assertions, no stubs)
Find the existing test surface for this script (look for `scripts/` tests, and
note `.claude/hooks/test_hooks.sh`-style suites elsewhere in the repo for the
house pattern). Extend it, or create one if none exists. Every case in "Target
state 1" above must be a named, executed assertion — especially `0.0.9 -> 0.0.10`
and the downgrade case. Plus: versioned change with a bump but NO changelog entry
must FAIL; a non-versioned change (e.g. `docs/*`, which is denylisted) must PASS
with no bump required.

## Verification (EXECUTE — inspection is not evidence)
- (a) Paste the full test output, verbatim.
- (b) Paste a live demonstration of the downgrade being rejected — construct the
      before/after versions and show the gate exit non-zero with its message.
- (c) Paste `0.0.9 -> 0.0.10` passing (proof you did not introduce a
      lexicographic-comparison bug while fixing a lexicographic-comparison bug).
- (d) Confirm the existing behavior still holds: a normal bump passes, an unchanged
      version with versioned content fails.

## Next step / future note
After this, the version gate is trustworthy in both directions. What breaks first:
the gate still can't tell whether the CHANGELOG entry is *accurate* — only that a
heading exists. An empty or copy-pasted section will pass. That is probably fine
(a human reads the changelog at release), but say so in your report rather than
letting it be discovered later.

## Activity log template
    ## 2026-07-12 HH:MM — kimi-cli
    - Action: Version gate now rejects downgrades + requires a CHANGELOG entry, per handoff 202607120022-version-gate-downgrade-and-changelog
    - Files: scripts/check-version-bump.sh, <tests>
    - Decisions: <comparison primitive + why; changelog-match strictness>

## Report back with
- (a) files changed + PR URL
- (b) full test output, verbatim
- (c) the downgrade-rejection demo and the 0.0.9 -> 0.0.10 proof
- (d) anything you could NOT verify, stated plainly

## When complete (protocol v3)
Self-retire: set Status `DONE`, move this file to `.ai/handoffs/to-kimi/done/`.
Do NOT merge (Tier C — owner gates).

---

## Completion report — kimi-cli, 2026-07-12

### (a) Files changed

- `scripts/check-version-bump.sh` — semver ordering + CHANGELOG-entry requirement + fail-closed parsing (see grep evidence below)
- `scripts/test-check-version-bump.sh` — NEW, 30 named assertions (18 unit + 12 e2e in real temp git repos)
- `.ai/activity/log.md` — prepended kimi-cli entry; repaired kiro header clobber (see (d))
- PR: opened by kimi-cli on branch `exec/kimi/version-gate-ordering` (cut from `origin/master` @ 9c959ef) — URL in chat report

No version bump for this PR: `scripts/check-version-bump.sh` and its test are NOT
versioned content per `is_versioned()` (scripts/* allowlist covers only
`git-hooks/*`, `install-template.sh`, `fleet-init.sh`, `sync-4ai-panes-install.ps1`),
and the gate run against this branch returns
`no versioned framework content changed — PASS`. The gate was run against its own
branch post-commit and obeyed.

### Comparison primitive + why

Pure-bash field-wise numeric compare (`version_gt`), NOT `sort -V`: no external
binary, no dependence on coreutils version-sort semantics, and the lexicographic
traps are provable by direct numeric comparison of each component (`10#` forces
base-10 against leading-zero octal). Unparseable input on either side returns
non-0 → FAIL CLOSED.

CHANGELOG strictness: `grep -q "^## \[<new-version>\]" CHANGELOG.md` on the
working-tree file — heading existence only. Per the future-note: entry ACCURACY
(empty/copy-pasted sections) is NOT gate-checkable; that stays a human
release-read responsibility.

### Grep evidence (self-verify)

```
$ grep -n "version_gt\|is_semver\|CHANGELOG" scripts/check-version-bump.sh
18:#  - A bump requires a matching '## [<new-version>]' heading in CHANGELOG.md
30:CHANGELOG="CHANGELOG.md"
38:# is_semver <v> — strict x.y.z, all three components numeric.
39:is_semver() {
43:# version_gt <new> <old> — 0 iff new > old by semantic-version ordering.
47:version_gt() {
48:  is_semver "$1" || return 1
49:  is_semver "$2" || return 1
127:  if ! is_semver "$new_version"; then
134:  if ! is_semver "$old_version"; then
141:  if ! version_gt "$new_version" "$old_version"; then
159:  if ! grep -q "^## \[$new_version\]" "$CHANGELOG" 2>/dev/null; then
161:    echo "FAIL: version bumped to '$new_version' but $CHANGELOG has no '## [$new_version]' heading."
```

### (b) Full test output, verbatim

```
== Part 1: version comparison (unit) ==
PASS  is_semver 1.2.3
PASS  is_semver 0.0.10
PASS  is_semver empty
PASS  is_semver two-part
PASS  is_semver four-part
PASS  is_semver v-prefix
PASS  is_semver letters
PASS  is_semver prerelease
PASS  gt 0.0.20 -> 0.0.21
PASS  gt 0.0.21 -> 0.0.21 equal
PASS  gt 0.0.21 -> 0.0.20 downgrade
PASS  gt 0.0.9 -> 0.0.10 (lex trap)
PASS  gt 0.9.0 -> 0.10.0 (lex trap)
PASS  gt 1.0.0 -> 0.9.9 downgrade
PASS  gt 0.0.08 -> 0.0.9 (leading zero)
PASS  gt malformed new
PASS  gt malformed old
PASS  gt empty old
== Part 2: gate end-to-end in real git repos ==
PASS  e2e 0.0.20 -> 0.0.21 PASS (exit 0)
PASS  e2e 0.0.21 -> 0.0.21 unchanged FAIL (exit 1)
PASS  e2e 0.0.21 -> 0.0.20 DOWNGRADE FAIL (exit 1)
PASS  e2e 0.0.9 -> 0.0.10 lex-trap PASS (exit 0)
PASS  e2e 0.9.0 -> 0.10.0 lex-trap PASS (exit 0)
PASS  e2e 1.0.0 -> 0.9.9 DOWNGRADE FAIL (exit 1)
PASS  e2e malformed HEAD version FAIL CLOSED (exit 1)
PASS  e2e malformed BASE version FAIL CLOSED (exit 1)
PASS  e2e bump without CHANGELOG entry FAIL (exit 1)
PASS  changelog-fail message names ## [0.0.22]
PASS  e2e docs-only change PASS (no bump needed) (exit 0)
PASS  e2e no changed files PASS (exit 0)

==============================================
RESULT: 30 passed, 0 failed
==============================================
```

### (c) Live demos — real temp git repos, gate stdout + exit codes

Downgrade rejected (0.0.21 -> 0.0.20, changelog entry present so ONLY ordering decides):

```
Versioned framework content changed:
  - .ai/tools/tool.sh
package.json .version: base='0.0.21' head='0.0.20'

FAIL: tools/multi-cli-install/package.json version 0.0.21 -> 0.0.20 is a DOWNGRADE.
      Adopters holding '0.0.21' would see the drift warning INVERTED.
      The version must strictly increase.
exit=1
```

Lexicographic trap (0.0.9 -> 0.0.10 must PASS):

```
Versioned framework content changed:
  - .ai/tools/tool.sh
package.json .version: base='0.0.9' head='0.0.10'
check-version-bump: version bumped 0.0.9 -> 0.0.10 with CHANGELOG entry — PASS
exit=0
```

Existing behavior intact — normal bump passes; unchanged version fails:

```
### normal bump 0.0.20 -> 0.0.21 with changelog
check-version-bump: version bumped 0.0.20 -> 0.0.21 with CHANGELOG entry — PASS
exit=0

### unchanged 0.0.21 -> 0.0.21, versioned content changed
FAIL: Framework content changed but tools/multi-cli-install/package.json version was not bumped
      (still '0.0.21') — onboarded projects won't see the drift.
      Bump the version.
exit=1
```

### (d) Could NOT verify / caveats, stated plainly

1. **CHANGELOG accuracy** is unverifiable by a gate (agreed with the future-note):
   an empty or copy-pasted `## [x.y.z]` section passes. Human release-read stands.
2. **Linux CI run of the new tests is unverified locally** — tests were executed
   under Git Bash (Windows). They use only bash + git + sed/grep/mktemp, same as
   the existing suites, but `bash scripts/test-check-version-bump.sh` on ubuntu
   is proven only by the CI run on this PR.
3. **CI does not run the new suite yet.** `gates.yml` has no step for it and I was
   forbidden to touch that file (OpenCode's lane — which turned out BLOCKED on a
   lane conflict anyway, see `.ai/reports/opencode-2026-07-12-gates-blocked.md`).
   Follow-up for whoever lands gates.yml: add `bash scripts/test-check-version-bump.sh`.
4. **The missing `[0.0.20]` entry was NOT back-filled**, per instruction 3. Open
   item for the owner: reconstruct it or explicitly declare 0.0.20 unreleased.
5. **Shared-tree findings handled, not silently absorbed:** opencode's 07:12
   activity prepend had clobbered the `## 2026-07-11 22:59 — kiro-cli` header
   line in the uncommitted working tree — restored verbatim from git HEAD, no
   entry content rewritten. Opencode's complete 07:12 BLOCKED entry was orphaned
   uncommitted; it rides in this commit. An uncommitted
   `.ai/tools/dispatch-handoffs.sh` edit (F2 thread, `--dangerously-skip-permissions`
   for headless claude) is NOT mine and was left untouched in the working tree.
