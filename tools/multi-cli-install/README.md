# @rwn34/multi-cli-install

Single-command installer for the multi-CLI AI coordination framework.

Inspects your project, reorganizes files into the framework's canonical layout where safe, falls back to adapt mode for framework-pinned dirs, and generates `.ai/project-context.md` so all AI agents understand your project.

## Usage

Build locally first (not yet published to npm):

```bash
cd tools/multi-cli-install
npm install && npm run build
```

Five invocation modes:

```bash
# 1. Inspect only — read-only, dump detected profile as JSON
node bin/multi-cli-install.ts /path/to/project --inspect-only

# 2. Dry-run — read-only, show full plan (framework copy + reorganize moves)
node bin/multi-cli-install.ts /path/to/project --dry-run

# 3. Greenfield — create a new project with the framework
node bin/multi-cli-install.ts my-new-project --new

# 4. Existing-project install — copy framework + reorganize layout
node bin/multi-cli-install.ts /path/to/existing/project

# 5. Refresh context — regenerate .ai/project-context.md only
node bin/multi-cli-install.ts /path/to/project --refresh-context
```

Design context: [`.ai/research/multi-cli-install-v2-plan.md`](../../.ai/research/multi-cli-install-v2-plan.md).

## What it does

1. **Inspects** — detects stack, framework, dirs, commands, conventions, secret risks
2. **Classifies** — each root dir as movable / movable-with-rules / framework-pinned / unknown
3. **Plans** — generates migration operations (file moves + config updates)
4. **Executes** — moves files, updates configs (or dry-run)
5. **Patches** — generates `.ai/project-context.md` for AI agents

### CodeGraph

Every install ships `.codegraph/config.json` (the semantic code-graph index config)
and create-or-merges a `.mcp.json` with a `codegraph` MCP server entry. The
`.codegraph/config.json` is git-tracked; the local `.db`/cache are gitignored.

The entry only connects if the `codegraph` binary is installed globally
(`npx @colbymchenry/codegraph`). Without it, new projects will log MCP connection
errors on session start — install the binary, or remove the `codegraph` entry from
`.mcp.json`.

## Supported stacks

- TypeScript/JavaScript (npm, pnpm, yarn)
- Rust (Cargo, workspaces)
- Go (modules, workspaces)
- Python (pip, Poetry, pyproject.toml)
- Ruby (Bundler)
- PHP (Composer)

## Supported frameworks

- Next.js (App Router, Pages Router)
- Vite
- Django (framework-pinned)
- Rails (framework-pinned)
- Cargo workspaces
- Go workspaces
- Turborepo, pnpm workspaces

## Development

```bash
cd tools/multi-cli-install
npm install
npm run build
npm test
npm run lint
```

## Status

Pre-v1.0.0. Validated against test fixtures. Real-project validation (P6) pending.
