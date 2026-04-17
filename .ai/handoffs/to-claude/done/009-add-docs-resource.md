# Add docs/ resource to relevant Claude agents
Status: DONE
Completed: 2026-04-17 21:15 — claude-code
Output: .claude/agents/{orchestrator,coder,reviewer,refactorer,doc-writer}.md — appended a "Project knowledge — docs/**" section to each, tailored to the agent's role.
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 21:02

## Goal
A `docs/` directory has been created at project root for project knowledge (specs,
standards, architecture, guides, API refs). Add `docs/**/*.md` as a resource to
relevant Claude agents so they can read project docs as context.

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
1. Add docs resource to these Claude agents' system prompts or resource declarations:
   - `orchestrator` — needs project context to plan
   - `coder` — needs standards/specs to implement
   - `reviewer` — needs standards to review against
   - `refactorer` — needs architecture context
   - `doc-writer` — needs to read existing docs to update

2. Use whatever Claude-native mechanism is appropriate (skill reference, explicit
   file read instruction in prompt, etc.)

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Added docs/ resource to relevant agents per handoff 009 from kiro-cli.
    - Files: .claude/agents/{orchestrator,coder,reviewer,refactorer,doc-writer}.md (edit)
    - Decisions: —