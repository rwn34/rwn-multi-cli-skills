# Framework Install Drift Check — Spec

## Summary

An onboarded project adopts the multi-CLI framework once, at first pane launch,
and then never hears about it again: `Install-Framework` in
`tools/4ai-panes/Selector.ps1` is guarded by a **silent, one-time marker skip**
(`if (Test-Path .ai/.framework-version) { … return }`), so a project that was
onboarded at framework v0.0.3 keeps running v0.0.3 forever with no signal that
the template has moved on. Separately, the installer's own copy list has
**drifted behind the framework** — it never copies `.opencode/`, `opencode.json`,
or `.github/workflows/gates.yml`, and it never prunes the deprecated Crush-era
and per-CLI-graph artifacts that ADR-0002 and ADR-0003 removed. This spec does
two things: (Part 1) corrects `scripts/install-template.sh` to copy the missing
framework files and prune the known-deprecated ones, and (Part 2) replaces the
launcher's silent marker skip with a **warn-only version-drift check** that tells
the operator when their project trails the template and prints the exact adopt
command — without ever auto-mutating the project.

## Motivation

Two audiences feel this, both the framework maintainer (`claude-code` as fleet
git operator) and any human who opens a previously-onboarded project through the
4AI Panes launcher.

**No per-open validation, no update path.** `Install-Framework`
(`Selector.ps1`, ~lines 189-392) treats the presence of `.ai/.framework-version`
as "done forever." Its marker gate (lines 200-206) is:

```powershell
$fwMarker = Join-Path $targetDir ".ai\.framework-version"
if (Test-Path $fwMarker) {
    Write-Host "Framework already installed, skipping" -ForegroundColor DarkGray
    return
}
```

That is install-ONCE. A project onboarded months ago at an older framework
version is never told that the template advanced — there is no warning, no diff,
no prompt. The operator has no way to know, at the moment they open the project,
that their `.ai/`, `.claude/`, hooks, and ADRs are stale.

**The installer's copy list has fallen behind the framework it installs.**
`phase1()` (`install-template.sh`, lines 242-263) copies an explicit allowlist —
`.ai`, `.claude`, `.kimi`, `.kiro`, `.archive`, `CLAUDE.md`, `AGENTS.md`, the
root-file-exceptions ADR, `.github/workflows/framework-check.yml`,
`.codegraph/config.json`, and `scripts/git-hooks`. It does **not** copy three
files that are now part of the framework and verified present in the template
repo today: `.opencode/` (OpenCode's config dir), `opencode.json` (root config),
and `.github/workflows/gates.yml` (a CI workflow alongside the one already
copied). A freshly-installed project is therefore born incomplete.

**The installer never prunes deprecated artifacts.** `copy_dir` does `rm -rf`
then `cp -R` (lines 216-219), so stale files *within* a copied directory are
pruned on re-run — but files the framework no longer ships at all are never
removed, because nothing copies over them. ADR-0002 (2026-07-09) replaced Crush
with OpenCode, retiring `CRUSH.md` / `.crush/` / `.crush.json`. ADR-0003
(2026-07-09) rationalized code graphs down to a single CodeGraph, removing the
per-CLI `.kimigraph/` and `.kirograph/` graphs (the repo `.gitignore` lines 85-88
still carry their config-file carve-outs). A project onboarded before those ADRs,
then re-installed, keeps those dead files indefinitely.

**Why the two parts belong in one spec.** Part 1 makes the version bump
*meaningful*: bumping the framework version is only useful if already-onboarded
projects can observe the drift, which is exactly what Part 2 adds. And Part 2 is
only actionable if the fix it points at (re-running the installer) actually
brings a project fully up to date — which requires Part 1's corrected copy +
prune. Ship them together.

## Non-goals

- **Auto-update / auto-install on open.** The drift check is warn-only. It never
  mutates the project on launch. Silent broad rewriting of a project's source
  files at open time is the rejected Alternative A below — it violates the
  autonomy-gate principle (a Tier-B/C mutation dressed up as a Tier-A read).
- **File-content hash drift detection.** v1 compares *versions*, not file
  contents. Detecting that a specific framework file was edited locally (or
  differs byte-for-byte from the template) is a documented future enhancement —
  noisier, more work, and prone to false positives on a project's own legitimate
  local framework edits.
- **Touching `.mcp.json` wiring behavior.** `wire_mcp` (install-template.sh
  lines 454-511) is out of scope; this spec adds nothing to the MCP merge path.
- **The Node installer's `--upgrade` path.** `tools/multi-cli-install`'s
  TypeScript upgrade mechanism is a separate track. This spec touches only the
  bash `install-template.sh` and the PowerShell launcher.
- **A blanket "delete anything not in the template" sync.** The prune list is an
  explicit allowlist of known-deprecated artifacts only — never a diff-and-delete
  against the template, which would nuke a project's own files.

## Design

### API / interface

**Part 1 — installer corrections (`scripts/install-template.sh`).**

Extend `phase1()`'s copy calls (each is a no-op if the source is missing — see
`copy_dir`/`copy_file`, which already `warn` and `return 0` on an absent source):

```bash
# add to phase1(), after the existing copy_* calls:
copy_dir  ".opencode"
copy_file "opencode.json"
copy_file ".github/workflows/gates.yml"
```

Add a new `prune_legacy()` function that removes known-deprecated artifacts from
the target *if present*, and stages the deletions explicitly:

```bash
prune_legacy() {
  log "=== Prune deprecated artifacts (ADR-0002, ADR-0003) ==="
  local path
  for path in \
    "CRUSH.md" \
    ".crush" \
    ".crush.json" \
    ".kimigraph" \
    ".kirograph" \
  ; do
    local abs="$TARGET/$path"
    [ -e "$abs" ] || continue          # idempotent: absent → no-op
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY: prune $path (rm -rf + git add -A -- $path)"
      continue
    fi
    rm -rf "$abs"
    # phase5's manifest loop only stages paths that STILL EXIST (line ~851:
    # `if [ -e "$TARGET/$rel" ]`), so a deletion would never be committed.
    # Stage it here, explicitly. `git add -A -- <path>` stages the deletion of
    # a tracked path and is a safe no-op for an untracked one.
    git -C "$TARGET" add -A -- "$path" 2>/dev/null || true
    log "Pruned deprecated artifact: $path"
  done
}
```

Invoke `prune_legacy` from `phase2()` (state sanitization is the natural home for
"remove stale template state") — or as its own phase between `phase1` and
`phase2`. Either placement must run *before* `phase5`'s staging loop so the
deletion lands in the same install commit.

> **Staging note (load-bearing).** `git rm -rf --ignore-unmatch <path>` is an
> acceptable equivalent for tracked artifacts and is idempotent, but it *errors*
> on a path that is present-but-untracked in the target. `rm -rf` followed by
> `git add -A -- <path>` handles both the tracked and untracked cases and is the
> recommended form. Whichever is chosen, the deletion MUST be staged here because
> `phase5` will not stage it (its loop skips non-existent paths by design — see
> Data).

Bump the framework version SSOT so already-onboarded projects observe drift:

```jsonc
// tools/multi-cli-install/package.json — current version is 0.0.4 (verified)
"version": "0.0.5",   // bump because framework content changed (Part 1)
```

**Part 2 — launcher drift check (`tools/4ai-panes/Selector.ps1`).**

Replace the silent marker skip (lines 202-206) with a warn-only drift check. The
check needs the template source, which is currently resolved *after* the marker
gate (`$fwSource`, lines 212-218) — so the replacement must resolve the template
source (or at least the template `package.json` path) *before* comparing. Reuse
the exact `$frameworkRepo`-then-`$scriptDir` fallback the install path already
uses.

Introduce a helper (shape shown; inline is acceptable):

```powershell
function Test-FrameworkDrift {
    param($ProjVersionFile, $TemplatePkgJson, $AdoptCmd)
    # Returns nothing; emits a yellow WARNING iff projVer < tmplVer.
    # NEVER throws, NEVER mutates. Any read/parse failure => stay silent.
    try {
        $projVer = ([version](Get-Content $ProjVersionFile -Raw |
            ConvertFrom-Json).framework_version)
        $tmplVer = ([version](Get-Content $TemplatePkgJson -Raw |
            ConvertFrom-Json).version)
    } catch { return }                      # unparseable / missing => silent
    if ($null -eq $projVer -or $null -eq $tmplVer) { return }
    if ($projVer -lt $tmplVer) {
        Write-Host "Framework drift: project is v$projVer, template is v$tmplVer." `
            -ForegroundColor Yellow
        Write-Host "  To adopt updates: $AdoptCmd" -ForegroundColor Yellow
        Write-Host "  (lands on an isolated 'ai-template-install' branch to review before merging)" `
            -ForegroundColor Yellow
    }
    # projVer >= tmplVer, or equal, or any error => no output.
}
```

Wired into `Install-Framework`, replacing the current marker gate:

```powershell
if (Test-Path $fwMarker) {
    # Resolve template source (same fallback as the install path below).
    $src = if ((Test-Path $frameworkRepo) -and (Test-Path (Join-Path $frameworkRepo '.ai'))) {
        $frameworkRepo
    } elseif (Test-Path (Join-Path $scriptDir '.ai')) { $scriptDir } else { $null }

    if ($src) {
        $adopt = "bash $src/scripts/install-template.sh $targetDir"
        Test-FrameworkDrift `
            -ProjVersionFile $fwMarker `
            -TemplatePkgJson (Join-Path $src 'tools/multi-cli-install/package.json') `
            -AdoptCmd $adopt
    }
    return    # still return without installing — warn-only, never auto-update
}
```

The launcher **always continues to launch** regardless of the check's outcome —
the drift warning is advisory text printed before the panes split; it neither
blocks nor delays the launch, and it never sets a failing exit.

### Data

**`.ai/.framework-version`** — the per-project marker `write_framework_marker`
already writes (install-template.sh lines 802-824). No schema change; the drift
check only *reads* its `framework_version` field:

```jsonc
{
  "framework_version": "0.0.5",           // <- read as projVer
  "installer_name": "scripts/install-template.sh",
  "installer_version": "0.0.5",
  "installed_at": "2026-07-11T...Z",
  "upgrade_history": []
}
```

**Template version SSOT** — `tools/multi-cli-install/package.json` `.version`
(read as `tmplVer`). This is the *same* SSOT `install-template.sh` already reads
at runtime to stamp the marker (lines 125-135), and the *same* file
`Selector.ps1`'s fallback path already parses for its version (lines 363-371).
The drift check adds no new source of truth — it compares the marker's recorded
version against this one file.

> **Observation (not a change this spec makes):** the hard-coded fallback
> literals still read `0.0.3` — `install-template.sh:21`
> (`FRAMEWORK_VERSION="0.0.3"`) and `Selector.ps1` (`$fwVersion = '0.0.3'`,
> ~line 364). Both code paths *prefer* the package.json read and only fall back
> to the literal when that file is unreadable, so the stale literal is harmless
> today. Refreshing those literals to match is optional hygiene, out of this
> spec's required scope.

**Staging semantics for deletions.** `phase5`'s commit loop (lines 849-854)
stages only manifest paths that still exist:

```bash
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  if [ -e "$TARGET/$rel" ]; then          # <- pruned paths are gone; skipped
    git add -- "$rel" ...
  fi
done < "$uniq_manifest"
```

This is why `prune_legacy` must stage its own deletions (Part 1) rather than
relying on the manifest — a removed path is, by definition, no longer present for
this loop to stage.

### UX / behavior

- **On open, project up to date (`projVer >= tmplVer`):** silent. No output, no
  change, panes launch as before. This is the common case and must stay quiet.
- **On open, project behind (`projVer < tmplVer`):** a yellow, multi-line
  WARNING names both versions and prints the exact adopt command
  (`bash <fwSource>/scripts/install-template.sh <target>`), with a note that it
  lands on an isolated `ai-template-install` branch to review before merging.
  Then the launcher continues and splits panes. The operator is informed, not
  interrupted.
- **On open, marker unparseable / template version unreadable / any error:**
  silent. The check swallows every failure (`try { … } catch { return }`) and
  never throws — a broken or hand-edited marker must not break launch.
- **Fresh project (no marker):** unchanged behavior — the install path runs
  exactly as today (bash installer + PowerShell fallback copy).
- **Idempotent installer prune:** re-running `install-template.sh` on a project
  with no deprecated artifacts left is a no-op — every prune target is absent, so
  each iteration `continue`s. `--dry-run` prints the planned `rm -rf` + stage per
  present artifact and touches nothing.
- **Version-compare edge cases:** `[version]` parsing tolerates `Major.Minor` and
  `Major.Minor.Build`. A non-numeric or pre-release tag (e.g. `0.0.5-beta`)
  throws on cast → caught → silent. Equal versions → silent (not behind).

### Dependencies

- **Framework-version SSOT discipline (process dependency).** The drift check is
  only as good as the version number. If framework *content* changes but
  `tools/multi-cli-install/package.json` `.version` is **not** bumped, every
  already-onboarded project's `projVer` still equals `tmplVer` and the check
  stays silent — drift ships undetected. Bumping the version on every
  framework-content change is a required part of the release process, not
  optional. (Enforcement is an Open question.)
- **`$frameworkRepo` / `$scriptDir` resolution** (Selector.ps1 line 22 and the
  install-path fallback, lines 212-218) — the drift check reuses this existing
  logic to locate the template `package.json`. No new discovery mechanism.
- **PowerShell 5.1+** — already a launcher prerequisite. `ConvertFrom-Json` and
  the `[version]` cast are built in; no new modules.
- **`git` in the target** — `prune_legacy`'s `git add -A --` runs in the target
  repo, which `phase0` already validates as a clean git working tree. No new
  requirement.
- **No new third-party libraries** on either side.

### Note on `.opencode/` copy contents

`.opencode/` in the template contains a `.gitignore` and `contract.md` as the
only git-tracked files; `node_modules/`, `package.json`, and `package-lock.json`
are ignored by `.opencode/.gitignore` (OpenCode regenerates them on first run).
`copy_dir` does a physical `cp -R`, which would copy the (large, ignored)
`node_modules/` tree into the target on disk — though `phase5`'s `git add`
respects the copied `.opencode/.gitignore` and would not *stage* it. The on-disk
bloat is a known cost of the straight `copy_dir` approach; whether to filter it
is an Open question below.

## Alternatives considered

- **(A) Auto-update / auto-install on open.** Instead of warning, re-run the
  installer automatically whenever `projVer < tmplVer`. Rejected: this is a
  silent, broad mutation of the project's source (overwriting `.ai/`, `.claude/`,
  hooks, ADRs) performed at launch without operator consent — a Tier-B/C action
  masquerading as a Tier-A read. The autonomy-gate principle requires the human
  to be the gate on that kind of sweeping change. Warn-only keeps the operator in
  control: they see the drift and choose when to adopt, on a reviewable branch.
- **(C-hash) Full file-content hash drift detection.** Compare every framework
  file's hash in the project against the template and report per-file drift.
  Deferred, not rejected: it is strictly more work, noisier, and produces false
  positives whenever a project legitimately edits a framework file locally (which
  the framework explicitly permits in places). Version-compare is cheap, robust,
  and has no false positives from local edits — the right v1. Hash drift is
  recorded as a future enhancement (Non-goals + Open questions).
- **(status quo) Silent marker skip.** Keep the current one-time gate. Rejected:
  it is precisely the failure being fixed — zero visibility, zero validation, a
  project silently frozen at its onboarding version forever.

## Open questions

- **How is the version-bump discipline enforced?** The drift check goes silent if
  a framework-content change ships without a `package.json` version bump. Options:
  a CI check (`gates.yml`) that fails a PR touching framework paths without a
  version change; a pre-commit reminder; or convention + reviewer diligence.
  Owner: framework maintainer.
- **Should the installer later gain an opt-in `--update` flag?** Warn-only points
  the operator at re-running the full installer. A narrower, explicitly-invoked
  `--update` that refreshes framework files without the full onboarding ceremony
  might be a friendlier adopt path. Deferred; noted so it is a known future
  option, not a surprise.
- **Should the drift check also flag specific missing framework files?** As a
  secondary heuristic, the launcher could warn when a known framework path (e.g.
  `.opencode/` absent, or `opencode.json` missing) is not present in an onboarded
  project — catching drift even when versions happen to match. Deferred to keep
  v1 a pure version-compare; a candidate companion to the hash-drift enhancement.
- **Should `copy_dir ".opencode"` filter `node_modules/`?** The straight `cp -R`
  copies the ignored `node_modules/` tree onto disk (never staged, but bloats the
  target). Copying only tracked files, or excluding `node_modules/`, would be
  leaner. Deferred — the task specifies plain `copy_dir` for v1; revisit if the
  on-disk cost matters.
- **Does `Selector.ps1`'s fallback copy list need the same three files?** The
  PowerShell fallback `$templateItems` (lines 289-304) already lists
  `opencode.json`, ADR-0002, and ADR-0003 but not `.opencode/` or `gates.yml`, so
  it has drifted the same way `phase1` did. Aligning it is a natural follow-up but
  is outside this spec's Part 1 (bash installer) / Part 2 (drift check) scope.

## References

- `docs/specs/TEMPLATE.md` — the spec section structure this document follows.
- `scripts/install-template.sh` — the installer corrected in Part 1: `phase1()`
  copy allowlist (lines 242-263), `copy_dir`/`copy_file` (lines 203-240, no-op on
  missing source), `phase2` sanitization (lines 337-375, `prune_legacy`'s home),
  `write_framework_marker` (lines 802-824), `phase5` manifest staging loop that
  skips non-existent paths (lines 849-854), and the `FRAMEWORK_VERSION="0.0.3"`
  fallback literal (line 21) vs. the runtime SSOT read (lines 125-135).
- `tools/4ai-panes/Selector.ps1` — `Install-Framework` (lines 189-392); the
  silent marker gate replaced in Part 2 (lines 200-206); the
  `$frameworkRepo`/`$scriptDir` template-source fallback reused by the drift check
  (line 22, lines 212-218); the fallback copy list + version read (lines 289-304,
  363-371).
- `tools/multi-cli-install/package.json` — the framework-version SSOT; `.version`
  is `0.0.4` today (verified), bumped to `0.0.5` by Part 1.
- `docs/architecture/0002-cli-role-topology.md` — OpenCode replaced Crush
  (2026-07-09); basis for pruning `CRUSH.md` / `.crush/` / `.crush.json` and for
  copying `.opencode/` + `opencode.json`.
- `docs/architecture/0003-code-graph-rationalization.md` — per-CLI graphs removed
  (2026-07-09); basis for pruning `.kimigraph/` / `.kirograph/`.
- `.gitignore` (lines 85-88) — the residual `.kimigraph/` / `.kirograph/`
  config-file carve-outs, evidence those artifacts are legacy.
- `docs/specs/4ai-panes-install-sync.md` — sibling spec on keeping the executable
  launcher install in lockstep with the repo; its resolved "self-heal at launch"
  open question anticipates exactly this on-open drift-check direction. This spec
  is the framework-version analogue of that tool-file sync.
- `.ai/activity/log.md` — the investigation that surfaced the copy-list drift and
  the install-once gap (see the `claude-code` entry accompanying this spec).
