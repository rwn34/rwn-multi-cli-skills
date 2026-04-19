# `.ai/tools/` — framework invariant checks

Utility scripts that audit the multi-CLI framework. Read-only — they detect
problems, they do not fix them. Fixes are a separate decision (regenerating
replicas is manual per `.ai/sync.md`).

## `check-ssot-drift.sh`

Verifies that every CLI-native replica matches its source-of-truth in
`.ai/instructions/`. The SSOT map is defined in `.ai/sync.md` — 12 replicas
across Claude, Kimi, and Kiro.

**Usage (from repo root):**

```bash
bash .ai/tools/check-ssot-drift.sh
```

**Exit codes:**
- `0` — all 12 replicas match their source (after preamble stripping where applicable)
- `1` — at least one replica drifted, or a file is missing

**Output:**
- `Checked: N replicas, Drift: M` summary line
- `DRIFT: <src> -> <dst> (N lines differ)` for each drifted pair
- `MISSING: <path>` for any source or destination file that doesn't exist

**Preamble stripping:**
Four of the 12 replicas have CLI-specific frontmatter + provenance comments
that sit above the body copied from SSOT:
- `.claude/skills/karpathy-guidelines/SKILL.md`
- `.claude/skills/orchestrator-pattern/SKILL.md`
- `.claude/skills/agent-catalog/SKILL.md`
- `.kiro/skills/karpathy-guidelines/SKILL.md`

For these, the script strips everything from the start of the file through
the first `<!-- SSOT: ... -->` line plus one trailing blank line, then
compares the remaining body to the source.

## When to run

- **Pre-commit** — catch drift before it lands on `master`.
- **CI** — wire into the workflow that runs the hook-test suites.
- **Ad hoc** — whenever `.ai/instructions/` is edited, to confirm replicas
  were regenerated.

Runtime: under 2 seconds on the full matrix.

## Known edge cases

- **Trailing-newline mismatch** surfaces as a 1-line "difference" (diff
  reports `\ No newline at end of file`). This is real drift — regenerate
  the replica by re-copying from source.
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
- This tool does **not** regenerate replicas. Drift fixes go through
  `.ai/sync.md`.

## Sibling tools (planned / in flight)

- Claude's `test_hooks.sh` — hook suite, landed.
- Kiro and Kimi hook test suites — in progress.
