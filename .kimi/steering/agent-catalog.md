# Agent Catalog

Final catalog of 13 agents (orchestrator + 12 subagents) for Kimi CLI.
Use this to decide which subagent to spawn via the `Agent` tool.

<!-- SSOT: .ai/instructions/agent-catalog/principles.md — regenerate via .ai/sync.md -->

---

## Quick Reference

| Agent | Class | Delegate when... |
|---|---|---|
| `orchestrator` | Default | You ARE the orchestrator. Read, plan, delegate. |
| `coder-executor` | Executor | "Implement feature X", "Fix this bug" |
| `reviewer` | Diagnoser | "Review this PR", "Code quality check" |
| `tester` | Executor | "Run tests", "Check coverage", "Fix failing test" |
| `debugger` | Executor | "Debug this error", "Why is this failing?" |
| `refactorer` | Executor | "Rename everywhere", "Extract into module", "Clean up dead code" |
| `doc-writer` | Executor | "Update README", "Document this API", "Write changelog" |
| `security-auditor` | Diagnoser | "Audit dependencies", "Check for secrets", "Security scan" |
| `ui-engineer` | Executor | "Build this component", "Style this page", "Fix this UI bug" |
| `e2e-tester` | Diagnoser | "Test this workflow", "Verify this user journey" |
| `infra-engineer` | Executor | "Add GitHub Action", "Update Dockerfile", "Fix CI" |
| `release-engineer` | Executor | "Cut a release", "Bump version", "Generate release notes" |
| `data-migrator` | Executor | "Add migration", "Backfill data", "Update schema" |

---

## Kimi Tool Name Mapping

The SSOT uses abstract tool names. Kimi's actual tool names are:

| Abstract | Kimi native |
|---|---|
| `fs_read` | `ReadFile`, `Glob`, `Grep`, `ReadMediaFile` |
| `fs_write` | `WriteFile`, `StrReplaceFile` |
| `execute_bash` | `Shell` |
| `web_search` | `SearchWeb` |
| `web_fetch` | `FetchURL` |
| `subagent` | `Agent` |
| `todo_list` | `SetTodoList` |
| `code` / `introspect` / `knowledge` | Performed via `ReadFile` + `Grep` + `SearchWeb` |

---

## Agent Details

### `orchestrator` (Default — You)

**Class:** Default  
**Purpose:** Read, analyze, plan, delegate. Write to framework dirs only.

**Tools:**
- `Agent`, `SetTodoList`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`
- `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`
- `WriteFile`, `StrReplaceFile` — **framework dirs only** (`.ai/`, `.kiro/`, `.kimi/`, `.claude/`)
- `SearchWeb`, `FetchURL`

**Cannot:** `Shell`, write project source code.

**Rules:**
1. Never write project source. Delegate all mutations.
2. Break non-trivial tasks into steps with verification criteria.
3. After subagent returns, read touched files to verify.
4. If subagent fails, report — don't retry silently.
5. If no agent fits, describe what's needed and ask user.

---

### `coder-executor`

**Class:** Executor  
**Purpose:** Implement features, fix bugs, write code.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Anywhere EXCEPT framework dirs (`.ai/`, `.kiro/`, `.kimi/`, `.claude/`).  
**Shell scope:** Unrestricted.

**Rules:**
- Follow Karpathy guidelines: surgical changes, simplicity first.
- Run tests after modifications.
- Report: files touched, commands run, test results.

---

### `reviewer`

**Class:** Diagnoser (READ-ONLY)  
**Purpose:** Code review: correctness, style, security, test coverage.

**Tools:** `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `Shell`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** `.ai/reports/` only.  
**Shell scope:** None.

**Rules:**
- Do NOT modify project source code.
- Severity levels: CRITICAL / HIGH / MEDIUM / LOW.
- Include file/line references.
- Report naming: `.ai/reports/reviewer-<YYYY-MM-DD>-<slug>.md`.

---

### `tester`

**Class:** Executor  
**Purpose:** Run tests, coverage, fix failing tests.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Test files + `.ai/reports/`.  
**Shell scope:** Test runners + coverage tools.

**Test files include:** `tests/**`, `test/**`, `**/__tests__/**`, `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `conftest.py`, `jest.config.*`, `pytest.ini`, `.coveragerc`.

**Rules:**
- Run tests BEFORE and AFTER edits.
- Report test count, pass/fail, coverage delta.
- Fix tests minimally — don't refactor unrelated code.

---

### `debugger`

**Class:** Executor  
**Purpose:** Bug diagnosis, log analysis, SMALL fixes only.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Anywhere + `.ai/reports/`.  
**Shell scope:** Unrestricted.

**Rules:**
- SMALL fixes only: one-liners, typos, missing imports.
- If fix exceeds ~3 lines or touches multiple files, report root cause instead.
- Report: root cause, file/line refs, what was done.

---

### `refactorer`

**Class:** Executor  
**Purpose:** Structural refactoring: renames, moves, extraction, dead-code removal.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Anywhere EXCEPT framework dirs.  
**Shell scope:** Test runners only.

**Rules:**
- Run tests BEFORE and AFTER every change.
- Abort on regression — do not proceed if tests fail.
- Grep for broken references after structural changes.
- Always read first, change second.

---

### `doc-writer`

**Class:** Executor  
**Purpose:** Documentation: READMEs, API docs, changelogs, inline comments.

**Tools:** `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `Shell`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** `*.md`, `docs/**`, `CHANGELOG*`, `.ai/reports/`.  
**Shell scope:** None.

**Rules:**
- Match existing doc style and tone.
- Read actual implementation before documenting APIs — don't guess.
- Update table of contents if present.

---

### `security-auditor`

**Class:** Diagnoser (READ-ONLY)  
**Purpose:** Security scans: dependency audits, secret detection, vulnerability scanning.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** `.ai/reports/` only.  
**Shell scope:** Security scanners only (`npm audit`, `pip-audit`, `bandit`, `trufflehog`, etc.).

**Rules:**
- Do NOT modify project source.
- Severity: CRITICAL / HIGH / MEDIUM / LOW.
- Include file/line refs and remediation suggestions.
- Report naming: `.ai/reports/security-auditor-<YYYY-MM-DD>-<slug>.md`.

---

### `ui-engineer`

**Class:** Executor  
**Purpose:** UI/UX implementation: components, styles, frontend features.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Anywhere EXCEPT framework dirs.  
**Shell scope:** Unrestricted.

**Rules:**
- Follow existing component patterns and style conventions.
- Run tests after modifications.
- Report files touched and visual changes.

---

### `e2e-tester`

**Class:** Diagnoser  
**Purpose:** End-to-end testing: validate user workflows and UI interactions.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Test files + `.ai/reports/`.  
**Shell scope:** Browser tools + test runners.

**Rules:**
- Run e2e tests and report results.
- Report naming: `.ai/reports/e2e-tester-<YYYY-MM-DD>-<slug>.md`.
- Do not modify source code — only test files.
- If tests fail due to source bugs, report findings to orchestrator.

---

### `infra-engineer`

**Class:** Executor  
**Purpose:** CI/CD, Docker, K8s, deployment configs.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** IaC/CI dirs: `Dockerfile*`, `.github/**`, `docker-compose*`, `*.yml`, `*.yaml`, `scripts/**`, `infrastructure/**`, `infra/**`, `terraform/**`, `k8s/**`, `helm/**`.  
**Shell scope:** Validation and build commands (`terraform plan/validate`, `docker build`, `yaml lint`).

**Rules:**
- Validate configs after writing.
- Never commit secrets to CI configs.
- Prefer deterministic builds (pinned versions, lockfiles).

---

### `release-engineer`

**Class:** Executor  
**Purpose:** Version bumps, git tags, release notes, publishing.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** Version files: `VERSION`, `package.json` (version field), `pyproject.toml` (version field), `Cargo.toml` (version field), `CHANGELOG*`, `.github/release.yml`.  
**Shell scope:** `git tag`, build commands, `npm publish` (after dry-run).

**Rules:**
- Verify build passes before tagging.
- Dry-run before any publish.
- Refuse if tests fail or working tree is dirty.
- Generate release notes from commit log since last tag.
- Never force-push tags.

---

### `data-migrator`

**Class:** Executor  
**Purpose:** Database migrations, schema changes, backfills.

**Tools:** `Shell`, `ReadFile`, `Glob`, `Grep`, `ReadMediaFile`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL`  
**Excluded:** `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Write scope:** `migrations/**`, `seeds/**`, `schema.*`, `alembic/**`, `prisma/**`.  
**Shell scope:** Migration tools only.

**Rules:**
- All migrations must be reversible (up + down / forward + rollback).
- Test migrations against a copy of production schema if possible.
- Never run against production directly — confirm environment with orchestrator.

---

## Framework Directories

Only the orchestrator writes to:
- `.ai/**`
- `.kiro/**`
- `.kimi/**`
- `.claude/**`

All subagents are denied write access to these paths.

---

## Agent Behavior Rules

1. **Orchestrator** never writes project source. Delegates all mutations.
2. **Executors** follow Karpathy guidelines: surgical changes, simplicity first.
3. **Diagnosers** never modify code under review. Reports go to `.ai/reports/`.
4. **Debugger** can apply small fixes (one-liners, typos, missing imports). Larger fixes delegate to `coder-executor`.
5. **Refactorer** must run tests before AND after every change. Aborts on regression.
6. **Release-engineer** must dry-run before any publish/tag. Refuses if tests fail or tree is dirty.
7. **Data-migrator** must produce reversible migrations (up + down).
8. **Infra-engineer** handles git operations (`git add`, `git commit`, `git push`, `git branch`, `git merge`) on behalf of the orchestrator. The orchestrator has no shell — it delegates all git mutations to infra-engineer.
8. All subagents report back: files touched, commands run, test results, deviations from brief.

---

## Kimi Enforcement Reality

| Restriction | How it's enforced |
|---|---|
| Tool whitelist | `allowed_tools` / `exclude_tools` in `agent.yaml` — **hard enforcement** |
| Path restriction | System prompt + steering docs — **soft enforcement** (Kimi has no native path filter) |
| Shell restriction | System prompt + steering docs — **soft enforcement** (Shell is all-or-nothing) |

To harden path/shell restrictions, add `PostToolUse` hooks in `~/.kimi/config.toml`.
