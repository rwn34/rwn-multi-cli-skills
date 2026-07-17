# `.ai/tools/` — framework invariant checks

Utility scripts that audit the multi-CLI framework.

## `sync-replicas.sh` — the ONE replica generator and drift authority

`.ai/instructions/` is the source of truth; the CLI-native files under
`.claude/skills/**`, `.kimi/steering/**`, `.kimi/resource/**`, `.kiro/steering/**`
and `.kiro/skills/**` are **build artifacts** regenerated from it. The source →
destination map (24 replicas) is declared in ONE place: `.ai/sync.md`.

**Usage (from repo root):**

```bash
bash .ai/tools/sync-replicas.sh           # regenerate all replicas in place
bash .ai/tools/sync-replicas.sh --check   # drift report only; exit 1 on drift
```

`--check` regenerates every replica into a temp tree and diffs it against the
committed one — the checker and the generator are the same code, so they can
never disagree (ADR-0005 second amendment).

**Exit codes:**
- default mode: `0` on success; non-zero (fail closed) on any error
- `--check`: `0` iff all 24 replicas match their source; `1` on drift, with
  each offending pair printed and the copy-pasteable fix on stderr

**Output (`--check`):**
- `Checked: N replicas, Drift: M` summary line
- `DRIFT: <src> -> <dst> (N lines differ)` for each drifted pair
- `MISSING: <path>` for any source or destination file that doesn't exist

**Preamble preservation:**
The eight `SKILL.md` replicas carry CLI-specific frontmatter + provenance
comments above the body copied from SSOT. Regeneration keeps everything
through the first `<!-- SSOT: ... -->` line plus one trailing blank line, and
replaces only the body below it.

**Junction safety (ADR-0004):** in-place regeneration refuses to write through
any symlink or Windows-junction ancestor of a replica path, and refuses any
registry destination under `.ai/` outright — the reverse-write class that
clobbered the primary checkout's live `.ai/` on 2026-07-12/13. `--check` and
`--dest-root` write only to their explicit sink and are not guarded.

## `check-ssot-drift.sh` — compatibility shim

Kept for existing callers and docs. It `exec`s
`sync-replicas.sh --check` with the identical output contract and exit codes.
New call sites should use the authoritative entry point directly.

## `check-log-superset.sh` — activity-log entry-loss gate

Verifies that a candidate `.ai/activity/log.md` would not DROP any entry
headers that already exist in `origin/main`, the current working tree, or any
`.ai/activity/log.md.bak` / `.ai/activity/log.md.KEEP*` file.

**Usage (from repo root):**

```bash
bash .ai/tools/check-log-superset.sh <candidate-log.md>
```

**Exit codes:**
- `0` iff the candidate contains every `^## ` header from every source.
- `1` on any missing entry, with the verbatim lost headers listed per source.
- `2` on setup/argument errors (missing argument, unreadable candidate, etc.).

**Why this exists:** the log is prepend-order and its timestamps are
annotations, so diffing a recovery candidate against `main` is structurally
blind to entries that exist on disk but in no commit. PR #107 nearly lost two
such entries because an "additions-only" diff against `main` read green while
the true working-tree diff showed deletions. This checker compares entry
headers as a **set**, not line counts.

**Pre-commit:** `scripts/git-hooks/pre-commit` runs this on any staged
`.ai/activity/log.md` and rejects the commit if the staged content is not a
strict superset of all sources.

## `guard-ai-destructive.sh` — junction-aware destructive-op guard

Blocks destructive commands while a worktree's `.ai/` is still a junction or
symlink into the canonical coordination plane. Prevents the 2026-07-16 class
of incident where `git clean -fd` or `git worktree remove --force` followed
the junction and deleted shared `.ai/` state.

**Usage:**

```bash
bash .ai/tools/guard-ai-destructive.sh --check [path]   # exit 0 if safe
bash .ai/tools/guard-ai-destructive.sh git clean -fd    # run if safe
bash .ai/tools/guard-ai-destructive.sh rm -rf junk
```

**Safe paths:** `.ai/` absent, or a normal directory. **Blocked paths:** `.ai/`
is a symlink or Windows junction. Use `scripts/wt-bootstrap.sh --remove` to
unmount `.ai/` and remove a worktree safely.

## `checkpoint-ai.sh` — mechanical `.ai/` durability commits

Commits the current state of `.ai/` with a signless, mechanical message so the
shared coordination plane is recoverable from git history. Designed to be called
manually, from a scheduler, or at the end of a dispatch cycle.

**Usage:**

```bash
bash .ai/tools/checkpoint-ai.sh              # checkpoint current repo
bash .ai/tools/checkpoint-ai.sh --dry-run    # preview only
```

**Guards:**
- Refuses linked worktrees (the junction makes `.ai/` look like local changes).
- Refuses if non-`.ai/` changes are present.
- Only commits paths under `.ai/`.

## `fleet-health.sh` — pane liveness and queue-dir watchdog

Cross-checks heartbeat sidecars (`.ai/.heartbeat-<cli>.json`) against open
handoff queues and classifies each pane as OK, DOWN (idle), STALL, or WEDGED.
Also verifies every `to-<actor>/{open,review,done}/` queue directory exists.

**Usage:**

```bash
bash .ai/tools/fleet-health.sh [project-dir]
```

Exit `1` only on STALL/WEDGED/missing queue dir; internal checker errors fail
open.

## When to run

- **CI** — wired into `framework-check.yml` and `gates.yml`: an SSOT-changing
  PR without regenerated replicas fails with the fix printed.
- **Pre-commit** — `scripts/git-hooks/pre-commit` regenerates-and-compares on
  any staged `.ai/instructions/**` change and refuses stale commits (the
  `claude-code` committer auto-stages the regenerated replicas instead).
- **Ad hoc** — whenever `.ai/instructions/` is edited: run the generator,
  commit SSOT + replicas together.
- **Before destructive ops** — run `guard-ai-destructive.sh --check <worktree>`.
- **Durability** — run `checkpoint-ai.sh` after heavy handoff activity or from
  a periodic scheduler.
- **Fleet monitoring** — run `fleet-health.sh` to detect stale panes or missing
  queue directories.

Runtime: under 2 seconds on the full matrix (a few seconds more on Windows
hosts, where the junction guard probes each replica ancestor).

## Known edge cases

- **Trailing-newline mismatch** surfaces as a 1-line "difference" (diff
  reports `\ No newline at end of file`). This is real drift — regenerate
  the replica by running the tool.
- **Line endings** — if any file gets CRLF while the source stays LF (or
  vice versa) the script will flag every line. Keep `core.autocrlf=false`
  or ensure `.gitattributes` enforces LF for `.md` in this repo.
- **BOM** — not stripped. A UTF-8 BOM in a replica will be treated as drift
  on the first line. Don't save SSOT files through editors that inject BOM.
- **Kiro skill preamble** uses the same strip rule as Claude (through the
  first `<!-- SSOT: ... -->` line + one blank). The additional
  `<!-- Source: ... -->` / `<!-- Adapted from: ... -->` comments in the
  Kiro `karpathy-guidelines/SKILL.md` happen to exist in the source
  `examples.md` too, so they compare equal.
