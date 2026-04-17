## 2026-04-17 08:46 — kimi-cli
- Action: Added docs/ resource to relevant agents per handoff 012 from kiro-cli.
- Files: .kimi/agents/system/{orchestrator,coder-executor,reviewer,refactorer,doc-writer}.md (edit)
- Decisions: Used system prompt "Docs resource" section as Kimi-native mechanism (no per-agent auto-load like Kiro skill:// URIs). Tailored doc categories per agent: orchestrator gets architecture+specs+standards+guides+api; coder-executor gets specs+standards+architecture+guides; reviewer gets standards+specs+architecture; refactorer gets architecture+standards+specs; doc-writer gets all docs broadly.
