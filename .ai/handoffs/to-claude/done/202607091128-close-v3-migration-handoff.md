# Close out the v3 migration handoff (202607091430) — deliverables verified, ADR-0007 unblocks it
Status: OPEN
Sender: kiro-cli
Recipient: claude-code
Created: 2026-07-09 11:28 UTC
Auto: yes
Risk: B

## Why this is yours
`.ai/handoffs/to-kiro/open/202607091430-migrate-to-v3.md` carries a kiro-cli
completion note and was explicitly "Kept OPEN for claude-code to validate +
move." Kiro-side work is complete; the only remaining actions are the
sender-side validate/move + the commit — both in your lane (protocol: sender
moves `to-kiro/` to `done/`; Kiro has no git lane; `.kiro/**` + `.ai/**` commit
is yours as `git -c user.name=kiro-cli` per the ADR-0005 backstop territory rule).

## What changed since the handoff was written
The open question the handoff flagged as "changes the merge decision" is now
**owner-decided** in ADR-0007 (accepted 2026-07-09) + the ADR-0006 amendment:
- Framework use stays on **Kiro v2**; **v3 deferred**.
- v3 config stays **committed but DORMANT** (not on the active enforcement path).
- Re-adoption is gated on a **future ADR**, when v3 ships a headless + agent-pin
  surface.

⇒ The Step-4 live-validation gate (v3 headless enforcement evidence) is
**moot / explicitly deferred** — v3 has no headless surface to validate in
(report §3), so there is nothing for you to live-validate before close. The
report's §5 recommendation was adopted into ADR-0006/0007. Headless Kiro
dispatch stays v2 + the git backstop.

## Deliverables — verified present on disk (delivery-integrity)
| File | Size | Status |
|---|---|---|
| `.kiro/agents/orchestrator.md` | 5593 B | present (v3 markdown agent, `permissions.rules`) |
| `.kiro/hooks/guards.json` | 3108 B | present (v3 standalone hooks, no python) |
| `.ai/config-snippets/kiro-v3-permissions.yaml` | 4343 B | present (owner-installed user-scope template) |
| `.ai/reports/kiro-cli-2026-07-09-v3-migration.md` | — | present (full report, findings A/B) |

v2 fallback untouched: `.kiro/agents/*.json` + `.kiro/hooks/*.sh` all still present.

## Do
1. Confirm the four files above (inspection is sufficient — live v3 validation
   is deferred per ADR-0007, not a close gate).
2. Commit `.kiro/**` + `.ai/**` as `git -c user.name=kiro-cli` (backstop
   territory rule).
3. Move `202607091430-migrate-to-v3.md` from `to-kiro/open/` → `to-kiro/done/`,
   set its Status: DONE.
4. Move THIS handoff to `to-claude/done/` when complete.

## Report back with
- Commit SHA(s); confirmation both handoffs moved to their `done/` dirs.
