# `.kiro/agents/` — Kiro agent configurations

JSON files defining agent behavior, tools, resources, and hooks. Each file becomes
an agent selectable via `--agent <name>` or `chat.defaultAgent` setting.

## Agents

| Agent | Role | Tools | Write scope |
|---|---|---|---|
| `orchestrator` | Default. Read + delegate + framework writes. | read, write (.ai/.kiro/.kimi/.claude/ only), grep, glob, code, introspect, knowledge, web, todo, subagent | Framework dirs only |
| `coder` | General implementation | read, write, bash, grep, glob, code | Anywhere except framework dirs |
| `reviewer` | Read-only code review | read, grep, glob, code, introspect, write (.ai/reports/) | `.ai/reports/` only |
| `tester` | Tests + coverage | read, write, bash, grep, glob, code | Test files + `.ai/reports/` |
| `debugger` | Bug diagnosis + small fixes | read, write, bash, grep, glob, code, web | Anywhere + `.ai/reports/` |
| `refactorer` | Behavior-preserving restructuring | read, write, bash, grep, glob, code | Anywhere except framework dirs |
| `doc-writer` | Documentation | read, write, grep, glob | `*.md`, `docs/`, `CHANGELOG*`, `.ai/reports/` |
| `security-auditor` | Security scans | read, grep, glob, bash, web, write (.ai/reports/) | `.ai/reports/` only |
| `ui-engineer` | Frontend/UI | read, write, bash, grep, glob, code, web | Anywhere except framework dirs |
| `e2e-tester` | Browser E2E testing | read, write, bash, grep, glob, web | Test files + `.ai/reports/` |
| `infra-engineer` | IaC, CI/CD, Docker, git ops | read, write, bash, grep, glob, web | IaC/CI dirs only |
| `release-engineer` | Version, tag, publish | read, write, bash, grep, glob, web | Version files + `CHANGELOG*` |
| `data-migrator` | DB migrations | read, write, bash, grep, glob | `migrations/`, `seeds/`, `schema.*` |

## How agents work

- Local agents (`.kiro/agents/`) override global (`~/.kiro/agents/`) with same name
- `tools` array is a hard whitelist — unlisted tools are invisible to the LLM
- `toolsSettings.fs_write.allowedPaths`/`deniedPaths` enforce path restrictions
- `resources` array loads files/skills into agent context
- `hooks` wire lifecycle scripts from `.kiro/hooks/`
- Default agent set via `kiro-cli settings chat.defaultAgent orchestrator`

## Spec

Full agent catalog: `.ai/instructions/agent-catalog/principles.md`
Orchestrator pattern: `.ai/instructions/orchestrator-pattern/principles.md`