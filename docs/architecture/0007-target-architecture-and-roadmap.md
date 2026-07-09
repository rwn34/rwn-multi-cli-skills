# 7. Target Architecture and Roadmap — The Framework's North Star

## Status

Accepted (owner-approved 2026-07-09)

This ADR is the framework's north star. It sits above ADR-0005 (git pre-commit
backstop) and ADR-0006 (Kiro v3 + headless-by-default): those two record the
mechanical floor and the Kiro-specific ceiling discovered on 2026-07-09; this
ADR ranks the enforcement layers into an authoritative model, fixes the Kiro
version stance, and sets the roadmap that the rest of the framework's work
should track against.

## Context

A single day (2026-07-09) — the OpenCode swap, the cross-CLI validation campaign
(`.ai/reports/claude-2026-07-09-validation-rollup.md`), and the Kiro v3
migration investigation (`.ai/reports/kiro-cli-2026-07-09-v3-migration.md`) —
converged on one uncomfortable truth: **per-CLI mechanical enforcement is
inconsistent and version-fragile.** Proven by live execution, not unit suites:

- **Kimi headless (`kimi -p`) runs zero hooks** — a runtime limitation, not a
  config bug.
- **Kiro v2 under `--trust-all-tools`** (mandatory for `--no-interactive`) makes
  `preToolUse` hooks and `allowedPaths` **inert**.
- **Kiro v3 has NO headless surface at all** (v3 docs "Known gaps": the legacy
  non-TUI mode does not support the v3 engine) **and `kiro-cli --v3` rejects
  `--agent`** — so the documented v3 launch cannot even carry the guard-bearing
  orchestrator agent pin.
- The per-CLI bash hooks previously **failed open** because host `python3` is a
  WindowsApps alias stub (empty stdout, exit 0) — every rule became a no-op until
  the 2026-07-09 python-independent rewrite.

Two further facts frame the decision. First, the owner set **headless-by-default**
as the operating posture (ADR-0006 Decision 2): fleet execution runs headless
unless interactive is explicitly requested — which makes the weakest surface
(headless enforcement) the *primary* one. Second, the owner reviewed and
**greenlit the target architecture and roadmap** recorded below on 2026-07-09.

The strategic question this raises: should the framework keep chasing per-CLI
mechanical parity across every runtime and version, or accept that as infeasible
and invest in a uniform chokepoint instead? This ADR answers that.

## Decision

### 1. Enforcement model — authoritative ranking

The framework's mechanical guarantees are layered and **ranked**:

1. **PRIMARY mechanical guarantee** — the git pre-commit backstop (ADR-0005)
   **plus a CI gate (still to build, see Roadmap P2)**. This layer is uniform
   across **every CLI, every mode, and every version**, because every CLI passes
   through `git commit` and (once built) through CI regardless of its runtime
   hook behavior.
2. **Best-effort defense-in-depth** — per-CLI hooks (`.claude/hooks/`,
   `.kimi/hooks/`), Kiro `permissions.yaml` / agent-md `permissions` block, and
   the OpenCode guard plugin. These are **interactive-strong, headless-varies**
   (Claude and OpenCode enforce in all modes; Kimi and Kiro enforce only
   interactively).
3. **Behavioral floor** — prompt-level SAFETY RULES baked into each executor's
   agent prompt. Soft, but proven to hold under adversarial test (Kiro T-K3).

**Explicit NON-GOAL:** pursuing per-CLI mechanical **headless** parity. It is
proven infeasible — Kiro v3 cannot run headless at all, and Kimi `-p` runs no
hooks — so effort spent forcing every CLI to mechanically block writes in every
headless runtime is effort wasted. The uniform chokepoint (layer 1) is the
answer instead.

### 2. Kiro version stance

- **Framework use stays on Kiro v2.** v2 gives working interactive guards
  (python-independent, fail-closed after the 2026-07-09 fix) plus the ADR-0005
  git backstop underneath every commit.
- **Kiro v3 is deferred.** It is early-access, has no headless surface, and
  `kiro-cli --v3` rejects `--agent` (so it cannot carry the guard-bearing agent
  pin the T-K2 default-agent gap requires).
- **The v3 config stays committed but DORMANT** — `.kiro/agents/orchestrator.md`
  (agent-md `permissions` block), `.kiro/hooks/guards.json`, and the
  `permissions.yaml` template remain in the tree for owner-experimental,
  interactive-only use; they are not on the framework's active enforcement path.
- **Re-adopt when v3 ships a headless surface and an agent-pin surface** — a
  future ADR gated on that live capability.

### 3. Headless-by-default (operating principle, ref ADR-0006)

Fleet execution is headless unless the owner explicitly requests interactive.
This is precisely **why** the backstop-plus-CI model (Decision 1, layer 1)
matters: the default execution path is the one where per-CLI hooks are weakest,
so the uniform chokepoint carries the load.

### 4. Roadmap

- **P0 — Merge the truthful baseline.** Land the enforcement fixes, Kiro v2 as
  the framework version, and honest docs (no "hard block" overclaim).
- **P1 — Visible per-pane dispatch (Approach A).** cwd / multi-tab-scoped, with a
  per-project claim-lock. This is the owner's **core UX expectation** and ranks
  ahead of parity polish.
- **P2 — The real net.** Build the CI gate (layer 1's second half); ship an
  installer-driven launcher to kill manual-copy drift; add dispatcher flag-probe
  and version pins to stop silent version breakage.
- **P3 — Optional.** Kimi `kimi.plugin.json` enforcement; Kiro v3 re-adoption
  (when it ships headless + agent-pin); spec workflows.

### 5. Open question (tracked, not decided here)

**CLI-count right-sizing.** A post-merge, data-backed analysis — usage patterns,
Kimi/Kiro capability overlap, maintenance cost — will inform whether four CLIs is
the optimal fleet size. This ADR does **not** decide it; it records that the
question is open and how it will be answered.

## Consequences

- **Less effort chasing per-CLI enforcement.** The NON-GOAL frees the framework
  from an infeasible target and redirects that effort to the uniform chokepoint.
- **CI becomes load-bearing.** Layer 1 is only half-built until the CI gate ships
  (P2). Until then the git pre-commit backstop is the sole uniform mechanical
  layer — a per-clone hook that a fresh unwired clone lacks.
- **Version-pinning discipline is required.** The dispatcher flag-probe and
  version pins (P2) exist because silent version breakage (e.g. `--v3` rejecting
  `--agent`) is now a known failure class.
- **The framework's honest security posture is documented.** No "hard block"
  overclaim survives — the ranking and the NON-GOAL state plainly what is and is
  not mechanically guaranteed.
- **SSOT sync flag (do NOT edit in this ADR):** the operating-prompt SSOT
  (`.ai/instructions/operating-prompt/principles.md`) should absorb the
  enforcement-model ranking (Decision 1) and headless-by-default (Decision 3) in
  a **later, drift-safe sync** — flagged here, deliberately not edited, to avoid
  a drift cascade (SSOT plus its replica channels) landing atop the ADR.

## References

- `docs/architecture/0002-cli-role-topology.md` — CLI role lanes
- `docs/architecture/0003-*` — single-graph topology / graph removal
- `docs/architecture/0004-worktree-multi-project-topology.md` — worktree confinement
- `docs/architecture/0005-commit-governance-backstop.md` — the git pre-commit
  backstop (layer 1, first half)
- `docs/architecture/0006-kiro-v3-and-headless-default.md` (incl. 2026-07-09
  amendment) — Kiro v3 findings + headless-by-default principle
- `.ai/reports/claude-2026-07-09-validation-rollup.md` — the enforcement-reality
  matrix and GO/NO-GO this ADR builds on
- `.ai/reports/kiro-cli-2026-07-09-v3-migration.md` — the v3 Findings A/B behind
  the version stance
- `.ai/known-limitations.md` — the enforcement-reality entry (2026-07-09)
- `.ai/instructions/operating-prompt/principles.md` — SSOT to absorb Decision 1
  + Decision 3 in a later sync (flagged above)
</content>
</invoke>
