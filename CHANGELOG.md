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
