# Regen Kiro steering replicas — SSOT overclaim softening (agent-catalog + operating-prompt)
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 15:21
Auto: yes
Risk: B

## Why
The SSOTs `.ai/instructions/agent-catalog/principles.md` and
`.ai/instructions/operating-prompt/principles.md` were just updated (honesty
fix per validation campaign + ADR-0007): the old "cross-CLI writes are
hard-blocked by each CLI's pre-write hook" overclaim is softened to the layered
reality (git pre-commit backstop = universal net; per-CLI hooks = interactive
best-effort, headless varies; prompt SAFETY RULES = floor). operating-prompt
also gained a short "headless by default (ADR-0006)" execution-mode note. Your
steering replicas are now drifted and must be regenerated.

## Steps
1. Regenerate from SSOT per `.ai/sync.md`:
   - `.kiro/steering/agent-catalog.md` ← `.ai/instructions/agent-catalog/principles.md`
   - `.kiro/steering/operating-prompt.md` ← `.ai/instructions/operating-prompt/principles.md`
   (keep your replica preamble convention; replace the body.)
2. `bash .ai/tools/check-ssot-drift.sh` → paste the summary; expect no `.kiro/`
   drift lines (`.kimi/` may remain until Kimi runs its parallel handoff).
3. Prepend an activity entry (identity `kiro-cli`), set this handoff DONE + move
   to `to-kiro/done/`. Leave commits to claude-code (no Kiro git lane) — I'll
   commit `.kiro/**` as `git -c user.name=kiro-cli`.

## Report back with
Drift summary line + confirmation the two replicas match SSOT.
