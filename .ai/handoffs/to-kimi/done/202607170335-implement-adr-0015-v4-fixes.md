# Implement ADR-0015 required modifications to handoff protocol v4

Status: DONE
Sender: claude-cockpit
Recipient: kimi-auto
Owner: kimi-auto
Created: 2026-07-17 10:35 (UTC+7)
Completed: 2026-07-17 11:47 (UTC+7) by kimi-auto
Auto: yes
Risk: B
Base: origin/main
Observed-in: main@536d0a72bf1b08a17ac4dfd69a0fcf5389c824a0
Evidence: VERIFIED

## Goal

ADR-0015 (`docs/architecture/0015-handoff-protocol-v4.md`, authored this session)
ratifies your protocol-v4 design **in part**. The diagnosis and the field shapes
are accepted — good work, and the confidently-wrong-sender problem is real. Three
defects must be fixed in the **shipped** code (`53c1ff4`, live on `main`).

**Step 3 is the priority: it closes a live defect in the owner's single
release-path gate.** Do it first and land it on its own if that is faster. Steps 1
and 2 are correctness fixes with no safety component.

Read `docs/architecture/0015-handoff-protocol-v4.md` first — it carries the full
reasoning. This handoff is the execution list only.

**Note on where the ADR lives:** it is on branch
`exec/claude/202607170308-ratify-adr-0015-handoff-protocol-v4`, not yet on `main`.
Read it from that branch (`git ls-tree` + `git cat-file -p <blobsha>` — do not use
`git show "<ref>:<path>"`, MSYS mangles colon args).

## Steps

### 1. `Observed-in` — compare by ancestry, not string equality (`dispatch-handoffs.sh:669`)

Current: `[ "$base_sha" != "$observed_sha" ]`. Two bugs in one line.

- **Normalize both SHAs.** `base_sha` is a 40-char `rev-parse` output;
  `observed_sha` is whatever the sender typed. The spec's OWN example
  (`Observed-in: origin/main@a1b2c3d4`, 8 chars) can therefore never match — a
  handoff written exactly as documented is guaranteed to FAIL. Resolve the
  sender's value through `git rev-parse --verify "<observed>^{commit}"` and
  compare full SHAs. An unresolvable SHA is a FAIL with a distinct message
  (`unknown commit`), not a mismatch.
- **Accept an ancestor.** If `git merge-base --is-ancestor <observed> <base>`,
  DISPATCH. The base advances on every merge; equality means near-certain FAIL
  for every handoff carrying the field, each writing a `dispatch-failure-*.md`
  and firing `fleet_notify alert`. As written, the field would stop the queue and
  spam alerts — and hit hardest the senders who followed the spec.
- **FAIL only on divergence or contradiction:** observed is not an ancestor of
  base, or a path the handoff cites changed in `<observed>..<base>`. The
  path-change check MAY ship in a follow-up; normalization + ancestor check is
  the minimum bar.

### 2. `Evidence: HYPOTHESIS` — dispatch verify-first, do not HOLD (`dispatch-handoffs.sh:538`)

Current: HOLD + `continue`. The spec says the recipient verifies the premise, but
the recipient is never launched — nothing can upgrade `HYPOTHESIS` to `VERIFIED`.
It deadlocks until a human notices, so the field punishes honest uncertainty and
rewards false confidence.

- `HYPOTHESIS` DISPATCHes with premise-verification as the recipient's explicit
  first step. Recipient either upgrades to `VERIFIED` and proceeds, or retires as
  NOT-A-BUG/BLOCKED with the disproof recorded.
- Cap `HYPOTHESIS` at Risk A/B. `Evidence: HYPOTHESIS` + `Risk: C` is a **lint
  error** in `.ai/tools/lint-handoff.sh`, not a HOLD.
- Keep the existing "a hypothesis may not carry a priority label" lint unchanged.

### 3. `Gate-satisfied-by` — never auto-dispatch the owner's hard gates (`dispatch-handoffs.sh:548`)

**This is live on `main` right now — treat it as the priority item.**

Current: `if [ -n "$(gate_satisfied_by "$f")" ]` → DISPATCH at Risk C. A bare
non-empty-string test on a plain-text markdown line any CLI can write. **One CLI
writing one line auto-launches a production deploy with no human involved.** The
gate is self-attested by the party it constrains. That contradicts §8 and
`CLAUDE.md`, which reserve production deploy as the owner's single gate.

For calibration: no evidence it has fired, not remotely exploitable, and it needs
a fleet CLI to author a Risk-C handoff carrying the field. Close it promptly; do
not panic.

- Maintain an explicit hard-gate list sourced from §8: **production deploy,
  publish to a public registry, tag/release cut, force-push or destructive ops on
  shared history, `git reset --hard` on shared state, secrets, production data.**
- A `Gate:` value matching that list → **HOLD for a cockpit, always**, regardless
  of `Gate-satisfied-by`. It forces this path no matter what else the file says.
- Non-hard-gate Risk C MAY auto-dispatch when `Gate:` names the action AND
  `Gate-satisfied-by:` records the authorization.
- A Risk-C handoff with missing/empty `Gate:` HOLDs.

### 4. Tests

- Rewrite **`v4-3`** — it currently asserts the exact behavior ADR-0015 refuses
  (self-written `Gate-satisfied-by` auto-dispatching at Risk C). It must assert
  that a hard-gate `Gate:` value HOLDs *even with* `Gate-satisfied-by` present.
- Add: non-hard-gate Risk C + `Gate:` + `Gate-satisfied-by` → DISPATCH.
- Add: `Observed-in` with an **abbreviated** SHA of the base → DISPATCH. This is
  the case the current suite misses; `v4-5` feeds a full `rev-parse` SHA and so
  hides the documented-example bug.
- Add: `Observed-in` with an **ancestor** SHA (base advanced by ≥1 commit) →
  DISPATCH.
- Add: `Evidence: HYPOTHESIS` → DISPATCH (inverting the current `v4-1`), and
  `HYPOTHESIS` + `Risk: C` → lint error.
- **Repoint `v4-4`/`v4-5` from `origin/master` to `origin/main`** — the repo
  migrated and these refs are stale.

### 5. Update the spec

Update `docs/specs/handoff-protocol-v4.md` to match: the dispatch routing matrix
(the `C | yes | VERIFIED | DISPATCH` row now depends on whether `Gate:` is a hard
gate), the `HYPOTHESIS` semantics, and the `Observed-in` comparison rule.

## Constraints

- **Do not commit `.ai/**` from a bootstrapped worktree.** `guard_ai_reverse_write()`
  (`scripts/wt-bootstrap.sh:229`) sets skip-worktree on 39 `.ai/**` paths there, so
  `git add` stages nothing and `git status` reads clean. Verify with
  `git ls-files -v -- .ai/` (an `S` prefix = skip-worktree). The primary worktree
  has no such bits. If this blocks you, say so in a `## Blocker` — do not clear the
  bits yourself and do not work around the guard.
- **`.ai/tools/dispatch-handoffs.sh` is now enforcement layer** (ADR-0015 Decision
  3.4) — it decides whether a Risk-C action launches. Per ADR-0014 it reaches
  `main` only via a PR reviewed by a **different CLI than the author** and merged
  by neither. So: **author these fixes, do not merge them.** Route review to
  `kiro`; I hold the merge gate.
- Backward compatibility is ratified and must hold: absent `Evidence` = `VERIFIED`;
  an explicit `Base:` still wins over default-branch discovery; `Auto:` remains the
  ownership boundary (ADR-0013).

## Report back with

- Files touched: `.ai/tools/dispatch-handoffs.sh`, `.ai/tools/lint-handoff.sh`,
  `.ai/tests/test-dispatch-worktree.sh`, `docs/specs/handoff-protocol-v4.md`.
- `dispatch-handoffs.sh` fixes:
  - `Observed-in`: resolves sender SHA with `rev-parse --verify`, accepts an
    ancestor of the base via `merge-base --is-ancestor`, and reports distinct
    `unknown commit` / `unresolvable base` / `evidence-base mismatch` failures.
  - `Evidence: HYPOTHESIS`: DISPATCHes at Risk A/B with
    `recipient verifies premise`; Risk C HYPOTHESIS falls through to the Risk-C
    gate (lint-handoff.sh rejects it).
  - `Gate-satisfied-by`: Risk C now requires a non-empty `Gate:`; hard gates
    (`production deploy`, `publish to a public registry`, `tag/release`,
    `force-push`, destructive ops on shared history, `git reset --hard`, secrets,
    production data) HOLD regardless of `Gate-satisfied-by`; non-hard gates with
    `Gate-satisfied-by` DISPATCH.
- `lint-handoff.sh`: added `Evidence: HYPOTHESIS` + `Risk: C` lint error.
- `docs/specs/handoff-protocol-v4.md`: updated `Observed-in`, `HYPOTHESIS`,
  hard-gate semantics, dispatch routing matrix, failure outcomes, and tooling
  list.
- Test evidence (run from primary worktree; exec worktree reverts `.ai/**`
  edits via skip-worktree guard):

```
==== dispatch-worktree suite: 77 passed, 0 failed ====
```

- `v4-3` now asserts the hard-gate HOLD verbatim:

```
check "v4-3: Risk C hard gate HOLDs even with Gate-satisfied-by (exit 0)" ...
check "v4-3: dispatcher reports hard gate requires cockpit" ...
check "v4-3: kimi stub was not invoked" ...
```

- No blocker raised; the hard-gate list and ancestor rule are implementable and
  now covered by tests.

## Blocker

—
