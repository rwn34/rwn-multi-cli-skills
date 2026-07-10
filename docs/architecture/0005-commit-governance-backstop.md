# 5. Git Pre-Commit Backstop — Universal Cross-CLI Commit Guard

## Status

Accepted (2026-07-09)

## Amendment (2026-07-10): Claude fleet-commit of SSOT replica steering

The cross-CLI guard (Decision item 4) blocks committer `claude-code` from
committing paths inside another CLI's config dir. That is correct for genuine
wrong-CLI writes, but it also blocks the routine case where an SSOT source under
`.ai/instructions/**` changes and its generated replicas under `.kimi/steering/`
and `.kiro/steering/` must be committed to stay in sync. Kimi and Kiro CAN
self-commit their own steering when running interactively with a shell-capable
subagent — both did so on 2026-07-10 (Kimi committed `.kimi/steering/*` as
committer `kimi-cli`; Kiro committed `.kiro/steering/00-ai-contract.md` as commit
`052abd0`, hook passing without `--no-verify`). But that lane is NOT proven
reliable on the **headless self-driving pane-runner path** (the autonomous mode
ADR-0008/0009 describe), where a shell or hooks may be unavailable. On that
autonomous fleet path Claude is the fleet's git operator and should commit SSOT
replica syncs directly rather than block on a per-CLI handoff round-trip — yet the
guard blocked it from committing those replicas. This amendment carves a narrow exception: `claude-code` may
commit `.kimi/steering/` and `.kiro/steering/` paths **only** when they are
SSOT replicas listed in the replica registry `.ai/sync.md` (source → destination
map, generated from `.ai/instructions/**`). All non-replica paths in another
CLI's dir stay blocked. This section is the enforcement contract that the
`scripts/git-hooks/pre-commit` implementation must match. **Follow-up (separate
task):** `scripts/git-hooks/pre-commit` and `scripts/git-hooks/test-pre-commit.sh`
MUST be updated to implement and cover this exception.

## Context

The framework advertised a "hard block" enforcement layer: per-CLI hooks
(`.claude/hooks/`, `.kimi/hooks/`, `.kiro/hooks/`) plus an OpenCode guard plugin
that reject writes to another CLI's territory, sensitive files, and
non-allowlisted root files (see ADR-0001, ADR-0002, ADR-0004).

The cross-CLI validation campaign of 2026-07-09
(`.ai/reports/claude-2026-07-09-validation-rollup.md`) proved by live execution
that this claim only holds for **Claude (post-fix)** and **OpenCode**. The
per-CLI hooks **do not fire** in the modes that matter most for automation:

- **Kimi headless (`kimi -p`)** executes **zero hooks** — a runtime limitation,
  not a config bug.
- **Kiro under `--trust-all-tools`** (mandatory for `--no-interactive`) runs with
  `preToolUse` hooks and `allowedPaths` **inert**; bare `kiro-cli chat` runs a
  hookless default agent.
- **Subagent** tool calls in several runtimes never trigger the guards.
- The per-CLI bash hooks also previously **failed open** because `python3` on the
  host is a WindowsApps alias stub (empty stdout, exit 0) — every rule became a
  no-op. Fixed for Claude, but the failure class is a warning against relying on
  python in any enforcement path.

The result: a headless or subagent Kimi/Kiro session fed an adversarial or buggy
brief could write into another CLI's config dir, commit a secret, or drop a
non-allowlisted root file **with no mechanical net**, while CI stayed green
(the unit suites test relative paths and config tool-names, not live runtime
write-blocking).

Both Kiro and Claude independently converged on the same fix: the ONE mechanical
layer that every CLI passes through regardless of runtime hook behavior is the
`git commit` invocation itself.

## Decision

Add a **repo-level git pre-commit hook** at `scripts/git-hooks/pre-commit`,
versioned in the repo and wired via `git config core.hooksPath scripts/git-hooks`.
It is pure bash/sed with **no python dependency** (deliberately, given the
fail-open history).

On every `git commit` it inspects the staged set (`git diff --cached`) and
rejects (exit 1, listing offending paths) when any staged path violates:

1. **Sensitive files** — `.env*`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, `id_rsa*`,
   `id_ed25519*`, `.aws/`, `.ssh/`, `secrets.*`, `credentials*` — always,
   regardless of committer.
2. **Root-file policy** — a newly-added file at repo root not in the ADR-0001
   allowlist (same allowlist as `.claude/hooks/pretool-write-edit.sh` Rule 3).
3. **Removed-graph tombstones** — anything under `.kimigraph/` or `.kirograph/`
   (tools removed per ADR-0003 amendment).
4. **Cross-CLI territory** — committer identity from `git config user.name`
   (`claude-code`, `kimi-cli`, `kiro-cli`, `opencode`) maps to allowed dirs;
   staged paths inside another CLI's config dir are rejected. OpenCode's lane is
   a strict whitelist (`.ai/activity/log.md`, `.ai/reports/`, `.ai/handoffs/`).
   An unset/unknown committer gets the **strictest** interpretation (block all
   CLI-owned config dirs). Shared `.ai/` is writable by all (except OpenCode's
   whitelist). Source writes by claude/kimi/kiro are fine — this catches
   wrong-CLI writes to config dirs, not every source file.

   **Exception — SSOT replica steering *[added 2026-07-10]*:** committer
   `claude-code` MAY commit files under `.kimi/steering/` and `.kiro/steering/`
   **when and only when** those paths are SSOT-tracked replicas enumerated in
   `.ai/sync.md` (i.e. generated from `.ai/instructions/**`). Non-replica paths
   in another CLI's config dir remain blocked for `claude-code`. Rationale:
   Kimi/Kiro can self-commit their steering interactively (Kimi as `kimi-cli`;
   Kiro as commit `052abd0`, both on 2026-07-10), but not reliably on the headless
   self-driving pane-runner path — where Claude is the fleet's git operator and
   the replicas' upstream is shared `.ai/` state Claude already owns. This
   **narrows** the cross-CLI guard to the replica set — it does not remove it.

The hook **fails CLOSED**: if it cannot enumerate staged files it exits 1.

Wiring is per-clone (`core.hooksPath` is never inherited), so the installers set
it explicitly: `scripts/install-template.sh` (bash) and
`tools/multi-cli-install` (Node — `wireGitHooks`) both copy `scripts/git-hooks/`
into the target and run `git config core.hooksPath scripts/git-hooks`.

The owner may bypass in a pinch with git's standard `git commit --no-verify`.

## Consequences

- **Positive:** one mechanical layer reaches every CLI in every runtime —
  headless, trust-all, subagent, hookless-default — because they all commit
  through git. This closes the Kimi/Kiro headless gap at a single chokepoint.
- **Positive:** it stops a bad *commit* — the action that actually corrupts
  shared cross-CLI state — even when the bad *write* slipped past prompt/hook
  layers. Defense-in-depth that is honest about its layers.
- **Positive:** no python; cannot fail open via the WindowsApps-stub class of bug.
- **Negative:** it runs on the human owner's commits too. `--no-verify` is the
  intended escape hatch; the guard errs toward blocking.
- **Negative:** `core.hooksPath` is per-clone — a fresh clone that skips the
  installer has no backstop until wired. The installers automate this, but manual
  clones must run `git config core.hooksPath scripts/git-hooks`.
- **This complements, does not replace,** the per-CLI hooks (which still block
  bad *writes* interactively) and the prompt-level SAFETY RULES (which stop most
  bad writes at the model). It is the last mechanical line before shared state
  is corrupted.

## References

- `.ai/reports/claude-2026-07-09-validation-rollup.md` §4 — the convergent-fix rationale
- `docs/architecture/0001-root-file-exceptions.md` — root-file allowlist (reused verbatim)
- `docs/architecture/0002-*` / `0003-*` / `0004-*` — CLI lanes, graph removal, worktree topology
- `.claude/hooks/pretool-write-edit.sh` — the python-independent extraction pattern this hook mirrors
- `scripts/git-hooks/pre-commit`, `scripts/git-hooks/test-pre-commit.sh` — the implementation + tests. *[2026-07-10] These MUST be updated to implement the SSOT-replica-steering exception (see Amendment above) — separate follow-up task.*
- `.ai/sync.md` — the SSOT source → replica registry that scopes the 2026-07-10 exception
