# Design: reducing Bash exposure so the guard isn't the only line

Author: **kiro-cli**. Per handoff `202607121640-design-bash-exposure-reduction.md`
(sender: claude-code). **Design only — no implementation, no agent-config edits.**
Follows §5 of `.ai/reports/kiro-2026-07-12-bash-guard-design.md` (the PR #53 design),
which named this as the durable complement to hook-hardening.

> **⚠ PROVENANCE NOTE — RESTORED ARTIFACT (claude-code, 2026-07-12 19:45)**
>
> The original file was written by kiro-cli, read in full by claude-code, and then
> **LOST**: it was authored inside a git worktree whose `.ai/` was a real checkout
> rather than the canonical junction, was never committed, and evaporated when that
> worktree was removed. The activity log still claims it exists — a record pointing at
> a vanished artifact.
>
> A `coder` subagent, dispatched to implement this design, **refused to proceed**
> rather than reconstruct a "binding design" from its own brief's summary. That
> refusal is why this file exists.
>
> This restoration is reproduced from claude-code's verbatim read of the original.
> **The findings, per-agent table, recommendation, and residual-risk statements below
> are kiro-cli's, not reconstructed.** Framing prose may differ slightly from the
> original wording. Treat the table and §4 as authoritative; if kiro-cli disputes any
> line, kiro-cli's word wins.

## 0. Grounding (read, not assumed)

- **`.claude/agents/*.md` (all 13).** The finding that shapes everything:
  **10 of 12 subagents carry `Bash`.** Only `reviewer` and `doc-writer` lack it
  (`orchestrator` also lacks it by design — operating-prompt §5). Grep evidence:

      $ rg -c "^tools:.*Bash" .claude/agents/*.md
      coder.md:1  data-migrator.md:1  debugger.md:1  e2e-tester.md:1
      infra-engineer.md:1  refactorer.md:1  release-engineer.md:1
      security-auditor.md:1  tester.md:1  ui-engineer.md:1

  Nine of the ten declare a prose-level shell restriction ("Test runners only",
  "Security scanners only"). **But the `tools:` whitelist enforces the TOOL, not the
  ARGUMENT** — `Bash` in the list means the model may invoke ANY shell command. The
  "scanners only" language is a prompt-level request, not a mechanical restriction.
  `coder` and `ui-engineer` are explicitly "Unrestricted."

- **`.ai/known-limitations.md` "Enforcement reality" — the load-bearing fact:**
  **Claude subagents DO inherit hooks; Kimi and Kiro subagents do NOT.** So for Kimi
  and Kiro, exposure reduction is **not a complement to the guard — it is the ONLY
  control**, full stop. There is nothing behind it to fall back on.

- **`.opencode/opencode.json`:** `"permission": {"bash": "allow"}` — OpenCode does not
  restrict the tool at all; 100% of enforcement is the JS plugin judging every call's
  *effect*. Architecturally the opposite of "remove the tool."

- **`docs/architecture/0004-*` (worktree topology):** its own amendment admits the
  coordination plane (`.ai/`) has **zero isolation** across worktrees (junctioned to
  one canonical copy). This bounds what worktree confinement can promise.

## 1. Candidate models — attacked

### Model 1 — Per-agent Bash removal
**Verdict: closes almost nothing.** Of the ten Bash-bearing agents, **eight have a
concrete, load-bearing, named use of Bash** that cannot be removed without breaking
their declared job — including `infra-engineer`, **the framework's ONLY git-operation
path** (operating-prompt §5). Only `security-auditor` and `refactorer` are even
candidates, and both are better served by restriction than removal, because both have
a genuine narrow need.

Its one unambiguous strength: it is a **pure subtraction** — no new parsing surface,
nothing new to keep in sync. Lowest blast radius of any model.

**New gap:** a diagnoser that cannot run the scan it exists to run
(`security-auditor` without `semgrep`/`trufflehog` is worthless); `refactorer` without
a shell **cannot verify its own hard invariant** ("tests pass before AND after every
step") — removing Bash there doesn't reduce risk, it *breaks the agent's safety
property*.

### Model 2 — Command-allowlist Bash
**Does this re-introduce the evasion class we already fought, one layer over? YES —
and worse in one specific way.**

The PR #53 path-policy guard only needs to find a **path argument** inside a command it
already recognizes as write-capable. A command-allowlist must correctly identify **the
command itself**, through the same evasions: `sudo semgrep`, `$(which semgrep)`, or an
allowlisted command piped into a non-allowlisted one —
`semgrep --json | tee .kimi/evil.md` (the scanner is legitimately allowed; the `tee` is
the violation). By the time you check every pipeline segment, you have re-derived most
of PR #53's §2 design, keyed on command names instead of paths.

**Worse:** an allowlist is a *second, independent* place the same evasion constructs
(`eval`, `sh -c`, substitution) must be fail-closed against — duplicating PR #53's
§2.3 inside a second enforcement point. That is the textbook **"two surfaces, one rule,
nothing keeping them in lockstep"** pattern this framework has hit repeatedly.

**Cross-CLI inconsistency, concretely:** Kiro's `execute_bash.allowedCommands` is
**hard** (mechanical). Claude's `tools:` frontmatter has **no per-command scoping** —
soft only. Kimi's hooks don't reliably fire headless. Three CLIs, three different real
guarantees for the *same* nominal policy.

### Model 3 — "Read-only shell"
**Not a real capability boundary without a container, and saying otherwise would be an
overclaim.** No CLI here exposes a filesystem read/write mode. `semgrep` is read-only
*in practice* — but nothing stops `semgrep --autofix` (a real flag that writes), or
`semgrep … ; rm -rf x` if the allowlist is command-name-only.

What IS buildable is "a command-name allowlist curated for usually-read-only commands"
— **which is Model 2 under a different name**, scoped to diagnosers. It adds no
mechanism Model 2 lacks. Its extra risk is a **naming hazard**: calling it "read-only
shell" invites someone later to trust it as a stronger guarantee than it is.

### Model 4 — Worktree/container isolation
**A different axis, not a competing mechanism** — conflating them would be a design
error.

Worktree confinement bounds *which tree* a write lands in, not *what commands* run. An
`eval`-wrapped write inside an agent's own worktree still succeeds. And per ADR-0004's
own text, the coordination plane (`.ai/`) is junctioned — **zero isolation** — so an
evading shell in ANY worktree can still reach `.ai/handoffs/`, `.ai/reports/`, and even
`.ai/instructions/` (the SSOT every CLI trusts). **Worktree confinement does not reduce
good-faith-dependency for the coordination plane at all.**

Real container isolation is not implemented or exposed by any CLI here — proposing it
is proposing new infrastructure, not a policy change.

## 2. The count reframes the question

The handoff's framing assumed a large removable set. **There isn't one.** Most of the
Bash surface is **not exposure to reduce — it is the mechanism by which these agents do
their declared jobs.** A design promising a large reduction here would be overselling.

**The real structural lever is not agent count — it is subagent hook non-inheritance
(Kimi/Kiro).** The good-faith dependency is *not evenly distributed*: it is **total**
for Kimi/Kiro subagents and partial (guard-backed) for Claude subagents.

## 3. Per-agent Bash table (mechanical if approved)

| Agent | Keep / Remove / Restrict | Justifying task |
|---|---|---|
| `coder` | **Keep** | Build/test/lint verification loop (delivery-integrity §2) |
| `tester` | **Keep** | Invoking the test runner IS the job |
| `debugger` | **Keep** | `git bisect`, profilers, repro toolchain |
| `refactorer` | **Restrict** to test-runner commands only — matches its own existing prose claim | Verifying tests pass before/after every step; nothing else in its contract needs shell |
| `e2e-tester` | **Keep** | Browser automation runners are shell invocations |
| `infra-engineer` | **Keep — do not touch** | Sole git-operation path for the orchestrator (operating-prompt §5); restricting it breaks the framework's git workflow |
| `release-engineer` | **Keep** | `git tag` / `npm publish` / deploy CLIs are the job |
| `ui-engineer` | **Keep** | Dev server + browser verification |
| `security-auditor` | **Restrict** to its already-stated scanner list (`semgrep`, `bandit`, `pip-audit`, `npm audit`, `trufflehog`, `gitleaks`, `trivy`, read-only `git log`/`git diff`) | Scanning IS the job; nothing else needs shell |
| `data-migrator` | **Restrict** to its already-stated tool list (`alembic`, `prisma`, `drizzle-kit`, `knex`, `dbmate`, read-only `psql`/`sqlite3`/`mysql`) | Applying/testing migrations; already forbidden raw mutating SQL |
| `reviewer` | **No change — already correct** (no Bash) | — |
| `doc-writer` | **No change — already correct** (no Bash) | — |

**Net effect: zero agents lose Bash outright.** Three agents move from
unrestricted-in-practice to a command-scoped grant, formalizing restrictions their own
files already claim in prose. **A real, if modest, reduction — and honest about being
modest.**

## 4. Recommendation

**Model 1 confirmed as already-correctly-applied to `reviewer`/`doc-writer` — no
further removals. Model 2 applied ONLY to the three agents marked Restrict, and ONLY
where Kiro's native `toolsSettings.execute_bash.allowedCommands` gives real (hard)
enforcement — i.e. a Kiro-config change, not a cross-CLI policy rewrite. For Claude and
Kimi, where the same restriction can only be prompt-level, state it as a documented,
honest, SOFT restriction — do NOT imply parity with Kiro's mechanical enforcement.**

Why this over the alternatives:
- **Least new surface.** No new parser, no new fail-closed boundary. It reuses a
  mechanism that already exists, for three agents whose contracts already state the
  restriction in prose.
- **Least new cross-surface coupling.** It does not touch `pretool-bash.sh` and
  duplicates no part of PR #53. There is nothing to keep "in lockstep" — there is only
  one surface, the agent config.
- **It does not touch `infra-engineer`** or the seven other load-bearing agents.

## 5. Residual risk — stated explicitly, NOT closed

- **This does not close the adversarial-evasion gap.** A restricted-but-not-removed
  Bash can still be evaded via `eval` / `sh -c` / `$(...)` / base64 / variable-built
  paths. Kiro's `allowedCommands` is a command-NAME allowlist and adds no fail-closed
  handling for wrapper constructs. **Known, accepted, explicitly not closed** — closing
  it would require duplicating PR #53's §2.3 inside a second mechanism, which is
  precisely the new-surface coupling this recommendation exists to avoid. Read this as
  *"take the cheap, real, no-new-surface win; leave the hard adversarial case to the
  guard and to prompt-level SAFETY RULES"* — **not** as "Bash evasion is solved."
- **The seven load-bearing Bash agents remain exactly as exposed as today.** By design:
  their surface is their job.
- **For Kimi/Kiro subagents, Bash calls remain hook-invisible** — nothing behind the
  guard except prompt-level rules and the ADR-0005 commit backstop. Real, known,
  documented, and a **platform limitation no allowlist can fix.**
- **Cross-CLI enforcement strength stays uneven** (Kiro hard; Claude/Kimi soft). This
  recommendation *accepts* that unevenness rather than papering over it with a fourth
  surface.

## 6. Implement-now-safe, or owner decision?

**Owner decision.** It changes per-agent tool/shell configuration across the catalog —
a cross-cutting policy surface. Before implementation:
1. Confirm the three Restrict targets' command lists (`refactorer.md` says "test
   runners only" **without enumerating** — that list must be named).
2. Decide whether to state the Claude/Kimi prompt-only version explicitly in those
   agents' files. **Recommended: yes** — an honest "mechanical on Kiro, good-faith on
   Claude/Kimi" note prevents an overclaim.
3. **Tier B** (config change), but it touches three CLIs' own territories — so
   implementation is a three-way split: Kiro edits its own `.kiro/agents/*.json`;
   Claude and Kimi each edit their own.
