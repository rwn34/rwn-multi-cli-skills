# 4AI Panes Install Sync — Spec

> **Status: Implemented** in commit `fd206a4` (2026-07-10). This spec describes
> the file-scoped sync mechanism — now shipped — that keeps the executable
> install at `~/.rwn-auto/rwn-4AI-panes/` in lockstep with the canonical
> `tools/4ai-panes/`. Shipped files:
> - `scripts/sync-4ai-panes-install.ps1` — the allowlist-driven sync script.
> - `scripts/git-hooks/post-merge` — invokes the sync after `git pull` / merge.
> - `scripts/git-hooks/post-checkout` — invokes the sync after a branch switch.
> - `scripts/git-hooks/post-commit` — invokes the sync after a same-branch
>   commit (gap D2, 2026-07-11). Diffs `HEAD~1..HEAD`; skips the initial commit.
> - `scripts/git-hooks/post-rewrite` — invokes the sync after a `git rebase`
>   (including rebase-merge of a PR), closing the last common merge path that
>   leaves `~/.rwn-auto` stale.
>   Merge, checkout, AND same-branch commit now all auto-sync in lockstep.
>
> **Amendment (2026-07-13, hole 1):** the sync now carries a **provenance
> guard** — only the primary checkout on `master` may deploy (see
> **Provenance guard** below) — plus `scripts/test-sync-4ai-panes-install.ps1`
> (34-assertion harness) and the `.sync-provenance.json` sidecar the
> supervisor uses for a launch-time drift warning.
>
> The design content below remains valid as the rationale of record. See the
> resolved **Open questions** for the decisions taken before implementation.

## Summary

`tools/4ai-panes/` is the canonical source for the 4AI Panes launcher, but the
executable copy that actually runs — `~/.rwn-auto/rwn-4AI-panes/` — is populated
by a **manual `Copy-Item`** (README §3.2). There is no automation, so every edit
to a tool script silently re-stales the install until a human remembers to
re-copy. This spec is realized by a single **idempotent, allowlist-driven sync
script** plus **git `post-merge`, `post-checkout`, `post-commit`, and
`post-rewrite` hooks** that invoke it when `tools/4ai-panes/**` changes — copying only the nine tool files, never the
embedded framework or runtime state, and verifying by hash after each copy.

## Motivation

The install directory is not a clean mirror of the tool. It contains the tool
files **and** an embedded framework install (`.ai/`, `.claude/`, `.git/`,
`.kimi/`, `.kiro/`, `.github/`, `docs/`) **and** runtime state written next to the
scripts at launch (`.4pane-history`, `.4pane-layout`, `install-framework.log`,
`test-selector-e2e-*.log`, `.ai-install-rollback-point.txt`). A blind recursive
copy from the repo would clobber all of that. So the manual step is a *targeted*
copy — which means it depends entirely on a human correctly remembering which
files are tool files and running the copy after every change.

**The concrete incident (2026-07-10 13:34, `claude-code`, activity log top
entry):** the `pane-runner.ps1` claim-lock commit (repo mtime 07:44) was never
copied to the install (last synced 06:59). The result was a **new `Selector.ps1`
driving a stale `pane-runner.ps1`** — the installed runner (12576 B) was missing
the `$Owner` param and the entire ADR-0009 §3 per-handoff claim-lock, while the
installed Selector already spoke the new topology. The mismatch was caught only
by a manual byte-diff during an unrelated task. That entry's own closing decision
names the fix: *"no automated push repo→.rwn-auto, so future tools/4ai-panes edits
silently re-stale the install; wiring a sync step into install-framework / a hook
is the durable fix."* ADR-0009 already **asserts** the install "is updated in
lockstep" (Consequences → "Launcher change") — but nothing enforces that claim.
This spec makes lockstep mechanical instead of aspirational.

Audience: the framework maintainer (`claude-code` as fleet git operator, and the
human owner) who edits the launcher in-repo and expects the running install to
follow.

## Non-goals

- **Not a general package manager.** It syncs exactly one tool's file set, by a
  hard-coded allowlist — not arbitrary artifacts.
- **Not the embedded-framework installer.** Refreshing the `.ai/`/`.claude/`/etc.
  framework *inside* the install is `scripts/install-template.sh`'s job (invoked
  at launch by `Install-Framework`, README §6). This sync never touches those
  dirs.
- **Not shortcut management.** It does not create or repair the Start Menu
  shortcut, the `.lnk`, or `$projectsDir` configuration (README §3.2 steps 2–3
  stay manual, one-time).
- **Not a mirror push.** It does not push to the archived external
  `rwn-4AI-panes` GitHub repo (a read-only mirror pending archive, README §7 /
  Provenance).
- **Not a code change to the pane-runner or Selector logic.** Sync moves bytes;
  it does not modify what those scripts do.

## Design

### API / interface

A single sync script, **`scripts/sync-4ai-panes-install.ps1`**, invoked from the
bash git hooks under Git-Bash on Windows (see Dependencies). It is the **one
source of truth for "which files are tool files."**

```
scripts/sync-4ai-panes-install.ps1
    [-Target <path>]     # default: env RWN_AUTO_INSTALL_DIR
                         #          else ~/.rwn-auto/rwn-4AI-panes
    [-DryRun]            # report what would copy; change nothing
    [-Quiet]             # suppress per-file lines; still logs + warns
    [-Verify]            # opt-in post-sync tool tests (never passed by hooks)
    [-Force]             # override the provenance guard (see below);
                         # env SYNC_FORCE=1 is the equivalent for hook shells
```

Exit contract:
- **0** — synced (files copied) OR already in sync (no-op) OR target absent
  (graceful skip, see UX/behavior) OR **refused by the provenance guard**
  (refusal is correct behavior, not an error — see below).
- **non-zero** — a copy was attempted but post-copy verification failed, or the
  source tree is missing an allowlisted file. Loud warning to stderr.

**Tool-file allowlist (authoritative — the whole contract lives here):**

```
Launch4Panes.ps1
Launch4Panes.vbs
Selector.ps1
pane-runner.ps1
restart-pane.ps1
test-pane-runner.ps1
test-selector-e2e.ps1
README.md
icon.ico
```

All nine exist in `tools/4ai-panes/` today (verified). The list is a literal
array in the script — adding a tenth tool file is a one-line edit here, and the
allowlist is the ONLY place that knowledge lives.

**Explicitly excluded** (never copied, never deleted from the target):

- Embedded framework dirs: `.ai/`, `.claude/`, `.git/`, `.kimi/`, `.kiro/`,
  `.github/`, `docs/`
- Runtime state / artifacts: `.4pane-history`, `.4pane-layout`,
  `install-framework.log`, `test-selector-e2e-*.log`,
  `.ai-install-rollback-point.txt`, `*.tmp`
- `.gitignore` (tool-local ignore file, README §2 — not an executable file)

The sync is **copy-only, additive-safe**: it writes the nine allowlisted files
and touches nothing else. It never runs `Remove-Item`/recursive delete against
the target, so an extra file in the install is never a reason to delete embedded
framework or state.

### Hook trigger logic

Four repo-level hooks — **`scripts/git-hooks/post-merge`**,
**`scripts/git-hooks/post-checkout`**, **`scripts/git-hooks/post-commit`**
(gap D2, 2026-07-11), and **`scripts/git-hooks/post-rewrite`** (rebase/PR
rebase-merge path, 2026-07-15). These live alongside the existing
`scripts/git-hooks/pre-commit`, and the repo already sets
`git config core.hooksPath scripts/git-hooks` (ADR-0005), so a new hook file in
that dir is picked up with no extra wiring in existing clones. Fresh clones wire
`core.hooksPath` via the installers exactly as they already do for `pre-commit`.

Trigger shape (prose):

```
post-merge  (args: <squash-flag>)
  1. Determine the change range for this merge.
       ORIG_HEAD..HEAD   (post-merge runs after HEAD advances)
  2. If `git diff --name-only ORIG_HEAD HEAD` contains any path under
       tools/4ai-panes/  -> proceed; else exit 0 (nothing to sync).
  3. Locate the sync script relative to the repo root and invoke it:
       pwsh/powershell -File scripts/sync-4ai-panes-install.ps1
       (or the bash equivalent).
  4. NEVER block: post-merge cannot abort the merge (it already happened).
     On sync failure, print a LOUD multi-line warning to stderr naming the
     install path and the failing file, and exit 0 so the merge is not
     reported as broken — the human/fleet is warned, not halted.

post-checkout  (args: <prev-HEAD> <new-HEAD> <branch-flag>)
  - Same detection, using $1..$2 as the range; only act on branch checkouts
    (branch-flag == 1), skip file checkouts (branch-flag == 0).

post-commit  (no args)
  - Same detection, using HEAD~1..HEAD as the range (the commit just made).
    GUARD: exit 0 on the initial commit, where HEAD~1 does not resolve.
    Covers same-branch edit-then-commit — which touches neither merge nor
    checkout, and was the remaining silent-restale path (gap D2).

post-rewrite  (args: <command>)
  - Only act on `rebase` (skip `amend`; post-commit already handled it).
    Change range = `ORIG_HEAD..HEAD`. Covers `git pull --rebase` and
    `gh pr merge --rebase`, which rewrite history without a merge commit and
    therefore do NOT fire post-merge.
```

Key properties:
- **Never blocks.** `post-merge`/`post-checkout` are post-event hooks by nature;
  they cannot and must not gate anything. Failure is a warning, not a stop.
- **Cheap when irrelevant.** A single `git diff --name-only` path filter; if the
  merge/checkout didn't touch `tools/4ai-panes/**` the hook exits immediately.
- **Delegates the "what to copy" question entirely to the sync script** — the
  hook only decides *whether* to run it.

### Provenance guard (hole 1, 2026-07-13)

**The hole:** the hooks call the sync from whatever worktree fired them, on
whatever branch. On 2026-07-13 ~05:45 a `post-checkout` in a linked worktree
deployed unmerged branch code over the owner's live install (and the ~06:09
revert then had to be hand-repaired).

**The guard lives in the sync script, not the hooks** — one choke point covers
the hooks AND manual/agent invocation, and cannot drift between two hook files.
Before any file work (above the graceful-skip block) the sync requires:

1. **Primary-checkout test.** `git rev-parse --path-format=absolute --git-dir`
   must equal `--git-common-dir` for the source. Equal ⇒ primary checkout;
   different (git-dir is `<common>/worktrees/<name>`) ⇒ linked worktree.
   Canonical test — no path pattern-matching.
2. **Branch test.** `git symbolic-ref --short HEAD` must be `master`. A
   detached HEAD (`symbolic-ref` fails) refuses as `branch=DETACHED`.
3. **Fail closed.** git unavailable or the source not a repo ⇒ refuse. An
   unverifiable provenance is not a licence to deploy.

**Refusal exits 0, not 1.** The hooks treat non-zero as "sync REPORTED ERRORS"
with a loud banner; a refusal in a worktree is *correct behavior*, and exit 1
would spam that banner on every legitimate branch checkout in every worktree.
Refusal prints one clear line naming `toplevel`/`branch`/`primary`, still
writes its `install-sync.log` line (`result=refused`), and copies nothing.
Exit 1 stays reserved for genuine failures (syntax gate, hash verify, missing
source).

**Override:** `-Force` or `SYNC_FORCE=1` bypasses both tests, prints a loud
`FORCED` line naming what was overridden, and records `provenance=forced` in
the log line. This is the escape hatch for intentionally deploying from a
worktree (e.g. pre-merge acceptance against a sandbox install via `-Target`).

**Log provenance on every run:** the `install-sync.log` line carries
`branch=<b> primary=<yes|no>` alongside the existing `commit=`, so the next
post-mortem reads the provenance straight off the log.

**Drift sidecar + launch warning:** a successful real sync (not `-DryRun`, not
a refusal) writes `.sync-provenance.json` into the install
(`source_repo`, `commit`, `branch`, `synced_at`). At launch,
`tools/4ai-panes/run-pane-supervised.ps1` reads it and warns loudly — never
blocks, wrapped in try/catch — when the live install's core files
(`pane-runner.ps1`, `run-pane-supervised.ps1`, `Selector.ps1`) differ from the
recorded repo's `tools/4ai-panes/`. This is the detection half that would have
surfaced the 06:09 revert immediately; the guard is the causal fix.

### Data

No new persistent schema. The sync appends a line per run to a **sync log** —
proposed `~/.rwn-auto/rwn-4AI-panes/install-sync.log` (co-located with the
existing `install-framework.log`, which the tool already writes there and which
is not committed). Each line: timestamp, source commit (`git rev-parse --short
HEAD` if available), per-file action (`copied` / `unchanged`), and post-copy hash
result. This mirrors the tool's existing "trace every install attempt to
`install-framework.log`" convention (README §6) so the two logs read alike.

Verification uses **MD5 (or SHA-256) content hashes** compared source-vs-target
after each copy. A run is "in sync" iff every allowlisted file's target hash
equals its source hash. The 13:34 incident's own post-sync check ("Post-sync MD5
confirms all three byte-identical") is exactly this check, made automatic.

### UX / behavior

- **Target discovery:** default `~/.rwn-auto/rwn-4AI-panes`; overridable via env
  var **`RWN_AUTO_INSTALL_DIR`** (or the `-Target` param, which wins over the env
  var). This keeps the path out of the script body and lets a non-standard
  install location or a test sandbox redirect the sync.
- **Graceful skip when target absent:** not every clone has an install (CI, a
  fresh checkout on another machine, a Linux box). If the target dir does not
  exist, the sync **logs "no install at <path>, skipping" and exits 0** — a
  no-op, never an error. The hook stays silent in that common case.
- **Idempotent:** re-running when already in sync copies nothing and exits 0. The
  hash comparison happens *before* copying each file, so unchanged files are
  skipped and only drifted files are written. Running the sync twice back-to-back
  produces identical logs modulo timestamp.
- **Line-ending / EOL policy:** **preserve the repo's committed EOL.** The manual
  13:34 sync normalized `test-selector-e2e.ps1` from LF back to CRLF; the sync
  must reproduce byte-for-byte what the repo holds, so post-copy hashes match. Do
  a **binary copy** (byte-exact, no PowerShell `Get-Content`/`Set-Content`
  round-trip that would rewrite line endings or add a BOM). `icon.ico` is binary
  and makes byte-exact copy mandatory regardless.
- **Dry run:** `-DryRun` prints the would-copy set and the current drift, changes
  nothing — for the human to preview before trusting the hook.

### Failure handling — never corrupt the install

- **Copy to temp + atomic move.** Write each file to a temp path in the target
  dir, hash-verify the temp against source, then move it into place. A crashed or
  half-written copy never leaves a truncated tool file where the running launcher
  would load it. (Same spirit as ADR-0008's atomic activity-log write:
  temp-file + rename.)
- **Verify-then-commit per file.** If the post-copy hash does not match source,
  do **not** move the temp into place: leave the existing target file untouched,
  emit a loud warning naming the file and both hashes, and set a non-zero exit
  (script direct-invoke) — the hook downgrades this to a stderr warning + exit 0
  (never blocks) but still surfaces it.
- **Missing source file** (an allowlisted name absent from `tools/4ai-panes/`) is
  a hard warning: the allowlist and the tree have diverged and a maintainer must
  reconcile — do not silently drop it.

### Dependencies

- **`scripts/git-hooks/` + `core.hooksPath`** — the existing ADR-0005 wiring. New
  hook files drop in with no config change in existing clones; installers
  (`scripts/install-template.sh`, `tools/multi-cli-install`) already run
  `git config core.hooksPath scripts/git-hooks` for fresh clones.
- **Git-Bash on Windows** — the git hook process runs under Git-Bash, so the hook
  itself is bash. It shells out to PowerShell for the copy
  (`powershell -File …` / `pwsh -File …`). As resolved in Open questions, the
  bash hook calls the single PowerShell sync — the least-duplication path that
  matches the tool's PowerShell-native world — and skips gracefully if neither
  `powershell` nor `pwsh` is on PATH.
- **PowerShell 5.1+** — already a tool prerequisite (README §3.1).
- No new third-party libraries. Copy + hash are built into PowerShell
  (`Copy-Item`, `Get-FileHash`) and coreutils (`cp`, `md5sum`).

## Alternatives considered

- **(a) Status quo — manual `Copy-Item` after each edit.** Rejected: this is
  precisely what produced the 13:34 drift incident (new Selector + stale runner,
  caught only by luck). Human memory is not lockstep.
- **(b) Full recursive `Copy-Item -Recurse` repo→install.** Rejected: it clobbers
  the embedded framework (`.ai/`, `.claude/`, `.git/`, …) and the runtime state
  (`.4pane-history`, `install-framework.log`, rollback point, e2e logs) that live
  in the install dir. The install is a superset of the tool, not a mirror — which
  is exactly *why* the manual step is already targeted. File-scoped allowlist
  copy is the corrected form of what the human does by hand.
- **(c) Symlink / directory-junction install instead of copy.** Tradeoffs: a
  junction from `~/.rwn-auto/rwn-4AI-panes` (or per-file symlinks for the nine
  tool files) to the repo would make drift structurally impossible — the install
  *is* the repo file. But: (1) Windows junction/symlink creation can require
  elevated perms or Developer Mode; (2) the install dir is itself a git working
  tree with an embedded framework, so pointing tool files at the repo mixes two
  git trees in one directory and risks confusing in-place git operations and the
  `Install-Framework` flow; (3) per-file symlinks still need something to create
  them on first install and to notice new allowlist entries — i.e. the same
  allowlist machinery. Copy+sync is chosen for now because it is
  permission-free, keeps the install dir a plain directory, and reuses the exact
  targeted-copy the maintainer already trusts. Whether a junction is worth it
  long-term is left as an Open question.

## Open questions

All four questions below were **resolved by owner decision before implementation**
(commit `fd206a4`); the rationale is retained here rather than deleted.

- **post-merge vs post-checkout vs both.** `post-merge` covers `git pull` / merge
  (the 13:34 path). `post-checkout` also covers branch switches that change tool
  files. **Resolved: BOTH implemented** — `scripts/git-hooks/post-merge` and
  `scripts/git-hooks/post-checkout` both ship, so neither `git pull` nor a
  branch-switch can silently re-stale the install. **Follow-up (gap D2,
  2026-07-11): `scripts/git-hooks/post-commit` added** — merge and checkout still
  left one path uncovered, a same-branch edit-then-commit (touches neither a
  merge nor a checkout). post-commit diffs `HEAD~1..HEAD` and closes it, so
  merge, checkout, same-branch commit, and rebase now all auto-sync in lockstep.
  **Follow-up (gap D3, 2026-07-15): `scripts/git-hooks/post-rewrite` added** —
  rebase-based PR merges (`git pull --rebase`, `gh pr merge --rebase`) rewrite
  HEAD without a merge commit, so post-merge never fires. post-rewrite acts on
  `command == rebase`, diffs `ORIG_HEAD..HEAD`, and closes the last common
  merge path that could leave `~/.rwn-auto` stale.
- **Bash hook + PowerShell sync, or a full bash sync too?** One PowerShell sync
  called from a bash hook avoids duplicating the allowlist; a pure-bash sync would
  run natively in the hook but forks the "which files are tool files" truth into
  two places. **Resolved: bash hooks call the single PowerShell sync** as the one
  source of truth; if neither `powershell` nor `pwsh` is on PATH the hook skips
  gracefully (a warning, never a block).
- **Should `Selector.ps1` self-heal at launch?** An optional launch-time
  staleness backstop: on start, if the canonical repo path is discoverable (e.g.
  via `RWN_FRAMEWORK_REPO` / the `$frameworkRepo` the installer already knows),
  compare install tool-file hashes against the repo and warn (or re-sync) before
  splitting panes. **Resolved: deferred, not implemented** — it remains a future
  backstop, a second safety net rather than the primary mechanism, and it adds
  startup cost + a repo-path assumption the hook does not need.
- **Multiple installs.** If more than one install dir exists (e.g. a test sandbox
  plus the real `~/.rwn-auto` copy), the single `-Target`/env-var model syncs one
  at a time. A future multi-target list or a discovery glob is deferred — noted so
  a second install is a known, not a surprise.
- **Run the tool tests post-sync?** After copying, optionally run
  `test-pane-runner.ps1` / `test-selector-e2e.ps1` from the install to confirm the
  freshly-synced scripts parse and pass. **Resolved: implemented as an opt-in
  `-Verify` flag, OFF by default and NOT passed by the hooks** — so a routine
  merge/checkout stays fast (tests already run in-repo), while a human can request
  the post-sync check on demand.

**Still open (flagged during implementation):** on a clone where neither
`powershell` nor `pwsh` is on the hook's PATH (e.g. a Linux box or CI), the sync
**silently skips** — no install is updated. A **pure-bash sync sibling** that runs
natively in that environment remains a possible future item, so that lockstep is
not Windows-only. Until then, non-Windows clones fall back to the manual copy.

## References

- `docs/specs/TEMPLATE.md` — spec section structure this document follows.
- `tools/4ai-panes/README.md` — Provenance & Canonical Source (canonical =
  `tools/4ai-panes/`); §2 Files (the tool-file table + `.gitignore`); §3.2 Install
  (the manual `Copy-Item -Recurse … → ~/.rwn-auto/rwn-4AI-panes` step); §6
  Framework auto-install / `install-framework.log`.
- `docs/architecture/0009-operator-over-fleet-topology.md` — asserts the installed
  `~/.rwn-auto` copy "is updated in lockstep" (Consequences → Launcher change);
  this spec makes that mechanical.
- `docs/architecture/0008-self-driving-fleet-pane-runner.md` — the pane-runner
  design whose claim-lock version was the file that went stale in the incident;
  atomic temp-file + rename pattern reused here.
- `docs/architecture/0005-commit-governance-backstop.md` — establishes
  `scripts/git-hooks/` + `git config core.hooksPath scripts/git-hooks`, where the
  new `post-merge`/`post-checkout` hook lives and how installers wire it.
- `.ai/activity/log.md` — 2026-07-10 13:34 (`claude-code`) — the drift incident
  that motivates this spec (repo runner @ 07:44 vs install synced 06:59; new
  Selector + stale runner; post-sync MD5 confirmation).
- `scripts/install-template.sh` — the embedded-framework installer this sync is
  explicitly NOT (Non-goals), and the existing `core.hooksPath` wiring point.
