# Regenerate Kiro steering replicas after SSOT update
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-19 18:10

## Goal
SSOT principles were updated (karpathy + agent-catalog). Kiro's steering
replicas need to re-copy from the new sources so `.ai/tools/check-ssot-drift.sh`
reports 0 drift.

## Current state

Drift-check output after orchestrator's SSOT edits:
```
DRIFT: .ai/instructions/karpathy-guidelines/principles.md -> .kiro/steering/karpathy-guidelines.md (2 lines differ)
DRIFT: .ai/instructions/agent-catalog/principles.md -> .kiro/steering/agent-catalog.md (2 lines differ)
```

The SSOT changes:
- `karpathy-guidelines/principles.md`: added one body line `See \`EXAMPLES.md\` in this skill folder for worked anti-pattern / fix examples.` after the Tradeoff paragraph.
- `agent-catalog/principles.md`: added a trailing newline.

## Target state

Both Kiro steering files byte-identical to the new SSOT:
- `.kiro/steering/karpathy-guidelines.md` == `.ai/instructions/karpathy-guidelines/principles.md`
- `.kiro/steering/agent-catalog.md` == `.ai/instructions/agent-catalog/principles.md`

## Steps

1. From repo root:
   ```bash
   cp .ai/instructions/karpathy-guidelines/principles.md .kiro/steering/karpathy-guidelines.md
   cp .ai/instructions/agent-catalog/principles.md        .kiro/steering/agent-catalog.md
   ```
2. Run the drift checker:
   ```bash
   bash .ai/tools/check-ssot-drift.sh
   ```
   Once Kimi also regenerates (handoff 030 — dispatched in parallel), this should report `Checked: 12 replicas, Drift: 0`.

3. Also verify `.kiro/skills/karpathy-guidelines/SKILL.md` is NOT affected —
   it's bound to `examples.md` not `principles.md`, so this change shouldn't
   touch it. If the drift-check script flags it, investigate separately.

## Verification
- (a) Both `.kiro/steering/*.md` files match their SSOT sources byte-for-byte.
- (b) `.ai/tools/check-ssot-drift.sh` output shows no DRIFT lines naming `.kiro/`.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Regenerated Kiro steering replicas from updated SSOT (per handoff 016)
    - Files: .kiro/steering/karpathy-guidelines.md, .kiro/steering/agent-catalog.md
    - Decisions: <none expected>

## Report back with
- (a) Confirm both `cp` commands ran cleanly.
- (b) Paste the final `.ai/tools/check-ssot-drift.sh` output.

## When complete
Sender moves this to `.ai/handoffs/to-kiro/done/`. Trivial handoff, no BLOCKER.
