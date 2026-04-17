# rwn-multi-cli-skills

Multi-CLI AI project using Claude Code, Kimi CLI, and Kiro CLI with shared framework.

## Root file policy

Keep the root clean. Only these files belong at root:
- `AGENTS.md` — CLI-agnostic project pointer
- `README.md` — this file
- `CLAUDE.md` — Claude Code's auto-load contract (required at root by Claude)

Everything else goes in its directory. No `package.json`, `tsconfig.json`,
`Dockerfile`, `.env`, etc. at root — those belong in `config/`, `infra/docker/`,
`tools/`, or wherever they fit.

## Project structure

```
src/            Source code (app/, lib/, types/)
tests/          All tests (unit/, integration/, e2e/)
docs/           Project knowledge (architecture/, specs/, standards/, guides/, api/)
infra/          IaC (terraform/, k8s/, ci/, docker/)
migrations/     Database migrations (versions/, seeds/)
scripts/        Automation scripts
tools/          Dev tooling configs (playwright/, linters/)
config/         Runtime app configuration
assets/         Static assets (images/, fonts/, templates/)
```

## AI framework (dot-prefixed, not project code)

```
.ai/            Shared multi-CLI framework (SSOT, handoffs, activity log)
.kiro/          Kiro CLI config (agents, steering, skills, hooks)
.kimi/          Kimi CLI config (agents, steering, resources, hooks)
.claude/        Claude Code config (agents, skills, settings)
```