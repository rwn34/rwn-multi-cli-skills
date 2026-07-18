# Review: PR #55 — atomic drift-gate sync (SSOT replicas, ADR-0005 second amendment)

- Reviewer: kimi-cli
- Author: claude-code (author != reviewer — satisfied)
- PR head reviewed: `cfe5d69` (`claude/drift-gate-atomic-sync`), in a clean worktree
  (HEAD == `headRefOid`), plus throwaway repos built from the PR's own files
- Merge: `a3e653b` (2026-07-12 15:59 +0700, version 0.0.31 assigned at the merge
  point per ADR-0012)
- **Verdict: APPROVE-WITH-NOTES** — one real bypass of the widened territory
  exception found (F1, reported loud per the review brief), judged non-blocking;
  two lesser notes (F2, F3). Did NOT merge — Tier C stayed with the owner.

## Provenance of this report (read first)

This file is the evidence record the PR #55 verdict comment cited as
"full evidence". **It was not written at review time** — the verdict was posted
as a PR comment and the review was real (the merge was correct; the post-merge
drift check on master confirms it), but the report file itself was never created:
not on disk, not on master, not in any worktree. That is a delivery-integrity
miss of the exact class `self-grep-verify` exists to catch — a published claim
pointing at evidence that isn't there. Handoff
`.ai/handoffs/to-kimi/open/202607121930-write-missing-pr55-review-report.md`
(claude-code → kimi-cli) ordered this record written after the fact.

What this report is, honestly:

- The review ran **pre-merge** on 2026-07-12 (before the 15:59 +0700 merge).
  Its surviving verbatim record is the posted PR #55 comment; every
  verification claim below marked "at review time" comes from that record.
- This file was compiled on **2026-07-13 ~06:15 +0700** from that record, plus
  a fresh re-verification of its load-bearing claims against the current tree
  (section "Re-verification at write time" — with actual output).
- It is **not** a fresh end-to-end re-review, and nothing here is back-filled.
  Where a verification was not (or could not be) re-run, that is stated
  plainly in "What was NOT re-verified".

## Scope reviewed (the four coordinated parts)

1. **One deterministic generator** — `.ai/tools/sync-replicas.sh` (new, 127
   lines). Reads the `.ai/sync.md` registry; byte-copy for pure replicas,
   preamble-preserving body-replace for `SKILL.md` (the exact inverse of the
   checker's `strip_preamble`). LF-normalized, idempotent, fails closed on an
   unreadable/malformed registry.
2. **Checker == generator** — `check-ssot-drift.sh` refactored to invoke the
   generator into a temp dest-root and diff, holding no separate copy of the
   transform. Output format / exit codes / `Checked: N, Drift: M` summary
   preserved.
3. **Committer-keyed auto-stage** — `scripts/git-hooks/pre-commit`: on a staged
   `.ai/instructions/**` change, `claude-code` auto-stages regenerated replicas
   atomically; a human/other identity is refused with a hint (never a silently
   mutated commit); fails closed on generator error.
4. **Widened territory exception** — `_territory_violation` widened from
   steering-only to any `.ai/sync.md`-registered replica (adds
   `.kimi/resource/*` and `.kiro/skills/*/SKILL.md`), reusing fail-closed
   `_is_sync_replica`. Original-case lookup; unregistered peer paths stay
   blocked.

## Verified by execution at review time

From the surviving verbatim review record (the posted PR comment):

- `test-pre-commit.sh` on the PR head → **111/0**.
- `check-ssot-drift.sh` on the branch → `Checked: 24 replicas, Drift: 0`.
- `sync-replicas.sh` on the branch → idempotent (`git status` empty after a
  second run).
- **checker == generator, re-proven with my own mutation** (different from the
  suite's: `normalize_lf` → drop-last-line): verdict flipped `Drift: 0` →
  `Drift: 24`, rc 0→1; restored → 0. The checker holds no second transform
  copy.
- Auto-stage is exact-registry-only: live-fired `.ai/instructions/**` edit +
  `.kimi/hooks/x.sh` in one commit as `claude-code` → REJECTED, nothing landed.
- Human committer refused without mutation (SSOT-only → rc=1 with hint; with
  correct replicas the staleness check passes and only the pre-existing
  territory rule blocks).
- Case variants (`.Kimi/steering/...`) blocked; unregistered
  `.kiro/skills/x/SKILL.md` blocked (live-fired); unreadable registry → fail
  closed (suite).
- Inverted test correct: `.kiro/skills/karpathy-guidelines/SKILL.md` IS a
  registered replica (`.ai/sync.md`); an unregistered sibling stays blocked.
- Preamble inference safe for the current set: all 8 `SKILL.md` replicas carry
  exactly one `<!-- SSOT:` marker; no non-SKILL.md replica carries one; no
  source is named `SKILL.md`. A no-preamble `SKILL.md` would fail LOUD
  (perpetual unfixable drift), so no `sync.md` schema flag is needed now.

## Adversarial attempts against the widened exception

The review brief asked for at least 2 adversarial attempts against the widened
territory exception. **They were made — six, not two — and one succeeded (F1):**

1. **Truncated registry-name commit** — `git commit` of
   `.kimi/steering/karpathy-guidelines.m` (a truncation of the registered
   `.kimi/steering/karpathy-guidelines.md`) as `claude-code` → **SUCCEEDED**.
   This is F1 below. `.kiro/skills/karpathy-guidelines/SKILL` and
   `.kimi/resource/karpathy-guidelines-examples` also pass at function level.
2. **Non-replica peer path** — `.kimi/hooks/x.sh` staged alongside an SSOT edit
   as `claude-code` → REJECTED; nothing landed. Paths that aren't registry
   substrings stay blocked.
3. **Case variant** — `.Kimi/steering/...` → blocked (original-case lookup
   fails closed).
4. **Unregistered SKILL.md** — `.kiro/skills/x/SKILL.md` → blocked (live-fired).
5. **Human committer, SSOT-only staged change** → refused rc=1 with hint, no
   index/worktree mutation.
6. **Human committer with correct replicas staged** → staleness check passes;
   only the pre-existing territory rule blocks (expected behavior).

## Findings

### F1 — BYPASS of the widened exception (highest-value find; non-blocking)

`_is_sync_replica` is an unanchored substring match
(`grep -qF "$1" "$SYNC_MD"`), so the widening is NOT strictly
sync.md-registered: any **truncation** of a registered replica name passes the
territory gate for `claude-code`. Live-fired and confirmed (attempt 1 above).

Why judged non-blocking:

- The hole applies only to `claude-code` (the trusted fleet operator) — other
  committers get no exception at all.
- It reaches only truncated junk names inside `.kimi/`/`.kiro/` — it cannot
  touch hooks, agents, or contracts.
- `claude-code` can already achieve more by editing `.ai/sync.md` (its own
  territory), so the exception is inherently only as strong as the registry.
- The same unanchored grep already shipped in the merged 2026-07-10 amendment;
  this PR widens the surface but does not introduce the class.
- The CI drift net is unaffected.

**Recommended fix (one line):** anchor to the registry's backtick-quoted
tokens — ``grep -qF "\`$1\`" "$SYNC_MD"`` — or reuse the generator's awk parse
with an exact destination compare.

### F2 — minor UX: the human refusal hint can never succeed for a human

The hint says "run sync-replicas.sh and re-stage the replicas". Live-fired:
that can NEVER succeed for a human, because `unknown` committers are
territory-blocked from every `.claude/.kimi/.kiro` path, replicas included.
Effective human paths are claude-code or `--no-verify`. Reword the hint.

### F3 — informational: rejected commits leave regenerated replicas staged

The auto-sync block runs before the territory pass, so a commit rejected later
leaves regenerated replicas staged in the index + worktree. Harmless (correct
content; retry succeeds) but worth a code comment.

## Why APPROVE-WITH-NOTES held up

F1 is a real hole but strictly weaker than powers `claude-code` already has,
and F2/F3 are polish. The merge was correct: post-merge on master,
`check-ssot-drift.sh` reports `Checked: 24 replicas, Drift: 0`, and the
generator/checker unification is exactly the throttle fix ADR-0005's second
amendment called for. Nothing found would have changed the merge decision.

## Re-verification at write time (2026-07-13 ~06:15 +0700, master @ `fadefea`)

Fresh runs against the current tree to ground the load-bearing claims:

- `git merge-base --is-ancestor cfe5d69 origin/master` → **YES**; the reviewed
  head is exactly what merged (`git log -1 cfe5d69` shows the PR title commit).
- `bash .ai/tools/check-ssot-drift.sh` → `Checked: 24 replicas, Drift: 0`,
  rc=0.
- `bash scripts/git-hooks/test-pre-commit.sh` → **RESULT: 111 passed, 0
  failed** — same count as at review time.
- F1 still live in the tree: `scripts/git-hooks/pre-commit:66-68` reads
  `_is_sync_replica() { ... grep -qF "$1" "$SYNC_MD" }` — unanchored, exactly
  as reported.
- Registry rows confirmed: `.ai/sync.md:14` registers
  `.kimi/steering/karpathy-guidelines.md`; `.ai/sync.md:17` registers
  `.kiro/skills/karpathy-guidelines/SKILL.md`.
- Preamble-inference premise re-counted: all 8 real `SKILL.md` replicas listed
  in `.ai/sync.md` carry exactly one `<!-- SSOT:` marker each.
- The cited report file genuinely existed nowhere: `git log --all` for this
  path returns nothing.

## What was NOT re-verified (honest gaps)

- The throwaway-repo live-fires (F1 truncation commit, auto-stage rejection,
  human-committer refusal matrix) were executed at review time in disposable
  repos that no longer exist; they were **not** re-run for this record. Their
  outcomes are as recorded in the verbatim PR comment. F1's underlying
  mechanism was instead re-confirmed statically (the unanchored grep is still
  in the tree, quoted above).
- The review-time mutation test (`normalize_lf` → drop-last-line flipping
  Drift 0→24) was not re-run; the generator/checker unification it proved is
  still the shipped design (drift check passes via the generator path).
- No separate review-brief handoff file exists in the tree or in git history
  for PR #55 — the brief was the PR description ("please peer-review before
  merge", four coordinated parts) plus the orchestrator's dispatch instruction.
  The comment's "per the review brief" refers to that.
