# Add handoff-inbox pointer to Kiro's AI contract
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 13:30

## Goal
Teach Kiro's always-loaded contract that cross-CLI handoff instructions can arrive
in `.ai/handoffs/to-kiro/open/` and should be checked at the start of non-trivial
work (or whenever the user says "there's a handoff for you"). Without this, you
won't know the inbox exists until someone points you at a specific file.

## Current state
`.kiro/steering/00-ai-contract.md` talks about the activity log read/prepend
protocol but says nothing about the handoff directory.

## Target state
A short new section (or a short paragraph) in the contract:

> ## Cross-CLI handoffs
>
> When another CLI needs you to execute a change in `.kiro/` or in Kiro's portion
> of the shared docs, it writes a paste-ready instruction file to
> `.ai/handoffs/to-kiro/open/NNN-slug.md`. Glance at that directory when a session
> starts or when the user references a handoff. Follow the protocol in
> `.ai/handoffs/README.md`: review, execute the steps, prepend an activity-log
> entry, report back. The sender validates and moves the file to
> `.ai/handoffs/to-kiro/done/` on success.
>
> You can send handoffs too — write to `.ai/handoffs/to-claude/open/` or
> `.ai/handoffs/to-kimi/open/` when you need those CLIs to change files in their
> folders.

## Steps
1. Read `.kiro/steering/00-ai-contract.md`.
2. Add the section above (verbatim is fine, adapt if your contract prefers
   different phrasing). Placement: after the `## Cross-CLI activity log` section,
   before any closing/signoff. The two sections are peers.
3. Save. Do not touch other content.

## Verification
- (a) `.kiro/steering/00-ai-contract.md` contains a `## Cross-CLI handoffs` (or
  equivalently-titled) section that names the `to-kiro/open/` path and points at
  `.ai/handoffs/README.md`.
- (b) Diff is scoped to this addition plus whatever you added for handoff 001
  (timestamp rule). No other lines touched.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Added handoff-inbox pointer section to .kiro/steering/00-ai-contract.md per handoff 002. Names the to-kiro/open/ path and references .ai/handoffs/README.md.
    - Files: .kiro/steering/00-ai-contract.md (edit)
    - Decisions: <exact placement, any wording changes>

## Report back with
- (a) Where in the contract you placed the section (heading name + sibling sections).
- (b) Confirmation that handoff 001 also landed in the same edit (or separately).

## When complete
Claude reads `.kiro/steering/00-ai-contract.md` and validates. File moves to
`.ai/handoffs/to-kiro/done/`.
