# Agent Catalog Proposal — Kiro CLI

10 specialized subagents for the orchestrator pattern. Each agent has a clear
purpose, tool allowlist, restrictions, and trigger.

## Proposed agents

| # | Name | Purpose | Tools allowed | Restrictions | Trigger |
|---|------|---------|---------------|-------------|---------|
| 1 | `coder` | Write code, edit files, run builds | fs_read, fs_write, execute_bash, grep, glob, code | No subagent. No writes to .ai/.kiro/.kimi/.claude | "Implement X", "fix this bug" |
| 2 | `reviewer` | Read-only code review, security audit | fs_read, grep, glob, code, introspect | No fs_write, no execute_bash | "Review this PR", "audit this module" |
| 3 | `tester` | Run tests, analyze coverage, write test files | fs_read, fs_write, execute_bash, grep, glob, code | fs_write restricted to tests/**/*, __tests__/**/*, *.test.*, *.spec.* | "Run tests", "add tests for X" |
| 4 | `researcher` | Web search, read docs, summarize findings | fs_read, grep, glob, web_search, web_fetch, knowledge | No fs_write, no execute_bash | "Research X", "compare X vs Y" |
| 5 | `refactorer` | Restructure code, rename, move files | fs_read, fs_write, execute_bash, grep, glob, code | Prompt-constrained: refactoring only, no new features | "Extract into module", "rename across codebase" |
| 6 | `documenter` | Write/update docs, READMEs, comments | fs_read, fs_write, grep, glob | fs_write restricted to *.md, docs/**. No execute_bash | "Update README", "document this API" |
| 7 | `devops` | CI/CD, Docker, infra configs | fs_read, fs_write, execute_bash, grep, glob | fs_write restricted to Dockerfile*, .github/**, docker-compose*, *.yml, *.yaml, scripts/** | "Set up CI", "fix Dockerfile" |
| 8 | `db-migrator` | Database schemas, migrations, seed data | fs_read, fs_write, execute_bash, grep, glob | fs_write restricted to migrations/**, seeds/**, schema.* | "Create migration", "update schema" |
| 9 | `git-ops` | Git operations, branch management, conflicts | fs_read, fs_write, execute_bash, grep, glob | execute_bash restricted to git commands only | "Resolve conflicts", "cherry-pick", "clean branches" |
| 10 | `scaffolder` | Generate boilerplate, new project structure | fs_read, fs_write, execute_bash, grep, glob | Prompt-constrained: creation only, no modifying existing files | "Scaffold new service", "create component" |

## Rationale

- **Tester separate from coder** — prevents "fix the code to pass the test" temptation.
  Tester can only write test files.
- **Researcher has no write** — pure information gathering. Returns findings to
  orchestrator who decides what to do.
- **Documenter can't run shell** — docs don't need command execution. Reduces blast radius.
- **Git-ops has shell but restricted to git** — powerful but scoped.
- **DB-migrator has path-restricted writes** — can't accidentally edit application code.

## Core vs nice-to-have

**Core (start with these 4):**
1. `coder` — the workhorse, handles most mutations
2. `reviewer` — quality gate, read-only
3. `tester` — test-driven workflow
4. `researcher` — information gathering without side effects

**Add when needed:**
5-10 are specialized. Create them when the project actually needs CI/CD, database
migrations, git operations, etc. The orchestrator can recommend creating a new agent
when it encounters a task that doesn't fit the core four.

## Kiro-specific notes

- Tool names: `fs_read`, `fs_write`, `execute_bash`, `grep`, `glob`, `code`,
  `introspect`, `knowledge`, `web_search`, `web_fetch`, `subagent`, `todo_list`
- Path restrictions via `toolsSettings.fs_write.allowedPaths` / `deniedPaths`
- Command restrictions via `toolsSettings.execute_bash.allowedCommands`
- Each agent is a standalone JSON in `.kiro/agents/<name>.json`
- No inheritance — shared config (resources, hooks) must be duplicated
- DAG pipeline via `subagent` tool allows multi-agent workflows in one invocation