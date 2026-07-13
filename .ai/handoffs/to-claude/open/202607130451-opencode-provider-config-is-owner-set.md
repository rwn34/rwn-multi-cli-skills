# Rule: OpenCode's provider/key is owner-set — follow it, never switch it
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 11:52
Auto: yes
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
