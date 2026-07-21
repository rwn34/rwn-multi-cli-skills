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
   `.ai/tools/sync-ai-state.sh` on `main`, 2026-07-20; the third re-confirmed
   2026-07-21 after this PR's B3/B4/N3 edits shifted it from 303 to 312 —
   same `case` branch, no behavior change to this site itself)

```
61:  # Merge a worktree activity/log.md into the canonical log. If the worktree
107: f"LOG-MERGE WARN: worktree activity/log.md is missing {len(missing)} canonical entry header(s); merging to preserve history",
312: activity/log.md)
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
- **Line 312** (was 303 pre-B3/B4/N3) is the single call site inside the
  sync-back new-or-changed loop (`cmd_sync_back`) that special-cases
  `activity/log.md`: instead of the generic `cp -a "$wt_ai/$rel"
  "$canon_ai/$rel"` applied to every other new-or-changed file, it pipes both
  copies through `merge_activity_log()` and writes the result via a
  `.merge-tmp` + `mv` (atomic replace).

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

**Gap 1 (flagged in review handoff 202607201755, addressed here): the analysis
above covers only the sync-back direction. `cmd_snapshot` has a separate,
unaddressed exposure.** `cmd_snapshot` (line ~215) does not walk file-by-file —
it `tar`s the entire canonical `.ai/` into the worktree in one shot (see the
tar invocation before `manifest_for` records the resulting worktree state).
`manifest_for()`'s exclusion list only governs what gets *hashed into the
manifest*, not what the tar step *copies*. Excluding `activity/log.md` from
`manifest_for()` therefore stops it from being recognized as a change on the
sync-BACK side, but does **nothing** to stop `cmd_snapshot`'s tar from copying
canonical's current `log.md` (rendered, stale-by-construction the instant any
CLI writes a new entry elsewhere) forward into every fresh worktree it creates.

This is **harmless in effect**, for a specific reason worth stating rather than
assuming: the copied `log.md` is **worktree-local** — it never travels back
(§4.2's `manifest_for` exclusion, once added, stops sync-back from ever
touching it), and the executor session running inside that worktree reads
activity via the entries spool per the dual-mode hooks (see PR #130's fix in
this same review round), not via a locally-copied `log.md`. So a stale copy
sitting unused in a worktree that gets deleted at the end of that same
dispatch is a no-op in practice. It is flagged here because "no-op in
practice" is a weaker claim than "impossible by construction" — if a future
change ever has a worktree-side consumer read `log.md` directly instead of the
spool, this stale copy becomes a live staleness bug with no guard, and nobody
would think to look at `cmd_snapshot` for it since §4.2 as originally scoped
only ever discussed the sync-back side.

**Gap 2 (flagged in review handoff 202607201755, addressed here): a
conditionally-additive form of §4.2 was never considered, and it would have
let the exclusion ship now instead of waiting for the freeze.** The reason
§4.2 as specified above is deferred (see §6) is that adding a *bare*
`! -path "./activity/log.md"` exclusion today would stop the pre-freeze merge
path from ever running — `log.md` would never enter `manifest_new`, so the
`[ "$rel" = "activity/log.md" ]` branch in `cmd_sync_back` would never match,
silently breaking the live merge behavior tests #3/#11/#12/#13 depend on.
A **conditional** form avoids that entirely:

```bash
! ( [ "$rel" = "activity/log.md" ] && git -C "$dir" check-ignore -q "$rel" 2>/dev/null )
```

i.e. exclude `activity/log.md` from the manifest only when it is *currently
gitignored* in that tree. Pre-freeze, `log.md` is git-tracked (not
gitignored), the condition is false, and the merge path keeps running exactly
as it does today — tests #3/#11/#12/#13 stay green with zero change to their
setup. Post-freeze, `log.md` becomes gitignored as part of the freeze commit,
the condition becomes true, and the exclusion activates automatically — no
second flag day, no second PR gated on "has the freeze landed yet." This form
was not chosen for THIS PR (see the explicit rejection below), but it is a
real, viable alternative to the "land §4.1 and §4.2 together in one commit"
plan in §6/§7, and the freeze-implementer should decide between them rather
than assume the atomic-pair plan is the only option.

**Why it is still not implemented in this PR despite being safely additive in
principle:** `git check-ignore` is a real subprocess call inside
`manifest_for()`'s per-file walk (invoked once per file that matches the path,
so in practice once per manifest build, since only one file can be named
`activity/log.md`) — cheap here, but it is a process-spawn dependency on `git`
existing and the tree being inside a git working directory that
`manifest_for()` does not otherwise have (its only dependency today is
`sha256sum`). Introducing a new external-tool dependency and a git-repo
assumption into a function whose current contract is "hash whatever files
exist" is a scope increase beyond what this review round asked for (B1/B2 on
`sync-ai-state.sh` specifically), and it deserves its own review rather than
being folded silently into a nit-fix pass. It is specified here, fully, so the
freeze-implementer can adopt it instead of the atomic-pair plan with a clear
understanding of the tradeoff, but the choice between the two plans is left to
whoever actually performs the freeze.

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

**§4.3 (entries overwrite guard) is implemented and tested in this PR — and
was hardened further in a second review round (handoff 202607201755) after an
initial version shipped a real data-loss bug.**

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
  before writing), and everything else (unchanged, still `cp -a`).
- The `activity/entries/*` branch has three cases: absent-in-canonical →
  copy (also guarded against a dangling symlink at the target path, per the
  review's N3 — `[ ! -e ] && [ ! -L ]` rather than bare `[ ! -e ]`); identical
  content → no-op (idempotent re-sync); differing content → **preserve both
  sides**, not merely refuse. This last case is where the second review round
  changed the behavior:
  - **B3 fix:** the first version of this guard only warned and left
    canonical untouched — but `cmd_sync_back` unconditionally removes the
    worktree's `.ai/` at the end of every run (`safe_rm_rf "$wt_ai"`), which
    meant the worktree's differing body was destroyed the moment the function
    returned, for the exact scenario this test's own comment says must never
    happen. The fix now also copies the worktree body aside into canonical as
    a distinctly-named `<name>.conflict-<8-hex-hash>.md` file, so both bodies
    survive on disk for a human to reconcile.
  - **B4 fix:** exit 0 plus a `warn()` (stderr, non-fatal) is not a guard a
    headless pipeline will ever notice — `dispatch-handoffs.sh`'s
    `sync_back_ai()` calls this script with `... || true`, and
    `pane-runner.ps1` renders every sync-back line in dark gray, interleaved
    with dozens of routine lines, in a pane nobody watches during headless
    dispatch. `cmd_sync_back` now returns **2** (distinct from the
    pre-existing handoff-deletion guard's exit **1**) when a collision was
    preserved this run, and a durable `.sync-conflict-<hash>.marker` text file
    is written into canonical `.ai/` alongside the conflict file — greppable
    evidence that survives independently of whether any caller reads the exit
    code or the pane output.
  - **N3 fix:** `[ ! -e "$canon_ai/$rel" ]` was true for a dangling symlink at
    the target path (the target does not exist, but the symlink itself does),
    which would have let `cp -a` write through the symlink to wherever it
    points rather than treating the path as occupied. Changed to
    `[ ! -e "$canon_ai/$rel" ] && [ ! -L "$canon_ai/$rel" ]`, matching the
    review's exact suggestion.
- Also fixed in this round: **N1** (`sort -r` → `LC_ALL=C sort -r` in the two
  Kiro activity-log hooks — UTF-8 collation is not byte-wise) and **N2** (a
  stale `kiro-cli` display-text reference in `activity-log-inject.sh`, though
  NOT the sibling reference in `dispatch-own-queue.sh`, which is outside this
  PR's diff and left for its own pass rather than a drive-by edit).
- Test suite additions: the entries new-file case (test #17, unchanged), the
  idempotent-resync case (test #18) **was itself rewritten** — its original
  form wrote the canonical entry BEFORE the snapshot, so the snapshot's tar
  copied it into the worktree too, making `old_hash == new_hash` for that path
  and causing the outer diff loop to skip evaluating it entirely; the
  `cmp -s` branch the test claimed to exercise never ran (B5). It now writes
  the entry into canonical strictly AFTER the snapshot, forcing the file to be
  genuinely new-or-changed relative to `manifest_old` so the `cmp -s`
  comparison actually executes, with a new assertion confirming no conflict
  artifacts were produced. The collision case (test #19) was updated for the
  new exit code (2, not 0), the new warn text (`ENTRY FILENAME COLLISION`,
  not the old `REFUSING to overwrite`), and gained two new assertions: the
  conflict file exists and contains the worktree's body, and the marker file
  exists in canonical.
- Full suite after this round: **55/55 passing** (0 regressions to the
  pre-existing log.md merge behavior, the handoff deletion-policy guard, or
  any other prior case).

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
(A conditionally-additive alternative to the atomic-pair plan — gating the
exclusion on `git check-ignore` rather than on the freeze having landed — is
specified in §4.2 above per the review's Gap 2, and would have let this ship
now; it introduces a new external-tool dependency into `manifest_for()` that
this review round intentionally did not adopt without its own separate pass.)

**What the freeze-implementer gets from this PR:** a tested, hardened guard
for the one positive requirement (B2) that generalizes regardless of when the
freeze lands, plus an exact, harness-verified specification for the one
change (B2's log.md counterpart, §4.2) that must land atomically with the
freeze itself — including the specific pre-existing tests (#3/#11/#12/#13)
that will need to be deleted in that same commit once §4.1 removes the
function they test, and two viable plans (atomic-pair vs.
conditionally-additive) for the freeze-implementer to choose between.

## 7. Next step (delivery-integrity §3)

§4.3 ships in this PR, tested and hardened across two review rounds (55/55,
`.ai/tests/test-sync-ai-state.sh`). Whoever performs the freeze itself should,
in one commit: (1) delete the `merge_activity_log()` function (both Python and
awk implementations) and its call site per §4.1, (2) add the `manifest_for`
exclusion for `activity/log.md` per §4.2 in the *same* commit as (1) — landing
(1) without (2) is the resurrection bug from §5; landing (2) without (1) breaks
the still-live pre-freeze merge tests — OR adopt the conditionally-additive
`git check-ignore`-gated form of §4.2 instead, which does not require strict
commit-atomicity with (1) but does add a new dependency to `manifest_for()`,
(3) delete or rewrite tests #3, #11, #12, #13 in `test-sync-ai-state.sh` (they
assert on `merge_activity_log()` behavior that no longer exists post-freeze),
(4) address the `cmd_snapshot` tar-copy exposure noted in §4.2 Gap 1 if any
future change gives a worktree-side consumer a reason to read a locally-copied
`log.md` directly rather than the entries spool, and (5) re-run the existing
40/40 concurrent-writer demonstration (referenced in `.kiro`/`.kimi` hook
comments and Wave-1/2 log entries) through an actual `sync-ai-state.sh
snapshot`/`sync-back` cycle, not just direct spool writes — that demonstration
to date has exercised the spool directly and never through this sync path,
and §4.3's tests (#17-19) cover the sync path but with far fewer concurrent
writers than the spool-level demonstration used.

**What breaks first if the freeze lands without §4.1+§4.2 landing together:**
the first executor worktree that runs `render-activity-log.sh` locally
post-freeze — a stale render gets `cp -a`'d into canonical as a
gitignored-but-present phantom file (§5, risk #2). §4.3 (shipped and hardened
in this round) has already closed the other failure mode (a filename
collision silently destroying an entry) regardless of when the freeze lands —
and now does so loudly (exit 2 + a durable marker file) rather than via a
warn buried in pane output that nothing downstream reads.
