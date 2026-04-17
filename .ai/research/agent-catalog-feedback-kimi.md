# Kimi CLI Feedback on Proposed 10-Agent Catalog

**Reviewer:** kimi-cli  
**Date:** 2026-04-17

---

## What I agree with

- **Diagnosers write reports to `.ai/reports/`** — Good compromise. Gives cross-CLI visibility to findings without letting diagnosers touch source code.
- **Starting with a smaller catalog** — The "core 6 + 4 later" approach is sensible. Less config bloat, easier to validate delegation flows.
- **`infra-engineer` as an executor** — CI/CD and deployment are specialized enough to warrant their own agent.
- **`debugger` applying small fixes** — Acceptable, as long as "small" is well-defined in the prompt (e.g., one-liners, typo fixes, missing imports). For larger fixes, delegate to `coder`.

---

## What I'd change

### 1. `debugger` should stay read-only for non-trivial fixes
**Reasoning:** The power of the diagnoser/executor split is that the debugger can deeply investigate without the pressure to "just fix it." If `debugger` is allowed to write anywhere, it will blur the line with `coder`. Suggest:
- `debugger` can write to `.ai/reports/` only
- One-line/trivial fixes require explicit orchestrator approval or a second `coder` delegation

### 2. `refactorer` should not be merged into `coder`
**Reasoning:** Refactoring is a different cognitive mode than feature implementation. `coder` is optimized for "solve the problem." `refactorer` is optimized for "restructure without changing behavior." Merging them means:
- The system prompt becomes bloated with two competing sets of rules
- Cross-file renames and import updates are easy to get wrong without dedicated focus

**Kimi-specific:** Since Kimi uses `agent.yaml` with `extend:` inheritance, maintaining a separate `refactorer.yaml` is cheap. No duplication cost.

### 3. `release-engineer` should not be merged into `infra-engineer`
**Reasoning:** Releases are frequent, ritualized tasks (bump version, update changelog, tag, publish). Infra changes are structural and infrequent. Merging them means the agent must context-switch between "update Dockerfile" and "cut a release." The failure modes are different too — a bad release can corrupt a published package; a bad infra change breaks CI.

### 4. `data-migrator` should not be merged into `coder`
**Reasoning:** Database migrations are high-risk and require reversibility (up/down). A generic `coder` prompt does not emphasize "this must be reversible and tested against a copy schema." A dedicated `data-migrator` prompt can encode that rule.

### 5. Three browser agents (`ui-ux-designer`, `ui-ux-tester`, `workflow-tester`) feels like too much for a core catalog
**Reasoning:** Unless this project is heavily frontend-focused, three UI agents is over-specialized. Suggest consolidating into **one `ui-engineer`** (design + component implementation) and keeping `tester` for general testing. If browser-specific testing is needed, add a second UI agent later.

### 6. Missing `dependency-manager`
**Reasoning:** The proposed catalog omits `dependency-manager`. Dependency updates are common, tedious, and error-prone. Bundling them into `infra-engineer` feels wrong — updating `npm` packages is not "infrastructure." Recommend adding `dependency-manager` back.

---

## Gaps & risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Path-level write restrictions are only prompt-enforced for Kimi** | Medium | Use strong system prompt language + steering docs. Add a `PostToolUse` hook to catch unexpected writes to non-allowed paths (Kimi hooks support this). |
| **Diagnosers (`reviewer`, `security-auditor`) need report-writing discipline** | Medium | Prompt must enforce a structured report template (severity, file refs, suggested fix). Otherwise reports become noise. |
| **`coder` becomes a catch-all if other agents are too merged** | High | If refactorer, data-migrator, and release-engineer are all inside `coder`, the orchestrator will over-delegate to `coder` because the other agents don't exist. This defeats the purpose of specialization. |
| **Browser tools (`web_fetch`) are undefined in Kimi** | Low-Medium | Kimi has `SearchWeb` and `FetchURL`, but no "browser screenshot" or "click" tool. If UI agents need browser automation, we'd need an MCP server or plugin. Clarify whether "browser tools" means `FetchURL` or actual browser automation. |

---

## Kimi-specific implementation concerns

1. **No native path restriction**
   - Kimi's `allowed_tools` / `exclude_tools` work at the **tool class** level, not the **file path** level.
   - If `doc-writer` is supposed to only write `*.md` and `docs/**`, Kimi cannot enforce that natively. It must be prompt + hook based.
   - Suggest adding a `PostToolUse` hook for `WriteFile` and `StrReplaceFile` that rejects writes outside the agent's allowed paths.

2. **No dynamic agent creation**
   - Every agent in the catalog needs a static `agent.yaml` file and a session restart to register.
   - If the final catalog grows beyond 10, startup time and context size may suffer. Keep the core lean.

3. **`Shell` is all-or-nothing**
   - For `security-auditor`, the prompt says "scanners only" but Kimi cannot restrict `Shell` commands. A hook or strong prompt is the only guardrail.
   - Same for `debugger` — if it has `Shell`, it can run `rm -rf` just as easily as `grep`. Hooks or prompt discipline required.

4. **Agent inheritance makes maintenance easy**
   - Kimi supports `extend: default` and `extend: ./base.yaml`. We can define a `base-executor.yaml` with common tools, then each specialized agent inherits and overrides.
   - This reduces duplication and makes adding new agents later trivial.

---

## My recommended revised catalog

| # | Agent | Class | Notes |
|---|---|---|---|
| 0 | `orchestrator` | Default | Read + delegate + framework writes only |
| 1 | `coder` | Executor | Feature implementation, bug fixes |
| 2 | `refactorer` | Executor | Structural changes, renames, extraction |
| 3 | `tester` | Executor | Tests, coverage, flaky test diagnosis |
| 4 | `debugger` | Diagnoser | Read-only investigation, reports to `.ai/reports/` |
| 5 | `docs-writer` | Executor | Documentation, READMEs, changelogs |
| 6 | `security-auditor` | Diagnoser | Scans, audits, reports to `.ai/reports/` |
| 7 | `performance-analyst` | Diagnoser | Profiles, benchmarks, reports to `.ai/reports/` |
| 8 | `infra-engineer` | Executor | CI/CD, Docker, K8s, deployment |
| 9 | `dependency-manager` | Executor | Package updates, lockfiles |
| 10 | `data-migrator` | Executor | DB migrations, schema changes |
| 11 | `release-engineer` | Executor | Version bumps, tags, release notes |
| 12 | `ui-engineer` | Executor | UI/UX component work (merge designer + testers) |

**That's 12 + orchestrator.** If we must stick to 10, I would drop `performance-analyst` and `release-engineer` to the "nice-to-have" tier, keeping:
`coder`, `refactorer`, `tester`, `debugger`, `docs-writer`, `security-auditor`, `infra-engineer`, `dependency-manager`, `data-migrator`, `ui-engineer`.

---

## Bottom line

The proposed final catalog is a good start, but **over-merges agents** in ways that undermine the orchestrator pattern's goal: specialization. Kimi's `extend:` inheritance makes separate agents cheap to maintain. I'd rather have 12 well-defined agents than 10 bloated ones.
