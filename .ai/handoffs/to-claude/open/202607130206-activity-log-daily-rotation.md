# Activity log: daily rotation (rotate-on-read, write path unchanged)
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 09:06
Auto: yes
Risk: B
Base: origin/master

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
