# Re-sync orchestrator-pattern replica from updated SSOT
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-18 10:30

## Goal
Claude rewrote the SSOT at `.ai/instructions/orchestrator-pattern/principles.md`
to reflect the current 13-agent catalog (the old version only knew about
orchestrator/coder/reviewer — the catalog had since expanded to 13 but this
doc never caught up). Kimi's steering replica at
`.kimi/steering/orchestrator-pattern.md` now disagrees with the SSOT and must
be re-synced.

## Current state
`.kimi/steering/orchestrator-pattern.md` still contains the old 3-agent body
(Coder subsection, Reviewer subsection, Future agents listing db-migrator /
test-runner / deployer, 3-column write-path table, per-CLI notes listing only
`{orchestrator,coder-executor,reviewer}.yaml`).

The SSOT at `.ai/instructions/orchestrator-pattern/principles.md` was rewritten
per **Option B** — point at the agent-catalog rather than duplicate the roster.
Changes:
- Added "Companion doc" line pointing to agent-catalog
- Replaced Coder + Reviewer subsections with a compact "Subagents" section
  listing all 12 names + 3 classes (Executor / Diagnoser / Default)
- Deleted the "Future agents" section (catalog has landed)
- Rewrote the write-path table into 3 tiers (Framework / Reports / Project
  source) instead of 3 per-agent columns
- Updated delegation-flow diagram to list all 12 subagent names
- Updated per-CLI notes from `{orchestrator,coder,reviewer}` to `*.yaml`
  (13 files)
- Replaced research-doc reference with agent-catalog pointer

## Target state
`.kimi/steering/orchestrator-pattern.md` body matches the updated SSOT verbatim.

## Steps
1. Copy the SSOT body to Kimi's steering replica:

   ```bash
   cp .ai/instructions/orchestrator-pattern/principles.md .kimi/steering/orchestrator-pattern.md
   ```

   Kimi's steering files don't carry frontmatter, so a direct copy is correct.
   (See `.ai/sync.md` — this is the same command already documented there.)

2. Read the resulting file and confirm no drift between source and replica
   (line counts should match).

3. Prepend an activity-log entry.

## Verification
- (a) `.kimi/steering/orchestrator-pattern.md` is byte-identical to
      `.ai/instructions/orchestrator-pattern/principles.md`.
- (b) The old phrases are no longer present in Kimi's replica:
      `### Coder (subagent)`, `### Reviewer (subagent)`, `### Future agents`,
      `db-migrator`, `test-runner`, `deployer`.
- (c) The new phrases ARE present: `Companion doc:`, `Twelve specialized
      subagents`, `Three tiers`, `Executor` / `Diagnoser` / `Default`.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Re-synced .kimi/steering/orchestrator-pattern.md from updated SSOT (per handoff 021).
    - Files: .kimi/steering/orchestrator-pattern.md
    - Decisions: <any deviations — expected none, this is a byte-copy>

## Report back with
- (a) `diff .ai/instructions/orchestrator-pattern/principles.md .kimi/steering/orchestrator-pattern.md` output
      (expected empty).
- (b) Confirmation of the phrase-presence checks in verification (b) and (c).

## When complete
Sender (claude-code) validates by reading Kimi's replica. On success, moves
this file to `.ai/handoffs/to-kimi/done/`. Self-review acceptable — mechanical
copy, no judgment calls.
