# 4AI-panes integration notes

> **UPDATE 2026-07-08 (late evening; some same-batch artifacts carry 07-09
> UTC-style stamps) — launcher now lives IN this repo.** Per owner decision
> (2026-07-08, "personalised framework, no need for different repo"), the
> launcher was imported to `tools/4ai-panes/` from the local checkout at
> `C:\Users\rwn34\.rwn-auto\rwn-4AI-panes`, master @ `06c5d84` (verified
> byte-identical to the reviewed `0df6908` — nothing discarded). Two Selector
> badges were added and execution-verified: framework-version
> (`[v OK] / [! OLD] / [- none]` from `.ai/.framework-version`) and open
> handoff count (`[H:<n>]`). Consequences:
> - §5 "cross-repo coupling" below is OBSOLETE: launcher AND role policy now
>   live here; `tools/4ai-panes/` is the canonical launcher source.
> - The external repo + `~\.rwn-auto` checkout are pending an owner archive
>   decision; until then treat them as read-only mirrors.
> - Launch commands still to re-verify against amended ADR-0002 (P5 handoff
>   target 4) at the owner's next live launch.
> - Known fragilities (from import review): `wt.exe split-pane` flag semantics
>   drift across WT versions (pin tested version in a comment); hardcoded
>   `$projectsDir = "C:\Users\rwn34\Code"` will clash with any future move of
>   project roots.

Context captured 2026-07-07 from the user: this framework is tightly coupled to
**rwn-4AI-panes** (https://github.com/rwn34/rwn-4AI-panes) for daily usage.
These notes are design inputs for the framework-evolution roadmap (role
topology ADR-0002, Crush onboarding, delegation enforcement, handoff
triggering).

## What 4AI-panes is

Windows-only launcher: a Start Menu shortcut opens ONE maximized Windows
Terminal window with **four equal vertical panes**, each running an AI CLI in
the selected project directory:

| Pane | CLI | Launch command |
|---|---|---|
| 1 | Claude Code | `claude --dangerously-skip-permissions` |
| 2 | Kiro | `kiro-cli chat --trust-all-tools` |
| 3 | Kimi | `kimi --agent-file .kimi/agents/orchestrator.yaml --yolo` |
| 4 | Crush | `crush --yolo` |

PowerShell (`Launch4Panes.ps1` + `Selector.ps1`) + VBS wrapper; interactive
project selector; pane order persisted in `.4pane-layout`; missing CLIs
auto-skipped. The 4AI-panes repo itself is framework-adopted (has `.ai/`,
`.claude/`, `.kimi/`, `.kiro/`).

## Design consequences for this framework

1. **All four CLIs run in permission-bypass mode.** `--dangerously-skip-
   permissions` / `--trust-all-tools` / `--yolo` mean interactive permission
   prompts are OFF in daily use. **The hook layer is the only real guardrail.**
   - Raises priority of delegation/write-boundary enforcement via hooks
     (roadmap Phase 3).
   - Makes the known Kiro subagent-hook bug (#7671) more serious in daily use.
   - Makes Crush the most exposed surface: `--yolo` with NO hook layer at all
     today. Crush onboarding (Phase 2) must wire whatever native guardrails
     Crush supports before it gets any write-bearing role; its ADR-0002
     Stage-1 (prepare-only) scoping is load-bearing, not cosmetic.

2. **Crush is a confirmed daily-driver 4th CLI** — not hypothetical. Phase 2
   onboarding (per `.ai/cli-map.md` § "Adding a new CLI") is justified.

3. **Handoff trigger mechanism (Phase 4) constraint:** all four CLIs are
   already LIVE in panes, but Windows Terminal cannot inject input into a
   running pane programmatically (no tmux-send-keys equivalent). Therefore:
   - Dispatcher should launch **one-shot headless instances** (e.g.
     `claude -p "process handoff X"`, Kimi/Kiro headless equivalents) in a new
     WT tab/window — NOT try to drive the interactive panes.
   - Alternative worth evaluating in Phase 4: a selector-integrated poller in
     4AI-panes itself (PowerShell) that watches `.ai/handoffs/*/open/` and
     surfaces a toast/badge, keeping the human as the dispatcher with less
     friction.

4. **Kimi already launches as orchestrator** (`--agent-file
   .kimi/agents/orchestrator.yaml`) — the pane setup enforces Kimi's
   orchestrator entry point by construction. Claude gets it via settings;
   equivalent check needed for Kiro's `chat.defaultAgent orchestrator` setting
   (not visible in the launch command — verify in Phase 3).

5. **Cross-repo coupling:** changes to launch flags or pane roles belong in
   the 4AI-panes repo, but role *policy* (which CLI does what) is owned here
   by ADR-0002. If pane order/roles change there, ADR-0002 is the authority
   to reconcile against.
