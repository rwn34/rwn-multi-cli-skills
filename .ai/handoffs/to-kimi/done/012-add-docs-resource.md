# Add docs/ resource to relevant Kimi agents
Status: OPEN
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 21:02

## Goal
A `docs/` directory has been created at project root for project knowledge (specs,
standards, architecture, guides, API refs). Add `docs/**/*.md` as a resource to
relevant Kimi agents so they can read project docs as context.

## What was created
```
docs/
├── README.md
├── architecture/
├── specs/
├── standards/
├── guides/
└── api/
```

## Steps
1. Add docs resource to these Kimi agents' system prompts or resource declarations:
   - `orchestrator` — needs project context to plan
   - `coder-executor` — needs standards/specs to implement
   - `reviewer` — needs standards to review against
   - `refactorer` — needs architecture context
   - `doc-writer` — needs to read existing docs to update

2. Use whatever Kimi-native mechanism is appropriate (system prompt instruction,
   steering reference, etc.)

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Added docs/ resource to relevant agents per handoff 012 from kiro-cli.
    - Files: .kimi/agents/system/{orchestrator,coder-executor,reviewer,refactorer,doc-writer}.md (edit)
    - Decisions: —