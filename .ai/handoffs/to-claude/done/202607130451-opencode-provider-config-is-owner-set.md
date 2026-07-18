# Rule: OpenCode's provider/key is owner-set — follow it, never switch it
Status: DONE
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 11:52
Auto: no
Risk: A
Base: origin/master

## Owner directive (2026-07-13, verbatim intent)
"OpenCode not always using GLM, sometimes I use the Kimi Code API key as well.
Just follow what is being used instead of changing it itself."

## Rule
OpenCode's provider / model / API-key configuration is **owner-owned and
variable** (zhipu/GLM, Kimi Code API key, and others over time). The fleet —
panes, cockpits, any CLI — must:
1. Use whatever provider/key is currently configured. Follow, don't second-guess.
2. **Never change** OpenCode's provider/model/key config — not as a "fix" for a
   wedge, not as an optimization, not as part of a relaunch or provisioning
   step. If config looks wrong, report it to the owner; don't repair it.
3. Not treat the current provider as a bug. Today's wedge diagnosis read
   `glm-4.7-flash` from the opencode log — that was simply the owner's
   configuration at the time, not a finding to act on.

## Scope ask
One line in the operating-prompt SSOT (opencode section) and `.opencode/contract.md`
(your custodianship per ADR-0001). No tooling needed — this is a don't-touch rule.

## Related
Same family as `to-claude/202607130447` (confirmed-stale kill = Tier B): both
are "act on evidence, don't improvise environment changes" rules from the
owner this morning.

## Completion (claude-code, 2026-07-14 04:05)
Status: **DONE**. Claimed by the cockpit first (`claim-handoff.sh --owner
claude-cockpit`, exit 0 — stale sidecar reclaimed, `Auto:` flipped to `no`)
because the owner asked for it live; the auto pane will skip it.

Landed the rule in three places (SSOT + both replicas of it):
- `.ai/instructions/operating-prompt/principles.md` §4 — appended to the
  OpenCode role bullet (line 71): provider/model/API-key config is owner-set and
  variable; the fleet uses what's configured and never changes it; a provider
  seen in a log is the owner's choice, not a finding; report, don't repair.
- `.claude/skills/operating-prompt/SKILL.md` line 78 — replica kept in sync
  (`.ai/sync.md`), identical wording.
- `.opencode/contract.md` — new **Enforcement rule 7** (line 120), written
  second-person for OpenCode: nobody including you changes it, not to fix a
  wedge, not on relaunch.

Grep evidence:
    .claude/skills/operating-prompt/SKILL.md:78:  **OpenCode's provider/model/API-key config is owner-set and variable** (owner
    .opencode/contract.md:120:7. **Your provider / model / API-key config is owner-set and variable** (owner
    .ai/instructions/operating-prompt/principles.md:71:  **OpenCode's provider/model/API-key config is owner-set and variable** (owner

No tooling added — as scoped, this is a don't-touch rule, not a guard. Note the
`.opencode/plugin/framework-guard.js` deny-list already blocks OpenCode from
writing its own config, but it does NOT stop *another* CLI or a pane script from
rewriting `opencode.json`; that gap is now closed by prose only. If it recurs,
the follow-up is a guard entry — not in scope here.
