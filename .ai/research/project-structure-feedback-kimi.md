# Kimi CLI Feedback — Project Directory Structure Proposal

**Reviewer:** kimi-cli  
**Date:** 2026-04-17

---

## What I agree with

- **One boundary = one mental model.** `project/` = product code, outside = tooling/config. This makes agent reasoning simpler.
- **Simpler write scopes.** With everything under `project/`, agent path restrictions become prefix-based instead of scattered glob patterns. E.g.:
  - `coder-executor` → `project/src/**`, `project/config/**`, `project/assets/**`
  - `tester` → `project/tests/**`, `project/tools/**` (test configs)
  - `infra-engineer` → `project/infra/**`, `project/scripts/**`
  - `data-migrator` → `project/migrations/**`
  - `doc-writer` → `project/docs/**` + root `*.md` files
- **Infra separate from app code.** Keeping IaC in `project/infra/` makes sense — it's versioned with the app but not mixed into `src/`.
- **Tests centralized.** `project/tests/unit/`, `project/tests/integration/`, `project/tests/e2e/` is cleaner than `**/*.test.*` scattered everywhere.

---

## What I'd change

### 1. Drop `vendor/` — use lockfiles + package managers
In 2025, `vendor/` is an anti-pattern for most stacks. Use `package-lock.json`, `Cargo.lock`, `poetry.lock`, etc. instead. If you truly need vendoring (e.g., Go modules in air-gapped environments), name it `project/third_party/` — more explicit.

### 2. `scripts/` vs `tools/` overlap
Both contain automation. Suggest merging into one:
- Option A: `project/scripts/` for all automation (build, test, deploy scripts)
- Option B: `project/tools/` for dev tooling, `project/scripts/` for CI/build scripts

I prefer **Option A** — one directory for "things humans run to automate tasks."

### 3. Root-level docs should stay at root
`AGENTS.md`, `CLAUDE.md`, `README.md` at root are correct — they're project entry points. But `project/docs/` should contain:
- `project/docs/architecture/` — system design docs
- `project/docs/api/` — API reference
- `project/docs/guides/` — developer onboarding

Not root-level README content. The root README is the front door; `project/docs/` is the library.

### 4. `assets/` is frontend-centric
If this is a backend/API project, `assets/` is confusing. Suggest making it optional or renaming to `project/static/` (generic) or `project/web/` (if web-specific).

### 5. `config/` at root vs `project/config/`
Some projects put config at root (`.env`, `.env.example`, `tsconfig.json`, `pyproject.toml`). These are often tooling configs, not app configs. Suggest:
- Root: tooling configs (`.eslintrc`, `tsconfig.json`, `pyproject.toml`, `package.json`)
- `project/config/`: runtime app configs (feature flags, DB config, service endpoints)

This distinction matters for agents: `infra-engineer` touches root tooling configs; `coder-executor` touches `project/config/` runtime configs.

---

## Gaps & risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Backward compatibility** | Medium | Existing projects won't have `project/`. Migration is manual. The framework should support both layouts (detect `project/` presence). |
| **Monorepo scaling** | Medium | If the project grows into a monorepo, `project/` becomes `packages/` or `apps/`. Consider whether this structure is for single-repo or monorepo. |
| **Agent detection logic** | Low | Agents need to know whether `project/` exists or not. Add a `project/` detection check to the orchestrator's startup. |
| **Git tracking of empty dirs** | Low | Some dirs (`assets/`, `vendor/`) may be empty initially. Use `.gitkeep` or don't create them until needed. |

---

## Impact on Kimi agent configs

With `project/` in place, agent path scopes simplify:

| Agent | Current scope (messy) | Proposed scope (clean) |
|---|---|---|
| `coder-executor` | Anywhere except framework dirs | `project/src/**`, `project/config/**`, `project/assets/**` |
| `tester` | Test files scattered | `project/tests/**` |
| `refactorer` | Anywhere except framework dirs | `project/src/**`, `project/config/**` |
| `infra-engineer` | `Dockerfile*`, `.github/**`, `terraform/**` | `project/infra/**`, `project/scripts/**`, `.github/**` (root) |
| `data-migrator` | `migrations/**`, `seeds/**` | `project/migrations/**` |
| `doc-writer` | `*.md`, `docs/**` | `project/docs/**`, root `*.md` |

**Note:** Kimi has no native path-level restriction. The cleaner `project/` prefix makes prompt-based enforcement more reliable ("only write under `project/`" is easier to follow than "don't write to `.ai/`, `.kiro/`, `.kimi/`, `.claude/`").

---

## Alternative concept: the "app" layout

If `project/` feels too generic, consider:

```
rwn-multi-cli-skills/
├── .ai/ .kiro/ .kimi/ .claude/
├── app/          ← the actual application
│   ├── src/
│   ├── tests/
│   ├── config/
│   └── assets/
├── infra/        ← IaC (at root, not under app/)
├── docs/         ← project docs (at root)
└── scripts/      ← automation scripts (at root)
```

**Pros:** `app/` is more semantic than `project/`. Infra/docs/scripts at root are easily discoverable.
**Cons:** More top-level noise. Less strict boundary.

I prefer the original `project/` proposal over this alternative — the boundary is clearer.

---

## Bottom line

**Approve the `project/` concept with modifications:**
1. Drop `vendor/`
2. Merge `scripts/` + `tools/` into `scripts/`
3. Rename `assets/` → `static/` (or make it frontend-only)
4. Clarify root config vs `project/config/` distinction
5. Add `project/tests/e2e/` for the `e2e-tester` agent

This structure would make agent path scopes significantly cleaner and reduce the "where do I put this?" ambiguity.
