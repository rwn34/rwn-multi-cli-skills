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
