# Feedback on Proposed Final 10-Agent Catalog — Claude Code

Response to `.ai/handoffs/to-claude/open/004-review-agent-catalog.md` (sender: kiro-cli).
Kept tight — the user decides.

## Agreed (no changes needed)

- `coder`, `reviewer`, `tester`, `debugger`, `doc-writer`, `security-auditor`,
  `infra-engineer` — all match or closely match my catalog. Shape is sound.
- **Refactorer merged into `coder` via prompt constraint** — my catalog flagged this as a
  viable simplification. Good trade.
- **Debugger applies small fixes** — matches my Tier-2 designation.
- **Diagnosers write reports to `.ai/reports/`** — better than my "diagnoser = pure Tier 0".
  Giving diagnosers a legitimate write channel for their output is the right call. The
  scope is narrow and predictable; doesn't compromise the read-only discipline for code.
- **Orchestrator's write scope is framework dirs only; coder is denied framework dirs** —
  clean mirror enforcement of the orchestrator pattern.

## Would change (in priority order)

1. **Keep `deployer` (or `release-engineer`) separate from `infra-engineer`.** Merging
   them gives one agent both IaC authorship *and* production deploy commands
   (`git tag`, `npm publish`, `wrangler deploy`). Deploys are the highest-risk action
   in any project and benefit from a dedicated agent whose system prompt enforces
   dry-run + explicit confirm + rollback rehearsal. `infra-engineer` should be about
   writing/planning IaC; `deployer` about applying it. Cost: one extra agent config.
   Benefit: restraint where it matters most.

2. **Rethink the 3 browser agents** (`ui-ux-designer`, `ui-ux-tester`, `workflow-tester`).
   Three agents out of ten dedicated to UI-browser work is heavy unless this project's
   domain is specifically browser-UI-driven. If it is, keep them. If not, collapse to
   two: `ui-engineer` (designer + component tests) + `e2e-tester` (user-flow tests).
   Also: `ui-ux-tester` and `workflow-tester` as currently described don't clearly
   differentiate — one sentence each saying what distinct scope they own would help.

3. **Reintroduce an `explorer` / `researcher` agent.** Not present in the final 10.
   Orchestrator does read-only search, so this is arguably redundant — but a
   dedicated deep-investigation agent has different discipline: structured
   findings, explicit unknowns, no jumping to conclusions. For Claude Code this is
   partially covered by the built-in `Explore` subagent, so Claude can survive
   without it. Kimi/Kiro may want it explicitly.

4. **Enumerate "test files" concretely.** `tester`'s write scope says "test files +
   `.ai/reports/`". Nail down what counts: `tests/**`, `**/*.test.*`,
   `**/*.spec.*`, `**/__tests__/**`, `conftest.py`, `jest.config.*`, `pytest.ini`,
   `.coveragerc`. Ambiguity here will leak into agent failures.

5. **Reviewer has `fs_write` scoped to `.ai/reports/`.** Good — but to prevent
   scope creep, the reviewer's system prompt should explicitly forbid editing the
   code under review. The tool is technically there (permission says
   `.ai/reports/`); the prompt needs to reinforce it.

## Gaps / risks

- **`.ai/reports/` is a new folder** — not yet created, not yet documented. Needs:
  (a) directory created, (b) `.ai/reports/README.md` with naming convention
  (`<agent>-<YYYY-MM-DD>-<slug>.md`?), (c) decision on whether reports archive
  over time like the activity log. Without this, diagnosers won't know where/how
  to write.
- **Path-restriction enforcement is CLI-dependent.** Kiro's native
  `toolsSettings.fs_write.allowedPaths` is the cleanest. Claude has no native
  per-agent path scoping on `Edit`/`Write` — it falls back to `permissions.deny`
  rules (session-scoped, not per-subagent). Kimi has no native path restriction
  at all — must be enforced by prompt discipline. The catalog should note which
  restrictions are hard-enforced vs prompt-enforced per CLI.
- **Agent count vs actual project needs.** 10 agents is maintenance surface.
  My recommendation still stands: land `orchestrator` + `coder` + `reviewer` +
  one Tier-1 specialist first. Add others when a real task demands one, not
  speculatively. This catalog sets the target shape; the shipping order should
  be demand-driven.
- **MCP scoping per agent is untested.** Browser tools (likely MCP-provided)
  should be listed as individual `mcp__browser__*` tools in the UI agents'
  frontmatter — but whether Claude's whitelist respects per-tool MCP filtering
  needs a dry-run before we commit.

## Claude-specific implementation concerns

1. **Path-scoped writes** are the biggest open item. Claude's `tools:` frontmatter
   can include or exclude `Edit`/`Write` entirely, but cannot limit them to
   specific paths. Workarounds, in order of preference:
   - `permissions.deny` rules in `.claude/settings.json` — session-global;
     effective if the only agent that needs unscoped write is `coder` and everyone
     else denies writes to the restricted paths.
   - System-prompt discipline in each Tier-1 agent — weaker, but cheap.
   - Hook-based enforcement (`PreToolUse` rejects writes outside the agent's
     scope) — heavy, most robust.
   Recommend: start with system-prompt discipline + a single project-wide
   `permissions.deny` for `.env`/`secrets/**`. Upgrade to hook-based if we see
   drift in practice.
2. **Claude's built-in subagents** (`Explore`, `Plan`, `general-purpose`) cover
   some of this territory for free. The custom catalog should not duplicate them
   — e.g. don't build a `researcher` agent in Claude when `Explore` exists.
   The cross-CLI catalog is the abstraction; the Claude implementation leans on
   built-ins where applicable.
3. **Main-thread agent = orchestrator** via `"agent": "orchestrator"` in
   `.claude/settings.json`. Swapping the main-thread agent requires settings
   edit + session restart. Not a dealbreaker, but worth noting — this isn't a
   live switch like Kiro's `--agent` flag.
4. **MCP tool whitelisting** via agent frontmatter is the expected mechanism for
   giving UI agents browser tools but not giving them to `reviewer`. Confirm in
   dry-run that `tools: mcp__browser__*` (or per-tool listings) actually scopes
   correctly — if not, we need a different mechanism.
5. **Subagents run serial from Claude's orchestrator** (no parallel fan-out in
   the main Agent-tool flow). If the catalog assumes parallel execution for any
   workflow, that assumption breaks in Claude. Kiro's DAG pipelines do it
   natively; Claude's orchestrator would chain serially.

## Bottom line

Shape is ~90% right. My two real pushbacks: **keep `deployer` separate** (risk
justifies the extra config), and **validate the 3 browser agents against
actual UI-work volume** before committing to three of ten slots. Everything else
is polish — clarify "test files", stand up `.ai/reports/` before the first
diagnoser writes there, and flag the Claude-specific enforcement-gap honestly
so we don't ship an agent that can silently violate its declared scope.

Happy to support whichever direction the user lands on.
