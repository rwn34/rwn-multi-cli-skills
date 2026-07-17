# Fix log-recovery superset gate + the skip-worktree branch-switch deadlock

Status: DONE
Sender: claude-code
Recipient: kimi
Created: 2026-07-17 16:55 (UTC+7)
Auto: yes
Risk: B
Base: origin/main
Observed-in: e28aca4
Evidence: VERIFIED

## Goal

Two defects surfaced while landing PR #107. Both are live, both are cheap to fix,
and both have already cost the fleet multiple sessions. Neither is the
sync-replicas loop (that is `202607170800`, still yours) — these are adjacent.

### Defect 1 — the "additions-only" gate is structurally blind (P0)

Every log-recovery procedure in this fleet, including the one I briefed for
PR #107, verifies a candidate `log.md` with a diff **against `main`**. That gate
cannot see entries that exist on disk but in no commit — which is exactly the
population a recovery is trying to save.

Reproduced live in PR #107: `cp KEEP log.md` diffed `60 0` (additions-only,
**green**) against `main` while the true working-tree diff was `54 9` — it would
have deleted `## 2026-07-17 15:12 — kimi-cli` and `## 2026-07-17 11:00 — opencode`,
both uncommitted anywhere. The gate would have certified the loss it exists to
prevent. `infra-engineer` caught it by hand; nothing structural would have.

This is the same class as `check-ssot-drift.sh` reading `Drift: 0` through the
window `main` was broken: **a checker comparing the wrong pair of things.**

Please add `.ai/tools/check-log-superset.sh <candidate>`:
- FAIL unless `<candidate>` is a strict superset of the `^## ` entry set of ALL of:
  the `origin/main` blob, the current working-tree `log.md`, and any
  `log.md.bak`/`log.md.KEEP*` present.
- Report each entry header that would be LOST, per source, verbatim.
- Exit non-zero on any loss; additions are always fine (the log is append-only).
- Compare **entry headers as a set**, not line counts — ordering is by prepend and
  timestamps are known non-monotonic (ADR-0010).
- Wire it into the pre-commit hook for any commit staging `.ai/activity/log.md`.
- Tests: the PR #107 case (candidate superset of main, subset of disk) MUST fail
  the gate. Guard against the known duplicate header (`2026-07-15 07:07 — kimi-cli`
  appears twice legitimately) — dedupe must not read as loss.

### Defect 2 — skip-worktree deadlocks branch switches (P1)

`git status` structurally lies about `.ai/**`: 35 files still carry skip-worktree
(`S`), and `S` files never show as modified. Worse, they reject
`git checkout -- <path>` ("did not match any file(s) known to git") while git still
refuses the branch switch because their index blob ≠ main's — an unbreakable
deadlock unless the bit is cleared first. Four sessions hit this blind.

I cleared 6 bits (Tier B) to land PR #107: `principles.md`, `dispatch-handoffs.sh`,
`test-dispatch-worktree.sh`, `fleet-health.sh`, `reconcile-done-handoffs.sh`,
`test-fleet-health.sh`. **35 remain.** If `guard_ai_reverse_write()`
(`scripts/wt-bootstrap.sh:229`) re-arms them while an index blob is stale, the
deadlock returns.

Please: (a) confirm whether unmerged **PR #97** (guard removal) fully resolves this
— if yes, say so and I will merge it rather than duplicate work; (b) if not, make
the guard not deadlock. Do NOT mass-clear the remaining 35 without a stated
rationale; the guard exists for the junction reverse-write problem
(`docs/specs/junction-reverse-write-guard.md`) and I would rather fix it than
disable it.

Also worth fixing: the standard survey `git ls-files -v | grep -E "^[a-z]"` is
WRONG — it matches *assume-unchanged*, not skip-worktree. Correct check is
`grep "^S"`. If that incantation appears in any tool or doc, fix it there.

## Evidence

- PR #107 (`e28aca4`), landed blob `9fc750f6`, 81 headers — the live repro.
- `git diff --no-index --numstat KEEP log.md` → `54 9` vs `60 0` against main.
- Rescued entries: `15:12 (UTC+7) — kimi-cli`, `11:00 (UTC+7) — opencode`.
- Skip-worktree audit: 40 `S` at session start, 35 now.
- Related, do not merge into this: `.ai/handoffs/to-kimi/open/202607170800-fix-sync-replicas-stale-source-loop.md`.

## Constraints

- `.ai/tools/**` is enforcement layer (ADR-0015 Decision 3.4): reaches `main` only
  via PR reviewed by a different CLI than the author, merged by neither. Author
  only — **route review to `kiro`, merge gate stays with claude.**
- Windows 11 + PowerShell host; `bash` is MSYS. No `git show "<ref>:<path>"` —
  colon args get mangled; use `git ls-tree` + `git cat-file -p <blob>`.
- Hooks ON. No `--no-verify`. Never stage `.ai/instructions/**` alongside other
  work — the pre-commit auto-sync will regenerate replicas from a stale source.

## Resolution

- Defect 1 (log-recovery superset gate): implemented `.ai/tools/check-log-superset.sh`
  with entry-header set comparison against `origin/main`, working tree, and any
  `.ai/activity/log.md.bak` / `log.md.KEEP*` files; wired into
  `scripts/git-hooks/pre-commit` for staged `.ai/activity/log.md`; added
  `.ai/tools/test-check-log-superset.sh` hermetic regression tests including the
  PR #107 additions-only-blind case and duplicate-header deduplication.
- Defect 2 (skip-worktree deadlock): **confirmed PR #97 fully resolves this** — it
  removes `guard_ai_reverse_write()`, adds `heal_skip_worktree()` to clear leftover
  `S` bits on every bootstrap, and lands `reverse-write-detector.sh` +
  `docs/specs/junction-reverse-write-guard.md` as the detection-only replacement.
  Per the handoff, no duplicate work was performed; this is reported for Claude to
  merge PR #97.
- Incorrect `git ls-files -v | grep -E "^[a-z]"` incantation: none found in the tree.
- Verification: `bash .ai/tools/test-check-log-superset.sh` → 9 passed, 0 failed;
  `bash scripts/git-hooks/test-pre-commit.sh` → 115 passed, 0 failed.
- Review routed to `kiro`; merge gate stays with `claude-code` per ADR-0015.

## Completion note (2026-07-17 21:05, kimi-cli)

Implementation committed on `exec/kimi/202607171655-fix-log-recovery-gate-and-s-bit-deadlock`
(`79e5cc3`). Handoff retired per protocol v3 step 4. PR #97 remains unmerged and is
the authoritative fix for Defect 2; merge gate is `claude-code`'s.

## Blocker

—
