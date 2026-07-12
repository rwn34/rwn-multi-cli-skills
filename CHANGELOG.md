# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog v1.1.0](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- [TODO: new features]

### Changed

- [TODO: changes to existing behavior]

### Deprecated

- [TODO: features marked for removal]

### Removed

- [TODO: features removed this release]

### Fixed

- [TODO: bug fixes]

### Security

- [TODO: vulnerabilities addressed]

## [0.0.25] - 2026-07-12

### Security

- **The Claude territorial guard never fired on absolute paths — and the test suite was
  certifying the bypass.** `.claude/hooks/pretool-write-edit.sh` computed
  `project_root=$(pwd)`, which under Git Bash yields the MSYS form (`/c/Users/...`),
  while the Write/Edit tools emit the Windows form (`C:\Users\...`). The prefix test
  never matched, so `rel` stayed **absolute** and every territorial `case "$rel" in
  .kimi|.kimi/*)` arm silently missed. A subagent — which under the orchestrator pattern
  is who does all the writing — could write into any other CLI's territory just by using
  an absolute path:

      SUBAGENT + relative   .kimi/foo.md            -> exit=2  BLOCKED
      SUBAGENT + absolute   C:\...\.kimi\foo.md     -> exit=0  ALLOWED

  Reproduced against the pre-fix hook in a **normal (non-worktree) checkout**, which is
  what every onboarded project has. Inside a `.wt/` executor worktree the escape was
  *incidentally* caught by the later ADR-0004 worktree-confinement arm (with a misleading
  "escaping the worktree" reason) — which is why the bug survived: it looked blocked
  wherever the executors actually ran.
- **Paths are now normalized before any rule runs**, by a deliberately **lexical**
  converter (no `realpath`, no `cygpath`). `realpath`/`cygpath -a` resolve symlinks and
  Windows junction reparse points — which would *reintroduce* an escape, since `.ai/` is
  a junction. `cygpath -u` was tried and **fails open**: it canonicalizes the two shapes
  we deliberately refuse (bare drive `C:`, drive-relative `C:foo`) instead of erroring.
- **Normalization fails CLOSED.** An un-canonicalizable `file_path` (bare drive,
  drive-relative, unrecognized shape) is now `exit 2`. A guard that cannot understand its
  input must deny.

### Fixed

- **`test_hooks.sh` fixtures only ever used RELATIVE paths**, so the tests and the runtime
  disagreed about the input domain and the suite had been green *because* it never fed the
  hook what the tools actually send. Fixture set now covers relative, Windows-absolute
  (forward- **and** back-slash), MSYS `/c/` form, mixed case, and the fail-closed shapes.
  **17 → 98 assertions.**
- **`.claude/hooks/README.md` documented the broken behavior.** It advertised
  `PASS: 17/17`, omitted normalization entirely, and — load-bearing — instructed hook
  authors to *"prefer **fail-open** (exit 0 on unexpected input)"*, which is precisely the
  guidance that produced this bug class. Enforcement hooks are now documented as
  fail-**closed**; only advisory hooks may fail open.

### Known gap

- **The Bash tool is NOT path-checked.** `pretool-bash.sh` screens for destructive command
  *shapes* but does no path matching, so `cp`/`mv`/`sed -i`/`tee`/`>` can still write any
  protected path. This change raises the wall; the door beside it is still open. Tracked
  separately — do not treat protected paths as unreachable.
## [0.0.24] - 2026-07-12

### Fixed

- **Onboarded projects received OpenCode with NO mechanical guard layer.** The
  installer manifests (`scripts/sync-assets.ts` and
  `src/installer/copy-framework.ts`) shipped `opencode.json` — which points
  OpenCode at `.opencode/contract.md` — but never shipped `.opencode/` itself.
  Every adopted project therefore ran OpenCode on prompt-level rules alone: no
  write-lane enforcement, no sensitive-file guard, no destructive-command
  guard. This is exactly the no-hook-layer situation ADR-0002's 2026-07-09
  amendment rejected when Crush was replaced. Both manifests now include
  `.opencode`, and a new installer test (`installed OpenCode guard actually
  blocks out-of-lane writes`) imports the guard OUT OF A FRESH INSTALL TARGET
  and proves it blocks `src/`, `.opencode/contract.md`, `.env`, and
  `git push --force` — presence is no longer assumed, it is exercised.
- **Nothing gated the installer asset tree, so it rotted invisibly.** A stale
  generated `assets/` tree (protocol-v2 `AGENTS.md`, dozens of drifted files)
  lingered undetected. New gate `.ai/tools/check-asset-drift.sh`, wired into
  the `gates` workflow after asset regeneration: (1) enforces parity between
  the two ship manifests plus required coverage (`.opencode`, `AGENTS.md`,
  `opencode.json`) — the 2026-07-12 defect class fails here even on a clean
  checkout; (2) rejects any committed file under
  `tools/multi-cli-install/assets/` (a build artifact that goes stale the
  moment its source changes); (3) glob-walks every file of any on-disk asset
  tree and fails on any byte-divergence from its source — no hardcoded file
  list, so new files are covered automatically. Proven both directions:
  53 failures on the real stale tree, PASS once regenerated.
## [0.0.23] - 2026-07-12

### Added

- **OpenCode's two enforcement layers now accept `.ai/activity/entries/**`** — the
  entry-per-file activity-log spool of ADR-0010. Both layers hardcoded the log path
  as an **exact string** (`scripts/git-hooks/pre-commit` L96
  `case "$p" in .ai/activity/log.md|…`; `.opencode/plugin/framework-guard.js`
  `WRITABLE_LANE`), so the first spool entry OpenCode ever wrote would have been
  **blocked by its own guard** and its commit **rejected by the hook** — silently,
  with no error a human would see. This is **permission plumbing only**: it makes the
  spool landable later. Nothing is migrated, `entries/` is not created, no contract's
  logging prose changed, and `.ai/tools/activity-append.sh` is untouched.
  `.ai/activity/log.md` keeps working exactly as before — it is still the live log.

### Fixed

- **OpenCode could write `.github/**` but not commit it.** The 0.0.22 repo-ops
  widening (PR #45) added `.github/**` to the *write* guard and to the contract
  ("you own … CI config/workflow fixes … opening PRs"), but never to the *commit*
  hook's OpenCode whitelist. The result was the same defect class it set out to fix,
  one layer down: OpenCode could produce the workflow fix and then be rejected at
  `git commit`. `.github/*` is now in the pre-commit lane too, so the two layers agree.

### Security

- The spool widening is asserted **not to leak**: the guard suite grew 96 → 133
  assertions and the pre-commit backstop suite 54 → 86, covering relative,
  Windows-absolute, backslash, `./`-prefixed, MSYS `/c/…`, traversal-escape and
  mixed-case forms. Project source, `.claude/**`, `.kimi/**`, `.kiro/**`,
  `.opencode/**`, `.ai/instructions/**` (SSOT), `docs/architecture/**` (ADRs),
  `scripts/**` and secrets remain blocked from OpenCode, and rule 5 (secrets) still
  outranks the lane *inside* the spool (`.ai/activity/entries/id_rsa` is denied).
  `.ai/activity/archive/**` was deliberately **not** granted.
- **Documented, not fixed:** the pre-commit hook matches the lowercased path (`_lc`),
  which makes OpenCode's *whitelist* branch case-INSENSITIVE (fail-**open**) while
  the guard's lane is case-SENSITIVE (fail-**closed**) — the two disagree on
  `.AI/Activity/Entries/x.md`. The leak **cannot escalate** (no case variant reaches
  another CLI's territory, source, or a secret — now asserted), and tightening it
  risks false-blocking a real entry, which is the exact "OpenCode goes silent"
  failure this change prevents. The assertions pin the contract for whoever revisits it.

## [0.0.22] - 2026-07-12

### Fixed

- **OpenCode's guard denied the job its contract assigns it.** `.opencode/contract.md`
  gives OpenCode a "GitHub / repo-ops lane" (PRs, release chores, **CI config/workflow
  fixes**) and operating-prompt §14 routes GitHub work to it — but
  `.opencode/plugin/framework-guard.js` enforced a writable lane of `.ai/activity/log.md`,
  `.ai/reports/**`, `.ai/handoffs/**` only. The first real ops handoff
  (`202607120021-gates-required-check-and-step-order`, a `.github/workflows/gates.yml`
  edit) was therefore mechanically impossible; OpenCode correctly refused and reported
  BLOCKED (`.ai/reports/opencode-2026-07-12-gates-blocked.md`). The lane now includes
  `.github/**` — and nothing else. `infra/`, `scripts/`, `Dockerfile`, `docker-compose*`
  were deliberately NOT added: widening a security guard is a one-way ratchet, and only
  `.github/**` is needed for the documented job.
- **`AGENTS.md` never mirrored the repo-ops lane.** The paragraph was added to
  `.opencode/contract.md` on 2026-07-11 and never propagated, so OpenCode's shipped
  contract did not say it owns GitHub/CI work at all — a contributing cause of the lane
  starvation, not just a symptom (ADR-0011 Context). `AGENTS.md` now carries an
  OpenCode-only lane section.

### Added

- **`WRITABLE_LANE` is now a single exported constant** in `framework-guard.js`, and the
  guard suite **fails loudly if it drifts from the `LANE:BEGIN`/`LANE:END` block in
  `.opencode/contract.md` or `AGENTS.md`.** The doc/enforcement divergence *is* the bug
  above; its recurrence is now a test failure, not a comment.
- **Guard rule 5 (secrets) is enforced mechanically, ahead of every allow rule.** A
  sensitive basename (`.env*`, `*.key`, `*.pem`, `id_rsa*`, `secrets.*`, `credentials*`)
  is denied everywhere — including inside the newly-widened `.github/**` and inside
  `.ai/reports/**`. Previously secrets were blocked only incidentally, by default-deny.
- **OpenCode guard suite: 45 → 96 assertions.** New coverage: `.github/**` allowed in
  relative/absolute/backslash/`./`-prefixed/traversal forms; source, `.claude/`, `.kimi/`,
  `.kiro/`, `.ai/instructions/` (SSOT), `docs/architecture/` (ADRs) and `.opencode/` still
  denied in relative **and absolute and backslash** forms; mixed-case variants fail closed;
  secrets denied inside the lane; doc/guard lane drift.

### Security

- **Project-root prefix comparison is now case-insensitive only on Windows.** It was
  unconditionally case-insensitive, so on a case-sensitive filesystem a sibling directory
  differing only in case (`/PROJ/` next to `/proj/`) would have been folded *inside* the
  project root and its lane paths allowed. Legitimate paths always match case exactly, so
  the strict compare costs nothing and closes the fold.

## [0.0.21] - 2026-07-12

### Fixed

- **`.ai/tools/dispatch-handoffs.sh`: headless dispatch no longer runs every CLI in the
  shared primary checkout.** The dispatcher used to `cd` into the repo root and launch the
  recipient CLI there, so two concurrently dispatched CLIs shared one HEAD and one working
  tree — either could clobber the other's in-flight files with a `git checkout` (the
  ADR-0004 "2026-07-11 near-miss"). Each dispatched CLI now runs inside its **own git
  worktree** at `<parent>/.wt/<project>/<cli>/`, resolved by `worktree_path_for()` and
  created/reused by `ensure_cli_worktree()`. Worktree creation reuses
  `scripts/wt-bootstrap.sh` (single implementation); a healthy existing worktree is reused,
  never destroyed. Worktree setup failure **fails that dispatch** — the handoff stays
  `OPEN` and a failure report is written. Falling back to the primary checkout is forbidden,
  so the race cannot silently reappear.
- **`.ai/tools/dispatch-handoffs.sh`: per-handoff branches are cut from a declared base, not
  ambient HEAD.** A dispatch used to branch from whatever HEAD happened to be, so a handoff
  could inherit unrelated in-flight work from a previous dispatch. `ensure_declared_base_branch()`
  now cuts (or reuses) `exec/<cli>/<slug>` from an explicitly declared base: the handoff's
  optional `Base:` field, else `origin/master`. This is a second, independent defect from the
  shared-HEAD one and is fixed independently.

### Added

- **`.ai/handoffs/` `Base:` field (optional).** A handoff may declare the branch its exec
  branch is cut from; read by `base_for()` from the status block. Absent, dispatch falls back
  to `origin/master`.
- **`.ai/tests/test-dispatch-worktree.sh` — 24 assertions** covering worktree path resolution,
  create-vs-reuse, the no-fallback-to-primary-checkout contract, declared-base branch cuts
  (`Base:` honored, `origin/master` default), and the failure path leaving the handoff `OPEN`.

### Changed

- **`docs/architecture/0004-worktree-multi-project-topology.md` amended (2026-07-11)** to make
  worktree-per-CLI the dispatch contract rather than a manual convention, and to record the
  near-miss that motivated it.

## [0.0.19] - 2026-07-11

### Fixed

- **`tools/4ai-panes/Selector.ps1`: the framework source repo no longer badges itself
  `[! OLD]`.** `Get-ProjectBadges` decided staleness from `.ai/.framework-version` — a
  marker the installer writes *into target projects*. The source repo never carries one
  (its version is `tools/multi-cli-install/package.json` `.version`), so the repo that IS
  the framework reported itself stale against itself. It now badges **`[v SRC]`**: the
  resolved dir is compared to `$frameworkRepo` (`RWN_FRAMEWORK_REPO`-overridable) as
  canonicalized full paths — case-insensitive, trailing-slash and separator tolerant, and
  safe on paths that do not exist. The `[H:n]` handoff badge still applies to it
  unchanged. The one-line badge legend documents `[v SRC]` and stays within its 70-char
  box budget (68).
- **`Selector.ps1`: batch launches no longer race Windows Terminal.** Marking N projects
  used to pack ALL of their `new-tab` groups into as few `wt` invocations as a 7000-char
  budget allowed — WT applies each chained subcommand against whatever pane is focused
  when it reaches it, so ~7 projects dumped dozens of splits at once and the layout came
  out scrambled. Each project now gets **its own `wt` invocation (one tab)**, fired
  sequentially with a settle delay between projects; the cross-project char-budget packing
  is gone.
- **`Selector.ps1`: pane splits within a tab no longer race either.** `Build-FleetTabCmd`
  returned one string chaining `new-tab ; split-pane ; … ; move-focus up ; split-pane`,
  fired as a single atomic `wt` call, so even a lone project could land messy. It is
  replaced by `Build-FleetTabStages`, which returns the tab as a structured `[string[]]`
  of stages (built at the KNOWN boundaries rather than by splitting a chained string on
  `' ; '`, which a quoted CLI payload could otherwise corrupt). Each stage is issued as
  its own `wt -w rwn4ai <stage>` invocation with a delay between. Every stage acts on the
  active pane of the active tab in the `rwn4ai` window — exactly the pane the atomic chain
  acted on — so **the layout is identical; only the timing changes**. `--title` / `-d` /
  `-w rwn4ai` semantics are byte-identical. Applied to the batch path AND both
  single-project (6pane/5pane) paths.

### Added

- **Two pacing knobs (documented in `tools/4ai-panes/README.md`):**
  `RWN_4AI_PANE_DELAY_MS` (default `250`) between pane stages within a tab, and
  `RWN_4AI_TAB_DELAY_MS` (default `1200`) between project tabs in a batch. Setting either
  to `0` restores the legacy **atomic single-invocation** behavior for that dimension
  (escape hatch): pane `0` collapses a project's tab to one chained call; tab `0` collapses
  the whole batch to one chained call. Values are parsed defensively — non-numeric,
  negative or empty fall back to the default and never crash the launcher. An
  over-long atomic invocation (> 7000 chars) is now warned about rather than silently
  truncated by Windows.
- **`tools/4ai-panes/test-selector-e2e.ps1`: four new suites (Tests 3-6), 46 new
  assertions (35 -> 81).** Badge resolution (`[v SRC]` for the source repo including
  trailing-slash / forward-slash / case / non-existent-path tolerance and the retained
  `[H:n]`; `[v OK]` / `[! OLD]` / `[- none]` for temp targets; the legend's 70-char
  budget); staged emission of a 6-pane group asserted **stage-by-stage equal** to the
  legacy atomic chain, with a guard that no stage contains a literal `' ; '`; a batch of N
  projects producing exactly N `new-tab` launches and no packed invocation; and the delay
  knobs (default when unset, honored when set, default on garbage/negative/empty, `0`
  restoring atomic behavior), including contract guards that the production assignments
  still read those env names with those defaults. The plan builders
  (`Build-FleetTabStages`, `Get-FleetLaunchPlan`) are pure, so the suite asserts on the
  constructed `wt` command/stage arrays and never launches Windows Terminal.

## [0.0.18] - 2026-07-11

### Added

- PowerShell syntax gate in `scripts/git-hooks/pre-commit`: a `.ps1` that does not parse
  can no longer enter history. For every staged `.ps1`, the hook extracts the **staged
  blob** (`git show ":$file"`) — not the working tree — and runs it through
  `[System.Management.Automation.Language.Parser]::ParseFile`. Any syntax error rejects
  the commit, naming the file, the first error message and its line number. Reading the
  index rather than the disk is deliberate: a file that is valid on disk but broken in the
  staged version (a partial `git add`) is still caught. This complements the 0.0.17 sync
  gate, which is the *last* line of defense — deploy-time. The commit is the *first*: a
  broken `Selector.ps1` was committed and then carried toward the owner's live launcher by
  the post-commit sync hook, gated only by a copy-hash check that proves fidelity, not
  validity. The gate is a graceful no-op where no PowerShell host exists (`pwsh` and
  `powershell` both absent — i.e. Linux CI), so it can never break commits or CI on
  ubuntu; it enforces on the Windows box, the only place a `.ps1` actually runs. It blocks
  only on a *definitive* parse error, never on a PowerShell host that failed to answer.
  All other guards (territory, sensitive-file, tombstone, root-file) are unchanged; test
  coverage in `scripts/git-hooks/test-pre-commit.sh` goes 50 -> 54 cases.

## [0.0.17] - 2026-07-11

### Added

- Syntax gate in `scripts/sync-4ai-panes-install.ps1`: every `.ps1` source file is now
  parsed (`[System.Management.Automation.Language.Parser]::ParseFile`) before it is
  deployed into the live launcher install (`~/.rwn-auto/rwn-4AI-panes`). A file with
  syntax errors is REFUSED — not copied — the previously deployed known-good version is
  left untouched, the failure is printed loudly (file, first error message, line number),
  and the script exits 1 so the calling git hook surfaces it. The pre-existing hash-verify
  only proves *fidelity* (the bytes that landed are the bytes from source); it cannot
  detect a broken file, so a `Selector.ps1` with an unbalanced brace used to deploy
  cleanly and hash-verify green. The parse gate is an additional precondition, not a
  replacement, and runs BEFORE the atomic move so the target is never half-updated.
  Non-`.ps1` files (README.md, icon.ico, Launch4Panes.vbs) keep hash-verify-only behavior.

## [0.0.16] - 2026-07-11

### Fixed

- Telegram emoji arrived as mojibake (`??` / `?`) from the headless bash notify path.
  `.ai/tools/notify.sh` built the robot/check/warning emoji as raw UTF-8 byte
  sequences (`printf '\xf0\x9f\xa4\x96'`) and shipped them through curl
  `--data-urlencode`; the shell/locale/urlencode chain mangled the bytes before they
  reached Telegram. The request is now sent as a JSON body
  (`Content-Type: application/json`, `--data-binary @-`) with the emoji encoded as
  JSON `\uXXXX` escapes (U+1F916 as a UTF-16 surrogate pair, U+2705 and U+26A0 as
  single escapes), so the payload is pure ASCII on the wire and no locale or
  encoding step can corrupt it. Interpolated values (project, handoff, owner,
  chat_id, thread_id) are JSON-escaped, so a quote or backslash in a name can no
  longer break the request body. The PowerShell path was already correct and is
  unchanged in this respect.

### Added

- Notifications now carry a local wall-clock `HH:MM:SS` timestamp on a third line
  (`_HH:MM:SS_`), so the owner can see when a pick-up / finish / alert actually
  happened. Applied identically to both notify paths (`.ai/tools/notify.sh` and
  `tools/4ai-panes/notify.ps1`) so the bash and PowerShell messages stay in lockstep.

## [0.0.15] - 2026-07-11

### Changed

- Version bump to detect adopter drift for the CLAUDE.md owner-interaction-preference
  directive that landed in the prior commit (7eff945) direct-to-master without a bump.
  The directive tells CLIs to act-and-inform on reversible Tier-A/B work (act, then
  report what was done and how to verify) rather than pausing to ask the owner to
  confirm low-level steps — questions are reserved for genuine blockers and Tier-C
  gates (reinforcing operating-prompt SSOT §8). CLAUDE.md is versioned framework
  content shipped to adopters, but the direct-to-master push bypassed the PR-only
  `check-version-bump.sh` gate, so onboarded projects comparing their
  `.ai/.framework-version` against the template `package.json` .version would not
  have seen the change. This bump versions that framework change so drift detection
  fires.

## [0.0.14] - 2026-07-11

### Added

- Headless dispatch now notifies Telegram (notification coverage gap): the bash
  auto-dispatch path (`.ai/tools/dispatch-handoffs.sh`) was silent — only the
  PowerShell pane-runner loop notified, so `Auto:yes` Risk-A/B handoffs dispatched
  headless never reached the owner. New `.ai/tools/notify.sh` mirrors
  `tools/4ai-panes/notify.ps1` (env-first config resolution, the same 2-line
  bold-project Markdown format, robot/check/warning emoji, 5s curl timeout,
  fail-open) and is wired into the dispatcher at three lifecycle points — `picked`
  before launch, `done` on exit 0, `alert` on a non-zero exit. Both paths share the
  throttle file `.ai/handoffs/.claims/.fleet-notify-throttle.json` (60s dedup on
  `kind|project|handoff`) so they never double-send. `dispatch-own-queue.sh`
  variants inherit this by delegating to `dispatch-handoffs.sh`.

## [0.0.13] - 2026-07-11

### Security

- pre-commit guards failed OPEN on case-insensitive filesystems (latent-issue
  audit #4): the sensitive-file, removed-graph-tombstone, and cross-CLI territory
  checks in `scripts/git-hooks/pre-commit` matched staged paths case-SENSITIVELY,
  so on Windows/macOS a file committed as `.ENV`, `ID_RSA`, or `.Kimi/x` — the SAME
  file — slipped past the backstop. `_is_sensitive`, `_is_tombstone`, and
  `_territory_violation` now match on the lowercased path (new `_lc` helper),
  restoring fail-CLOSED behavior without changing which patterns/territories are
  blocked.

### Fixed

- `install-template.sh` update mode wiped gitignored local state (latent-issue
  audit #6): `.ai/research/` and `.claude/settings.local.json` were destroyed by the
  `rm -rf`+copy path on a framework update of an onboarded project. `.ai/research/`
  is now stashed/restored alongside `.ai/activity` and `.ai/reports`, and a new
  `preserve_local_state`/`restore_local_state` pair carries `.claude/settings.local.json`
  across the destructive `.claude` copy.
- `check-version-bump.sh` version-gate allowlist omitted two shipped scripts
  (latent-issue audit #5): `scripts/fleet-init.sh` and
  `scripts/sync-4ai-panes-install.ps1` are copied into every adopter by the
  installer but changes to them required no version bump, so drift shipped silently.
  Both are now in the `is_versioned` allowlist (`tools/4ai-panes/**` stays excluded —
  it is intentionally not shipped that way).

## [0.0.12] - 2026-07-11

### Security

- Handoff-dispatch command injection (two CRITICAL findings, latent-issue audit
  #1/#2): a crafted handoff **filename** (e.g. `x$(touch pwned).md` or one with
  backticks) could execute arbitrary code when a handoff was auto-processed. Both
  the dispatcher (`.ai/tools/dispatch-handoffs.sh`) and the pane runner
  (`tools/4ai-panes/pane-runner.ps1`) built a shell/PowerShell command STRING with
  the handoff path embedded, then ran it via `eval` / `Invoke-Expression`. Both now
  invoke the recipient CLI with a native argv array (`"${cmd[@]}"` in bash, the call
  operator `& $exe @args` in PowerShell); the handoff path is a single inert argv
  element that is never re-parsed by a shell. The interactive pause hatch was
  likewise converted off `Invoke-Expression`.

### Fixed

- Cross-consumer claim-write race (latent-issue audit #10): the dispatcher created
  the per-handoff claim empty (`:>`) and filled it in a separate `printf`, leaving a
  0-byte window in which the PowerShell pane runner would read it as *unclaimed* and
  double-process the handoff. The claim is now written to a temp file and published
  atomically (hard-link on the common path, atomic rename to overwrite a stale
  claim), mirroring the PowerShell `Write-Claim` pattern — the claim name never
  points at an empty file.

## [0.0.11] - 2026-07-11

### Added

- `install-template.sh` now copies the full `docs/architecture/` ADR set (0001–0009,
  not just 0001) plus the concrete files copied guards/hooks reference
  (`scripts/fleet-init.sh`, `scripts/sync-4ai-panes-install.ps1`,
  `docs/specs/4ai-panes-install-sync.md`), so no governance/automation link dangles
  in an adopted project. The `tools/4ai-panes/` pane fleet is intentionally left
  unshipped by default (labeled STUB/owner-decision flag in the installer).

### Fixed

- `install-template.sh` Kimi-hook idempotency: `wire_kimi_hooks` now strips any
  legacy `# ADDED BY install-template.sh kimi-hooks` block (pre-sentinel append-once
  format) before reconciling, so re-runs converge to exactly one sentinel-fenced
  managed block instead of appending a third block on machines wired before the
  sentinel scheme. Only the four clearly-marked legacy guard stanzas are removed;
  unrelated hooks (safety-check.ps1, activity-log-remind.sh, user hooks) are preserved.
