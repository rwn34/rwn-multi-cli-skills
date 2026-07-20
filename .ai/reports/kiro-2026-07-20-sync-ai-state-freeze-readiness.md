# sync-ai-state.sh — ADR-0010 freeze readiness design note

Author: kiro (Task B, per claude-cockpit brief 2026-07-20)
Audience: whoever implements the ADR-0010 Wave-3 freeze — written for a reader
who was not in the originating conversation.

## 1. Scope and non-scope

This note specifies what `.ai/tools/sync-ai-state.sh` must do differently once
the ADR-0010 freeze lands (`log.md` git-mv'd to archive, gitignored,
`.ai/tools/render-activity-log.sh` becomes runnable). **It does not perform the
freeze** and does not modify `sync-ai-state.sh`'s `activity/log.md` merge path
today — that path keeps working unchanged pre-freeze, per the brief's explicit
instruction. B4 (implementation) is included below where it was safely
additive; where it was not, this note is the deliverable on its own.

## 2. The three existing log.md-specific sites (line numbers confirmed against
   `.ai/tools/sync-ai-state.sh` on `main`, 2026-07-20)

```
61:  # Merge a worktree activity/log.md into the canonical log. If the worktree
107: f"LOG-MERGE WARN: worktree activity/log.md is missing {len(missing)} canonical entry header(s); merging to preserve history",
303: if [ "$rel" = "activity/log.md" ]; then
```

- **Line 61** is the doc comment introducing `merge_activity_log()`, a ~60-line
  function (through the awk fallback) that does 3-way-ish reconciliation
  between a canonical `log.md` and a worktree's possibly-divergent copy: it
  parses both into `## `-delimited entries by header line, computes
  `canon_headers - wt_headers` (entries the worktree copy is missing relative
  to canonical — usually because the worktree snapshot predates newer
  canonical entries written by other concurrent sessions), warns if any are
  missing, and emits `new_entries_from_worktree ++ all_canon_entries` — i.e. it
  prepends only the genuinely-new worktree entries onto the full canonical
  log, preserving canonical history unconditionally.
- **Line 107** is the Python variant's warning message when that reconciliation
  finds canonical entries the worktree copy doesn't have (the common case,
  since canonical accrues entries from other sessions while this worktree ran).
- **Line 303** is the single call site inside the sync-back new-or-changed loop
  (`cmd_sync_back`) that special-cases `activity/log.md`: instead of the
  generic `cp -a "$wt_ai/$rel" "$canon_ai/$rel"` applied to every other
  new-or-changed file, it pipes both copies through `merge_activity_log()` and
  writes the result via a `.merge-tmp` + `mv` (atomic replace).

There is also a fourth, *implicit* site not named in the brief: the awk
fallback for hosts without Python, lines ~120-165, which duplicates the same
reconciliation logic in awk. Any change to the merge semantics needs to touch
both interpreters or delete both — they are not independently switchable.

## 3. Why this code is a symptom, not infrastructure (confirmed against the
   actual mechanics, not just the framing in the brief)

The manifest (`manifest_for()`, line 168) is **file-level**, built by `find .
-type f`, sorted by relative path. Two manifests are compared in
`cmd_sync_back`: `manifest_old` (recorded at snapshot time, traveling with the
worktree as `.snapshot-manifest`) and `manifest_new` (recomputed from the
worktree's current state at sync-back time). For every path present in
`manifest_new`, if its hash differs from `manifest_old`'s recorded hash for
that same path (or the path is new), the generic loop (lines ~292-307) copies
it into canonical — `cp -a`, unconditional overwrite, **except** for the one
path matching `activity/log.md`, which gets the merge treatment instead.

This means: **every other file under `.ai/`, including every file under
`activity/entries/`, already goes through the generic copy path today.** The
merge-and-warn machinery exists for exactly one path in the whole tree, because
that path is the one place where two independent writers (canonical, updated
by other concurrent sessions; worktree, updated by this session) can each hold
a different but equally valid version of the *same file* — a single mutable
shared file split across two copies is a reconciliation problem by
construction. `activity/entries/*.md` never has this problem: each writer's
file has a filename no other writer will ever produce (UTC timestamp + cli
identity + slug + 4 random hex chars), so canonical and worktree can never
legitimately disagree about the content behind one filename. There is nothing
to reconcile. The removal at freeze time is not a simplification of the
mechanism — it is the mechanism (a single-file merge function) no longer
applying to anything, because the object it existed to merge no longer exists
as a *live, mutable, dual-copy* file.

## 4. What changes at freeze time — exact specification

### 4.1 Remove (freeze commit, not this PR)

- `merge_activity_log()` (both the Python and awk implementations) — lines
  ~59-166 in full, once nothing calls it.
- The `if [ "$rel" = "activity/log.md" ]; then ... else ... fi` branch at line
  ~303 — replaced by the generic `cp -a` for every path, i.e. deleting the
  special case entirely and falling through to what every other file already
  does.

### 4.2 Add — the exclusion that MUST land alongside the removal

Post-freeze, `activity/log.md` is a **generated, gitignored VIEW**
(`.ai/tools/render-activity-log.sh`), not a source file. It can be present on
disk in a worktree (a stale render left over from before the dispatcher
snapshotted it, or produced by the executor running the renderer mid-session)
while holding **zero authority** — the spool is authoritative, and this file
is a derived artifact of it.

**Confirmed gap (this is the addendum claude-cockpit asked me to check):**
`manifest_for()`'s exclusions (line ~194-197) are `$MANIFEST_NAME`,
`handoffs/.quarantine/*`, `activity/archive/*` — there is **no
gitignore-awareness** anywhere in `sync-ai-state.sh`, and no existing exclusion
for `activity/log.md`. The final canonical-commit step
(`git -C "$project" commit ... -- "$canon_ai"`, line ~366) does respect
`.gitignore` because `git add`/`git status --porcelain` are gitignore-aware —
so a gitignored `log.md` will not get *committed*. But the **file-copy loop
runs before that commit step and is not gitignore-aware at all**. If the
`activity/log.md` special case is deleted without adding an explicit
exclusion, the generic path takes over: a stale render sitting in the
worktree, if its hash differs from what the snapshot manifest recorded (which
it will, every time the renderer runs), gets unconditionally `cp -a`'d into
canonical as an ordinary file. Canonical then has an **untracked,
gitignored-but-present `log.md`** that looks authoritative to anyone who does
`cat .ai/activity/log.md` without checking `git status`, and that file goes
stale the moment the next entry is written anywhere. This is exactly risk #2
from the brief ("RESURRECTS a gitignored log.md with stale or partial
content"), and it is not hypothetical — it is what the *current* manifest
exclusions guarantee will happen if the special case is deleted with no
replacement.

**Required fix, to be added to `manifest_for()`'s exclusion list at freeze
time:**

```bash
! -path "./activity/log.md" \
```

alongside the existing three. This makes the render artifact invisible to the
sync mechanism entirely, on both the snapshot side and the sync-back side —
it is never captured into `manifest_old`, never captured into `manifest_new`,
and therefore never enters the new-or-changed loop at all. A worktree is free
to render `log.md` locally for a session's own convenience; it simply never
travels.

(This exclusion is orthogonal to, and does not replace, B2's directory-copy
add below — it stops a *bad* sync, B2 adds the *correct* one for a different
path.)

### 4.3 Add — B2's positive requirement (the entries sync-back)

Today, `activity/entries/*.md` files already sync back correctly **as an
accident of the generic file-level loop**, not by any explicit design for
them: each entry file is enumerated by `manifest_for`, and if new (not in
`manifest_old`) or changed, the generic `cp -a` branch copies it into
canonical. In the overwhelmingly likely case (no filename collision — the
rand4 suffix exists precisely to make collision residual), this already
satisfies "copy new entry files from the worktree snapshot into canonical."

**The gap is that this is a coincidence of the current file-level algorithm,
not a guarantee.** Specifically:

- `old_hash != new_hash` is computed against `manifest_old`, the manifest
  **recorded at snapshot time** — not against whatever canonical currently
  holds at sync-back time. If, by the incredibly narrow but nonzero chance of
  two writers producing the same `<timestamp>-<cli>-<slug>-<rand4>.md`
  filename with *different* content (adversarial clock skew, a broken RNG, a
  copy-paste of another session's filename), the generic `cp -a` would
  silently overwrite canonical's copy with the worktree's, because the loop
  has no per-path "does this already exist in canonical with different
  content" check at all — it only compares worktree-old vs. worktree-new.
- This is invisible today because entry files are new enough (5 files, one CLI
  dogfooding early) that no such collision has occurred, and the brief's own
  framing (§ THE CENTRAL INSIGHT) states the invariant this project actually
  wants: **"no CLI ever rewrites another CLI's entry."** The current code
  does not enforce that; it merely hasn't been tested against a case where it
  would fail to hold.

**Required behavior, to be implemented explicitly rather than left implicit:**

For any path under `activity/entries/`, before copying:

1. If the path does not exist in canonical → copy (new entry, normal case).
2. If the path exists in canonical **and its content is byte-identical** to
   what's being synced → no-op (idempotent re-sync, e.g. a retried
   dispatch — harmless).
3. If the path exists in canonical **and its content differs** → refuse to
   overwrite, warn loudly, and leave canonical's copy untouched. This is the
   one case the generic loop cannot currently distinguish from case 1, because
   it never reads canonical's current file — only the two manifests.

This is strictly additive to the existing behavior for case 1 (still copies,
same as today) and case 2 (today's `cp -a` would also no-op-equivalent since
content is identical — same end state, this makes it an explicit
comparison instead of an accidental one). Case 3 is the only behavior change,
and it only fires on the exact condition ADR-0010 says must never happen — so
firing it is diagnostic of a bug elsewhere (filename generation), never a
normal-path outcome.

## 5. What breaks if this is missed

- **If the log.md special case is removed with no `manifest_for` exclusion
  (§4.2 skipped):** every worktree that renders `log.md` locally — which any
  session following the post-freeze contract might do for its own
  convenience, since `render-activity-log.sh` is unrestricted post-freeze —
  resurrects a stale, gitignored `log.md` into canonical on its next
  sync-back. Canonical accumulates a phantom file that looks authoritative,
  contradicts the spool the moment any new entry is written anywhere, and
  will confuse the next reader who trusts `cat .ai/activity/log.md` over
  `git status`. This is risk #2 from the original brief, concretely realized.
- **If §4.3 (explicit per-file overwrite guard) is skipped and only the
  generic `cp -a` is relied on:** entries still sync back correctly in the
  overwhelming common case (no filename collision), so this failure mode is
  latent, not immediate — the freeze does not visibly break on day one. It
  resurfaces exactly once two writers ever produce the same entry filename
  with different content, at which point one CLI's entry is silently
  destroyed with no warning — the exact class of data loss ADR-0010 exists to
  make structurally impossible. Skipping §4.3 means the *structural*
  impossibility claim is actually an *empirical* one (no collision observed
  yet), which is a materially weaker guarantee than what ADR-0010 advertises.
- **If both the removal and the additions are skipped (freeze lands, sync
  tool untouched):** the log.md special case silently no-ops post-freeze —
  `[ "$rel" = "activity/log.md" ]` still matches the path string, but per
  §4.2's analysis the file may or may not appear in the manifest depending on
  whether it exists in the worktree; if it does exist (e.g. a stale
  pre-freeze copy nobody deleted, or a local render), the merge function
  still runs, parses a `log.md` that is no longer receiving new prepended
  entries from any live writer (all writers moved to the spool), and produces
  an increasingly stale "merged" file that gets written back to canonical.
  This is risk #1 from the original brief, and it compounds with risk #2:
  the file both no-ops in intent (nobody is prepending to it) and actively
  resurrects in effect (the sync tool still writes it).

## 6. Implementation status (B4)

**§4.3 (entries overwrite guard) is implemented and tested in this PR.**
Correction to an earlier draft of this note: I initially wrote that no
fixture-based test harness for `sync-ai-state.sh` existed. That was wrong — a
real harness already exists at `.ai/tests/test-sync-ai-state.sh` (16 cases,
44 assertions before this change), built exactly on the snapshot → mutate →
sync-back → assert pattern this task needs. I found it by re-checking with
`glob`/`grep` before finishing, per self-grep-verify — the claim in the first
draft was fixed rather than left standing. Using that harness:

- `.ai/tools/sync-ai-state.sh`'s new-or-changed loop (`cmd_sync_back`) now
  branches three ways instead of two: `activity/log.md` (unchanged, still the
  merge path), `activity/entries/*` (new: compares against canonical's
  *current* file content — not just the worktree-vs-worktree-snapshot diff —
  before writing; identical content no-ops, absent-in-canonical copies,
  differing content refuses and warns rather than overwriting), and
  everything else (unchanged, still `cp -a`).
- Added 3 new test cases (8 assertions) to `test-sync-ai-state.sh`: a new
  entry file syncs normally (#17), a byte-identical re-sync is a harmless
  no-op (#18), and a simulated filename collision with differing content is
  refused rather than silently resolved either direction (#19).
- Full suite after the change: **52/52 passing** (44 pre-existing + 8 new),
  confirming zero regression to the existing log.md merge behavior, handoff
  deletion-policy guard, or any other existing case.

**§4.2 (the manifest exclusion for a stale-render `log.md`) is
specified but deliberately NOT implemented in this PR.** Unlike §4.3, this one
is not safely additive: pre-freeze, `activity/log.md` is git-tracked and
always present, and the existing merge path is exercised by tests #3, #11,
#12, #13 in the harness. Excluding `activity/log.md` from `manifest_for()`'s
walk *now* would silently stop the merge path from ever running (the file
would never enter `manifest_new`, so the `activity/log.md` case in the
sync-back branch above would never match), breaking those four tests and,
more importantly, breaking the live pre-freeze sync-back behavior this
project depends on today. §4.2 is correct **only** once §4.1's removal of the
`merge_activity_log()` function and its call site lands in the same commit —
they are a matched pair, and landing one without the other is the
half-migrated state the original brief explicitly warned against. This is why
§4.1/§4.2 stay specification-only here while §4.3 ships as working, tested
code: §4.3's correctness does not depend on the freeze; §4.2's does.

**What the freeze-implementer gets from this PR:** a tested guard for the one
positive requirement (B2) that generalizes regardless of when the freeze
lands, plus an exact, harness-verified specification for the one change (B2's
log.md counterpart, §4.2) that must land atomically with the freeze itself —
including the specific pre-existing tests (#3/#11/#12/#13) that will need to
be deleted in that same commit once §4.1 removes the function they test.

## 7. Next step (delivery-integrity §3)

§4.3 ships in this PR, tested (52/52, `.ai/tests/test-sync-ai-state.sh`).
Whoever performs the freeze itself should, in one commit: (1) delete the
`merge_activity_log()` function (both Python and awk implementations) and its
call site per §4.1, (2) add the `manifest_for` exclusion for `activity/log.md`
per §4.2 in the *same* commit as (1) — landing (1) without (2) is the
resurrection bug from §5; landing (2) without (1) breaks the still-live
pre-freeze merge tests, (3) delete or rewrite tests #3, #11, #12, #13 in
`test-sync-ai-state.sh` (they assert on `merge_activity_log()` behavior that
no longer exists post-freeze), and (4) re-run the existing 40/40
concurrent-writer demonstration (referenced in `.kiro`/`.kimi` hook comments
and Wave-1/2 log entries) through an actual `sync-ai-state.sh
snapshot`/`sync-back` cycle, not just direct spool writes — that demonstration
to date has exercised the spool directly and never through this sync path,
and §4.3's new tests (#17-19) cover the sync path but with far fewer
concurrent writers than the spool-level demonstration used.

**What breaks first if the freeze lands without §4.1+§4.2 landing together:**
the first executor worktree that runs `render-activity-log.sh` locally
post-freeze — a stale render gets `cp -a`'d into canonical as a
gitignored-but-present phantom file (§5, risk #2). §4.3 (already shipped) has
already closed the other failure mode (a filename collision silently
destroying an entry) regardless of when the freeze lands.
