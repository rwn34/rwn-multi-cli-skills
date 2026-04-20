# Project structure + root file policy
Status: DONE
Completed: 2026-04-17 21:35 — claude-code
Output: .claude/agents/orchestrator.md (new "Root file policy" section with exception-handling clause), .claude/agents/infra-engineer.md (write scope rewritten around infra/** with tooling-required root exceptions called out explicitly). docs/ resource already wired in handoff 009 — no additional work there.
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 21:23

## Goal
The project directory structure has been created. Note the root file policy and
add `docs/` resource to relevant Claude agents.

## Root file policy
Only these files at root:
- `AGENTS.md`
- `README.md`
- `CLAUDE.md` (Claude-specific, required at root)

No `package.json`, `tsconfig.json`, `Dockerfile`, `.env`, etc. at root. Those go
in `config/`, `infra/docker/`, `tools/`, etc.

## Directory structure created
```
src/app/, src/lib/, src/types/
tests/unit/, tests/integration/, tests/e2e/
docs/architecture/, docs/specs/, docs/standards/, docs/guides/, docs/api/
infra/terraform/, infra/k8s/, infra/ci/, infra/docker/
migrations/versions/, migrations/seeds/
scripts/
tools/playwright/, tools/linters/
config/
assets/images/, assets/fonts/, assets/templates/
```

## Steps
1. If not already done from handoff 009: add `docs/**/*.md` as a resource/context
   to orchestrator, coder, reviewer, refactorer, doc-writer agents.
2. Note the root file policy in Claude's orchestrator system prompt — the
   orchestrator should enforce "no files at root" when delegating to subagents.
3. Update agent write scopes if needed to reference the new directory paths
   (e.g., infra-engineer → `infra/**` instead of scattered `Dockerfile*` patterns).

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Acknowledged project structure + root file policy per handoff 010 from kiro-cli.
    - Files: <any agents updated>
    - Decisions: <any scope changes>