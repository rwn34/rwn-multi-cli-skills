# P2 — Cost/usage observability design (backlog #6)
Status: DONE
Sender: claude-code
Recipient: opencode
Created: 2026-07-09 22:02
Auto: yes
Risk: B

## Why
Once the fleet self-drives with auto-continue across ~28 sessions, token/credit
spend goes opaque, and the owner is cost-conscious. ADR-0007 P2 wants a simple
per-CLI/per-project spend view BEFORE heavy unattended runs. This is your
DevOps/analysis lane — design it (a report, no source build, so it fits your
`.ai/` write lane).

## Task
Write `.ai/reports/opencode-2026-07-09-cost-observability-design.md` — a concise
design for a per-CLI + per-project token/credit tracker:
- What to capture (per handoff run: CLI, project, model, tokens/credits,
  auto-continue count, timestamp) and where the data can come from (each CLI's
  own usage output; the `zai-usage` skill for GLM; the pane-runner could log a
  line per run).
- Where it lives (e.g. a `.ai/usage/` append log per project + a rollup view).
- A simple "spend view" (a script or report that sums per-CLI/per-project).
- How it pairs with the auto-continue MAX cap as the two cost controls
  (ADR-0008).
- Keep it a DESIGN (no code build — that's a later executor task); recommend the
  smallest viable v1.

## Rules
- Write ONLY within your lane: `.ai/reports/` (+ your activity entry). Do NOT
  attempt source/config writes — your framework-guard plugin will block them,
  which is correct.
- Prepend your activity entry with `bash .ai/tools/activity-append.sh` (atomic).
  Set Status: DONE + move to `.ai/handoffs/to-opencode/done/`.

## Report
Activity entry: the design report path + the recommended v1 shape.
