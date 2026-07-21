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

**Junction safety (ADR-0004) / snapshot-copy (ADR-0016):** in-place
regeneration refuses to write through any symlink or Windows-junction ancestor
of a replica path, and refuses any registry destination under `.ai/` outright.
ADR-0016 removed the junction entirely in favor of a dispatcher-owned snapshot
copy, so the symlink/junction guard is now a defense-in-depth belt-and-suspenders
layer. `--check` and `--dest-root` write only to their explicit sink and are not
guarded.

**Skip-worktree source guard (ADR-0015 follow-up, 2026-07-17):** the worktree
layout may set `skip-worktree` on `.ai/**` sources so that git stops trusting
the working-tree view. A generator that reads such a source would regenerate
replicas from the index's stale blob while the commit stat claims an update.
The generator therefore checks `git ls-files -v <ssot>` for every source and
aborts if the flag is 'S'. Clear the bit with `git update-index
--no-skip-worktree <path>` before regenerating.

## `check-ssot-drift.sh` — compatibility shim

Kept for existing callers and docs. It `exec`s
`sync-replicas.sh --check` with the identical output contract and exit codes.
New call sites should use the authoritative entry point directly.

## `render-activity-log.sh` — generate the human-readable activity log

ADR-0010 Wave-3 replaced the prepend-whole-file `.ai/activity/log.md` model with
an entry-per-file spool under `.ai/activity/entries/*.md`. This script renders
those entries into the human-readable `.ai/activity/log.md` view (newest first).
The rendered file is generated and gitignored; never edit it directly.

**Usage (from repo root):**

```bash
bash .ai/tools/render-activity-log.sh
bash .ai/tests/test-render-activity-log.sh
```

## `check-log-superset.sh` — legacy activity-log entry-loss gate (deprecated)

Used during the ADR-0010 transition to verify that a candidate
`.ai/activity/log.md` would not drop entry headers. With the entry-spool model,
entry loss is prevented by the pre-commit hook (`scripts/git-hooks/pre-commit`)
which blocks deletions under `.ai/activity/entries/`. Retained for reference
until the transition is fully closed.

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
