# Plan template completeness — remaining project scaffolding
Status: DONE
Completed: 2026-04-17 22:25 — claude-code; decision phase closed 2026-04-17 22:55
Output: .ai/research/template-completeness-claude.md (feedback), docs/architecture/0001-root-file-exceptions.md (ADR — Option A strict, full exception list), CLAUDE.md + .claude/agents/orchestrator.md (trimmed to ADR pointers), .ai/handoffs/to-{kimi,kiro}/open/{017,006}-option-a-root-file-policy.md (handoffs to the other two CLIs).
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 22:02

## Goal
We're turning this repo into a reusable multi-CLI project template. Review the
remaining items below and give your input on what to implement and how. Write to
`.ai/research/template-completeness-claude.md`.

## Items to implement (Kiro's proposed plan)

1. **`.gitignore`** — comprehensive ignore rules (secrets, build artifacts, node_modules, __pycache__, .env, etc.)
2. **`.editorconfig`** — universal formatting baseline (indent, charset, line endings)
3. **Doc templates** — ADR template in docs/architecture/, spec template in docs/specs/, standard template in docs/standards/
4. **`config/.env.example`** — template showing expected env vars
5. **CI pipeline** — basic GitHub Actions in infra/ci/ (lint + test on push)
6. **License** — MIT (or user's choice) — note: root file policy says no files at root except AGENTS.md/README.md/CLAUDE.md. Where should LICENSE go?
7. **Changelog** — CHANGELOG.md — same root policy question
8. **Contributing guide** — docs/guides/contributing.md
9. **Testing framework config** — jest.config or pytest.ini in tools/ or config/
10. **MCP servers** — which MCP servers should each CLI configure? (git, github, browser/playwright, filesystem, etc.)
11. **System prompts as external files** — should agent prompts be inline or file:// refs?
12. **`.gitattributes`** — line ending normalization, binary file handling
13. **Pre-commit hooks** — git pre-commit for linting/formatting (separate from CLI hooks)

## What I need from you
1. Which items do you agree with / disagree with?
2. For item 6+7 (LICENSE, CHANGELOG): should we make an exception to the root file policy? These are universally expected at root.
3. For item 10 (MCP): which MCP servers does Claude Code benefit from?
4. For item 11: does Claude prefer inline prompts or file refs?
5. Any items I missed?
6. Anything Claude-specific that should be in the template?

Keep it concise — bullets.

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Reviewed template completeness plan per handoff 013 from kiro-cli.
    - Files: .ai/research/template-completeness-claude.md (new)
    - Decisions: <key feedback>