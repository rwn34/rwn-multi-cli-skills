# Feedback on `project/` Directory Structure — Claude Code

Response to `.ai/handoffs/to-claude/open/008-review-project-structure.md` from kiro-cli.
Tight bullets; user decides.

## What I agree with

- **Framework dirs stay outside.** `.ai/`, `.claude/`, `.kimi/`, `.kiro/` at root is the
  right call — they're tooling, not product. No argument.
- **The intent** (clear product boundary + simpler agent scopes) is valid. It's
  the mechanism I'm uneasy about.
- **`infra/` separate from app code** is genuinely useful regardless of whether
  the wrapper is `project/` or root. Keep that split.

## What I'd change — the main pushback

**Don't wrap everything in `project/`. Keep standard layout at root.**

Reasoning:

1. **Tooling expects root-level canonical paths.** `package.json`, `pyproject.toml`,
   `Cargo.toml`, `go.mod`, `Dockerfile`, `.gitignore`, `.github/workflows/`,
   `README.md`, `LICENSE`, `CHANGELOG*` — every build tool, test runner, linter,
   IDE, and CI platform expects these at repo root. Moving them into `project/`
   forces every tool to be told "cwd = project/" — either via wrapper scripts or
   per-tool configuration. Constant low-grade friction that buys little.
2. **Which files move vs stay is genuinely ambiguous.** `CHANGELOG.md` is
   product-ish (goes in `project/`?) but release tooling expects it at root.
   `package.json` is product (`project/package.json`?) but `npm` expects root.
   Either the "project/" rule has many exceptions — defeating the "one boundary"
   benefit — or tooling breaks. There's no clean answer.
3. **The scope-simplification benefit is real but achievable another way.** See
   the alternative below — positive-scope subagents at root directly.
4. **Monorepo smell.** This layout looks like a monorepo pattern (`packages/`,
   `apps/` style), but for a single-product repo it's an unusual wrapper. Devs
   coming in will wonder what `project/` means and whether there's a
   `project/`-sibling they're missing.

## Risks

- **Migration cost** if this is later applied to a repo that already has files at
  root — mechanical but annoying, breaks git blame history on every file.
- **Build-tool lock-in**: once `project/package.json` is chosen, wrapping every
  `npm` invocation with `cd project && ...` permeates scripts and CI. Reversing
  is harder than avoiding.
- **Path typos scale with depth**. `project/src/components/Foo.tsx` vs `src/components/Foo.tsx` — one more segment means more typos, longer commit diffs.
- **Partial adoption**. If even one tool refuses to be moved (e.g. Next.js hardcodes
  `app/` or `pages/` at root), you get a mix of "most things under project/,
  except X and Y" which is worse than fully standard layout.

## Impact on Claude's agent configs

If `project/` lands, every subagent's write-scope prose needs updating (system prompts only — tool list stays the same). Roughly:

| Subagent | Old scope (at root) | New scope (under `project/`) |
|---|---|---|
| `coder` | anywhere except framework dirs | `project/**` except `project/tests/**` |
| `tester` | `tests/**`, `*.test.*`, test configs | `project/tests/**`, `project/**/*.test.*` |
| `refactorer` | anywhere except framework dirs | `project/**` |
| `debugger` | anywhere + `.ai/reports/` | `project/**` + `.ai/reports/` |
| `doc-writer` | `*.md`, `docs/**`, `CHANGELOG*`, `.ai/reports/` | `project/docs/**`, root `CHANGELOG*`, `.ai/reports/`, in-code comments in `project/src/**` |
| `infra-engineer` | IaC dirs at root | `project/infra/**`, `project/tools/**` |
| `release-engineer` | version files at root | `project/package.json` etc. + root `CHANGELOG*` — **mixed, confusing** |
| `data-migrator` | `migrations/**`, etc. | `project/migrations/**` |
| `ui-engineer` | anywhere except framework | `project/src/**` (frontend-specific) |
| `e2e-tester` | E2E dirs | `project/tests/e2e/**`, playwright/cypress configs |

Two implications:
1. `release-engineer` sits awkwardly — version files under `project/`, but
   `CHANGELOG.md` ambiguous (product or meta?). Needs an explicit decision.
2. The "except framework dirs" negative filter goes away, replaced by
   "only `project/**`". **This is the simplification the proposal promised** — it
   is real, but it comes with the above costs.

Low absolute effort for me (~30 minutes of system-prompt edits across 10 agents),
so cost is not a blocker. I'm flagging this to balance the equation, not to veto.

## Alternative concept (my preference)

**Keep root layout. Positive-scope subagents by listing product directories explicitly.**

```
rwn-multi-cli-skills/
├── .ai/ .claude/ .kimi/ .kiro/ .git/    ← framework + tooling (hidden dirs)
├── src/                                  ← app code
├── tests/                                ← tests
├── docs/                                 ← docs
├── infra/                                ← IaC
├── migrations/                           ← DB migrations
├── scripts/                              ← automation
├── tools/                                ← dev tooling (playwright, docker configs)
├── assets/                               ← static
├── config/                               ← app config
├── vendor/                               ← vendored deps
├── package.json / pyproject.toml / etc.  ← at root (tooling expects it)
├── README.md, LICENSE, CHANGELOG.md, AGENTS.md, CLAUDE.md
```

Subagent write scopes become **positive allowlists** without the `project/` prefix:
- `coder`: `src/**`, `config/**`, `vendor/**` (and scripts/ by explicit permission)
- `tester`: `tests/**`, test configs, `.coveragerc`, etc.
- `doc-writer`: `docs/**`, `*.md` at root, in-code comments
- `infra-engineer`: `infra/**`, `scripts/**`, `tools/**`, `.github/**`, `Dockerfile*`
- `data-migrator`: `migrations/**`, `schema.*`
- `ui-engineer`: `src/**` (component layers — frontend-specific)
- `release-engineer`: `CHANGELOG.md`, `package.json` (version field), `VERSION`
- etc.

Benefits:
- Positive filter still simplifies scopes (was the proposal's real goal)
- Root-level tooling just works
- No `project/` wrapper, no wrapper-unwrapper mental tax
- Framework dirs (`. `-prefixed) stay clearly separated from product dirs (no `.` prefix)
- Hidden-dir convention is universally understood

Costs:
- Root has more top-level entries (but they're all single-word, semantically clear)
- Requires discipline to keep new stuff in the right bucket (but so does `project/`)

## TL;DR

**Keep files at root. Use positive allowlists per subagent for scope clarity.**
You get the agent-scope simplification the proposal wants, without the tooling
friction the `project/` wrapper introduces. If you feel strongly about visual
separation, mask framework dirs in your editor or rely on the `.`-prefix
convention (already 100% separate from product dirs visually).

If the decision is to go with `project/` anyway, the Claude-side work is ~30 min
of system-prompt edits across 10 agents, plus documenting the CHANGELOG /
package-manifest exceptions. Not a blocker — just a tax with a recurring cost.
