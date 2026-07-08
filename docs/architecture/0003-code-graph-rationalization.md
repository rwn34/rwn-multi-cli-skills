# 3. Code-Graph Rationalization

## Status

Accepted (2026-07-07, decided by project owner)

## Context

- Three code-graph tools existed in parallel — CodeGraph (Claude Code), KimiGraph (Kimi CLI), KiroGraph (Kiro CLI) — each wired into every CLI's MCP config ("all 3 graphs in all 4 CLIs").
- In practice the cross-wiring generated recurring breakage and maintenance: MCP servers failing to start, stale PATH snapshots after installs, dangling config entries, and index staleness (documented in `.ai/known-limitations.md` and in repeated repair handoffs in the activity log).
- Under ADR-0002 role lanes, the executors (Kimi/Kiro) receive precise briefs with file paths and rarely need whole-repo structural queries; the architect/orchestrator (Claude) does the bulk of exploration.

## Decision

1. **Keep CodeGraph active for Claude Code.** The exploration payoff concentrates in the architect/orchestrator lane.
2. **Demote KimiGraph and KiroGraph to optional-off.** The tools remain documented and installable, and their `.kimigraph/` / `.kirograph/` config dirs remain in the repo, but their MCP server entries are removed from all CLI configs. Either may be re-enabled individually if a demonstrated need arises.
3. **End cross-wiring.** Each CLI's MCP config registers at most its OWN graph. Claude's `.mcp.json` keeps only `codegraph`. Kiro's `.kiro/settings/mcp.json` and Kimi's `~/.kimi/mcp.json` drop graph entries (Kimi's is user-global — flagged for the user to apply on their machine).
4. **Crush gets no graph wiring.** Its ADR-0002 ops/release lane doesn't need structural code queries; `.crush.json` MCP entries are removed.
5. **Kill criterion going forward.** Any enabled graph that fails MCP twice in a month, or goes unused for a month, is disabled rather than repaired.

## Consequences

- `.ai/instructions/code-graphs/principles.md` (SSOT) and its replicas are updated to match (same change set).
- `~/.kimi/mcp.json` cleanup is on the user — it is a user-global file, unreachable from the repo.
- The `tools/multi-cli-install` installer's wire-mcp step (which wires all graphs to all CLIs) is now out of line with this ADR — flagged as a follow-up implementation task, not changed by this ADR.
- Reversal path: MCP entries can be re-added per CLI without reinstalling the tools.

## References

- `docs/architecture/0002-cli-role-topology.md` — role lanes underpinning the keep/demote split
- `.ai/instructions/code-graphs/principles.md` — code-graph usage SSOT (updated in the same change set)
- `.ai/known-limitations.md` — documented graph/MCP breakage that motivated this decision
- `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` — original "all 3 graphs in all 4 CLIs" adoption plan, superseded in part by this ADR
