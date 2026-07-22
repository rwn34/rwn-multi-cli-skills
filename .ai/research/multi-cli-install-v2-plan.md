# multi-cli-install v2 — design plan

**Status:** APPROVED for phased execution (decisions locked + revised 2026-04-27 by user)
**Author:** claude (orchestrator)
**Date:** 2026-04-27 (revised from morning draft after objective revisit)

---

## Goal

A single executable that, against any directory, sets up the multi-CLI AI
coordination framework correctly:

- **New project**: scaffold + framework, ready to code in.
- **Existing project**: inspect the project's actual structure, **reorganize
  the project's files into the framework's canonical layout where safe**, fall
  back to adapt mode for framework-pinned dirs that can't move, and inject
  project-specific facts into all 13 subagents per CLI without manual edits.

Replaces today's two-script setup (`scripts/new-project.sh` +
`scripts/install-template.sh`) which does mechanical install + light language
detection but neither learns project structure nor reorganizes nor adapts AI
behavior.

---

## Locked decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Runtime | **Node.js**, distributed as `@rwn34/multi-cli-install` via `npx` | Cross-platform out of the box (Windows native, macOS, Linux). Native JSON/YAML/TOML parsing for the inspector. Single command. |
| 2 | Existing-project default mode | **Reorganize project → framework canonical layout** (what can move, moves; what's framework-pinned, stays + documented) | Matches the user's original objective verbatim ("put the existing project into the new structure"). Yields uniformity across all adopting projects, not "different layout per project documented in a context file." |
| 3 | When inspector detects framework-pinned layout (Rails, Django, Next.js App Router, Phoenix, etc.) | **Fall back to adapt mode for pinned dirs only** | Reorganize what's safe, leave framework-pinned dirs in place, document them in `.ai/project-context.md`. Pragmatic compromise — still "project into structure" for everything that can move. |
| 4 | How project-specific facts reach 39 subagent files | **Single `.ai/project-context.md`, agents read it at session start** | One file. No per-agent patching. Easy to regenerate when project evolves. Drift-check unaffected. |

---

## Architecture

Four logical components, one binary:

### Component 1 — Project Inspector (read-only)

Walks the target directory. Outputs structured profile **plus a per-directory
movability classification.**

**Captures:**

| Category | What | How |
|---|---|---|
| Stack | language + package manager | `package.json` / `Cargo.toml` / `pyproject.toml` / `go.mod` / `Gemfile` / `composer.json` |
| Framework | Next.js (Pages vs App), Nuxt, Django, Rails, Phoenix, monorepo (Turbo/Nx/Lerna/pnpm-workspace/Cargo workspace/go.work) | config-file presence + key fields |
| Source dirs | actual location of source code | top-2-level dir scan, classify by file ratio |
| Test dirs | actual location of tests | conventional names + content sniff |
| Docs dirs | existing docs structure + presence of ADRs | `docs/`, `documentation/`, `doc/`, `wiki/`, `adr/`, `decisions/` |
| CI | CI system + workflow file paths | `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `Jenkinsfile`, `azure-pipelines.yml` |
| Conventions | naming style, lint config | sample filenames + `.eslintrc*` / `ruff.toml` / `clippy.toml` / `.rubocop.yml` |
| Commands | actual test/build/lint commands | parse `package.json scripts`, `Cargo.toml`, `pyproject.toml`, `Makefile` |
| Existing ADRs | are decision records already in place? | `docs/architecture/`, `docs/decisions/`, `adr/` |
| Secret risk | accidentally committed secrets | scan for `.env`, `*.key`, `*.pem`, `id_rsa*` (read-only warning) |

**Movability classifier — new** — for each dir at root, classify:

| Class | Meaning | Examples |
|---|---|---|
| `movable` | Reorganize safely with simple `git mv` + import update | loose JS files at root, simple Python packages, isolated `lib/` |
| `movable-with-rules` | Reorganize requires running a per-framework rule set | Next.js App Router (`app/` → `src/app/`), Cargo workspace (`crates/` → keep, but rewrite `[workspace] members`), Vite (`src/` already canonical, just verify), pyproject packages (update `[tool.poetry] packages`), Go workspace (update `go.work`), Turbo (update `turbo.json` paths), pnpm-workspace |
| `framework-pinned` | Layout enforced by framework — reorganizing breaks the framework | Rails (`app/`, `config/`, `db/`, `spec/`, `test/`), Django (`manage.py` + apps with `INSTALLED_APPS` string refs), Phoenix (`lib/`, `priv/`), Hanami |
| `unknown` | Inspector can't classify confidently | Custom layouts, exotic frameworks |

**Outputs:**

- `.ai/project-profile.json` — machine-readable, consumed by Migration Engine + Strategy Picker.
- `.ai/project-context.md` — human-readable + agent-readable canonical project facts.

### Component 2 — Strategy Picker (interactive, with non-TTY fallback)

For each detected mismatch between project's layout and framework canonical
(`src/`, `tests/`, `docs/`, `infra/`, `migrations/`, `scripts/`, `tools/`,
`config/`, `assets/`), the picker presents the user with:

| Movability class | Default action | User options |
|---|---|---|
| `movable` | Reorganize | accept / decline / preview-diff |
| `movable-with-rules` | Reorganize via rule set | accept / decline / preview-diff |
| `framework-pinned` | Adapt (skip reorg) | accept-adapt / refuse-and-abort |
| `unknown` | Adapt with explicit prompt | adapt / try-reorg-anyway-with-warning / refuse-and-abort |

Non-TTY default: take the "default action" column without prompting. Log
every decision to `.ai/reports/install-adapt-decisions.md`.

### Component 3 — Migration Engine (new — does the actual reorganization)

Runs only when the Strategy Picker chose to reorganize a dir. For each dir to
move, runs a sequence:

1. **Plan** — generate the file moves + reference updates as a list of
   operations (no writes yet).
2. **Preview** — print plan; user confirms.
3. **Execute** — run operations atomically (file moves via `git mv`,
   reference updates via codemods), all in one new commit on a separate
   branch.
4. **Verify** — run project's existing test/build/lint commands (captured
   by inspector). If any fail, offer rollback.

**Per-framework rule sets** — Tier 1 (must ship in v1.0.0):

| Framework / pattern | What the rule set does |
|---|---|
| Loose JS/TS at root | Move loose `*.ts/*.js` to `src/`. Update imports via TypeScript Compiler API or `jscodeshift`. Update `package.json` `main` / `bin` paths. |
| Next.js (Pages Router) | Move `pages/` → `src/pages/`. Update `next.config.js` if it references paths. |
| Next.js (App Router) | Move `app/` → `src/app/`. Update `next.config.js`. Verify routes still resolve. |
| Vite + plain TS | Already canonical; verify, don't move. |
| Rust workspace | Rewrite `[workspace] members` in root `Cargo.toml` if member paths change. |
| Go workspace | Update `go.work` `use` directives. |
| pnpm workspace | Update `pnpm-workspace.yaml` packages glob. |
| Turborepo | Update `turbo.json` `pipeline` paths if they reference moved dirs. |
| Python with pyproject | Update `[tool.poetry] packages` or `[tool.setuptools] packages` after package dir move. |
| CI globs | Find `.github/workflows/*.yml`, `.gitlab-ci.yml`, etc., update path globs. |
| tsconfig paths | Update `tsconfig.json` `compilerOptions.paths` and `include`/`exclude`. |
| Test framework configs | jest `roots`, pytest `testpaths`, vitest `include`. |

Tier 2 (post-v1.0.0): Rails, Django, Phoenix, Laravel, ASP.NET — these
default to `framework-pinned` (Tier 1 doesn't migrate them).

### Component 4 — Behavior Patcher

After Migration Engine completes:

1. **Generate `.ai/project-context.md`** from `project-profile.json`, but
   **after** any reorganization so paths reflect the post-move state. Format:

   ```markdown
   # Project context

   Generated by multi-cli-install v2 on YYYY-MM-DD. Regenerate via
   `npx @rwn34/multi-cli-install --refresh-context`.

   ## Stack
   - Language: TypeScript (Node.js 20)
   - Package manager: pnpm
   - Framework: Next.js 14 (App Router)

   ## Layout (post-install)
   - Source: `src/app/` (Next.js App Router, moved from `app/` during install)
   - Tests: `tests/`
   - Docs: `docs/`
   - CI: `.github/workflows/`

   ## Framework-pinned dirs (NOT moved during install)
   - (none in this project) | OR
   - `config/` — Rails framework dir, layout enforced by Rails

   ## Commands
   - Test: `pnpm test`
   - Build: `pnpm build`
   - Lint: `pnpm lint`

   ## Conventions
   - Naming: camelCase (TypeScript convention)
   - Lint config: ESLint + Prettier

   ## Notes for AI agents
   When making changes, follow this project's existing patterns. Layout above
   reflects the post-install state. Framework-pinned dirs (if any) must not be
   relocated.
   ```

2. **Wire each CLI's orchestrator steering** to read this file at session
   start. Single paragraph added via SSOT regen:

   > **Project context** — at the start of substantive work, read
   > `.ai/project-context.md`. It captures this project's stack, layout, and
   > commands as of the most recent install or refresh. If the project has
   > evolved since, run `npx @rwn34/multi-cli-install --refresh-context`.

3. **Patch ADR-0001** for any project-root files the inspector found that
   aren't in the default allowlist.

4. **Patch root-guard hooks** to allow those files (existing
   `patch_hook_allow` logic, expanded).

5. **Skip per-agent config edits.** Context propagates through normal
   session-start reading.

---

## Implementation phases

| Phase | Scope | Deliverable | Estimated effort |
|---|---|---|---|
| **P0** | Repo home decision (in-repo `tools/multi-cli-install/` vs sibling repo `rwn34/multi-cli-install`) + scaffolding | `package.json`, `tsconfig.json`, vitest, bin entry. Commit on a feature branch. | ½ day |
| **P1a** | Inspector — basic profile (stack, framework, dirs, commands, conventions) | Module + unit tests on fixture projects (Next.js App, Next.js Pages, Vite, Django, Rails, Rust workspace, Go monorepo, Python with pyproject). | 2–3 days |
| **P1b** | Inspector — movability classifier | Classifies each root dir as `movable` / `movable-with-rules` / `framework-pinned` / `unknown`. Tested against same fixtures. | 1–2 days |
| **P2** | Strategy Picker | Interactive prompt loop (`@inquirer/prompts`). Non-TTY default behavior using the movability defaults table. Decision log output. | 1 day |
| **P3** | Migration Engine — Tier 1 rule sets | Per-framework migrations: loose JS/TS, Next.js Pages, Next.js App, Vite verify, Rust workspace, Go workspace, pnpm-workspace, Turborepo, Python pyproject, CI globs, tsconfig paths, jest/pytest/vitest configs. Each rule set unit-tested. | 4–6 days |
| **P4** | Behavior Patcher | Port copy-framework-files + sanitize-state from current bash installer to TS. Generate `project-context.md`. Wire orchestrator-steering reference via SSOT (so the regen pipeline propagates to all 3 CLI replicas). ADR + hook patching for detected root files. | 2 days |
| **P5** | Distribution | `package.json` + `bin/` + publish dry-run to npm. README quick-start updated to `npx @rwn34/multi-cli-install <target>`. | ½ day |
| **P6** | Validate on real projects (**mandatory** before v1.0.0) | Run on at least 3 real existing projects of different stacks (Next.js App, Rust workspace, plain Node lib). Document every failure. Iterate Tier 1 rule sets until clean. | 2–4 days, possibly more |

Total: ~14–20 days of focused work. Dominated by P1b + P3 (movability classifier + migration rule sets).

---

## Compatibility / migration

- **Existing bash scripts (`scripts/install-template.sh`, `scripts/new-project.sh`) stay** during P0–P5. Mark deprecated in `scripts/README.md` once v2 is published, remove in a later cycle (v2.1+).
- **Repo policy:** P0 deferred decision. Either `tools/multi-cli-install/` (per ADR-0001 Category D) or sibling repo `rwn34/multi-cli-install`.
- **Framework versioning:** v2 installer copies framework files from a pinned template ref. The published `@rwn34/multi-cli-install@X.Y.Z` corresponds to a specific framework SHA. Bump together; cross-pin in the installer's README.

---

## Risks

1. **Inspector complexity grows unbounded.** Every framework adds detection + migration rules. Mitigation: hard-cap at Tier 1 list above for v1.0.0; explicitly mark Rails/Django/Phoenix/Laravel/ASP.NET as `framework-pinned` (no migration attempted) until Tier 2.
2. **Migration breaks real codebases.** Reorganize-default + buggy rule set = corrupted real projects. Mitigation: P6 validation phase is **mandatory before publish**; every migration runs project's own test/build/lint as verification gate; Migration Engine commits on a separate branch so rollback is `git branch -D`.
3. **Framework-pinned detection misses edge cases.** Inspector classifies a Rails project as `movable` because no `Gemfile`. Mitigation: detection rules are conservative — if confidence below threshold, classify `unknown` and prompt user.
4. **Hybrid mode UX is heavy.** Many mismatches × many prompts. Mitigation: batch prompts logically (all source-dir mismatches together), offer "apply same answer to all" toggle, summary screen before execute.
5. **`.ai/project-context.md` drifts as project evolves.** Today's commands won't match next year's. Mitigation: `--refresh-context` subcommand reruns inspector and regenerates only the context file; orchestrator steering checks freshness and suggests refresh if older than 30 days.
6. **Cross-CLI parity for the steering edit.** Each CLI's steering format differs. Mitigation: source the wiring text from the SSOT (`.ai/instructions/orchestrator-pattern/principles.md`), regenerate replicas via existing `.ai/sync.md` flow, drift-check enforces consistency.
7. **Reorganize creates a giant migration commit.** Hard to review. Mitigation: Migration Engine emits one commit per framework rule set (e.g., one for "Next.js app/ → src/app/", one for "tsconfig paths", one for "CI globs") — reviewable by topic rather than as a single megablob.
8. **Real-project surprises.** Inspector and migration will miss things on first runs. Mitigation: P6 budget; don't publish v1.0.0 until 3 real adoptions succeed cleanly.

---

## Open questions (deferred to P0)

- Does the new package live in this repo (`tools/multi-cli-install/`) or as a sibling repo (`rwn34/multi-cli-install`)?
- npm package name: `@rwn34/multi-cli-install` (scoped) or `rwn-multi-cli-install` (matching `rwn-kimigraph` convention)?
- Should the inspector also emit a `docs/architecture/0002-adopted-framework.md` ADR documenting the install + migration decisions?
- For `framework-pinned` projects (Rails et al.), should the installer print a recommendation to `--refresh-context` periodically, or trust user discipline?

---

## Execution checklist

- [ ] P0 — package home decision + scaffold
- [ ] P1a — Inspector (basic profile)
- [ ] P1b — Inspector (movability classifier)
- [ ] P2 — Strategy Picker
- [ ] P3 — Migration Engine (Tier 1 rule sets)
- [ ] P4 — Behavior Patcher (incl. project-context.md + orchestrator-steering wiring via SSOT)
- [ ] P5 — Distribution
- [ ] P6 — Validate on 3 real projects (mandatory before v1.0.0)
- [ ] Deprecate old bash scripts in `scripts/README.md`
- [ ] Update top-level `README.md` quick-start to `npx @rwn34/multi-cli-install <target>`
- [ ] Activity log entries per phase
