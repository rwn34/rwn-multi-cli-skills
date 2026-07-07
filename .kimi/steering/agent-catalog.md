# Agent Catalog

Final catalog of 13 agents (orchestrator + 12 subagents) for the multi-CLI project.
All three CLIs implement these agents in their native config format.

## Agents

| # | Agent | Class | Tools | Write scope | Shell scope |
|---|---|---|---|---|---|
| 0 | `orchestrator` | Default | fs_read, fs_write, grep, glob, code, introspect, knowledge, web_search, web_fetch, todo_list, subagent | `.ai/**`, `.kiro/**`, `.kimi/**`, `.claude/**` | None |
| 1 | `coder` | Executor | fs_read, fs_write, execute_bash, grep, glob, code | Anywhere except framework dirs | Unrestricted |
| 2 | `reviewer` | Diagnoser | fs_read, grep, glob, code, introspect, fs_write | `.ai/reports/` only | None |
| 3 | `tester` | Executor | fs_read, fs_write, execute_bash, grep, glob, code | Test files + `.ai/reports/` | Test runners + coverage |
| 4 | `debugger` | Executor | fs_read, fs_write, execute_bash, grep, glob, code, web_search, web_fetch | Anywhere + `.ai/reports/` | Unrestricted |
| 5 | `refactorer` | Executor | fs_read, fs_write, execute_bash, grep, glob, code | Anywhere except framework dirs | Test runners only |
| 6 | `doc-writer` | Executor | fs_read, fs_write, grep, glob | `*.md`, `docs/**`, `CHANGELOG*`, `LICENSE*`, `README*`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `.ai/reports/` | None |
| 7 | `security-auditor` | Diagnoser | fs_read, grep, glob, execute_bash, web_search, web_fetch, fs_write | `.ai/reports/` only | Scanners only |
| 8 | `ui-engineer` | Executor | fs_read, fs_write, execute_bash, grep, glob, code, web_fetch | Anywhere except framework dirs | Unrestricted + browser tools |
| 9 | `e2e-tester` | Diagnoser | fs_read, fs_write, execute_bash, grep, glob, web_fetch | E2E test files + `.ai/reports/` | Browser tools + test runners |
| 10 | `infra-engineer` | Executor | fs_read, fs_write, execute_bash, grep, glob, web_search, web_fetch | IaC/CI dirs only | plan/validate/build + git operations |
| 11 | `release-engineer` | Executor | fs_read, fs_write, execute_bash, grep, glob, web_fetch | Version files + `CHANGELOG*` | git tag, npm publish, dry-run first |
| 12 | `data-migrator` | Executor | fs_read, fs_write, execute_bash, grep, glob | `migrations/**`, `seeds/**`, `schema.*` | Migration tools only |

## Agent classes

- **Default (orchestrator):** Read + delegate + framework-only writes. Cannot touch project source.
- **Executor:** Can write and run commands within its declared scope.
- **Diagnoser:** Primarily read-only. Can write reports to `.ai/reports/` and test files where noted.

## Framework directories (orchestrator-only writes)

`.ai/**`, `.kiro/**`, `.kimi/**`, `.claude/**` — only the orchestrator writes here.
All subagents are denied write access to these paths.

**Per-CLI nuance:** while this catalog lists all four framework dirs as the
orchestrator's write scope, each CLI's implementation narrows this to **its own
dir + the shared `.ai/`**. Cross-CLI writes (e.g., Claude editing `.kimi/`) are
hard-blocked by each CLI's pre-write hook and always go through the handoff
queue (`.ai/handoffs/`) — never direct. This matches the same nuance in
`.ai/instructions/orchestrator-pattern/principles.md`.

## Reports directory

`.ai/reports/` — diagnosers write structured reports here. Naming convention:
`<agent>-<YYYY-MM-DD>-<slug>.md`. Each report includes severity levels and
file/line references where applicable.

## Write scope details

### Test files (tester)
`tests/**`, `test/**`, `**/__tests__/**`, `*.test.*`, `*.spec.*`, `*_test.*`,
`*_spec.*`, `conftest.py`, `jest.config.*`, `pytest.ini`, `.coveragerc`

### E2E test files (e2e-tester — superset of tester scope)
Everything in the tester list above, plus E2E-framework dirs at root:
`e2e/**`, `tests/e2e/**`, `**/*.e2e.*`, `playwright/**`, `cypress/**`.
Plus E2E config files: `playwright.config.*`, `cypress.config.*`.

### IaC/CI paths (infra-engineer)
Primary directory scope — everything here is inside `infra/**`:
`infra/**` (covers `infra/docker/Dockerfile*`, `infra/docker/docker-compose*`,
`infra/terraform/**`, `infra/k8s/**`, `infra/helm/**`, `infra/ci/**`), `scripts/**`,
`tools/**`.

Root-level exceptions (permitted per ADR-0001 category D and tooling requirements):
`.github/workflows/**` (GitHub Actions — GitHub-mandated location), `.gitlab-ci.yml`,
`.circleci/**`, `.buildkite/**`, `.dockerignore`.

`Dockerfile` and `docker-compose.yml` at repo root are NOT permitted by ADR-0001 —
use `infra/docker/` instead. Amend the ADR first if a project-specific tooling
constraint requires the root location.

### Version files (release-engineer)
`VERSION`, `package.json` (version field only), `pyproject.toml` (version field only),
`Cargo.toml` (version field only), `CHANGELOG*`, `.github/release.yml`

### Migration files (data-migrator)
`migrations/**`, `seeds/**`, `schema.*`, `alembic/**`, `prisma/**`

## Enforcement per CLI

| Mechanism | Kiro | Claude | Kimi |
|---|---|---|---|
| Tool whitelist | `tools` array (hard) | `tools:` frontmatter (hard) | `allowed_tools` / `exclude_tools` (hard) |
| Path restriction | `toolsSettings.fs_write.allowedPaths` (hard) | `permissions.deny` or prompt (soft) | Prompt + PostToolUse hook (soft) |
| Shell restriction | `toolsSettings.execute_bash.allowedCommands` (hard) | Prompt (soft) | Prompt + hook (soft) |

## CLI role lanes (ADR-0002)

The 13-agent roster is implemented per CLI, but each CLI occupies a distinct
lane — see `docs/architecture/0002-cli-role-topology.md` (authoritative):

- **Claude Code** — architect + orchestrator + final reviewer (specs, ADRs,
  PR gating, merge recommendation).
- **Kimi CLI** — high-throughput executor; peer-reviews Kiro's work.
- **Kiro CLI** — premium-reasoning executor; peer-reviews Kimi's work.
- **Crush** — narrow-scope ops/release operator (release review: dry-runs,
  checklists, deploy reports — NOT code review). Staged deploy authority per
  the ADR.
- **Deploy separation:** Kimi and Kiro have NO deploy lane — deploy actions
  are out of scope for their `release-engineer` agents. Interim deployer is
  Claude's `release-engineer` (dry-run + explicit user confirmation) until
  Crush Stage 1 lands. Author ≠ reviewer ≠ deployer.

## Agent behavior rules

1. **Orchestrator** never writes project source. Delegates all mutations.
2. **Executors** follow Karpathy guidelines: surgical changes, simplicity first.
3. **Diagnosers** never modify code under review. Reports go to `.ai/reports/`.
4. **Debugger** can apply small fixes (one-liners, typos, missing imports). Larger fixes delegate to coder.
5. **Refactorer** must run tests before AND after every change. Aborts on regression.
6. **Release-engineer** must dry-run before any publish/tag. Refuses if tests fail or tree is dirty.
7. **Data-migrator** must produce reversible migrations (up + down).
8. **Infra-engineer** handles git operations (add, commit, push, branch, merge) on behalf of the orchestrator. The orchestrator delegates git mutations here — it has no shell access itself.
9. All subagents report back: files touched, commands run, test results, deviations from brief.
