# docs/

Project knowledge — specs, standards, architecture decisions, guides, API references.
AI agents read this directly via `file://docs/**/*.md` in their resource configs.

## Structure

    docs/
    ├── architecture/    ADRs, system design decisions
    ├── specs/           Feature specs, requirements
    ├── standards/       Coding standards, conventions
    ├── guides/          How-to guides, onboarding
    └── api/             API reference docs

## Who writes here

- `doc-writer` agent (primary)
- Humans (directly)
- Other agents may suggest docs but delegate writing to `doc-writer`

## Who reads here

All agents that need project context load `file://docs/**/*.md` as a resource.
Content is read directly from disk — no duplication, no sync.