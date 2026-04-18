# Kimi CLI Agent Catalog Proposal

**10 specialized subagents for the orchestrator pattern**

---

## The 10 Agents

| # | Agent | Purpose | Tools allowed | Tools denied / restrictions | Orchestrator spawns when... |
|---|---|---|---|---|---|
| 1 | `tester` | Run tests, analyze coverage, fix failing tests | `Shell`, `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode` | User says "run tests", "check coverage", "fix this test", "add a test for X" |
| 2 | `debugger` | Diagnose bugs via logs, traces, reproduction | `Shell`, `ReadFile`, `Glob`, `Grep`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `WriteFile`, `StrReplaceFile`, `EnterPlanMode`, `ExitPlanMode` | User reports a bug, "why is this failing?", "debug this error" |
| 3 | `refactorer` | Structural changes: renames, moves, extraction, dead-code removal | `Shell`, `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode` | "Rename this everywhere", "Extract into shared lib", "Move these files" |
| 4 | `docs-writer` | Write docs, READMEs, changelogs, API references | `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `Shell`, `EnterPlanMode`, `ExitPlanMode` | "Update README", "Document this API", "Write changelog entry" |
| 5 | `security-auditor` | Security scans: deps, secrets, auth, permissions | `Shell`, `ReadFile`, `Glob`, `Grep`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `WriteFile`, `StrReplaceFile`, `EnterPlanMode`, `ExitPlanMode` | "Audit dependencies", "Check for secrets", "Security scan" |
| 6 | `performance-analyst` | Profile, benchmark, find bottlenecks | `Shell`, `ReadFile`, `Glob`, `Grep`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `WriteFile`, `StrReplaceFile`, `EnterPlanMode`, `ExitPlanMode` | "Why is this slow?", "Profile this", "Benchmark this API" |
| 7 | `infra-engineer` | CI/CD, Docker, K8s, deployment scripts | `Shell`, `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode` | "Add GitHub Action", "Update Dockerfile", "Fix CI build" |
| 8 | `dependency-manager` | Update packages, resolve lockfile conflicts | `Shell`, `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode` | "Update dependencies", "Bump React to v19", "Fix lockfile conflict" |
| 9 | `data-migrator` | DB schema changes, migrations, backfills | `Shell`, `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode` | "Add migration", "Backfill data", "Update schema" |
| 10 | `release-engineer` | Version bumps, git tags, release notes, publish | `Shell`, `ReadFile`, `Glob`, `Grep`, `WriteFile`, `StrReplaceFile`, `SearchWeb`, `FetchURL` | `Agent`, `AskUserQuestion`, `SetTodoList`, `EnterPlanMode`, `ExitPlanMode` | "Cut a release", "Bump version", "Generate release notes" |

---

## Rationale

### Separation of concerns
I chose 10 agents that cover the **full software delivery lifecycle** without overlap:
- **Code quality:** `tester`, `debugger`, `refactorer`
- **Communication:** `docs-writer`
- **Operational excellence:** `security-auditor`, `performance-analyst`
- **Platform & delivery:** `infra-engineer`, `dependency-manager`, `data-migrator`, `release-engineer`

### Diagnoser vs Executor split
Three agents are **read-only diagnosers** (`debugger`, `security-auditor`, `performance-analyst`). They investigate and report findings but do not mutate project source. This prevents half-baked fixes. The orchestrator delegates the actual fix to `coder`, `tester`, or `refactorer`.

### Why I kept `refactorer` separate from `coder`
Refactoring is structurally different from feature work. It requires cross-file coordination, import updates, and verification that references aren't broken. A dedicated `refactorer` can have a system prompt optimized for structural integrity, while `coder` focuses on implementing features.

### Why I kept `release-engineer` separate from `infra-engineer`
Releases happen frequently and have a specific ritual (version bump, changelog, tag, publish). Infra changes are structural and happen rarely. Merging them means the agent's prompt has to context-switch between two very different modes.

### Why `docs-writer` has no Shell
Documentation is pure file editing. Removing `Shell` minimizes blast radius and makes the agent's scope crystal clear.

---

## Essential vs Nice-to-Have

### Core 6 (start here)
| Agent | Why essential |
|---|---|
| `tester` | Every code change needs verification |
| `debugger` | Bugs are the most common user request |
| `refactorer` | Large renames/cleanups are too risky for generic `coder` |
| `docs-writer` | Docs drift is constant; needs dedicated attention |
| `infra-engineer` | CI/CD breaks block all development |
| `security-auditor` | Security issues are high-stakes and need focused review |

### Nice-to-have 4 (add after core is working)
| Agent | Why nice-to-have |
|---|---|
| `performance-analyst` | Not every project needs profiling |
| `dependency-manager` | Often bundled with `tester` or `infra-engineer` in small projects |
| `data-migrator` | Only relevant for projects with databases |
| `release-engineer` | Small projects can release manually or via CI |

---

## Recommendation

**Start with the Core 6.** Implement them first, test delegation flows, and measure whether the orchestrator picks the right agent. Once the core is stable, add the Nice-to-Have 4. This avoids config bloat and makes debugging agent selection easier early on.

---

## Kimi-Specific Notes

- **Tool restriction:** Achieved via `allowed_tools` + `exclude_tools` in `agent.yaml`. Read-only agents simply exclude `WriteFile` and `StrReplaceFile`.
- **Path restriction:** Kimi has **no native path-level write filtering**. For agents like `docs-writer` (path-restricted in concept), enforcement must come from the system prompt + steering docs.
- **Dynamic creation:** Not possible. All 10 need static YAML files. Each addition requires a session restart to register in the `LaborMarket`.
