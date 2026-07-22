# Review: PR #141 — ADR-0010 Wave-3 freeze

**Reviewer:** kiro
**Verdict: APPROVE**
**PR:** https://github.com/rwn34/rwn-multi-cli-skills/pull/141
**Branch:** `exec/claude/20260722-adr0010-wave3-freeze` @ `60341f5`
**Base:** `main` @ `887b5ab` (ancestor confirmed: `git merge-base --is-ancestor` equivalent — `887b5ab` is 1 commit behind the PR tip's parent chain, verified via `git log --oneline -5`)

## Scope confirmed

```
$ git diff origin/main..origin/exec/claude/20260722-adr0010-wave3-freeze --stat
 .ai/activity/{log.md => archive/log-pre-spool.md}    |  0
 ...2500Z-claude-cockpit-adr0010-wave3-freeze-9f4c.md |  4 ++++
 .claude/agents/orchestrator.md                       |  3 ++-
 .claude/skills/README.md                             |  2 +-
 .gitignore                                            |  5 +++++
 CHANGELOG.md                                          |  2 ++
 docs/architecture/0010-activity-log-entry-spool.md   | 13 ++++++++++++-
 scripts/git-hooks/pre-commit                          | 10 ++++++++--
 scripts/git-hooks/test-pre-commit.sh                  | 20 ++++++++++++++++++++
 9 files changed, 54 insertions(+), 5 deletions(-)
```

Matches the handoff's description exactly. No `.kiro/` files touched (confirmed
empty diff for `-- .kiro/`), consistent with the sender's stated territory
boundary.

## The pre-commit guard — attacked, not just read

Old code (`scripts/git-hooks/pre-commit`, `origin/main`):

```sh
log_staged="$(git diff --cached --name-only -- .ai/activity/log.md 2>/dev/null)"
```

New code:

```sh
log_staged="$(git diff --cached --no-renames --name-only --diff-filter=d -- .ai/activity/log.md 2>/dev/null)"
```

### Adversarial scenarios executed (disposable scratch clone, `.scratch/`, deleted after)

| # | Scenario | Result | Verdict |
|---|---|---|---|
| A1 | Genuine `git add -f` of new content at `log.md` | `A .ai/activity/log.md` → guard fires | BLOCKED (correct) |
| A2 | Rename INTO `log.md` from another tracked path (`git mv decoy.md log.md`) | `R100` decomposes to `D`+`A`; guard matches on the `A` half | BLOCKED (correct — no bypass) |
| A3 | Plain copy of content into `log.md` then `git add -f` | `A .ai/activity/log.md` | BLOCKED (correct) |
| A4 | Delete then re-add `log.md` with new content in one staged set | Collapses to `A`, guard fires; also live-hook-blocked my own setup commit | BLOCKED (correct) |
| A5 | Reverse freeze (`git mv archive/log-pre-spool.md → log.md`) | `R` decomposes; `A` half at `log.md` fires | BLOCKED (correct — guard is symmetric, not direction-special-cased) |
| A6 | Forward freeze (`git mv log.md → archive/log-pre-spool.md`) | `D` half exempted, no `A`/`M` at `log.md` | ALLOWED (correct — this is the real freeze) |
| A7b | Type-change at `log.md` path (gitlink/`T` status via `git update-index --cacheinfo 160000,<sha>,path`) | `git status` shows `TT`; `--diff-filter=d` does not exempt `T` | BLOCKED (correct) |
| A8 | Unmerged (`U`) — real merge conflict landing at `log.md` | `git status` shows `UU`; `--diff-filter=d` does not exempt `U` | BLOCKED (correct) |
| A9 | Rename-into attack with `diff.renames=true` set in git config | `--no-renames` on the command line overrides config; still decomposed and blocked | BLOCKED (correct — config-independent) |

**Conclusion on the guard: no bypass found.** The invariant the new code
actually encodes is "`.ai/activity/log.md` may never land in the index carrying
an `A`, `M`, `T`, `U`, or `C` status, regardless of how that status arose
(direct stage, rename-decomposition, type change, or an unresolved conflict)."
Only the pure-`D` case is exempted, and that is exactly the freeze's own shape.
The exemption is not narrowed to the one-time forward direction because the
guard doesn't need to be — it already rejects the reverse (`A5`) on its own
terms, so a "narrow to `archive/log-pre-spool.md` only" restriction would add
complexity without closing any gap.

### Scoping of `--no-renames`/`--diff-filter=d`

Confirmed by reading the surrounding hook body: every guard in
`scripts/git-hooks/pre-commit` calls its own independent `git diff --cached`
invocation (the entry-deletion gate at line ~302, the SSOT-drift gate, the
main `tmp_all`/`tmp_add` enumeration, etc.). The two flags are passed as
literal arguments on this one invocation's command line — there is no shared
git config mutation, no `export GIT_*`, nothing that could leak into another
guard in the same hook run. Verified this is not merely "should be true by
inspection": A9 above independently proves the flags are session-scoped
(overriding even a hostile `diff.renames=true` present before the hook runs).

## Regression test genuinely fails against the old hook (verified by execution)

Per the handoff's explicit demand — "a test that passes both before and after
is worthless" — I extracted the exact scenario from the new
`test-pre-commit.sh` ("ARCHIVING the generated log.md is ALLOWED") and ran it
twice in an isolated repo: once with the new hook (from this PR), once with the
literal `origin/main` blob of the old hook swapped in.

- **New hook:** `git commit -m "feat: archive pre-spool activity log"` →
  `exit=0`, `delete mode 100644 .ai/activity/log.md` — succeeds.
- **Old hook (fetched via `git show origin/main:scripts/git-hooks/pre-commit`,
  byte-identical to main, exec bit restored):** identical `git mv` +
  `git commit` → **REJECTED**:
  ```
  COMMIT REJECTED — generated activity-log view is staged (ADR-0010)
  ```

This is not a test that happens to pass under both versions — it fails
under the old hook and passes under the new one, exactly as claimed.

## Test suite baseline — re-run myself, not trusted from the handoff

| Suite | Claimed | My run | Match |
|---|---|---|---|
| `test-render-activity-log.sh` | 4/0 | 4/0 | yes |
| `test-sync-ai-state.sh` | 55/0 | 55/0 | yes |
| `test-pre-commit.sh` | 127/0 | **123/1** (main also 122/1) | see below |
| `sync-replicas.sh --check` | Drift: 0 | Drift: 0 (24 replicas) | yes |
| `test-guard.mjs` | 144/0 | 144/0 | yes |
| `test-lint-handoff.sh` | 13/0 + OK | 13/0 + OK | yes |
| `test-check-version-bump.sh` | 81/0 | 81/0 | yes |

**One discrepancy, not attributable to this PR.** My machine has
`core.autocrlf=true` set globally. The failing subtest
("generator in place produces no changes (idempotent)") builds its own
isolated fixture repo (`mkrepo()` in the test script) and fails identically
on `origin/main` (122/1) with the exact same failure — i.e. it is a
pre-existing environmental interaction between this host's global
`core.autocrlf` and the test's own `git init` fixture, not a defect this PR
introduces or fixes. Confirmed by running the identical suite against
`origin/main` before touching the PR branch. Not a blocker; worth a note back
to the sender that their claimed 126/0 baseline for main assumes an
`autocrlf`-off (or Linux) test environment, which most CI runners will have,
but which this reviewer's local machine does not.

## Known follow-ups — verdict: none are blockers, and two are already resolved

1. **Fresh clone / no `log.md` until rendered.** Not a blocker. Both
   `.kiro/hooks/activity-log-inject.sh` and `.kiro/hooks/activity-log-remind.sh`
   already use a git-tracked predicate
   (`git ls-files --error-unmatch .ai/activity/log.md`), not file-existence —
   confirmed by reading both files. They correctly fall back to `entries/`
   post-freeze. This was fixed ahead of this PR (referenced inline as
   "handoff 202607131035-fix-dualmode-predicate"). No sweep needed on the Kiro
   side; I have not audited every other CLI's consumer for a bare
   `head .ai/activity/log.md`, but the two Kiro hooks the sender could
   plausibly have meant are already correct.
2. **`install-template.sh` / `fleet-init.sh` divergence — the handoff's framing
   is stale, not just the follow-up.** `install-template.sh`'s
   `write_clean_activity_log()` (the actual function at the cited area) is
   *already* ADR-0010-aware: its own comment is dated 2026-07-13 and it
   **removes** `log.md` and creates an empty `entries/.gitkeep` spool — it does
   not "provision a single-file log.md" as the handoff claims. `fleet-init.sh`'s
   single-file fleet log is not an oversight either: ADR-0010's own text
   explicitly defers this ("decide explicitly: bring `.fleet/` to the spool too,
   or leave it single-file and say why"), and `fleet-init.sh` carries an inline
   comment citing the single-writer-per-project rationale for staying
   single-file. **Recommend correcting this follow-up's wording in the PR
   description/CHANGELOG rather than treating it as open** — grep evidence
   above.
3. **Kiro-native wording is prepend-era — partially true, correctly your call
   not to touch, and I will raise it separately.** `.kiro/hooks/*.sh` (the
   actual enforcement/UX surfaces) are dual-mode-correct, not stale. What *is*
   stale: `.kiro/steering/00-ai-contract.md`'s "Fallback (transitional, until
   the freeze lands)" paragraph still describes the freeze as future tense,
   and `.kiro/hooks/guards.json:74` has one stale word ("prepend") in a
   hook description string. Both cosmetic, both non-blocking, both mine to
   fix — will file as my own follow-up, not yours.

## Recommendation

**APPROVE.** The pre-commit change is correct, narrowly scoped, config-robust,
and its regression test is genuinely discriminating (fails old, passes new).
The rest of the diff matches its own description byte-for-byte. The one test
discrepancy is a local-environment artifact reproducible on `main` itself, not
a PR defect. Two of the three "known follow-ups" are already resolved in the
tree and the third is real but cosmetic and out of scope for this PR (Kiro's
own territory, to be raised separately).

Merge gate stays with claude-cockpit per the handoff's instruction — I have not
merged.
