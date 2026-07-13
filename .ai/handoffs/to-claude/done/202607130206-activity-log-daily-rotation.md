# Activity log: daily rotation (rotate-on-read, write path unchanged)
Status: DONE
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 09:06
Auto: no
Risk: B
Base: origin/master

> **DONE (resolved, NOT merged) 2026-07-13 by claude-code.** The proposal is
> **declined as specified** and superseded by executing ADR-0010 instead. The
> rotation branch is abandoned; the corruption repair and the `known-limitations`
> promotion stand. See `## Resolution` at the bottom — that is the authoritative
> ending. `## Blocker` is retained as the record of why.

## Problem (measured, not hypothetical)
`.ai/activity/log.md` is **507,862 bytes / 2,011 lines / 339 entries** spanning
2026-04-17 → 2026-07-13 (`wc -l -c`; `grep -c '^## '`). The protocol requires
every CLI to read it at the start of non-trivial work — that is ~125k tokens of
mostly-irrelevant history per session, 4+ sessions/day, growing ~5–10 KB/day.
Owner proposal (2026-07-13): rotate by date — when a day change is noticed, move
prior days' entries into `log-YYYYMMDD.md` and leave `log.md` holding only the
current day. **Write path (prepend one entry) stays exactly as-is.**

## Relationship to ADR-0010
ADR-0010 designed a per-entry spool (`.ai/activity/entries/**` exists as
permission plumbing) but never migrated. Daily rotation delivers ~90% of that
read-cost benefit with ~10% of the change and zero write-path migration.
Recommend ratifying rotation as a small ADR that amends/supersedes the ADR-0010
spool plan (spool stays as plumbing; no migration).

## Design (owner-approved shape; details from tonight's outage lessons)
1. **Rotate by entry header date, never by "stamp yesterday".** Parse
   `## YYYY-MM-DD HH:MM — <cli>` headers; group entries by their own date;
   keep entries with date == local today in `log.md`; move each older date's
   entries into `.ai/activity/log-YYYYMMDD.md`. Clock skew across CLIs is real
   (tonight: a 09:40 entry landed below an 08:56 entry) — the header date is the
   only authoritative filing key.
2. **Idempotent, rotate-on-read.** A shared script
   (`.ai/tools/rotate-activity-log.sh`) runs before the start-of-work read and
   on pane-runner pickup; if no stale-dated entries exist it is a strict no-op
   (no commit churn). First run of the day does the rotation + one
   `chore(ai): rotate activity log` commit. No cron, no midnight race — second
   rotator of the day finds nothing.
3. **Dated files keep newest-first order** (same convention as log.md). If a
   skewed late entry lands after rotation, merge it into the existing
   `log-YYYYMMDD.md` by prepend (prepend order authoritative, per protocol).
4. **Atomic**: build temp files, `mv` into place — same reason the sync deploy
   is atomic; three panes can be mid-prepend.
5. **Protocol change is one line**: routine read = `log.md`; history =
   `grep .ai/activity/log-*.md`. Archive-skip convention unchanged.
6. **One-time backfill**: first run splits the current 496 KB into ~90 daily
   files. Part of this change, verified by diff (concatenation of all dated
   files + log.md == original log.md, byte-for-byte modulo the regrouping).

## Known accepted caveat
A badly skewed CLI clock can file an entry into a date file another CLI still
considers "today." Harmless: the entry is one glob away, and the protocol
already tolerates skew via prepend-order-authoritative.

## Alternatives considered and rejected
- Read-discipline only ("read first N entries") — relies on every reader
  behaving forever; rotation makes the cheap thing the physical default.
- UTC dates for filenames — entries are local wall-clock per the timestamp
  rule; filing by header date keeps the two consistent.

## Touches (SSOT — your lane)
- `AGENTS.md` "Activity log protocol" section (all four contracts reference it)
- `.ai/instructions/` SSOT (activity-log protocol)
- new `.ai/tools/rotate-activity-log.sh` + one-time backfill run
- small ADR amending ADR-0010

## Verify
- Byte-level round-trip: original log.md content fully recoverable from
  log.md + log-*.md after backfill.
- Idempotency: second consecutive run = no diff, no commit.
- A synthetic skewed-clock entry (header date yesterday, written today) files
  into the correct dated file, newest-first merge.
- All four CLIs' contracts still describe the write path unchanged (prepend).

---

## Delivered (claude-code, 2026-07-13) — branch, unmerged

Branch `exec/claude/202607130206-activity-log-daily-rotation` (cut from
`origin/master` @ `1ca3f03`; commits `62e2cbb`, `da54c6c`). **Not merged, no PR.**

- `.ai/tools/rotate-activity-log.sh` — new. Files each entry by its **own header
  date** (never "today minus one" — clock skew makes header date the only sound
  key). Idempotent silent no-op when nothing is stale. Atomic (temp + `mv`).
  Junction-safe path resolution by pure string manipulation on `$0` (never
  `cd "$(dirname "$0")"` — that resolves the `.ai/` junction and targets the wrong
  repo; same bug class as the `check-ssot-drift.sh` false-pass). Deliberately does
  **not** `git commit` — a commit from an executor worktree stages the primary
  checkout's files against the wrong branch (ADR-0004 reverse-write hazard).
- `.ai/tools/test-rotate-activity-log.sh` — new, **42/42 pass**. Covers idempotent
  no-op, header-date filing incl. skew, prepend-merge, `--check` purity, CWD/junction
  safety.
- Backfill run: **333 entries → 17 dated files**; `log.md` 2025 lines / 514,829 B →
  49 lines / 19,504 B (**−96%**).
- Round-trip proof: `9 + 333 = 342` = pre-rotation count. Sorted entry-block diff of
  baseline vs. union is **empty** (0 baseline blocks absent). Every dated file has 0
  foreign-date entries and its header sequence md5-matches the baseline's for that
  date — filed by header date, never re-sorted.
- SSOT + replicas: `Checked: 24 replicas, Drift: 0`.
- Protocol text: `AGENTS.md`, `CLAUDE.md`, `.ai/instructions/operating-prompt/principles.md`
  (+3 replicas), `.claude/settings.json` (rotate-on-read wired into `UserPromptSubmit`).

**Two bugs caught by the test harness, both fixed:**
1. `grep -c` prints `0` **and exits 1** on no match, so `$(grep -c … || echo 0)`
   yields the two-line string `"0\n0"`. Would have fired at the summary line every
   day when `log.md` holds zero today-entries — i.e. **the normal state just after
   midnight**.
2. **Prepend-merge was not convergent under replay.** Rotation is idempotent against
   its own output, but `log.md` is a *tracked* file under the shared junction, so it
   can be restored behind the script's back (branch switch in any worktree,
   `checkout --`, stash pop, revert). Reproduced live: rotate → restore → rotate
   doubled every entry in `log-20260712.md` (3 → 6). With rotate-on-read firing across
   four CLIs, that would have duplicated 333 entries into shared state within hours of
   the first branch switch. Merge is now identity-filtered; replay is a no-op.

## Blocker

**1. The premise in `## Relationship to ADR-0010` is false, and it inverts the decision.**

The handoff states the spool "exists as permission plumbing" and that rotation
"delivers ~90% of that read-cost benefit", recommending an ADR that
"amends/supersedes the ADR-0010 spool plan".

Checked against `origin/master`, not disk:

- **ADR-0010 (`0010-activity-log-entry-spool.md`) is `Status: Accepted`** (owner-approved
  2026-07-11), and **its design was never implemented.** `.ai/activity/entries/` **does
  not exist on disk at all** — not empty plumbing, absent. `log.md` is still tracked,
  still shared, **not** gitignored. Both hard blockers named in the ADR's own migration
  table (`scripts/git-hooks/pre-commit`, `.opencode/plugin/framework-guard.js`) still
  hardcode the old path.
- ADR-0010 does not exist to reduce read cost. It exists to **structurally eliminate the
  concurrent-write race** — unique filename per entry ⇒ no shared write ⇒ no lock ⇒ no
  clobber, including in the headless/hookless runtimes where our enforcement layer
  provably does not fire.
- **It also already delivers the read-cost win** the handoff is chasing: its §3 replaces
  `head -40 log.md` with "cat the newest N entry files" in all three injection hooks.
- **Daily rotation does not fix the race.** It keeps `log.md` a single shared mutable
  file and *adds one more whole-file rewriter to it*.

So the trade is not "90% of the benefit for 10% of the change". It is: **give up the race
fix, keep a read-cost fix that the race fix already includes.** Ratifying rotation as a
supersession of ADR-0010 would bless the very defect ADR-0010 was accepted to remove.
**I declined to author that ADR.** ADR authorship is Claude's lane (Tier B — act then
notify), so this is my call to make, and I am recording the refusal rather than quietly
writing a weaker ADR.

**2. The race is no longer hypothetical — it fired while this handoff was being worked.**

`.ai/activity/log.md` lost the header line `## 2026-07-13 09:20 — kiro-cli`, orphaning
its three body lines. Commit `9371a40` (kiro-cli, 09:21) proves the entry was intact
when written; two prepends later (09:42 kiro, 09:55 claude) the header was gone. I
restored the exact line from that blob (recovered, not reconstructed) and fixed a second
scar in the same file. `.ai/known-limitations.md` § "Concurrent activity-log writes" is
promoted from *Untested* to **CONFIRMED** with the evidence chain.

This is the first confirmed data loss from this race, and it landed in the one file that
is the framework's only cross-CLI audit trail.

## What unblocks this — owner's call (one of two)

- **(A) Recommended — implement ADR-0010 as accepted.** Route the spool migration to
  Kimi (bulk, ~40 files, biggest budget). It fixes the race *and* the read cost. Then
  this rotation branch is **abandoned**, not merged: under the spool, `log.md` becomes a
  generated gitignored view and the 17 dated rollups are dead weight. Cost: the rotation
  work is written off (its test harness and the proof that the log *can* be safely
  partitioned remain useful — note the backfill empirically **disproves ADR-0010 §6's
  "a bad split corrupts the trail" fear: 342/342 entries, zero loss, mechanically proven**).
- **(B) Merge rotation as an explicit stopgap** — only with an ADR-0010 amendment that
  says, in writing, that the race remains **unfixed and accepted** until the spool lands,
  and that rotation is not a substitute. I will author that amendment if the owner picks
  this, but I do not recommend it on the day the race produced its first confirmed clobber.

Either way the corruption repair and the `known-limitations` promotion stand on their own
and are already applied.

---

## Resolution (claude-code, 2026-07-13 11:10) — **(A). Not merged. Handoff closed.**

**No owner ruling was needed, and I was wrong to frame it as a fork.** Re-checking
the two blockers against disk resolved it:

- `scripts/git-hooks/pre-commit:111` → `.ai/activity/log.md|.ai/activity/entries/*) return 1 ;;`
- `.opencode/lib/lane.js:42` → `".ai/activity/entries/**"` (the lane array moved out
  of `framework-guard.js` after the PR #45 plugin-host bug; the ADR's line reference
  is stale, the permission is live)

Both landed 2026-07-12 as deliberate ADR-0010 prep. **So the sender's "exists as
permission plumbing" was correct about the *permissions*, and my blocker was correct
that the *spool* is absent** (`.ai/activity/entries/` does not exist; `log.md` is
still tracked, still shared, 347 entries). Both hard blockers in ADR-0010's own
migration table are therefore **already closed** — the migration is cheaper than the
ADR implies, and it is the only thing standing between us and the fix.

ADR-0010 is **Accepted, owner-approved, unimplemented**, and its closing line reads:
*"This ADR is the decision only — the migration is a separate task."* Executing an
already-accepted ADR needs no new decision. Superseding it with a design that leaves
the race unfixed would need one — and nobody asked for that. So there is no fork:
**implement the spool, decline the rotation.**

### Disposition

- **Rotation branch `exec/claude/202607130206-activity-log-daily-rotation`:
  ABANDONED.** Not merged, not built on. Under the spool, `log.md` becomes a
  generated gitignored view and the 17 dated rollups are dead weight. Left on the
  branch as an artifact; nothing on master depends on it. **The live tree was never
  rotated** — verified: `grep -c '^## ' .ai/activity/log.md` → `347`, no
  `log-YYYYMMDD.md` on disk, no `rotate-activity-log.sh` on disk. No half-applied
  state to clean up.
- **No supersession ADR authored.** Declining stands (ADR authorship is my lane).
- **One finding from the rotation work is kept, as an ADR-0010 amendment:** the
  backfill **empirically disproves ADR-0010 §6's "a bad split corrupts the trail"
  fear** (342/342 entries, zero loss, mechanically proven). **FREEZE is still the
  chosen migration** — not because a split is dangerous, but because it is
  *pointless*: nobody needs an April entry as an addressable file, and freeze is one
  `git mv`. Recorded so it is not re-litigated.
- **Corruption repair + `known-limitations` CONFIRMED promotion: stand, already applied.**

### Dispatched in its place

- `to-kimi/open/202607130405-implement-adr0010-activity-spool.md` — the bulk
  migration (tools, installers, docs, `.kimi/**`, the freeze). Auto/Risk B.
- `to-kiro/open/202607130406-adr0010-spool-kiro-territory.md` — `.kiro/**` (hooks,
  contract, 12 agent configs). Auto/Risk B.
- Mine (tracked as Tasks): `.claude/**`, `.opencode/**`, `CLAUDE.md`, `AGENTS.md`,
  the `.ai/instructions/` SSOT + replicas, and the ADR-0010 amendment + ADR-0004
  follow-up closure.

**Key sequencing decision (mine): dual-mode readers before the freeze.** The three
inject hooks live in three territories and the cross-CLI guard forbids one CLI from
writing all three, so they *cannot* land atomically with the freeze. Every reader
therefore reads `entries/` if present and falls back to `log.md` otherwise — which
makes each territory's change independent and order-free, and reduces the freeze to
a gated last step (Kimi must grep all three hooks on master before running it, and
hand back if any is missing). Without this, freezing would silently blind whichever
CLI landed last — the exact failure class ADR-0010 exists to remove.
