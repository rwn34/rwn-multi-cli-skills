# 3. Code-Graph Rationalization

## Status

Accepted (2026-07-07, decided by project owner)

Amended 2026-07-09 (owner directive): single-graph topology. KimiGraph and
KiroGraph are REMOVED entirely — MCP registrations, steering files,
index/config dirs (`.kimigraph/` / `.kirograph/`), global npm binaries, and
the `tools/kirograph/` source clone. Rationale: both repeatedly malfunctioned
in practice (KiroGraph produced MCP load warnings in dispatched sessions on
2026-07-09; both required multiple repair handoffs in June); maintenance cost
exceeded value. CodeGraph (Claude) remains the sole code-knowledge graph.
Decisions below are superseded where marked.

## Context

- Three code-graph tools existed in parallel — CodeGraph (Claude Code), KimiGraph (Kimi CLI), KiroGraph (Kiro CLI) — each wired into every CLI's MCP config ("all 3 graphs in all 4 CLIs").
- In practice the cross-wiring generated recurring breakage and maintenance: MCP servers failing to start, stale PATH snapshots after installs, dangling config entries, and index staleness (documented in `.ai/known-limitations.md` and in repeated repair handoffs in the activity log).
- Under ADR-0002 role lanes, the executors (Kimi/Kiro) receive precise briefs with file paths and rarely need whole-repo structural queries; the architect/orchestrator (Claude) does the bulk of exploration.

## Decision

1. **Keep CodeGraph active for Claude Code.** The exploration payoff concentrates in the architect/orchestrator lane.
2. **Demote KimiGraph and KiroGraph to optional-off.** The tools remain documented and installable, and their `.kimigraph/` / `.kirograph/` config dirs remain in the repo, but their MCP server entries are removed from all CLI configs. Either may be re-enabled individually if a demonstrated need arises. *[Superseded 2026-07-09: Kimi → no graph, Kiro → no graph. The optional-off tier is eliminated — both tools are removed entirely (see Status amendment), including their config dirs; there is no re-enable path short of a fresh ADR.]*
3. **End cross-wiring.** Each CLI's MCP config registers at most its OWN graph. Claude's `.mcp.json` keeps only `codegraph`. Kiro's `.kiro/settings/mcp.json` and Kimi's `~/.kimi/mcp.json` drop graph entries (Kimi's is user-global — flagged for the user to apply on their machine). *[Superseded 2026-07-09 for Kimi/Kiro: with both their graphs removed, "at most its OWN graph" reduces to Claude/`codegraph` only; Kimi and Kiro register no graph at all.]*
4. **Crush gets no graph wiring.** Its ADR-0002 ops/release lane doesn't need structural code queries; `.crush.json` MCP entries are removed. *[Amended 2026-07-09: this now reads "OpenCode gets no graph wiring" — OpenCode replaces Crush in this lane per the ADR-0002 amendment of 2026-07-09. And with KimiGraph/KiroGraph removed (Status amendment above), the no-graph rule now covers every CLI except Claude. This annotation discharges the ADR-0003 decision-4 follow-up flagged in `.ai/research/adr-drafts-crush-to-opencode.md` §3.7.]*
5. **Kill criterion going forward.** Any enabled graph that fails MCP twice in a month, or goes unused for a month, is disabled rather than repaired.

## Consequences

- `.ai/instructions/code-graphs/principles.md` (SSOT) and its replicas are updated to match (same change set).
- `~/.kimi/mcp.json` cleanup is on the user — it is a user-global file, unreachable from the repo.
- The `tools/multi-cli-install` installer's wire-mcp step (which wires all graphs to all CLIs) is now out of line with this ADR — flagged as a follow-up implementation task, not changed by this ADR.
- Reversal path: MCP entries can be re-added per CLI without reinstalling the tools. *[Superseded 2026-07-09 for Kimi/Kiro: their tools are uninstalled, not just unwired — reversal would require reinstalling and a fresh ADR.]*
- *[Amendment 2026-07-09]* Cross-CLI graph parity rules (e.g. "Claude never writes `.kimigraph`/`.kirograph`") become dead paths and are simplified out of the enforcement layer (hooks/guards) the same day. The `.ai/instructions/code-graphs/principles.md` SSOT and its replicas are reduced to CodeGraph-only in the same change set.

## References

- `docs/architecture/0002-cli-role-topology.md` — role lanes underpinning the keep/demote split
- `.ai/instructions/code-graphs/principles.md` — code-graph usage SSOT (updated in the same change set)
- `.ai/known-limitations.md` — documented graph/MCP breakage that motivated this decision
- `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` — original "all 3 graphs in all 4 CLIs" adoption plan, superseded in part by this ADR
