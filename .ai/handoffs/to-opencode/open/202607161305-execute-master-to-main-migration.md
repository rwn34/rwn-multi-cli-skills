# Execute default-branch migration `master` → `main`
Status: IN_PROGRESS (PR created, awaiting merge)
Sender: claude-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-16 20:05 (UTC+7)
Auto: yes
Risk: B
Next: claude-code (final review and merge)

## Goal

Apply the file changes and GitHub operations that make `main` the sole default branch of
`rwn-multi-cli-skills`, retiring `master`, per the audited plan at
**`.ai/reports/migrate-master-to-main-plan.md`**. Read that plan first and in full — it is
binding. This handoff is the execution wrapper; the plan is the spec.

## Current state

- Default branch is `master`. **`main` does not exist** — not local, not remote, not on GitHub.
- `master` is protected: required checks `["gates","framework-check"]`, strict=false,
  `allow_force_pushes: false`, `allow_deletions: false`, `enforce_admins: false`.
- `gh` 2.87.3 is authenticated as `rwn34` (scopes include `repo`, `workflow`).
- 172 `master` occurrences across 27 files — but **most must NOT change** (plan §1C).
- The dispatch/base-resolution path is **already migrated**: `base_for()` in
  `.ai/tools/dispatch-handoffs.sh` and `Get-DeclaredBase` in `pane-runner.ps1` resolve
  `origin/HEAD → origin/main → main → HEAD` and never hardcode `master`. **Do not "fix"
  them** — they need zero changes.

## Target state

`main` is the default branch, protection migrated intact, `master` gone, all tests green,
`origin/HEAD → origin/main` so base resolution auto-follows.

---

## ⛔ P0 — BLOCKING PRECONDITION. Check this FIRST.

**Do not start until both are true.** Verify, do not assume:

```bash
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills status --short .ai/   # expect: NO ' D ' lines
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills log origin/master..master --oneline  # expect: empty
```

**P0 status as of `kimi-cockpit` handoff review (2026-07-16 19:41 UTC+7): CLEAR.**
- `git status --short .ai/` shows **zero** ` D ` lines.
- `git log origin/master..master --oneline` is **empty**.

Run the two commands yourself and verify they are still clear before starting. **If either
fails at execution time: STOP.** Set this handoff to `BLOCKED`, append a `## Blocker`
section with verbatim command output, and leave it in `open/`.

---

## Steps

Work on a branch. Do not commit to `master` directly.

1. **Verify P0** (above). If blocked, stop and report.

2. **Apply file changes** exactly as tabled in plan §1A, §1B, §1D. Cut a branch from
   `origin/master`. Do not touch anything in plan **§1C** (deliberate `master` that must
   survive: ADRs, CHANGELOG, force-push-guard fixtures, and the `test-pane-runner.ps1`
   502–510 master-default regression test). **No repo-wide find-and-replace** — §1C exists
   precisely because that would break things.

   Excluded — Claude's lane, do not edit: `.claude/agents/release-engineer.md`, any ADR,
   `CHANGELOG.md`.

3. **Item 12 — `Assert-WorktreeFresh` in `tools/4ai-panes/pane-runner.ps1` (line 1278).**
   Do **not** simply swap `origin/master` → `origin/main`. Implement plan §2: extract the
   offline-first resolution from `Get-DeclaredBase` (lines 380–421) into a shared
   `Resolve-DefaultBase` helper, call it from both sites, and **fail CLOSED** when the base
   cannot resolve. Rationale: today the hardcoded ref makes this guard **fail open** on a
   non-`master` repo (`rev-list` yields nothing → `$behind` fails `^\d+$` → guard silently
   passes), defeating the ADR-0004 reverse-write guard. Add a `test-pane-runner.ps1` case
   for the fail-closed path, keeping 502–510 intact.

4. **Open a PR into `master`** (still the default at this point, so `gates` +
   `framework-check` run normally). **Do not merge it yourself** — final review and merge
   are Claude's gate (author ≠ reviewer). Report the PR URL and stop for review.

5. **After Claude merges**, rename on GitHub — one atomic operation that moves the branch,
   the default, and the protection rules, and installs redirects:
   ```bash
   gh api -X POST repos/rwn34/rwn-multi-cli-skills/branches/master/rename -f new_name=main
   ```
   **Do not delete `master` manually** and do not remove protection to do it — the rename
   consumes `master`. (`allow_deletions: false` means a delete would require dropping
   protection first, opening an unprotected window on the default branch. Don't.)

   ⚠ Timing: once step 4's changes are merged, `gates.yml`/`framework-check.yml` trigger on
   `main` only — so pushes to `master` stop running required checks. Run the rename
   **immediately after** the merge, same session. Do not leave that window open.

6. **Repoint refs and config** (plan §3.6):
   ```bash
   git -C <primary> remote set-head origin -a
   git -C <primary> config init.defaultBranch main
   ```
   `origin/HEAD → origin/main` is the linchpin: it is what makes `base_for()` and
   `Get-DeclaredBase` resolve `main` with no code change. Leave global
   `init.defaultBranch` alone (unset, out of repo scope).

7. **Repoint stale branch tracking.** ~40 of ~120 `branch.*` entries have
   `merge = refs/heads/master` and GitHub's rename does not touch local config:
   ```bash
   git -C <primary> config --get-regexp "^branch\..*\.merge$" | grep "refs/heads/master$"
   git -C <primary> config branch.<name>.merge refs/heads/main   # for each branch still in use
   ```
   Dead branches may be left as-is. **Do not prune or delete worktrees/branches** — that is
   Tier-B repo hygiene and belongs to Claude.

8. **Reconcile live worktrees** (plan §4) — for each of `claude`, `kimi`, `kiro`,
   `opencode` under `C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/`:
   ```bash
   git -C <wt> fetch origin --prune
   git -C <wt> rebase origin/main
   ```
   `.ai/` needs no per-worktree action — it is a junction to the primary.

9. **Run the full verification suite** (plan §7). Paste raw output.

10. **Emit the verification handoff to kimi-cockpit** — required, not optional:
    `.ai/handoffs/to-kimi/open/<UTC YYYYMMDDHHMM>-verify-master-to-main-migration.md`
    (filename prefix from `date -u +%Y%m%d%H%M`; `Created:` line in UTC+7). It must set
    `Sender: opencode-auto`, `Recipient: kimi-cockpit`, `Auto: yes`, `Risk: A`, reference
    `.ai/reports/migrate-master-to-main-plan.md`, and ask Kimi to independently verify plan
    §7 — in particular that the §1C `master` references **survived** and that
    `test-pane-runner.ps1` cases 502–510 still pass.

11. **Self-retire** (protocol v3): set this file's Status to `DONE` and move it to
    `.ai/handoffs/to-opencode/done/`.

## Verification

Execute every item — do not read and assume. Paste raw output for each.

- (a) `gh repo view --json defaultBranchRef` → `{"defaultBranchRef":{"name":"main"}}`
- (b) `gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection` → contexts
      `["gates","framework-check"]`, `allow_force_pushes: false`, `allow_deletions: false`
- (c) `git ls-remote origin refs/heads/master` → empty
- (d) `git -C <primary> symbolic-ref refs/remotes/origin/HEAD` → `refs/remotes/origin/main`
- (e) `bash .ai/tests/test-dispatch-worktree.sh` → passes (esp. case 4c)
- (f) `pwsh tools/4ai-panes/test-pane-runner.ps1` → passes, **including 502–510**
- (g) `bash scripts/test-check-version-bump.sh` → passes
- (h) `pwsh scripts/test-sync-4ai-panes-install.ps1` → passes
- (i) `bash .ai/tools/dispatch-handoffs.sh` (dry-run, no `--exec`) → base resolves `origin/main`
- (j) `grep -rn "origin/master" tools/ scripts/ .github/ --include=*.ps1 --include=*.sh --include=*.yml`
      → only §1C-sanctioned hits
- (k) A PR into `main` triggers both `gates` and `framework-check`

## Constraints

- **Windows 11 + PowerShell host. No WSL.** `bash` is Git-for-Windows (MSYS) only.
- **MSYS mangles colon-joined args** — never `git show "<ref>:<path>"`; use `git ls-tree` +
  `git cat-file -p <blobsha>`.
- **Grep/Glob do not traverse the `.ai/` junction** from inside a worktree. Audit `.ai/`
  against the primary path or via `git ls-files`.
- Do not merge to `main`/`master` yourself — Claude's gate.
- Do not prune worktrees/branches; do not touch the P0 `.ai/` deletions.
- Do not edit ADRs, `CHANGELOG.md`, or `.claude/`.
- No deploy, no publish, no tag. This migration triggers none of them — and note
  `release.yml` fires on push to the default branch, so **confirm the rename does not
  fire an unintended release run**; if it does, report it immediately.

## Rollback

Reversible at every step — see plan §5. The rename undoes with:
```bash
gh api -X POST repos/rwn34/rwn-multi-cli-skills/branches/main/rename -f new_name=master
```
then `git remote set-head origin -a` in every clone. Nothing in this plan rewrites history.

## Next step / future note

After Kimi's verification, Claude decides whether the decision warrants an ADR or an
amendment note (Claude's lane, Tier B). First thing to break if the surrounding system
changes: any *new* code that hardcodes a branch name instead of resolving `origin/HEAD` —
item 12 is the second instance of that bug class in this repo, which is why §2 asks for a
shared helper rather than another literal.

## Activity log template
    ## 2026-07-16 HH:MM (UTC+7) — opencode-auto
    - Action: executed master→main migration per handoff 202607161305-execute-master-to-main-migration
    - Files: <paths touched>
    - Decisions: <non-obvious choices, or "—">

## Report back with
- (a) The PR URL, and the merge commit SHA Claude approved.
- (b) Full list of files touched, and confirmation that §1C files were NOT touched.
- (c) Raw pasted output for verification items (a)–(k) — output, not a summary.
- (d) The `Resolve-DefaultBase` diff for item 12 + the new fail-closed test result.
- (e) Path of the verification handoff emitted to `to-kimi/open/`.
- (f) Whether the rename fired a `release.yml` run.

## When complete (protocol v3)
Self-retire: set Status to `DONE`, move this file to `.ai/handoffs/to-opencode/done/`.
If blocked (P0 or otherwise), leave it in `open/`, set Status to `BLOCKED`, and append a
`## Blocker` section with **verbatim** error output — not a paraphrase.
