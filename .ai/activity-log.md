## 2026-04-17 09:30 — kimi-cli
- Action: Aligned with Option A root-file policy + ADR per handoff 017 from claude-code.
- Files: .kimi/steering/00-ai-contract.md (edit), .kimi/hooks/README.md (new), .kimi/agents/README.md (new)
- Decisions: Added ADR reference to 00-ai-contract.md (points to docs/architecture/0001-root-file-exceptions.md, no re-duplication). Wrote hooks/README.md documenting all 9 hooks, stdin JSON parsing, exit codes, manual testing. Wrote agents/README.md covering extend: inheritance, adding new agents, tool restriction, system prompts as file refs, nesting restriction, restart requirement. Did not update .ai/instructions/orchestrator-pattern/principles.md — it doesn't mention root file policy; the ADR reference in 00-ai-contract.md closes the loop for Kimi's steering.

## 2026-04-17 09:20 — kimi-cli
- Action: Reviewed template completeness plan per handoff 016 from kiro-cli.
- Files: .ai/research/template-completeness-kimi.md (new)
- Decisions: LICENSE and CHANGELOG.md should be exceptions to root file policy (universal convention, tooling expects them at root). MCP: enable git+github as optional, skip filesystem/playwright (Kimi native tools are sufficient). System prompts: strongly prefer file refs via system_prompt_path (inline bloats YAML). Missing items: .kimi/agents/README.md, hooks/README.md, config/.kimi-config-template.toml, root policy amendment. Kimi-specific additions: agent config template, hook script template, max_steps guidance, cross-CLI handoff protocol doc.

## 2026-04-17 09:09 — kimi-cli
- Action: Implemented 7 hooks per handoff 015 from kiro-cli.
- Files: ~/.kimi/config.toml (edit), .kimi/hooks/{root-guard,framework-guard,sensitive-guard,destructive-guard,git-status,handoffs-remind,git-dirty-remind,activity-log-inject,activity-log-remind}.sh (new/fix)
- Decisions: Stored all hooks as bash scripts in .kimi/hooks/ (not inline in config.toml) to avoid TOML quote-escaping hell on Windows. Fixed existing activity-log hook paths (.ai/activity/log.md → .ai/activity-log.md). Used PreToolUse for guards (blocks before write — safer than Kiro post-hoc). Used SessionStart for git-status + handoffs reminder (run in parallel). Added git-dirty-remind as second Stop hook alongside existing activity-log-remind. Python JSON parsing with fail-open fallback.

## 2026-04-17 09:02 — kimi-cli
- Action: Wrote hooks recommendation per handoff 014 from kiro-cli.
- Files: .ai/research/hooks-recommendation-kimi.md (new)
- Decisions: Recommended PreToolUse root-guard (blocks before write — better than Kiro post-hoc), SessionStart git-status, Stop git-dirty-reminder. Added Kimi-unique hooks: SubagentStart/Stop audit trail, PreCompact warning, PostToolUseFailure pattern detection. Reminder-only for git (never auto-push). Documented 5 impossible/impractical hooks.

## 2026-04-17 08:55 — kimi-cli
- Action: Acknowledged project structure + root file policy per handoff 013 from kiro-cli.
- Files: .kimi/agents/system/{orchestrator,infra-engineer,data-migrator,release-engineer,tester,e2e-tester}.md (edit)
- Decisions: Added root file policy to orchestrator (only AGENTS.md/README.md/CLAUDE.md at root). Updated infra-engineer to use infra/** instead of broad root patterns (Dockerfile*, *.yml). Updated release-engineer to config/ paths. Updated data-migrator, tester, e2e-tester to reference new directory paths.

## 2026-04-17 08:46 — kimi-cli
- Action: Added docs/ resource to relevant agents per handoff 012 from kiro-cli.
- Files: .kimi/agents/system/{orchestrator,coder-executor,reviewer,refactorer,doc-writer}.md (edit)
- Decisions: Used system prompt "Docs resource" section as Kimi-native mechanism (no per-agent auto-load like Kiro skill:// URIs). Tailored doc categories per agent: orchestrator gets architecture+specs+standards+guides+api; coder-executor gets specs+standards+architecture+guides; reviewer gets standards+specs+architecture; refactorer gets architecture+standards+specs; doc-writer gets all docs broadly.
