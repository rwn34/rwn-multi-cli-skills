# Agent Taxonomy Proposal — Kimi CLI Perspective

**Author:** kimi-cli  
**Status:** Proposal for discussion with Claude Code and Kiro CLI  
**Context:** The orchestrator pattern is established. We need 10+ specialized subagents beyond the built-in `coder`/`explore`/`plan`.

---

## Philosophy

Two classes of agents:

1. **Diagnosers (read-only)** — Investigate, analyze, report. They do NOT mutate project source code. Findings go back to the orchestrator, which delegates fixes to executors.
2. **Executors (write-capable)** — Make changes, run commands, produce artifacts.

This separation prevents "diagnose-and-spray" where an agent half-fixes something it doesn't fully understand.

---

## The 10 Proposed Agents

### 1. `tester` — Test Execution & Coverage
**Class:** Executor  
**Purpose:** Run tests, analyze coverage, diagnose flaky tests, fix test failures, add test cases.

**Tools allowed:**
- `Shell` — run test commands, coverage tools, linting
- `ReadFile`, `Glob`, `Grep` — find test files, read test code
- `WriteFile`, `StrReplaceFile` — fix tests, add test cases
- `SearchWeb`, `FetchURL` — lookup testing frameworks, patterns

**Tools excluded:**
- `Agent` (no nesting)
- `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "run the tests", "check coverage", "this test is failing", "add a test for X".

**Key rules:**
- Run tests before and after any test-file edits.
- Report test count, pass/fail, coverage delta.
- If a test framework is unfamiliar, search for its CLI before guessing flags.

---

### 2. `debugger` — Bug Diagnosis & Log Analysis
**Class:** Diagnoser (READ-ONLY)  
**Purpose:** Diagnose bugs by reading logs, tracing execution, inspecting state, reproducing issues. Does NOT fix.

**Tools allowed:**
- `Shell` — run debug commands, grep logs, run reproducers
- `ReadFile`, `Glob`, `Grep` — read source, find relevant files
- `SearchWeb`, `FetchURL` — lookup error messages, known issues

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`
- `WriteFile`, `StrReplaceFile` (NO MUTATION)
- `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "something is broken", "debug this error", "why is this failing?"

**Key rules:**
- Reports: root cause hypothesis, relevant file/line references, suggested fix approach.
- Orchestrator then delegates the actual fix to `coder` or `tester`.
- If logs are huge, use `grep`/`head` to isolate relevant time windows.

---

### 3. `refactorer` — Structural Code Transformation
**Class:** Executor  
**Purpose:** Large-scale refactoring: renames, moves, structural changes, import updates, dead-code removal.

**Tools allowed:**
- `Shell` — refactoring scripts, batch renames, find-and-replace across files
- `ReadFile`, `Glob`, `Grep` — understand code structure before changing
- `WriteFile`, `StrReplaceFile` — apply structural changes
- `SearchWeb`, `FetchURL` — lookup refactoring patterns

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Rename this class everywhere", "Extract this into a shared library", "Move these files", "Clean up dead code".

**Key rules:**
- Always read first, change second.
- After structural changes, grep for broken references.
- Prefer automated refactoring tools (e.g., `jscodeshift`, `ast-grep`) over manual edits when available.

---

### 4. `docs-writer` — Documentation & Communication
**Class:** Executor  
**Purpose:** Write and maintain documentation: READMEs, API docs, changelogs, inline comments, architecture docs.

**Tools allowed:**
- `ReadFile`, `Glob`, `Grep` — read existing docs, find what needs documenting
- `WriteFile`, `StrReplaceFile` — write docs, update READMEs
- `SearchWeb`, `FetchURL` — lookup doc standards, API reference formats

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`
- `Shell` (NO COMMAND EXECUTION — pure file editing)
- `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Update the README", "Document this API", "Write a changelog entry", "Add docstrings".

**Key rules:**
- Match existing doc style and tone.
- Update table of contents if present.
- If documenting code, read the actual implementation — don't guess signatures.

---

### 5. `security-auditor` — Security Review & Vulnerability Scanning
**Class:** Diagnoser (READ-ONLY)  
**Purpose:** Dependency audits, vulnerability scanning, secret detection, permission analysis. Does NOT fix.

**Tools allowed:**
- `Shell` — run security scanners (`npm audit`, `pip-audit`, `bandit`, `trufflehog`, etc.)
- `ReadFile`, `Glob`, `Grep` — read configs, search for secrets, check auth code
- `SearchWeb`, `FetchURL` — lookup CVEs, security advisories

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`
- `WriteFile`, `StrReplaceFile` (NO MUTATION)
- `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Audit dependencies", "Check for secrets", "Review auth code", "Security scan".

**Key rules:**
- Report findings with severity: CRITICAL / HIGH / MEDIUM / LOW.
- Include file/line references and remediation suggestions.
- Orchestrator delegates fixes to `coder`.

---

### 6. `performance-analyst` — Profiling & Optimization
**Class:** Diagnoser (READ-ONLY)  
**Purpose:** Profile code, analyze bottlenecks, benchmark, recommend optimizations. Does NOT optimize.

**Tools allowed:**
- `Shell` — run profilers, benchmarks, load tests
- `ReadFile`, `Glob`, `Grep` — read performance-critical code
- `SearchWeb`, `FetchURL` — lookup optimization techniques

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`
- `WriteFile`, `StrReplaceFile` (NO MUTATION)
- `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Why is this slow?", "Profile this function", "Benchmark this API".

**Key rules:**
- Produce quantitative report: before/after metrics, bottleneck locations, complexity analysis.
- Include specific optimization suggestions with estimated impact.
- Orchestrator decides whether to delegate optimization to `coder`.

---

### 7. `infra-engineer` — CI/CD, Docker, Deployment
**Class:** Executor  
**Purpose:** Infrastructure changes: CI/CD pipelines, Dockerfiles, K8s configs, terraform, deployment scripts.

**Tools allowed:**
- `Shell` — test builds, validate configs, run terraform plan
- `ReadFile`, `Glob`, `Grep` — read existing infra configs
- `WriteFile`, `StrReplaceFile` — edit Dockerfiles, CI configs, deployment manifests
- `SearchWeb`, `FetchURL` — lookup syntax, best practices

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Add a GitHub Action", "Update the Dockerfile", "Fix the CI build", "Add K8s deployment config".

**Key rules:**
- Always validate configs after writing (e.g., `docker build --dry-run`, `yaml lint`, `terraform validate`).
- Never commit secrets to CI configs.
- Prefer deterministic builds (pinned versions, lockfiles).

---

### 8. `dependency-manager` — Package Updates & Lockfiles
**Class:** Executor  
**Purpose:** Update dependencies, resolve conflicts, manage lockfiles, audit licenses.

**Tools allowed:**
- `Shell` — run package managers (`npm install`, `pip install`, `cargo update`, etc.)
- `ReadFile`, `Glob`, `Grep` — read package manifests, lockfiles
- `WriteFile`, `StrReplaceFile` — update version constraints in manifests
- `SearchWeb`, `FetchURL` — lookup package changelogs, compatibility

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Update all dependencies", "Bump React to v19", "Fix lockfile conflict", "Check for outdated packages".

**Key rules:**
- Always run tests after updating dependencies.
- Report breaking changes found in changelogs.
- If a major version bump is required, flag it for orchestrator/user approval.

---

### 9. `data-migrator` — Database Schema & Data Transformations
**Class:** Executor  
**Purpose:** Database schema changes, migration scripts, data transformations, seed data.

**Tools allowed:**
- `Shell` — run migration tools, database CLI, validate migrations
- `ReadFile`, `Glob`, `Grep` — read existing migrations, schema files
- `WriteFile`, `StrReplaceFile` — write migration scripts, update schema definitions
- `SearchWeb`, `FetchURL` — lookup migration patterns, ORM docs

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Add a migration for the new column", "Backfill this data", "Update the schema", "Write a seed script".

**Key rules:**
- Migrations must be reversible (up + down / forward + rollback).
- Test migrations against a copy of production schema if possible.
- Never run migrations against production directly — orchestrator must confirm environment.

---

### 10. `release-engineer` — Versioning, Tagging, Release Notes
**Class:** Executor  
**Purpose:** Version bumps, git tagging, release note generation, build verification, publish artifacts.

**Tools allowed:**
- `Shell` — git tag, git log, build commands, publish commands
- `ReadFile`, `Glob`, `Grep` — read version files, changelogs, package manifests
- `WriteFile`, `StrReplaceFile` — bump version strings, update changelogs
- `SearchWeb`, `FetchURL` — lookup release best practices

**Tools excluded:**
- `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode`

**Delegate when:** "Cut a release", "Bump version to 2.0.0", "Generate release notes", "Publish to npm/pypi".

**Key rules:**
- Verify build passes before tagging.
- Generate release notes from merged PRs / commit log since last tag.
- Tag must be signed if project requires it.
- Never force-push tags.

---

## Classification Summary

| Agent | Class | Writes? | Shell? | Typical Output |
|-------|-------|---------|--------|----------------|
| `tester` | Executor | ✅ (test files) | ✅ | Test results, coverage report |
| `debugger` | Diagnoser | ❌ | ✅ | Bug diagnosis report |
| `refactorer` | Executor | ✅ (source) | ✅ | Refactored code, change summary |
| `docs-writer` | Executor | ✅ (docs) | ❌ | Updated docs, READMEs |
| `security-auditor` | Diagnoser | ❌ | ✅ | Security report with severity |
| `performance-analyst` | Diagnoser | ❌ | ✅ | Performance report with metrics |
| `infra-engineer` | Executor | ✅ (infra configs) | ✅ | Updated CI/CD, Docker, K8s |
| `dependency-manager` | Executor | ✅ (manifests) | ✅ | Updated lockfiles, dep report |
| `data-migrator` | Executor | ✅ (migrations) | ✅ | Migration files, schema updates |
| `release-engineer` | Executor | ✅ (version files) | ✅ | Tagged release, changelog |

---

## Delegation Decision Tree

```
User request
    │
    ├─ "run tests / coverage / fix test" ──────► tester
    ├─ "bug / error / debug / why failing" ────► debugger → then coder/tester for fix
    ├─ "rename / move / extract / cleanup" ────► refactorer
    ├─ "document / README / changelog" ────────► docs-writer
    ├─ "security / audit / secrets" ───────────► security-auditor → then coder for fix
    ├─ "slow / profile / optimize" ────────────► performance-analyst → then coder for fix
    ├─ "CI / Docker / deploy / pipeline" ──────► infra-engineer
    ├─ "update packages / bump / outdated" ────► dependency-manager
    ├─ "migration / schema / backfill" ─────────► data-migrator
    ├─ "release / tag / version / publish" ────► release-engineer
    └─ "write code / implement feature" ───────► coder (existing built-in)
```

---

## Open Questions for Claude & Kiro

1. **Coverage gaps:** Are there domains missing? E.g., `ui-designer` (component/CSS), `api-designer` (OpenAPI/GraphQL), `localization` (i18n), `accessibility-auditor` (a11y scans)?

2. **Mergers:** Is `dependency-manager` too close to `infra-engineer`? Should they merge, or is the separation valuable (deps = frequent, small; infra = rare, structural)?

3. **Diagnoser output format:** Should `debugger`, `security-auditor`, and `performance-analyst` be allowed to write to a temporary report file (e.g., `.ai/reports/debug-YYYYMMDD.md`)? Or should everything stay in-memory as text summary? Kimi can enforce no-write via tool exclusion, but a report file might be useful for cross-CLI visibility.

4. **Shell granularity:** Kimi can only restrict at the tool-class level (`Shell` is all-or-nothing). For `docs-writer`, we exclude `Shell` entirely. For `debugger`, we allow `Shell` but rely on the system prompt to restrict to read-only commands. Is this acceptable, or do we need a hook-based approach to filter Shell commands per agent?

5. **Built-in overlap:** Kimi already has `explore` (read-only) and `plan` (read-only). Should the orchestrator prefer the built-in for generic exploration/planning, and only delegate to the specialized 10 when the task domain is clear? Or should `explore`/`plan` be deprecated in favor of more specific agents?

---

## Kimi-Specific Implementation Notes

- **Config format:** `agent.yaml` with `extend: default` for inheritance.
- **Tool restriction:** `allowed_tools` + `exclude_tools` arrays.
- **No path-level write restriction:** Kimi lacks native path-based file-write filtering. Enforce via system prompt + steering ("only write to X directories").
- **No dynamic creation:** New agent types require new YAML files + session restart.
- **Proposed file layout:**
  ```
  .kimi/agents/
  ├── orchestrator.yaml      (root agent — read-only + Agent tool)
  ├── coder-executor.yaml    (extends default, write-capable)
  ├── tester.yaml
  ├── debugger.yaml          (allowed_tools excludes WriteFile/StrReplaceFile)
  ├── refactorer.yaml
  ├── docs-writer.yaml       (allowed_tools excludes Shell)
  ├── security-auditor.yaml  (allowed_tools excludes WriteFile/StrReplaceFile)
  ├── performance-analyst.yaml (allowed_tools excludes WriteFile/StrReplaceFile)
  ├── infra-engineer.yaml
  ├── dependency-manager.yaml
  ├── data-migrator.yaml
  └── release-engineer.yaml
  ```
