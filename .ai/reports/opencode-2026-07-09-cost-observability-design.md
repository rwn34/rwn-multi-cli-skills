# Cost/Usage Observability Design — P2 (backlog #6)

**Author**: opencode  
**Date**: 2026-07-09  
**Status**: DESIGN (v1 proposal, not implemented)  
**Context**: ADR-0007 P2 — before heavy unattended runs across ~28 sessions, owner needs cost visibility per CLI per project.

## Why This Exists

Once the fleet self-drives with auto-continue across ~28 sessions, token/credit spend goes opaque. The owner is cost-conscious and wants a simple per-CLI/per-project spend view BEFORE heavy unattended runs run wild. This pairs with the auto-continue MAX cap (ADR-0008) as the two cost controls.

## V1: Smallest Viable Design

### 1. What to Capture (per handoff run)

For each CLI session/handoff execution, capture:

| Field | Description | Source |
|-------|-------------|--------|
| `timestamp` | UTC timestamp of run start | System clock |
| `cli` | CLI identity (claude-code, kimi-cli, kiro-cli, opencode) | CLI's own identity |
| `project` | Project identifier (from git repo name or config) | Environment/git |
| `model` | Model used (e.g., zhipu-coding/glm-4.7) | CLI's model config |
| `tokens_in` | Input tokens consumed | CLI usage output / zai-usage skill |
| `tokens_out` | Output tokens consumed | CLI usage output / zai-usage skill |
| `credits` | Credit cost (if API uses credits instead of tokens) | API response / billing endpoint |
| `auto_continue_count` | Number of auto-continue cycles | pane-runner state machine |
| `handoff_ref` | Handoff file reference (if applicable) | Handoff system |

### 2. Where the Data Lives

**Primary data store**: `.ai/usage/<project>.logl` per project

Format: One JSONL line per run, append-only (no overwrites). Example:

```jsonl
{"timestamp":"2026-07-09T22:15:30Z","cli":"claude-code","project":"rwn-multi-cli-skills","model":"zhipu-coding/glm-4.7","tokens_in":12450,"tokens_out":3200,"credits":null,"auto_continue_count":3,"handoff_ref":"202607092202-p2-cost-observability-design.md"}
```

**Rollup view**: `.ai/usage/rollup/<project>-<date>.md` generated on demand

### 3. Data Sources

| CLI | Primary Source | Notes |
|-----|----------------|-------|
| claude-code | Native usage output + zai-usage skill | Already has usage tracking in session logs |
| kimi-cli | Native usage output + zai-usage skill | May need to capture from session logs |
| kiro-cli | Native usage output + zai-usage skill | May need to capture from session logs |
| opencode | Native usage output + zai-usage skill | Already has usage tracking |

**pane-runner integration**: The pane-runner (`tools/4ai-panes/pane-runner.ps1`) can write a line to `.ai/usage/<project>.logl` at the end of each CLAIM→RUN→DECIDE cycle, capturing the auto-continue count and handoff reference.

### 4. Simple Spend View

A script (`.ai/tools/usage-report.ps1`) that:

1. Reads all `.ai/usage/*.logl` files
2. Sums per-CLI/per-project/token-usage over configurable time windows (today, this week, this month)
3. Outputs a markdown table like:

| CLI | Project | Tokens In | Tokens Out | Credits | Auto-Continues | Runs Today |
|-----|---------|-----------|------------|---------|----------------|------------|
| claude-code | rwn-multi-cli-skills | 45,230 | 12,450 | $0.45 | 15 | 8 |
| kimi-cli | rwn-multi-cli-skills | 32,100 | 8,900 | $0.32 | 7 | 5 |
| kiro-cli | rwn-multi-cli-skills | 28,450 | 7,200 | $0.28 | 4 | 3 |
| **TOTAL** | — | **105,780** | **28,550** | **$1.05** | **26** | **16** |

### 5. Integration with Auto-Continue MAX Cap (ADR-0008)

The two cost controls work together:

1. **Auto-continue MAX cap** (ADR-0008): Hard per-handoff limit (e.g., MAX=5 auto-continue cycles). Prevents any single handoff from running away.
2. **Usage observability** (this design): Visibility across all runs over time. Lets the owner see patterns (e.g., "claude-code is 3x more expensive than kimi-cli for this project").

**Workflow**: Before launching heavy unattended runs, owner runs `bash .ai/tools/usage-report.ps1` to check recent spend. If spend looks high, they can:
- Reduce auto-continue MAX cap in handoff briefs
- Switch to a cheaper model for certain CLIs
- Pause unattended runs for high-cost projects

### 6. V1 Recommendation

**Smallest viable v1**:

1. **Pane-runner logging**: Modify `pane-runner.ps1` to append a JSONL line to `.ai/usage/<project>.logl` at the end of each RUN phase. Capture: timestamp, cli, project, model, tokens (from CLI session output), auto_continue_count, handoff_ref.
2. **Simple rollup script**: Write `.ai/tools/usage-report.ps1` that reads `.ai/usage/*.logl` and outputs the spend table for today/week/month.
3. **No backend**: Keep it append-only flat files. No database, no API, no complexity. If `.ai/usage/` gets too big, archive old `.logl` files monthly.

**Why this is v1**: It's append-only (simple), pane-runner already exists (minimal change), and the rollup script is a straightforward aggregation. Future v2 could add historical trends, cost alerts, or integration with billing APIs, but v1 solves the core visibility problem.

### 7. Edge Cases & Open Questions

| Question | V1 Approach | Future Consideration |
|----------|-------------|----------------------|
| What if CLI doesn't report token usage? | Use zai-usage skill as fallback (queries GLM API) | Some CLIs may not have zai-usage support; need graceful degradation |
| What about concurrent pane-runner instances? | Append-only JSONL is safe for concurrent writes (atomic line appends) | If corruption observed, add file locking in v2 |
| What if project name changes? | Use git remote URL as stable project identifier | Allow manual project alias configuration in v2 |
| What about non-handoff runs (interactive sessions)? | Pane-runner only logs handoff runs; interactive runs are out of scope for v1 | Could add manual logging command for interactive sessions in v2 |
| How to handle different pricing models? | Store raw token counts; convert to cost at report time using pricing table | v2 could fetch real-time pricing from provider APIs |

### 8. Success Criteria

V1 is successful when:

1. Owner can run `.ai/tools/usage-report.ps1` and see token/credit spend per CLI per project for today/week/month.
2. Pane-runner automatically logs every handoff run to `.ai/usage/<project>.logl`.
3. Data is accurate enough to inform cost-control decisions (e.g., reducing MAX cap or switching models).
4. No performance impact on pane-runner or handoff execution (append-only writes are fast).

---

**Next steps**: This is a design deliverable. Implementation (pane-runner modification + usage-report.ps1 script) is a separate executor task, likely handoff to Kimi/Kiro as it involves source code changes.