# Regenerate Kimi steering replicas after SSOT update
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-19 18:10

## Goal
SSOT principles were updated (karpathy + agent-catalog). Kimi's steering
replicas need to re-copy from the new sources so the drift-check script at
`.ai/tools/check-ssot-drift.sh` reports 0 drift.

## Current state

Drift-check output after orchestrator's SSOT edits:
```
DRIFT: .ai/instructions/karpathy-guidelines/principles.md -> .kimi/steering/karpathy-guidelines.md (2 lines differ)
DRIFT: .ai/instructions/agent-catalog/principles.md -> .kimi/steering/agent-catalog.md (2 lines differ)
```

The SSOT changes:
- `karpathy-guidelines/principles.md`: added one body line `See \`EXAMPLES.md\` in this skill folder for worked anti-pattern / fix examples.` after the Tradeoff paragraph.
- `agent-catalog/principles.md`: added a trailing newline (EOF hygiene).

## Target state

Both Kimi steering files byte-identical to the new SSOT:
- `.kimi/steering/karpathy-guidelines.md` == `.ai/instructions/karpathy-guidelines/principles.md`
- `.kimi/steering/agent-catalog.md` == `.ai/instructions/agent-catalog/principles.md`

## Steps

1. From repo root:
   ```bash
   cp .ai/instructions/karpathy-guidelines/principles.md .kimi/steering/karpathy-guidelines.md
   cp .ai/instructions/agent-catalog/principles.md        .kimi/steering/agent-catalog.md
   ```
2. Run the drift checker and verify only Kiro-side drifts remain (if any):
   ```bash
   bash .ai/tools/check-ssot-drift.sh
   ```
   Expected: the 2 Kimi-related DRIFT lines disappear. Exit is still 1 if Kiro hasn't regenerated yet — that's expected.
3. If any Kimi-related drift remains, investigate (line-ending differences, BOM, etc. — the drift-checker README documents these edge cases).

## Verification
- (a) Both `.kimi/steering/*.md` files match their SSOT sources byte-for-byte.
- (b) `.ai/tools/check-ssot-drift.sh` output shows no DRIFT lines naming `.kimi/`.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Regenerated Kimi steering replicas from updated SSOT (per handoff 030)
    - Files: .kimi/steering/karpathy-guidelines.md, .kimi/steering/agent-catalog.md
    - Decisions: <none expected>

## Report back with
- (a) Confirm both `cp` commands ran cleanly.
- (b) Paste the final `.ai/tools/check-ssot-drift.sh` output.

## When complete
Sender moves this to `.ai/handoffs/to-kimi/done/`. Trivial handoff, no BLOCKER.
