# Migration plan — default branch `master` → `main`

Author: claude-auto
Created: 2026-07-16 20:05 (UTC+7)
Source handoff: `.ai/handoffs/to-claude/open/202607161231-migrate-default-branch-master-to-main.md`
Executor: `opencode-auto` (see `.ai/handoffs/to-opencode/open/202607161305-execute-master-to-main-migration.md`)
Status: PLAN — not executed. Blocked on precondition P0 below.

---

## 0. Executive summary — read this before anything else

Three findings materially change the shape of the task the source handoff described.

**(a) The premise about `base_for()` is FALSE.** The handoff says
`.ai/tools/dispatch-handoffs.sh` and `base_for()` hardcode `origin/master` and must be
fixed. They do not. `base_for()` was *already* migrated and exists specifically to avoid
hardcoding. Its resolution order is:

    Base: field  →  origin/HEAD (offline)  →  origin/HEAD (network re-detect)
                 →  origin/main  →  main  →  HEAD

`master` is **not in the fallback chain at all**. The only `master` strings in that file
are comments describing what it avoids. Same for `tools/4ai-panes/pane-runner.ps1`'s
`Get-DeclaredBase` (lines 368–421) and `.ai/tests/test-dispatch-worktree.sh`, which
already carries a `main`-default regression test (case 4c). **No change is needed in the
dispatch/base-resolution path.** It resolves `origin/HEAD` today (= `origin/master`) and
will resolve `origin/main` automatically after the rename, with zero code edits.

**(b) There is a live coordination-plane incident that outranks this migration.**
The primary checkout has **268 uncommitted working-tree deletions under `.ai/`**.
`.ai/tools/` and `.ai/tests/` **do not exist on disk** — the entire dispatch toolchain
(`dispatch-handoffs.sh`, `reconcile-done-handoffs.sh`, `claim-handoff.sh`,
`fleet-health.sh`, 15 files) is gone from the working tree. Because every worktree's
`.ai/` is a junction to the primary, **all four CLIs see the missing files**. The blobs
are intact in git (`origin/master`), so this is recoverable, not lost. But it means the
documented dispatch command in `CLAUDE.md` — `bash .ai/tools/dispatch-handoffs.sh --exec`
— **cannot run right now.** This plan must not be executed on top of a broken plane.

**(c) The primary checkout is being mutated by another CLI right now.** During
fact-gathering it moved from `ai-template-install` @ `952070a` to `master` @ `65c1322`
mid-read, and its tree is missing `.github/workflows/gates.yml` and
`framework-check.yml`. `master` is currently **1 commit ahead of `origin/master`**
(unpushed). Audit facts in this plan were therefore taken from the
`exec/claude/202607161231-…` worktree (behind=0, ahead=0 vs `origin/master`), which is
the trustworthy reference.

**Net:** the real migration is much smaller than the handoff assumed — 3 workflow files,
2 scripts, 1 hardcoded staleness check, 1 git config, docs, plus the GitHub-side rename.

---

## P0 — BLOCKING PRECONDITION

**Do not begin this migration until the 268 `.ai/` deletions in the primary are
resolved.** Resolution means one of:

- The owning CLI commits them deliberately (they are intentional), **or**
- They are restored: `git -C C:/Users/rwn34/Code/rwn-multi-cli-skills restore -- .ai/`
  (recovers all 15 `.ai/tools/` files + `.ai/tests/` from the index), **or**
- The owner explicitly rules on them.

Rationale: this migration's own verification depends on `.ai/tools/` scripts existing,
and a branch rename executed against a tree in an unknown state cannot be safely rolled
back. Restoring is *not* part of this migration — it is a separate incident, flagged
to the owner. Note also that `master` @ `65c1322` is 1 ahead of `origin/master` and
unpushed; that commit must be pushed or dropped before the rename so nothing is stranded.

---

## 1. Audit — every `master` reference, mapped

172 occurrences across 27 files. Reference: the `exec/claude/202607161231-…` worktree at
`origin/master` (`95946eb`). Categorised by required action.

### 1A. MUST CHANGE — functional, branch-name-dependent

| # | File | Line(s) | Current | Replacement |
|---|---|---|---|---|
| 1 | `.github/workflows/gates.yml` | 17 | `      - master` (pull_request.branches) | `      - main` |
| 2 | `.github/workflows/gates.yml` | 20 | `      - master` (push.branches) | `      - main` |
| 3 | `.github/workflows/gates.yml` | 10 | comment: "enable branch protection on \`master\`" | `main` |
| 4 | `.github/workflows/gates.yml` | 97–98, 104 | comments: "master push", "previous master tip" | `main` |
| 5 | `.github/workflows/framework-check.yml` | 14 | `      - master` (push.branches) | `      - main` |
| 6 | `.github/workflows/framework-check.yml` | 5 | comment: "before they land on master" | `main` |
| 7 | `.github/workflows/release.yml` | 35 | `      - master` (push.branches) | `      - main` |
| 8 | `.github/workflows/release.yml` | 9, 24, 42, 44, 109, 120, 187 | comments: "push to master", "master pushes", "master path" | `main` |
| 9 | `scripts/sync-4ai-panes-install.ps1` | 196 | `$branch -ne 'master'` — **live provenance guard** | `$branch -ne 'main'` |
| 10 | `scripts/sync-4ai-panes-install.ps1` | 197 | REFUSED message "not primary/master … Only merged master code" | `main` |
| 11 | `scripts/sync-4ai-panes-install.ps1` | 14, 26–27, 146 | doc-comments describing the guard | `main` |
| 12 | `tools/4ai-panes/pane-runner.ps1` | 1278 | `git rev-list --count HEAD..origin/master` — **hardcoded** | resolve default branch (see §2) |
| 13 | `tools/4ai-panes/pane-runner.ps1` | 1269, 1283, 1285 | `origin/master` in synopsis + STALE messages | resolved default branch |
| 14 | `scripts/check-version-bump.sh` | 61–62 | local usage default `BASE_REF=origin/master` | `origin/main` |
| 15 | `scripts/check-version-bump.sh` | 3, 5–6, 13, 20, 60, 224 | comments: "push: master", "previous master tip" | `main` |
| 16 | git config (repo-local, **not a file**) | — | `init.defaultbranch master` | `main` |

**Item 12 is a latent bug independent of this migration.** `Assert-WorktreeFresh`
hardcodes `origin/master` while `Get-DeclaredBase` in the *same file* (line 369)
explicitly documents "never hardcodes `origin/master`". The two disagree. On a `main`
repo, `git rev-list --count HEAD..origin/master` fails, `$behind` does not match
`^\d+$`, and the staleness guard **silently passes** — fail-open. That is exactly the
reverse-write guard ADR-0004 added after the 2026-07-13 outage. Fixing it by
substituting `origin/main` reintroduces the same fragility for adopter repos on
`master`; it should instead reuse the existing offline-first resolution.

### 1B. MUST CHANGE — tests that assert on the above

| # | File | Line(s) | Note |
|---|---|---|---|
| 17 | `scripts/test-sync-4ai-panes-install.ps1` | 4, 8, 10, 58, 118–119, 144, 148–149, 162–163, 166–167, 170, 176, 187 | Sandbox builds `git init -b master`; asserts `branch=master primary=yes`. Must track item 9. |
| 18 | `scripts/test-check-version-bump.sh` | 125, 281 | `git -c init.defaultBranch=master init -q` fixtures. Align to `main`. |
| 19 | `tools/4ai-panes/test-pane-runner.ps1` | 171 | Mock `GetDeclaredBase` returns `'origin/master'`; align to `origin/main`. |
| 20 | `tools/4ai-panes/test-pane-runner.ps1` | 591, 596 | `git branch -M master` / `git push -u origin master` fixture. Align to `main`. |
| 21 | `tools/4ai-panes/test-pane-runner.ps1` | 44 | Comment "defaults to origin/master" — now inaccurate either way; correct it. |

### 1C. MUST NOT CHANGE — deliberate `master` that must survive

Blind find-and-replace across the repo would break these. Enumerated so the executor
does not "helpfully" fix them.

| File | Line(s) | Why it stays |
|---|---|---|
| `tools/4ai-panes/test-pane-runner.ps1` | 502–510 | **Regression test** asserting a repo whose default is `master` resolves to `origin/master`. This tests *adopter* repos on `master`. Deleting it removes real coverage. Keep verbatim. |
| `.ai/tests/test-dispatch-worktree.sh` | 264–266, 315 | Case 4c already asserts a `main`-default repo cuts from `origin/main`. Its `master` mentions are the bug it guards. Keep. |
| `.opencode/plugin/test-guard.mjs` | 94–96 | Fixture strings for the force-push guard (`git push --force origin master`). Branch name is arbitrary; guard is branch-agnostic. |
| `tools/multi-cli-install/test/installer.test.ts` | 107 | Same — force-push guard fixture. |
| `CHANGELOG.md` | 15 occurrences | **Historical record.** Entries describe what happened on `master` at the time. Rewriting falsifies history. |
| `docs/architecture/0012-version-assigned-at-merge.md` | 20 occurrences | **ADR — immutable decision record.** |
| `docs/architecture/0013-auto-tag-as-handoff-ownership-boundary.md` | 5 | ADR. Line 126–130 cite `git ls-tree origin/master` as *forensic evidence from a past incident*. |
| `docs/architecture/0014-enforcement-layer-changes-via-peer-reviewed-pr.md` | 8 | ADR. |
| `docs/architecture/0004-worktree-multi-project-topology.md` | 3 | ADR. Lines 164–167 already document the `origin/HEAD → origin/main` chain. |
| `tools/4ai-panes/README.md` | 9 | Historical provenance ("imported from local checkout `master` @ `06c5d84`"). A past fact. |
| `README.md` | 250 | Troubleshooting entry `error: pathspec 'master' did not match…` — helps users whose repo has *no* master. Still correct. |
| `scripts/install-template.sh` | 29 | Comment `# target's branch at install time (main/master/etc.)` — branch-agnostic by design. |

**ADR handling:** ADRs are append-only decision records. Do **not** edit their bodies.
The default-branch change is a new decision; if the owner wants it recorded, it belongs
in a **new ADR or an amendment note**, authored by Claude (ADR authorship is Claude's
lane, Tier B — not OpenCode's). Explicitly out of scope for the execution handoff.

### 1D. DOCS — prose updates (non-functional, low risk)

| File | Line(s) | Change |
|---|---|---|
| `README.md` | 55, 76, 195, 199 | Already explains `main` vs `master` for adopters. Update the Phase-6 example `git checkout master` → `main`; keep the "substitute if yours differs" guidance. |
| `scripts/README.md` | 74, 86 | `git checkout master` → `main`. |
| `docs/specs/4ai-panes-install-sync.md` | 18, 207 | Documents the item-9 guard ("must be `master`"). Must track item 9. |
| `docs/specs/framework-install-drift-check.md` | 340 | "detective check on `push: master`" → `main`. |
| `docs/guides/framework-upgrade-runbook.md` | 1 | Prose. |
| `docs/guides/contributing.md` | 1 | Prose. |
| `.github/release.yml` | 7 | Comment "direct-to-master commits". |
| `.claude/agents/release-engineer.md` | 29, 34, 36–37 | **Claude's lane** — Claude edits this, not OpenCode. Excluded from the execution handoff. |

### 1E. Open handoffs with `Base:` lines

Grep for `Base: origin/master` across `.ai/handoffs/*/open/` and `*/review/` returned
**zero matches** (`.archive/` and `done/` excluded per constraint). No open handoff pins
a stale base. Nothing to do — but re-verify at execution time, since the queue is live.

---

## 2. Recommended fix for item 12 (`Assert-WorktreeFresh`)

Do not swap `origin/master` → `origin/main`. Reuse the resolution that already exists in
the same file, so the guard works on both `main` and `master` repos and cannot fail open:

```powershell
# Resolve the remote default branch offline-first, mirroring Get-DeclaredBase
# (pane-runner.ps1 ~line 380). Never hardcode a branch name here: on a repo whose
# default is not the hardcoded one, `git rev-list --count HEAD..origin/<wrong>`
# returns nothing, $behind fails the ^\d+$ match, and this guard SILENTLY PASSES —
# fail-open on the exact reverse-write guard ADR-0004 exists to enforce.
$base = Resolve-DefaultBase -ProjectDir $ProjectDir   # -> e.g. 'origin/main'
$behind = git rev-list --count "HEAD..$base" 2>$null
```

Extract the resolution chain from `Get-DeclaredBase` (lines 380–421) into a shared
`Resolve-DefaultBase` helper and call it from both sites. **If `$base` cannot be
resolved, the guard must FAIL CLOSED** (refuse to start the pane) — matching
`check-version-bump.sh`'s documented "fail CLOSED on an unresolvable base ref" (line
224). This is a behavioural change worth its own test in `test-pane-runner.ps1`,
alongside the preserved case at 502–510.

---

## 3. Git / GitHub steps

**Use GitHub's native branch rename, not delete-and-recreate.** Rename atomically
retargets open PRs, migrates branch-protection rules, and installs redirects for old
refs. Delete-and-recreate loses all three — and `master`'s protection currently sets
`allow_deletions: false`, so a delete would require *removing protection first*, opening
an unprotected window on the default branch.

Current GitHub state (verified via `gh`, authenticated as `rwn34`):
- `defaultBranchRef`: `master`; `main` does not exist (local, remote, or GitHub).
- `master` protection: required status checks `["gates","framework-check"]` (strict=false),
  `allow_force_pushes: false`, `allow_deletions: false`, `enforce_admins: false`.

Steps, in order:

1. **Verify P0 is clear.** `git -C <primary> status --short .ai/` returns no ` D ` lines.
   `git -C <primary> log origin/master..master` is empty (nothing unpushed).
2. **Land the file changes first, on a branch, via PR into `master`.** Items 1–21 + §1D,
   minus the Claude-lane files. The PR targets `master` while `master` is still default —
   `gates.yml` still triggers on `master`, so CI runs normally. The workflow edits pointing
   at `main` are inert until the rename.
   - Note: `gates.yml` and `framework-check.yml` are required checks. Editing their
     trigger to `main` means that after merge, **pushes to `master` no longer run them** —
     which is why the rename must follow immediately (step 4), same session.
3. **Merge the PR to `master`** (peer-reviewed, CI-green — Claude's gate, per the
   contract; OpenCode does not self-merge).
4. **Rename on GitHub** (this is the single authoritative action; it renames the remote
   branch, moves the default, and migrates protection):
   ```bash
   gh api -X POST repos/rwn34/rwn-multi-cli-skills/branches/master/rename \
     -f new_name=main
   ```
   Verify: `gh repo view --json defaultBranchRef` → `{"name":"main"}`; and
   `gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection` returns the same
   contexts `["gates","framework-check"]`.
5. **Sync every local clone/worktree** (step 5 in §4).
6. **Repoint repo-local git config:**
   ```bash
   git -C <primary> config init.defaultBranch main
   git -C <primary> remote set-head origin -a        # refresh origin/HEAD -> origin/main
   ```
   Verify `git symbolic-ref refs/remotes/origin/HEAD` → `refs/remotes/origin/main`.
   This single ref is what makes `base_for()` and `Get-DeclaredBase` resolve `main` with
   **no code change** — it is the linchpin of the whole migration. `git config --global
   init.defaultBranch` is unset; leave it (out of repo scope).
7. **Do not manually delete `master`.** The rename consumes it. Confirm
   `git ls-remote origin refs/heads/master` is empty.

---

## 4. Worktree reconciliation

12 worktrees exist; **`.ai/` in each is a junction to the primary**, so `.ai/` needs no
per-worktree action — but stale branches do, because `Assert-WorktreeFresh` (item 12)
refuses to start a pane that is behind, and after the rename it will be comparing against
a ref that may no longer resolve.

| Worktree | Branch | Behind `origin/master` | Action |
|---|---|---|---|
| `rwn-multi-cli-skills` (primary) | `master` | 0 (1 **ahead**, unpushed) | Push or drop the ahead commit (P0), then step 5. |
| `.wt/…/claude` (this one) | `exec/claude/202607161231-…` | 0 | Rebase onto `origin/main` after rename. |
| `.wt/…/kimi` | `exec/kimi/202607151144-…` | 12 | Rebase or recreate. |
| `.wt/…/opencode` | `exec/opencode/202607151138-…` | 21 | Rebase or recreate. |
| `.wt/…/kiro` | `exec/kiro/202607142348-…` | 33 | Rebase or recreate. |
| `.wt/…/kimi-202607131945` | `exec/kimi/202607131945-…` | 53 | Stale — recommend prune. |
| `.wt/…/.wt/claude/{claude,kiro,opencode}` | `exec/*/2026071?…` | 64 each | Nested `.wt/claude/.wt/` — topology smell; recommend prune. |
| `.wt-infra/…/bash-path-mangling` | `claude/fix-bash-path-mangling` | 121 | Recommend prune. |
| `.claude/worktrees/agent-af8880a7…` | `claude/sync-provenance-installer-fix` | 211 | git marks **prunable**. |
| `AppData/Local/Temp/kiro-rebase-check` | DETACHED `9371a40` | — | git marks **prunable**. |

**Step 5 — per live worktree, after the rename:**
```bash
git -C <wt> fetch origin --prune
git -C <wt> rebase origin/main          # or recreate the worktree from origin/main
```

**Stale `branch.<name>.merge` config — the sharp edge.** The primary carries ~120
`branch.*` entries, of which **~40 have `merge = refs/heads/master`** (including
`branch.exec/claude/202607161231-….merge`). GitHub's rename does not touch local config.
These branches will keep tracking a `refs/heads/master` that no longer exists; a bare
`git pull` on them fails or misbehaves. Repoint the ones still in use:
```bash
git -C <primary> config branch.<name>.merge refs/heads/main
```
Enumerate first: `git config --get-regexp "^branch\..*\.merge$" | grep "refs/heads/master$"`.
Dead branches can be left; they are noise, not risk.

**Pruning is Tier B (repo hygiene) and belongs to Claude**, not to this migration.
Listed here as context; the execution handoff must not prune.

---

## 5. Rollback

The rename is reversible, and each step is independently undoable.

| If this breaks | Roll back with |
|---|---|
| Rename was wrong / premature | `gh api -X POST repos/rwn34/rwn-multi-cli-skills/branches/main/rename -f new_name=master` — restores name, default, and protection. Then `git remote set-head origin -a` in every clone. |
| CI stops triggering after merge but before rename | Fastest path is *forward*: complete step 4. Otherwise revert the merge commit on `master` to restore `master` triggers. |
| Protection did not migrate | Re-apply from the recorded state in §3: contexts `["gates","framework-check"]`, strict=false, `allow_force_pushes: false`, `allow_deletions: false`, `enforce_admins: false`. Recorded here precisely so it can be rebuilt by hand. |
| A worktree wedges on a missing ref | `git -C <wt> fetch origin --prune && git -C <wt> config branch.<name>.merge refs/heads/main`. Recreating a worktree is always safe — `.ai/` is a junction, no coordination state lives in it. |
| `base_for()` resolves wrong | Set `origin/HEAD` explicitly: `git remote set-head origin main`. Per-handoff escape hatch: add an explicit `Base: origin/main` line. |
| Everything is on fire | Nothing here rewrites history. No commit is lost by any step; the rename is a ref operation. Worst case = rename back and `git remote set-head origin -a` everywhere. |

**Not rollback-covered:** the P0 `.ai/` deletions. If those are committed by another CLI
during the migration, recovery is a separate `git revert`, not part of this plan.

---

## 6. Windows / PowerShell constraints

- Host is **Windows 11 + PowerShell**; no WSL. `bash` is Git-for-Windows (MSYS) only.
- **MSYS mangles colon-joined args** — never `git show "<ref>:<path>"`. Use
  `git ls-tree` + `git cat-file -p <blobsha>`.
- `.ai/` is a Windows **junction** (`mklink /J`), not a POSIX symlink.
- **Grep/Glob do not traverse the `.ai/` junction from inside a worktree** (Read does).
  Any audit of `.ai/` must run against the primary `C:\Users\rwn34\Code\rwn-multi-cli-skills\.ai`
  or via `git ls-files`. This is why the source handoff's audit missed that
  `.ai/tools/` is absent from disk.
- `.ps1` suites are run with PowerShell; `.sh` suites via `bash <script>` (exec bit is
  not tracked — mode `100644`, so `./foo.sh` is not the convention).

---

## 7. Verification (execute, don't inspect)

- [ ] `gh repo view --json defaultBranchRef` → `main`
- [ ] `gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection` → contexts `["gates","framework-check"]`
- [ ] `git ls-remote origin refs/heads/master` → empty
- [ ] `git symbolic-ref refs/remotes/origin/HEAD` → `refs/remotes/origin/main` (in primary)
- [ ] `bash .ai/tests/test-dispatch-worktree.sh` → passes (esp. case 4c)
- [ ] `pwsh tools/4ai-panes/test-pane-runner.ps1` → passes, **including preserved case 502–510**
- [ ] `bash scripts/test-check-version-bump.sh` → passes
- [ ] `pwsh scripts/test-sync-4ai-panes-install.ps1` → passes
- [ ] `bash .ai/tools/dispatch-handoffs.sh` (dry-run) → resolves base as `origin/main`
- [ ] A no-op PR into `main` triggers both `gates` and `framework-check`
- [ ] `grep -rn "origin/master" tools/ scripts/ .github/ --include=*.ps1 --include=*.sh --include=*.yml`
      → only §1C-sanctioned hits

---

## 8. Sequencing summary

```
P0  resolve .ai/ deletions + unpushed master commit     [owner / incident — NOT this migration]
 1  file changes on a branch  →  PR into master         [opencode-auto]
 2  peer review + CI green    →  merge to master        [claude — the gate]
 3  gh api …/branches/master/rename -f new_name=main    [opencode-auto]
 4  remote set-head + init.defaultBranch + branch.*.merge  [opencode-auto]
 5  worktree rebase/recreate                            [opencode-auto]
 6  verification suite (§7)                             [opencode-auto]
 7  verification handoff → kimi-cockpit                 [opencode-auto]
 8  ADR / amendment note if owner wants it recorded     [claude — Tier B, out of scope here]
```

Claude-lane files excluded from the execution handoff (Claude edits these itself):
`.claude/agents/release-engineer.md`, and any ADR/CHANGELOG amendment.
