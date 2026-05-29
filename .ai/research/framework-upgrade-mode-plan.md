# Framework `--upgrade` mode for `@rwn34/multi-cli-install`

**Status:** plan, pre-implementation
**Scope:** Node installer at `tools/multi-cli-install/` only. Bash installer (`scripts/install-template.sh`) stays first-install-only legacy.
**Target release:** `0.0.3` (Phase A) and `0.1.0` (Phases B–F).
**Author:** Plan agent under claude-code orchestrator, 2026-05-29.

## 1. Problem statement

The installer ships exactly one mode today: first-install. `bin/multi-cli-install.ts` copies framework dirs and files via `copyFrameworkFiles()` (`src/installer/copy-framework.ts:27-51`), then sanitizes runtime state and adapts policy. There is no path to re-run it against a project that already has the framework in order to pull in a newer version's SSOTs, replicas, hooks, or reference files.

This gap surfaced concretely when `v0.0.2-pre.5` added the `self-grep-verify` SSOT (`.ai/instructions/self-grep-verify/principles.md` plus three replicas under `.claude/skills/`, `.kimi/steering/`, `.kiro/steering/`). Adopters who installed earlier had no way to acquire it except by hand-copying from the release tarball. The framework adds new SSOTs roughly every release; the problem will repeat indefinitely without an upgrade mode.

**Non-goals.** Upgrade mode must never touch adopter runtime state:
- `.ai/handoffs/{to-claude,to-kimi,to-kiro}/{open,done}/` (cross-CLI work queues)
- `.ai/activity/log.md` and `.ai/activity/archive/` (activity log)
- `.ai/reports/` (audit outputs)
- `.ai/research/` (long-form research, including this plan)
- `.archive/` (rolled-over state)

These are sanitized to empty on first install (`src/installer/sanitize.ts:30-73`) but become adopter data after that. Upgrade mode treats them as out of scope, full stop.

## 2. Design constraints

| Constraint | Source |
|---|---|
| Working tree must be clean before upgrade | mirrors install precondition at `bin/multi-cli-install.ts:57-67` |
| Offline — no network calls except optional `--check` version probe | matches install behavior (zero network today) |
| Reversible — `git reset --hard` restores prior state | upgrade commits on its own branch |
| `--dry-run` previews every operation before any write | matches existing `--dry-run` flag |
| Commits on branch `ai-template-upgrade` so adopter reviews diff | mirrors install's `ai-template-install` branch convention |
| Idempotent — running `--upgrade` when already at latest is a no-op with a friendly message | required for re-runs |
| No edits to adopter runtime state (see §1 non-goals) | hard rule |

## 3. Version marker

**Path:** `.ai/.framework-version` (proposed; see open question 1).

**Format:** JSON (matches the installer's existing style; `package.json`, `.ai/sync.md`-driven config, etc. are already JSON-native; no need to introduce YAML).

**Schema:**

```json
{
  "framework_version": "0.0.2",
  "installer_name": "@rwn34/multi-cli-install",
  "installer_version": "0.0.2",
  "installed_at": "2026-05-29T14:30:00Z",
  "upgrade_history": [
    { "from": "0.0.1", "to": "0.0.2", "at": "2026-05-29T14:30:00Z" }
  ]
}
```

`installer_name` distinguishes Node vs bash installs (bash installs initially leave this field absent — upgrade-mode degrades gracefully). `upgrade_history` is append-only; bounded to last 20 entries.

**Bootstrap migration.** Adopters installed before this marker existed are treated as `framework_version: "unknown"` — the manifest is rebuilt from current file content, but adopter-modification detection is conservative (assume every file may be customized; no force-overwrites).

## 4. Manifest scheme

**Path:** `.ai/.framework-manifest.json` (proposed).

**Purpose:** record sha256 of every framework-owned file at install/upgrade time so subsequent upgrades can detect adopter modifications by sha mismatch.

**Schema:**

```json
{
  "version": "0.0.2",
  "files": {
    ".ai/instructions/karpathy-guidelines/principles.md": {
      "sha256": "abc123...",
      "version_first_seen": "0.0.1",
      "classification": "framework-owned"
    },
    "AGENTS.md": {
      "sha256": "def456...",
      "version_first_seen": "0.0.1",
      "classification": "adopter-customized-expected"
    }
  }
}
```

Written by Phase A at the end of `copyFrameworkFiles()`. Read by Phase B (detector). Updated by Phase E (executor) on upgrade commit.

## 5. Per-file-class upgrade policy

The framework file inventory comes from `FRAMEWORK_DIRS` and `FRAMEWORK_FILES` in `src/installer/copy-framework.ts:5-11`, plus everything sanitized in `src/installer/sanitize.ts`, plus reference files in `src/installer/adapt-policy.ts:18-22`. Classified:

| Class | Glob | Classification | Baseline available? | On-upgrade action |
|---|---|---|---|---|
| SSOT principles | `.ai/instructions/*/principles.md` | framework-owned | yes (manifest) | overwrite if unmodified; 3-way merge if modified |
| SSOT examples | `.ai/instructions/*/examples.md` | framework-owned | yes | same as above |
| New SSOT directories | `.ai/instructions/<new-name>/**` | framework-owned, net-new | n/a | create |
| Claude skill replicas | `.claude/skills/*/SKILL.md`, `EXAMPLES.md` | framework-owned (body) + adopter (frontmatter occasionally) | yes | overwrite body, preserve frontmatter (per the `<!-- SSOT: ... -->` line convention in `.ai/sync.md:12`) |
| Kimi steering replicas | `.kimi/steering/*.md` | framework-owned | yes | overwrite if unmodified; 3-way otherwise |
| Kiro steering replicas | `.kiro/steering/*.md` | framework-owned | yes | same |
| Kiro Skills | `.kiro/skills/*/SKILL.md` | framework-owned (body) + Kiro frontmatter | yes | body-replace, preserve frontmatter |
| Sync map | `.ai/sync.md` | adopter-may-extend | yes | 3-way merge (adopter rows for their own SSOTs preserved) |
| Drift checker | `.ai/tools/check-ssot-drift.sh` | framework-owned (mostly) | yes | overwrite if unmodified; conflict if modified |
| `AGENTS.md` | root | adopter-customized expected | yes | 3-way merge or section-aware merge (see §6) |
| `CLAUDE.md` | root | adopter-customized expected | yes | same |
| Claude agents | `.claude/agents/*.md` (13 files per `ls .claude/agents`) | framework-owned | yes | overwrite if unmodified; 3-way otherwise |
| Kimi agents | `.kimi/agents/*.yaml`, `.kimi/agents/system/**` | framework-owned | yes | same |
| Kiro agents | `.kiro/agents/*.json` | framework-owned | yes | same |
| Hooks | `.claude/hooks/*.sh`, `.kimi/hooks/*.sh`, `.kiro/hooks/*.sh` | framework-owned, but ADR-F-patched by `adaptPolicy()` (`src/installer/adapt-policy.ts:82-99`) | yes (pre-patch baseline) | overwrite then re-run `adaptPolicy()` |
| Kimi resource | `.kimi/resource/*.md` | framework-owned | yes | overwrite if unmodified |
| ADR root-file-exceptions | `docs/architecture/0001-root-file-exceptions.md` | adopter-extended (Category F) | yes | 3-way merge; re-run `adaptPolicy()` for Category F amendment if missing |
| CI workflow | `.github/workflows/framework-check.yml` | framework-owned | yes | overwrite if unmodified; conflict otherwise |
| `.gitignore` | root | adopter-merged | yes | re-run `adaptPolicy()` merge logic (already idempotent — `src/installer/adapt-policy.ts:29-56`) |
| Settings | `.claude/settings.json`, `.kimi/config.toml`, `.kiro/settings/**` | framework-shipped default + adopter overrides | yes (defaults) | leave alone if modified, refresh if untouched |
| Cross-CLI handoff queues | `.ai/handoffs/{to-*}/open/`, `done/` | adopter runtime | n/a | **never touch** |
| Activity log | `.ai/activity/log.md`, `.ai/activity/archive/**` | adopter runtime | n/a | **never touch** |
| Reports | `.ai/reports/*` | adopter runtime | n/a | **never touch** |
| Research | `.ai/research/**` | adopter runtime | n/a | **never touch** |
| Handoff README + template | `.ai/handoffs/README.md`, `.ai/handoffs/template.md` | framework-owned | yes | overwrite if unmodified |
| `.archive/**` | adopter runtime | n/a | **never touch** |

## 6. Merge strategy for adopter-modified files

**Primary tool:** `git merge-file -p <current> <baseline> <new> > <merged>`. `git` is already required by the installer (`bin/multi-cli-install.ts:57-67`).

**Baseline source.** The previously installed framework version's content. Two options:
1. Re-fetch the previous version's tarball from npm (`npm pack @rwn34/multi-cli-install@<prev>` → extract `assets/`). Requires network at upgrade time.
2. Bundle a `baselines/` cache under `.ai/.framework-cache/` storing each historical version's framework files. Inflates install size by ~200 KB per release.

**Recommendation:** option 1 with a `--baseline-from <path>` escape hatch for offline scenarios. Network is acceptable here because upgrade is intentional and infrequent.

**Conflict handling.** When `git merge-file` exits 1 (conflict), leave Git-style conflict markers in the file, list the file in the upgrade report, and exit 1 from the CLI. Adopter resolves with their editor before merging the `ai-template-upgrade` branch.

**Section-aware merge for `AGENTS.md` / `CLAUDE.md`.** Optional Phase E+ enhancement. Parse H2 sections; framework-owned sections (e.g. "Per-CLI contract entry points" in `AGENTS.md:13`) get replaced; adopter-added sections (anything outside the known set) stay. Cuts conflict noise in the most-customized files. ~300 LOC including tests. Recommend deferring to Phase E+ to avoid blocking Phase B–E.

## 7. CLI UX

**Invocation:**
```
npx @rwn34/multi-cli-install <project-dir> --upgrade [--dry-run] [--baseline-from <dir>]
```

Flag added to the parser at `bin/multi-cli-install.ts:11-13`. Help text added to lines 25-31.

**Output sections:**
1. Header: `multi-cli-install v<X> (upgrade mode)`, current and target version
2. Manifest check: `<n> framework files tracked, <m> adopter-modified`
3. Per-file plan:
   - `+ added`: `.ai/instructions/<new>/principles.md`
   - `~ overwrite`: `.ai/instructions/karpathy-guidelines/principles.md` (unchanged from baseline)
   - `M merged`: `AGENTS.md` (3-way merge clean)
   - `! conflict`: `CLAUDE.md` (manual resolution needed)
   - `- skip`: `.ai/instructions/agent-catalog/principles.md` (no change in new version)
   - `K kept`: `.ai/handoffs/to-claude/open/handoff-001.md` (adopter runtime)
4. Footer: counts + commit summary if not dry-run

**Exit codes:**
- `0` clean upgrade (or no-op if already at latest)
- `1` conflicts requiring manual resolution (branch still created, adopter resolves)
- `2` precondition failure (dirty tree, missing manifest with `--strict`, etc.)

**Phase 6 follow-up message** (matches the install pattern at the end of `bin/multi-cli-install.ts:176`):
```
✓ Upgrade complete. Review changes on branch ai-template-upgrade, then merge.
```

## 8. Edge cases

| Case | Behavior |
|---|---|
| No manifest (pre-marker install or bash install) | Treat all framework files as "possibly modified". Emit warning. Use file-content equality with bundled new-version content as a weaker substitute for sha-vs-baseline. |
| N versions behind | No per-version replay. Compute diff from manifest's `version` directly to new version. 3-way merge handles intermediate changes. |
| Adopter renamed framework file | Surface as: new-version file `X` will be created; old file `Y` matches no expected path → report as "untracked, leaving alone". |
| Adopter deleted framework file | If absent on disk but in manifest, treat as intentional removal. Do not re-create. Print info line. |
| Framework removed file in new version | If file exists on adopter side, do not delete. Warn: "framework removed `<path>` in v<new>; your copy is preserved." |
| Dirty working tree | Refuse with the exact error message from `bin/multi-cli-install.ts:62`. |
| Adopter modified hooks for ADR Category F | `adaptPolicy()` is already idempotent (`src/installer/adapt-policy.ts:48`). Re-running after upgrade is safe. |
| Build-only `tools/multi-cli-install/assets/` | Never installed in adopter trees (`assets/` is build artifact, not framework). No upgrade concern. |
| `.claude/settings.local.json` | Adopter-local, gitignored. Never touched. |
| Target uses bash installer (no `.framework-version`) | Degraded-baseline mode (see "No manifest" row). Optional: write a marker post-upgrade. |

## 9. Test plan

**Unit tests** (new file `test/upgrade.test.ts`):
- Manifest read/write round-trip
- sha256 computation matches `git hash-object`-equivalent stability
- Per-file classifier returns correct class for each glob
- Planner decisions: framework-owned + unmodified → overwrite; + modified → merge; etc.
- Merger: clean 3-way passes; conflict produces markers

**Integration tests** (new file `test/upgrade-integration.test.ts`):
Use a `test/fixtures/upgrade/` tree with three fixture projects:
- `v0.0.2-clean/` — installed at 0.0.2, no adopter modifications
- `v0.0.2-customized/` — adopter has edited `AGENTS.md`, added a custom SSOT
- `v0.0.2-mixed/` — some files customized, some untouched

For each, run `upgrade()` to a synthetic `0.0.3-test` baseline (extra SSOT, modified karpathy principles, removed agent) and assert the resulting tree.

**Real-project validation** deferred to a separate handoff (matches the v0.0.1 install-mode pattern noted in `tools/multi-cli-install/README.md:76`).

## 10. Implementation breakdown

**New modules** (target ~1200 LOC including tests):

- `src/upgrade/types.ts` — `UpgradePlan`, `FileAction`, `UpgradeResult`, `ManifestEntry`
- `src/upgrade/manifest.ts` — read/write `.ai/.framework-manifest.json`, sha256 helper (~80 LOC)
- `src/upgrade/version.ts` — read/write `.ai/.framework-version` (~60 LOC)
- `src/upgrade/detector.ts` — scan current tree, compare to manifest, classify each file (~150 LOC)
- `src/upgrade/planner.ts` — produce `UpgradePlan` from detector output + new-version asset tree (~200 LOC)
- `src/upgrade/merger.ts` — wrap `git merge-file`, handle conflicts (~120 LOC)
- `src/upgrade/executor.ts` — apply plan, commit on branch (~150 LOC)
- `src/upgrade/index.ts` — orchestration entry point (~50 LOC)
- Export surface added to `src/index.ts`

**Existing code to reuse:**
- `resolveTemplateDir()` (`src/installer/copy-framework.ts:13-25`) — same logic locates the bundled new-version assets
- `adaptPolicy()` — re-run post-upgrade to re-apply ADR Category F amendments to refreshed hooks
- The dirty-tree check at `bin/multi-cli-install.ts:57-67` — extract to a shared helper
- vitest setup pattern from `test/installer.test.ts:43-58`

**Existing code to extend:**
- `bin/multi-cli-install.ts` — add `--upgrade` and `--baseline-from` flag handling; new branch
- `copyFrameworkFiles()` — Phase A: write manifest + version marker at end
- `package.json` `version` — bump to `0.0.3` for Phase A, `0.1.0` for Phases B–F

**Build implications.** `scripts/sync-assets.ts` is unchanged — it already copies the framework tree verbatim. The new marker files are *not* part of the source-of-truth tree (they're install-time outputs), so `sync-assets.ts` does not need to handle them.

## 11. Phasing

### Phase A — manifest + version marker (ships first, standalone)
- Add `src/upgrade/manifest.ts` and `src/upgrade/version.ts`
- Call them at the end of `copyFrameworkFiles()` (or in `bin/multi-cli-install.ts` after the copy/sanitize/adapt block, ~line 124)
- Add `.framework-version` and `.framework-manifest.json` to the install report
- Unit tests for the two modules
- Ship as `0.0.3`
- **Independently valuable:** every install after this point gets future-upgradability for free.

### Phase B — upgrade detector
- `src/upgrade/detector.ts`: scan current tree, sha256 every file, compare against manifest, label each as `unmodified | adopter-modified | adopter-added | framework-removed`
- Read the new-version asset tree via `resolveTemplateDir()` and diff against manifest
- Returns a typed detection summary

### Phase C — planner
- `src/upgrade/planner.ts`: convert detector output + per-file-class policy (§5) into a sequence of `FileAction` ops (`add`, `overwrite`, `merge`, `skip`, `keep-adopter`)
- Pure function, no I/O. Easy to unit-test.

### Phase D — merger
- `src/upgrade/merger.ts`: shell out to `git merge-file -p`, capture stdout, write to disk; on exit 1 leave conflict markers and add to conflict list
- Three-input file orchestration (current adopter file, baseline from previous version, new-version file)

### Phase E — executor + CLI wiring
- `src/upgrade/executor.ts`: walk the plan, dispatch to overwrite/merge/skip
- Create branch `ai-template-upgrade`, stage all changed files, commit with structured message including the upgrade report
- Re-run `adaptPolicy()` after copy to re-apply ADR Category F patches
- Update `.ai/.framework-version` (append history entry) and `.ai/.framework-manifest.json` (rewrite from new state)
- CLI wiring in `bin/multi-cli-install.ts`: `--upgrade`, `--dry-run`, `--baseline-from`
- Section-aware merge for `AGENTS.md`/`CLAUDE.md` is OPTIONAL in this phase (recommended deferral)

### Phase F — tests + docs + real-project validation
- Full unit + integration test suite (§9)
- README update at `tools/multi-cli-install/README.md` (new mode 6)
- A separate handoff for real-project validation against a stale checkout
- Ship as `0.1.0`

## 12. Open questions for the user

1. **Marker filename.** `.ai/.framework-version` (hidden, in SSOT zone) vs `.ai/FRAMEWORK_VERSION` (visible) vs `tools/multi-cli-install/.installed-version.json` (out of SSOT zone)?
2. **Manifest location.** Same as version marker, or hide deeper in `.ai/.framework-cache/manifest.json`?
3. **Bash-installed upgrades.** Patch `scripts/install-template.sh` to also write the marker, so future upgrades work for bash-installed adopters too? Or document as unsupported?
4. **`git merge-file` dependency.** Acceptable hard requirement (already implicit via the dirty-tree check)?
5. **Section-aware merge for `AGENTS.md`/`CLAUDE.md`.** Worth Phase E+ investment, or live with generic 3-way and accept noisier conflicts?
6. **Network for baseline fetch.** `npm pack @rwn34/multi-cli-install@<prev>` at upgrade time vs bundling historical baselines in package?
