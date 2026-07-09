# 6. Kiro CLI v3 Migration and Headless-by-Default Operating Principle

## Status

Accepted (2026-07-09)

This ADR records two linked decisions. Decision 2 (headless-by-default) is the
operating principle that makes Decision 1 (Kiro v3) a first-class requirement
rather than an optimization. It is the natural complement to ADR-0005 (the
git pre-commit backstop) — that ADR added a version-agnostic mechanical floor
under *every* CLI; this ADR raises the Kiro-specific ceiling and states the
reason both layers exist.

## Context

The cross-CLI validation campaign of 2026-07-09
(`.ai/reports/claude-2026-07-09-validation-rollup.md`) proved by live execution
that Kiro under v2 has **no mechanical headless enforcement**:

- `--trust-all-tools` (mandatory for `--no-interactive`) runs with `preToolUse`
  hooks and `allowedPaths` **inert** — only prompt-level SAFETY RULES stopped an
  adversarial `.claude/` write in the T-K3 probe.
- Subagent hook calls never fire.
- Bare `kiro-cli chat` runs a hookless built-in default agent.
- The v2 guards additionally used the python fail-open pattern (host `python3`
  is a WindowsApps alias stub → empty stdout, exit 0 → every rule a no-op).

The enforcement matrix (rollup §1) showed Kiro enforcing mechanically **only in
interactive mode**; the automation lane relied entirely on the prompt. This was
the campaign's #1 gap for Kiro.

In response, the owner adopted Kiro CLI v3 (`kiro-cli --v3`, a top-level flag;
pinned in the 4AI-panes pane and the dispatcher, commit `52b31fa`). Per the v3
docs (<https://kiro.dev/docs/cli/v3/>), v3 restructures enforcement to be
declarative and capability-based:

- **`permissions.yaml`** — capability-based, fine-grained, auditable permissions
  that replace `--trust-all-tools` and the `/tools trust` command (both removed).
- **`.kiro/hooks/*.json`** — versioned, standalone hook files (shell-command or
  agent-prompt actions, PascalCase triggers) replacing embedded / `.sh` hooks.
- **Unified Markdown agent config** — replaces the `toolsSettings` field with a
  `permissions` block; tag-based tool selection; inline MCP config supported.

The migration crosses **breaking changes**: v2↔v3 sessions are format-
incompatible (v3 sessions cannot resume in v2), classic non-TUI chat mode is
unsupported under v3, the AWS tool is removed entirely, supervised mode is
eliminated, and Amazon Linux 2 is unsupported.

Separately, the framework's operating posture has been implicit: the owner talks
to the Claude orchestrator, and fleet execution (Kiro / Kimi / OpenCode) runs
headless. The campaign showed why leaving this implicit is dangerous — if
headless is the normal path, then headless enforcement is the *primary* surface,
not an edge case, yet it was the weakest surface for Kimi and Kiro.

## Decision

### Decision 1 — Adopt Kiro CLI v3

Migrate Kiro to the v3 enforcement model:

- Capability-based **`permissions.yaml`** replaces `--trust-all-tools`.
- Versioned **`.kiro/hooks/*.json`** replace the embedded / `.sh` hooks.
- Unified **Markdown agent config** (`permissions` block) replaces
  `toolsSettings`.

The migration is **ADDITIVE**: v3 runs alongside v2 (the v3 engine does not
disturb the existing 2.x install), and the v2 `.sh` guards + `.json` agents are
**KEPT as fallback** until v3 enforcement is live-validated headless.

Rationale: v3 `permissions.yaml` is a declarative, auditable, mechanical layer
that is designed to enforce in headless mode too — directly closing the
campaign's #1 Kiro gap, which the v2 `--trust-all-tools`/hook model could not.

### Decision 2 — Headless-by-default operating principle

Fleet execution is **headless by default**. The owner interacts with the Claude
orchestrator; Claude dispatches Kiro / Kimi / OpenCode headless unless the owner
explicitly asks for an interactive session.

> **If the owner is not explicitly asking for interactive, it is headless.**

Claude infers the mode from the owner's request. Interactive is the explicit
exception, not the default.

The load-bearing consequence: because headless is the default, mechanical
**headless** enforcement is a first-class requirement, not optional. This is
*why* Decision 1 (`permissions.yaml`) matters and *why* the git pre-commit
backstop (ADR-0005) exists. Prompt-level SAFETY RULES are a floor, not the
ceiling.

## Consequences

- The v2 Kiro guard fixes from 2026-07-09 (python-independent extraction,
  fail-CLOSED, suite 52/52) remain the **v2-fallback** enforcement while v2 runs
  alongside v3.
- The git pre-commit backstop (ADR-0005) remains the **version-agnostic floor**
  under both v2 and v3 — every CLI commits through git regardless of runtime hook
  behavior, so it is unaffected by the v2↔v3 split.
- **Re-validation under v3 is required** before the v2 fallback can be retired.
  Retirement is a future ADR gated on live headless proof that `permissions.yaml`
  blocks cross-CLI / sensitive / root-policy writes in `--no-interactive` mode.
- Breaking-change fallout to track during the additive period: session state does
  not carry across v2↔v3; any workflow depending on classic chat mode, the AWS
  tool, or supervised mode must move off it before v2 is retired.
- **Follow-up — Kimi parity:** headless-by-default makes Kimi's gap first-class
  too (`kimi -p` runs zero config hooks — rollup §2). Pursue a Kimi headless-
  enforcement path (e.g. `kimi.plugin.json` lifecycle hooks) to reach parity with
  Kiro v3 and OpenCode. Until then, Kimi headless relies on prompt SAFETY RULES +
  the ADR-0005 git backstop.
- **SSOT sync flag (do not edit here):** the operating-prompt SSOT
  (`.ai/instructions/operating-prompt/principles.md`) should absorb the
  headless-by-default principle in a **later sync** — flagged now, deliberately
  not edited in this commit, to avoid a drift cascade (SSOT + its replica
  channels) landing atop the ADR. Track as a follow-up sync task.

## References

- `.ai/reports/claude-2026-07-09-validation-rollup.md` §1–§2 — the enforcement
  matrix and Kiro-specific findings this ADR responds to
- `docs/architecture/0005-commit-governance-backstop.md` — the complementary
  version-agnostic git pre-commit floor
- `docs/architecture/0002-cli-role-topology.md` — Kiro's executor + tester role lane
- `docs/architecture/0004-worktree-multi-project-topology.md` — worktree-confinement guards affected by the hook migration
- <https://kiro.dev/docs/cli/v3/> — Kiro CLI v3: invocation, `permissions.yaml`,
  `.kiro/hooks/*.json`, Markdown agent config, breaking changes
- commit `52b31fa` — `kiro-cli --v3` pinned in the 4AI-panes pane + dispatcher
- `.ai/instructions/operating-prompt/principles.md` — SSOT to absorb the
  headless-by-default principle in a later sync (flagged above)
