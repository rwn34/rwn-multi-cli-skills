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
