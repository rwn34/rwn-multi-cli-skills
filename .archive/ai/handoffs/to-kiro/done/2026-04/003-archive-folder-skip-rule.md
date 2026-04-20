# Add archive-folder skip rule to Kiro's AI contract
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 16:30

## Goal
Add a short section to `.kiro/steering/00-ai-contract.md` saying that folders
matching `.ai/**/archive/` contain historical content and should NOT be read during
routine work. Only consulted when the user explicitly references historical
content.

## Current state
`.kiro/steering/00-ai-contract.md` covers identity, SSOT, activity log, and
handoffs — but says nothing about the new archive folders. Without this rule in
your always-loaded steering, a future Kiro session might scan
`.ai/activity/archive/` or `.ai/research/archive/` thinking it's part of the
active state.

## Target state
A new short section in the contract (placement: as a peer after
`## Cross-CLI handoffs`, before any closing). Suggested wording (adapt if you
prefer, but preserve the meaning):

> ## Archive folders (skip during routine reads)
>
> Folders matching `.ai/**/archive/` (`.ai/activity/archive/`,
> `.ai/research/archive/`, and any future archive subfolders under `.ai/`) contain
> historical content. Do NOT read them during routine operations. Only consult
> when the user explicitly references historical activity or archived research
> (e.g., "what happened last month?", "pull up the old research on X"). See
> each archive folder's `README.md` for the archival protocol if you're asked to
> perform an archive move.

## Context (reference only)
Claude has already created `.ai/activity/archive/` and `.ai/research/archive/`
with README files in each explaining the layout and archival protocol, plus
updated the shared docs (`.ai/README.md`, `AGENTS.md`, `.ai/activity/log.md`
header, `/CLAUDE.md`) with the skip rule. This handoff mirrors the rule into
your always-loaded steering so it applies at every Kiro turn without having to
have read the shared docs first.

## Steps
1. Read `.kiro/steering/00-ai-contract.md`.
2. Add the `## Archive folders (skip during routine reads)` section above (spec
   wording or equivalent). Place as a peer after `## Cross-CLI handoffs`.
3. Save. Do not touch other content.

## Verification
- (a) `.kiro/steering/00-ai-contract.md` contains the archive-skip section.
- (b) Diff is scoped to this single addition. No other lines touched.
- (c) File still parses cleanly (no broken headings).

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Added archive-folder skip rule to .kiro/steering/00-ai-contract.md per handoff 003. Don't read .ai/**/archive/ unless user asks for historical content.
    - Files: .kiro/steering/00-ai-contract.md (edit)
    - Decisions: <placement, any wording changes>

## Report back with
- (a) Exact wording committed.
- (b) Placement (sibling sections).

## When complete
Claude reads `.kiro/steering/00-ai-contract.md` and validates. File moves to
`.ai/handoffs/to-kiro/done/` on success.
