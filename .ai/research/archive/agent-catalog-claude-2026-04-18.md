# Agent Catalog — Claude Code

Proposal for 10 specialized subagents beyond the orchestrator. Claude's input to the
three-way planning session (Kiro's version at `.ai/research/agent-catalog-kiro.md`;
Kimi's at `.ai/research/agent-catalog-kimi.md` when ready). Meant to be read alongside
`.ai/instructions/orchestrator-pattern/principles.md` (architectural rules) and
`.ai/research/orchestrator-claude.md` (Claude's native agent mechanics).

## Design criteria

1. **Distinct specialties** — each agent occupies a niche no other agent covers as
   well. Overlap is wasted config surface.
2. **Minimum privilege** — each agent gets the smallest toolset that does its job.
   An agent that only writes docs should not have `Bash`.
3. **Composability** — orchestrator should route one task to one agent cleanly.
   If two agents commonly chain, that's fine (orchestrator mediates); if they
   always chain, they should probably merge.
4. **Trust tier aware** — higher trust = more tools = more orchestrator scrutiny.
   Orchestrator prefers the lowest-trust agent that can do the job.

## Trust tiers (framework for the allowlists)

- **Tier 0 — Read-only.** No `Edit`, `Write`, `Bash`. Reads, web, task-tracking.
  Zero mutation risk. Safe to invoke eagerly.
- **Tier 1 — Scoped-write.** `Edit`/`Write` allowed only under specific path
  patterns. Shell either disallowed or narrowly allowed (single-purpose commands
  like `pytest` or `terraform plan`). Bounded blast radius.
- **Tier 2 — Trusted full.** Unrestricted `Edit`/`Write`/`Bash`. Reserved for
  general mutation work. Orchestrator routes here only when no Tier 1 agent fits.

## The 10 agents

### 1. `coder` (Tier 2)

**Purpose:** General implementation workhorse. Writes new code, edits existing,
runs tests, handles the bulk of orchestrator-delegated mutations.

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`, `NotebookEdit`,
`TaskCreate/Update/List`, `Skill`, `WebFetch` (for fetching docs during impl).

**Write scope:** Anywhere. **Shell:** Unrestricted.

**Behaviors:** Karpathy-disciplined — surgical, simplicity-first, verification
via tests before reporting done. Reports diff summary + tests passed.

**Distinct from:** `refactorer` (behavior-preserving only), `tester` (tests only),
`debugger` (repro-first workflow).

### 2. `reviewer` (Tier 0)

**Purpose:** Read-only code review — correctness, style, test coverage, obvious
smells. Not security-focused (that's `security-auditor`).

**Tools:** `Read`, `Grep`, `Glob`, `Skill`, `WebFetch` (for referencing standards).

**Write scope:** None. **Shell:** None.

**Behaviors:** Returns structured report — summary + issues by severity
(critical/high/medium/low) + suggested fixes with file:line references.
Never "proposes" a patch — describes what should change and why.

**Distinct from:** `security-auditor` (security-only), `explorer` (exploration,
not judgement).

### 3. `tester` (Tier 1)

**Purpose:** Write tests, run test suites, analyze coverage, diagnose flaky
tests. Does not implement feature code — just test code.

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`, `TaskCreate/Update`,
`Skill`.

**Write scope:** `tests/**`, `test/**`, `**/__tests__/**`, `*.test.*`, `*.spec.*`,
`*_test.*`, `*_spec.*`, `conftest.py`, `jest.config.*`, `pytest.ini`,
`.coveragerc`. **Shell:** allowed — test runners and coverage tools only in
intent; full shell in practice unless permission rules narrow it.

**Behaviors:** When writing tests: one behavior per test, clear names, edge cases
called out. When running: report pass/fail/flake counts + failing test names.

**Distinct from:** `coder` (which also writes tests but for the feature it
implemented). `tester` handles dedicated test-writing cycles, coverage sweeps,
flake investigation.

### 4. `debugger` (Tier 2)

**Purpose:** Reproduce bugs, isolate causes, produce minimal failing cases.
Usually hands off the fix to `coder`, or applies small fixes itself.

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`, `NotebookEdit`,
`TaskCreate/Update`, `Skill`, `Monitor`.

**Write scope:** Anywhere (but typically scratch files + test cases). **Shell:**
Unrestricted (needs `git bisect`, `strace`, profiler, etc.).

**Behaviors:** Reproduce-first — writes a failing test or a minimal repro script
before attempting a fix. Reports: hypothesis, repro steps, root cause, proposed
fix, verification.

**Distinct from:** `coder` (implementation-forward) and `tester` (test-forward).
`debugger` is investigation-forward; the deliverable is understanding, not
necessarily a landed fix.

### 5. `refactorer` (Tier 2)

**Purpose:** Behavior-preserving code restructuring — extract method, rename,
split file, flatten indirection, move types. Heavily disciplined around
"tests pass before and after."

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`,
`TaskCreate/Update`, `Skill`.

**Write scope:** Anywhere. **Shell:** Test runners only in intent.

**Behaviors:** Runs tests before + after each refactor step. Reports exactly
which refactors were applied + which tests remained green. Aborts and reports if
any test regressed — doesn't try to "fix" the regression (that's `coder`'s or
`debugger`'s job).

**Distinct from:** `coder` (which changes behavior); `reviewer` (which only
suggests refactors).

### 6. `explorer` (Tier 0)

**Purpose:** Deep read-only investigation of the codebase — understand how X
works, where Y is used, why a module looks the way it does. Project-aware
replacement for Claude's built-in `Explore` (which is general-purpose).

**Tools:** `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Skill`,
`TaskCreate/Update`.

**Write scope:** None. **Shell:** None.

**Behaviors:** Returns a structured summary — key files/functions with paths,
call graph sketches, unanswered questions. Never edits. May suggest where new
code should go but doesn't write it.

**Distinct from:** Claude's built-in `Explore` (this one is project-specialized
with our skills loaded — e.g. Karpathy guidelines shape how it describes
"overcomplicated" code).

### 7. `security-auditor` (Tier 0)

**Purpose:** Read-only security scan — secret leaks, injection patterns (SQL,
command, XSS, path traversal), unsafe deserialization, insecure defaults, auth
bypass patterns, dependency CVEs (via web lookup).

**Tools:** `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Skill`, possibly
`Bash` scoped to specific scanners (`semgrep`, `bandit`, `npm audit`,
`trufflehog`) via `permissions.allow` rules.

**Write scope:** None.

**Behaviors:** Report: vulnerabilities by severity, exploitability analysis,
suggested mitigations with references. No patch writing — routes fixes to
`coder`. Extra-careful with false positives in a report.

**Distinct from:** `reviewer` (correctness/style) — this agent has a security
lens and security-specific skills/tool knowledge.

### 8. `doc-writer` (Tier 1)

**Purpose:** Documentation work — README, architecture docs, API references,
in-code comments, release notes, migration guides. Does not implement.

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `WebFetch`, `Skill`,
`TaskCreate/Update`.

**Write scope:** `docs/**`, `doc/**`, `**/README.md`, `**/README*`, `**/*.md`,
`CHANGELOG*`, `LICENSE*`, in-code docstring/comment edits in source files
(scoped via review-and-accept in orchestrator workflow — Claude's `Edit` can
touch code, but `doc-writer`'s system prompt forbids changing non-comment code).
**Shell:** None.

**Behaviors:** Writes from the reader's perspective. Verifies code examples
actually match current code. Reports what was added/updated + links.

**Distinct from:** `coder` (which also writes doc-comments but for code it
implements). `doc-writer` handles cross-cutting documentation — migration
guides, READMEs, high-level architecture docs.

### 9. `infra-engineer` (Tier 1)

**Purpose:** Infrastructure-as-code — Terraform, Kubernetes manifests, Docker,
CI workflows, deployment configs. Does not modify application code.

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`,
`TaskCreate/Update`, `Skill`, `WebFetch`, optionally MCP servers (Cloudflare,
AWS, k8s — project-dependent).

**Write scope:** `infrastructure/**`, `infra/**`, `terraform/**`, `.terraform/**`
(generated only), `k8s/**`, `kubernetes/**`, `helm/**`, `docker/**`,
`Dockerfile*`, `docker-compose*`, `.github/workflows/**`, `.gitlab-ci*`,
`.circleci/**`, `.buildkite/**`. **Shell:** `terraform plan/validate/fmt`,
`kubectl` (read-only verbs: `get`, `describe`, `diff`), `docker build/lint`,
`gh workflow list/view`. Actual `apply`/`deploy` routed through `deployer`.

**Behaviors:** Proposes changes with `plan` output first. Never auto-applies.
Reports: diff summary, drift analysis, risks.

**Distinct from:** `deployer` (which executes changes in remote environments).
`infra-engineer` writes the IaC; `deployer` applies it.

### 10. `deployer` (Tier 1, highest-risk)

**Purpose:** Build, release, deploy. Executes deployments prepared by
`infra-engineer`, cuts release tags, publishes packages, kicks off CI deploys.

**Tools:** `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`,
`TaskCreate/Update`, `WebFetch`, `Skill`, relevant MCP (Cloudflare Workers,
`mcp__github__workflow_dispatch`, etc.).

**Write scope:** `CHANGELOG*`, `VERSION`, version files in manifests
(`package.json`, `pyproject.toml`, `Cargo.toml` — version bumps only),
`.github/release.yml`, release-notes files. **Shell:** release and deploy
commands — `git tag`, `npm publish`, `terraform apply` (in prod workflow),
`wrangler deploy`, `gh release create`, `gh workflow run`. Every high-impact
command goes through an explicit `AskUserQuestion` confirmation in the agent's
system prompt.

**Behaviors:** Dry-run first. Prints the exact commands it will run and waits
for explicit confirmation via the orchestrator. Refuses to proceed if working
tree is dirty, tests have failed, or source branch doesn't match policy.
Reports: version cut, artifacts published, deploy URLs, rollback steps.

**Distinct from:** `infra-engineer` (designs the infra), `coder` (writes the
app code). `deployer` is the last mile — highest risk, most confirmation,
smallest write scope.

## Summary table

| # | Agent | Tier | Write scope | Shell |
|---|---|---|---|---|
| 1 | coder | 2 | anywhere | full |
| 2 | reviewer | 0 | none | none |
| 3 | tester | 1 | `tests/**`, `*.test.*`, test configs | full (test runners) |
| 4 | debugger | 2 | anywhere | full |
| 5 | refactorer | 2 | anywhere | full (test runners) |
| 6 | explorer | 0 | none | none |
| 7 | security-auditor | 0 | none | scanners only (opt-in) |
| 8 | doc-writer | 1 | docs, README, CHANGELOG, in-code comments | none |
| 9 | infra-engineer | 1 | IaC + CI workflow dirs | plan/validate only |
| 10 | deployer | 1 | version files + release notes | deploy commands (confirmed) |

## Routing heuristics (for the orchestrator's system prompt)

1. Read or search only → answer directly, no delegation needed.
2. Need deep investigation before acting → `explorer`.
3. Code change needed → start with specialty check:
   - Tests only → `tester`.
   - Behavior-preserving refactor → `refactorer`.
   - Bug suspected, repro needed → `debugger`.
   - Docs only → `doc-writer`.
   - Infra / CI only → `infra-engineer`.
   - Otherwise → `coder`.
4. Reviewing existing code:
   - Security focus → `security-auditor`.
   - General quality → `reviewer`.
5. Shipping a change:
   - Version bump + release → `deployer`.
6. No existing agent fits → propose a new one, ask the user.

## Open questions / tradeoffs for the three-way merge

1. **Do we need `coder` and `refactorer` as separate agents?** Both are Tier 2
   with very similar tools. Argument for separate: different system prompts
   produce different behavior (refactorer is disciplined about test invariance).
   Argument against: orchestrator can just brief `coder` with "refactor only,
   tests must pass" — saves an agent.
2. **Is `debugger` worth a dedicated slot?** Same Tier-2 tools as coder. Could
   be a coder-with-system-prompt-variant. Pro: repro-first workflow is unusual
   enough to deserve its own persona. Con: another config to maintain.
3. **`security-auditor` vs `reviewer`.** Could merge into one `reviewer` with
   a "mode" parameter in the prompt. I kept them split because security review
   has different skills/tool recs (semgrep, bandit, trufflehog) that differ
   from general style/correctness review.
4. **Scoped-write enforcement in Claude Code.** Claude's `tools:` frontmatter
   whitelists tools, but does not (natively) scope `Edit`/`Write` to path
   patterns. Scoping is done via `permissions.deny` rules. Worth testing
   whether this works per-subagent or only at the main-thread level.
5. **MCP server scoping per agent.** MCP tools appear as `mcp__<server>__<tool>`.
   In principle, frontmatter `tools:` can whitelist individual MCP tool names.
   Untested at scale — need a dry-run before committing.
6. **Agent count.** 10 is already a lot to maintain. Kimi and Kiro's proposals
   should be judged partly on "did they cover the same specialties with fewer
   agents?" A 6-agent consolidation might be better than 10.

## Comparison hooks (for when Kimi/Kiro docs land)

Things I explicitly want to compare against:
- Whether Kimi/Kiro propose agents I missed (e.g. `data-analyst`, `api-designer`,
  `performance-engineer`, `migrator`, `dependency-updater`).
- Whether any CLI natively supports path-scoped write in a way Claude doesn't
  — if so, Tier-1 enforcement may be easier there and we should standardize
  on that CLI's pattern.
- Whether agent inheritance (Kimi's advantage) changes the calculus — with
  inheritance, specializing an agent is a 3-line extension, so the cost of
  having 10 vs 6 drops.

## Recommended next step after merge

One consolidated list (probably 6–8 agents) shipped as three handoffs —
Kimi/Kiro/Claude each build their native configs for the same agent set. Land
minimal versions first (`orchestrator` + `coder` + `reviewer` + one more),
dry-run, then expand.
