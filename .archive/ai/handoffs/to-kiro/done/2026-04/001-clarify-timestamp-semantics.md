# Clarify timestamp semantics in Kiro's AI contract
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 13:20

## Goal
Add an explicit line to `.kiro/steering/00-ai-contract.md` saying the activity-log
timestamp is the wall-clock time when you **prepend** the entry (i.e. when the work
finishes), not when it started. Prior entries have shown timestamps that don't sort
monotonically — e.g. the Kiro Priority 2 entry is stamped `11:44` but was written
after the Claude Priority 2 entry stamped `12:30`. The current contract is silent on
which point in time the timestamp refers to, so this ambiguity should be closed.

## Current state
`.kiro/steering/00-ai-contract.md` describes the log entry format:

    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: <one-line summary>
    - Files: <paths, or "—">
    - Decisions: <non-obvious choices, or "—">

…but does not say what the `HH:MM` represents.

## Target state
Immediately below the format block, a short paragraph clarifies timestamp semantics.
Suggested wording (adapt if you prefer, but preserve the meaning):

> **Timestamp rule:** use your current local wall-clock time at the moment you
> prepend the entry — i.e. after the work is finished, not when you started. CLIs
> running in different timezones or with drifted clocks may produce timestamps that
> don't sort monotonically; **prepend order is the authoritative sequencing**,
> timestamps are annotations.

## Context (reference only, not binding)
Claude has already updated the shared files it owns (`.ai/activity/log.md` header,
`AGENTS.md`, `/CLAUDE.md`) with the same clarification. This handoff just asks you
to add the matching note inside Kiro's own always-loaded contract so the rule is
visible at every Kiro turn without needing the activity log to be consulted.

## Steps
1. Read `.kiro/steering/00-ai-contract.md`.
2. Locate the `## Cross-CLI activity log` section and the fenced block showing the
   entry format.
3. Insert the "Timestamp rule" paragraph (above) immediately below the format block,
   before the line starting `Terse — one short paragraph max.` (or wherever makes
   natural narrative sense — you know your own contract best).
4. Save. Do not touch any other content in the file.
5. (Optional) If you disagree with the wording or want to adapt it for Kiro-specific
   nuances, that's fine — note the final wording in your activity log entry.

## Verification
- (a) `.kiro/steering/00-ai-contract.md` contains the new paragraph (verbatim from
  spec, or clearly equivalent).
- (b) Diff the file against its pre-edit version — only the new paragraph should
  appear. No other lines touched.
- (c) The file still parses cleanly as markdown (no broken headings, no orphaned
  code fences).

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Clarified timestamp semantics in .kiro/steering/00-ai-contract.md per handoff 001 — timestamp = wall-clock at prepend (finish time), not start. Prepend order is authoritative.
    - Files: .kiro/steering/00-ai-contract.md (edit)
    - Decisions: <wording used — spec verbatim or your adaptation>

## Report back with
- (a) The exact wording you committed (so Claude can confirm the rule's intent is
  preserved).
- (b) Confirmation that no other lines were changed.

## When complete
Claude will read `.kiro/steering/00-ai-contract.md` to validate. On success, this
file moves to `.ai/handoffs/to-kiro/done/`.
