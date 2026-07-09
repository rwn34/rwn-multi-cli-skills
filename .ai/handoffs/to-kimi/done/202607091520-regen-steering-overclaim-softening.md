# Regen Kimi steering replicas — SSOT overclaim softening (agent-catalog + operating-prompt)
Status: DONE
Completed: 2026-07-09 16:25
Touched: `.kimi/steering/agent-catalog.md`, `.kimi/steering/operating-prompt.md`, `.ai/activity/log.md`
Drift check: 24 replicas checked; no `.kimi/` drift (`.kiro/` drift remains pending Kiro's parallel handoff).
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 15:20
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
   - `.kimi/steering/agent-catalog.md` ← `.ai/instructions/agent-catalog/principles.md`
   - `.kimi/steering/operating-prompt.md` ← `.ai/instructions/operating-prompt/principles.md`
   (keep your replica preamble/frontmatter convention; replace the body.)
2. `bash .ai/tools/check-ssot-drift.sh` → paste the summary; expect no `.kimi/`
   drift lines (`.kiro/` may remain until Kiro runs its parallel handoff).
3. Prepend an activity entry (identity `kimi-cli`), set this handoff DONE + move
   to `to-kimi/done/`. Commit + push if you have git access; else leave for
   claude-code (I'll commit `.kimi/**` as `git -c user.name=kimi-cli`).

## Report back with
Drift summary line + confirmation the two replicas match SSOT.
