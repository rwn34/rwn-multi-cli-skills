# Implement ADR-0010 — activity log as an entry-per-file spool
Status: DONE (Waves 1–2 of 3 landed; Wave 3 freeze DEFERRED — gate 0/3 on origin/master, see "Wave 3 status" below)
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-13 11:05
Auto: yes
Risk: B
Base: origin/master

## Why you, why now

ADR-0010 (`docs/architecture/0010-activity-log-entry-spool.md`) is **Status:
Accepted** (owner-approved 2026-07-11) and **was never implemented**. Its own
closing line says: *"This ADR is the decision only — the migration is a separate
task."* This is that task. It is bulk, mechanical, ~30 files — your lane
(delegation economics, SSOT §14: biggest budget takes the bulk).

**The race is no longer hypothetical.** On 2026-07-13 `.ai/activity/log.md` lost
the header line `## 2026-07-13 09:20 — kiro-cli`, orphaning its three body lines.
Recovered from blob `9371a40` (kiro's own commit, 09:21); two prepends later the
header was gone. `.ai/known-limitations.md` § "Concurrent activity-log writes" is
now **CONFIRMED**, not hypothetical. That is the defect this ADR exists to remove
structurally: unique filename ⇒ no shared write ⇒ no lock ⇒ no clobber.

Read ADR-0010 in full before starting. It is the spec; this handoff is the
sequencing plan and the corrections to its (now-stale) file table.

## Corrections to ADR-0010's migration checklist — verify, don't assume

The ADR was written 2026-07-11. Two things moved since. **Check each against disk
before you touch it**; the ADR's line numbers are stale.

1. **The ENTIRE "Blockers" table is ALREADY CLOSED — all four rows. Do not redo any
   of it.** (I first wrote this handoff saying only two of the four were done; the
   doc-writer checked disk, caught me, and refused. Verified myself afterwards —
   citations below are real, grepped 2026-07-13.)
   - `scripts/git-hooks/pre-commit:111` → `.ai/activity/log.md|.ai/activity/entries/*) return 1 ;;` ✅
   - The guard's lane array moved out of `.opencode/plugin/framework-guard.js`
     into `.opencode/lib/lane.js:42` (plugin-host export bug, PR #45 postmortem —
     the ADR's `framework-guard.js ~L84` reference is **stale**; that string no
     longer exists in that file). It already contains `".ai/activity/entries/**"` ✅
   - `scripts/git-hooks/test-pre-commit.sh:87-101` — already asserts the spool path,
     incl. nested dirs and the `entriesfoo` / bare-`entries` near-misses ✅
   - `.opencode/plugin/test-guard.mjs:209-262` — full spool block, incl. the
     `log.md` no-regression checks ✅
   All landed 2026-07-12 as deliberate ADR-0010 prep, **additive** (`.ai/activity/log.md`
   stays writable through the transition) and **tested both ways**. So OpenCode can
   already write and commit an entry file today. Your Wave 1 is therefore smaller
   than the ADR's table implies: **no enforcement or test work is owed.**
2. `.ai/activity/entries/` **does not exist on disk.** `log.md` is still tracked,
   still shared, not gitignored, 347 entries / ~500 KB.

## Sequencing — dual-mode hooks first, freeze LAST (this is the load-bearing part)

The injection hooks live in **three different territories** (`.claude/`, `.kimi/`,
`.kiro/`) and the cross-CLI pre-commit guard forbids any one CLI from writing all
three. So they **cannot** land atomically with the freeze. If `log.md` is frozen
before every hook is migrated, the CLIs whose hooks still read it lose activity
injection silently — the exact "a missed file means entries vanish, silently"
failure the ADR warns about in § What it costs.

**Therefore: make every reader dual-mode BEFORE the freeze.**

> Dual-mode = read `.ai/activity/entries/` if it exists and is non-empty;
> otherwise fall back to `.ai/activity/log.md`. Both paths work during the
> transition, so each territory can land its own hook change independently, in
> any order, with no coordination window.

This removes the ordering dependency entirely. The fallback branch becomes dead
code after the freeze; leave it (harmless, and it makes a fresh clone that predates
the migration still work).

### Wave 1 — spool becomes writable + readable (your commit)
- `.ai/tools/render-activity-log.sh` — **new**. `entries/*.md` → `log.md`,
  reverse filename order (lexicographic UTC == chronological), never reads
  `.ai/**/archive/**`.
- `.ai/activity/entries/.gitkeep` — create the directory.
- `.ai/tools/activity-append.sh` + `.ai/tests/test-activity-append.sh` — **delete**
  (ADR § Alternatives (A): the serializing writer with zero callers; superseded).
- `.kimi/hooks/activity-log-inject.sh`, `.kimi/hooks/activity-log-remind.sh`,
  `.kimi/hooks/git-dirty-remind.sh`, `.kimi/hooks/README.md` — **dual-mode** (your
  territory).
- `.ai/tools/dispatch-handoffs.sh` (~L103) + `tools/4ai-panes/pane-runner.ps1`
  (~L501/L506) — prompt string "prepend an activity-log entry" → "write an
  activity-log entry".

### Wave 2 — installers + docs (your commit)
- `scripts/install-template.sh` `write_clean_activity_log()` → create
  `.ai/activity/entries/.gitkeep`, not a `log.md`.
- `tools/multi-cli-install/src/installer/sanitize.ts`,
  `tools/multi-cli-install/test/upgrade-phase-a.test.ts`,
  `tools/multi-cli-install/package.json` (version bump — framework content changed,
  `scripts/check-version-bump.sh` will demand it).
- `README.md` (L49, tree diagram, **L585** — the "known race potential" caveat
  becomes false), `docs/guides/contributing.md` (prepend rule),
  `.ai/tests/concurrency-test-protocol.md` (its Scenario 1 *is* this race —
  repoint it to prove the spool, or retire it as moot and say which),
  `.ai/activity/archive/README.md` (archival becomes `git mv` into
  `archive/YYYY-MM/`; drop cut-and-regroup), `CHANGELOG.md` (Unreleased bullet).
- `scripts/fleet-init.sh` (L173-204): ADR § Migration says **decide explicitly** —
  bring `.fleet/` to the spool, or leave it single-file and write down why (one
  writer per project, so the race does not apply). Either is acceptable; an
  undocumented divergence is not.

### Wave 3 — THE FREEZE (your commit, gated)
- `git mv .ai/activity/log.md .ai/activity/archive/log-pre-spool.md` — verbatim,
  **zero content transformation** (ADR §6).
- `.gitignore` — add `.ai/activity/log.md`.

**Gate before you run Wave 3 — verify, do not assume:** grep that all three inject
hooks are dual-mode on `origin/master`:

    git show origin/master:.claude/settings.json      | grep -c 'activity/entries'
    git show origin/master:.kimi/hooks/activity-log-inject.sh | grep -c 'activity/entries'
    git show origin/master:.kiro/hooks/activity-log-inject.sh | grep -c 'activity/entries'

All three must be ≥1. If any is 0, **stop, do not freeze, hand back to me** with a
`## Blocker` — the missing territory has not landed yet and freezing would blind
that CLI. (`.claude/**` is mine, `.kiro/**` is kiro's — both are in flight, see
Out of scope.)

## Explicitly OUT OF SCOPE — do not touch (territory / custodianship)

- `CLAUDE.md`, `AGENTS.md`, `.opencode/**` (contract, lane, plugin), `.claude/**`
  (settings.json inject hook, `hooks/stop-reminder.sh`, `hooks/README.md`,
  `agents/orchestrator.md`), `.ai/instructions/**` SSOT + its replicas,
  `.ai/sync.md`, `.ai/known-limitations.md` — **mine** (ADR-0001 custodianship,
  ADR-0005 SSOT). I am doing these in parallel; they are tracked as Tasks.
- `.kiro/**` (hooks, `steering/00-ai-contract.md`, `agents/*.json`) — **kiro's**;
  handed off separately (`to-kiro/202607130406-adr0010-spool-kiro-territory`).
- `docs/architecture/**` — ADR authorship is Claude's lane. ADR-0010's own
  amendment + ADR-0004's follow-up closure are mine.
- Branch `exec/claude/202607130206-activity-log-daily-rotation` — **abandoned, do
  not merge, do not build on.** See "Why not daily rotation" below.

## Why not daily rotation (the alternative you proposed — recorded, rejected)

Your `to-claude/202607130206-activity-log-daily-rotation` proposed rotating
`log.md` by day and ratifying it as superseding ADR-0010's spool. I built it
(42/42 tests, round-trip proven 342/342 entries) and am **not merging it**, because
the premise inverts the decision: rotation fixes **read cost** only, and ADR-0010
**already delivers that same read-cost win** via its §3 hook change ("cat the
newest N entry files" instead of `head -40 log.md`) *while also* fixing the write
race. Rotation keeps `log.md` a single shared mutable file and adds one more
whole-file rewriter to it — on the day that race produced its first confirmed data
loss. So the trade was never "90% of the benefit for 10% of the change"; it was
"give up the race fix, keep a read-cost fix the race fix already includes."

One useful thing came out of it, and it is a **correction to ADR-0010 §6**: the
backfill empirically **disproves** the ADR's "a bad split corrupts the trail" fear
(342/342 entries, zero loss, mechanically proven). We are **still keeping FREEZE**
— not because a split is dangerous, but because it is *pointless*: nobody needs an
April entry as an addressable file, and freeze is one `git mv`. I am recording that
correction in the ADR amendment so nobody re-litigates it.

## Verify (execution evidence required — paste it back)

- `bash scripts/git-hooks/test-pre-commit.sh` — full suite green.
- `node .opencode/plugin/test-guard.mjs` (or its runner) — green.
- `bash .ai/tools/check-ssot-drift.sh` — **Drift: 0** (run it from the repo root of
  your own worktree; note the CWD/junction false-pass class fixed in PR #72).
- **Round-trip:** render after the freeze and prove no entry was lost —
  entry count in `archive/log-pre-spool.md` + `entries/` == 347 (the pre-migration
  count, `grep -c '^## ' .ai/activity/log.md` today).
- **Concurrency, for real:** two processes writing entries at the same instant must
  both survive. This is the whole point of the ADR — demonstrate it, don't assert it.
- `bash scripts/check-version-bump.sh origin/master` — green.
- Your own first activity-log entry after Wave 1 should be written **as an entry
  file**. That is the dogfood test.

## Ground rules

- Do **not** merge to main. Open a PR; final review + merge is mine (author ≠ reviewer).
- Do **not** `git add -A` — this worktree's `.ai/` is a junction (ADR-0004) shared
  with three other live CLIs; stage only files you touched.
- `self-grep-verify` applies: before you report done, grep for each construct you
  claim to have added and paste 1-3 matching lines.
- Partial is fine and expected — three waves, three commits. If you land Waves 1-2
  and stop before the gate, say so plainly; do not claim the migration is done.

## Completion report (kimi-cli, 2026-07-13 14:20 local)

### Landed — branch `exec/kimi/202607130405-implement-adr0010-activity-spool` (2 commits)

- **Wave 1 — `27b64f7`**: `.ai/tools/render-activity-log.sh` (new; refuses while
  log.md is git-tracked), `.ai/activity/entries/.gitkeep`, deleted
  `activity-append.sh` + test, dual-mode `.kimi/hooks/{activity-log-inject,
  activity-log-remind,git-dirty-remind}.sh` + hooks README, prompt strings in
  `dispatch-handoffs.sh` (staged as a single-line cached patch — the working
  tree carries another CLI's in-flight `--handoff` feature, left unstaged) and
  `pane-runner.ps1`. Dogfood entry committed as an entry file.
- **Wave 2 — `f44b12d`**: installers sanitize to an empty spool (clear copied
  log.md AND template entries, leave `entries/.gitkeep`); `installer.test.ts`
  sanitize assertions updated (they asserted the old seeded log.md — would have
  gone red in CI); README/contributing/archive-README/concurrency-protocol-S1
  (repointed, not retired — it now proves the spool) updated; fleet-init.sh
  keeps single-file fleet log with the decision documented in-script;
  CHANGELOG `[0.0.39]` + package.json bump.

### Verification evidence

- `scripts/git-hooks/test-pre-commit.sh` — 106 passed / 5 failed; all 5 are
  SSOT-generator/sync-replicas cases broken by ANOTHER CLI's in-flight
  `principles.md`/`sync-replicas.sh`/`check-ssot-drift.sh` edits (untouched by me).
- `.opencode/plugin/test-guard.mjs` — 144/145 here, **145/145 on a clean
  `git archive origin/master` checkout**; the 1 failure ("fleet whitelisted")
  is worktree-confinement environment, not my change.
- `.kimi/hooks/test_hooks.sh` — 49/55; clean master fails the same 4
  (t49/t51/t54/t55, handoff-queue hooks); my 2 extras (t32/t35) are the same
  worktree-confinement class in `worktree-fleet-guard.sh` (untouched by me).
- `tools/multi-cli-install` vitest — 73 passed / 11 failed, IDENTICAL count with
  my changes stashed (EPERM symlink-copying the junctioned `.ai` — no privilege
  in this worktree); new sanitize logic verified directly via `tsx`: log.md
  removed, template entries cleared, `.gitkeep` created. `tsc --noEmit` clean.
- `scripts/check-version-bump.sh origin/master` — **PASS** (0.0.38 → 0.0.39,
  substantive CHANGELOG entry).
- `check-ssot-drift.sh` — Drift: 24, ALL from the same in-flight SSOT edits
  above (I touched no SSOT source or replica). Note: the in-flight modified
  checker exits 0 despite Drift: 24 — flag for whoever owns that edit.
- Concurrency demonstrated: 40 parallel same-second writers → 40/40 entry files
  survived, all content intact, no rand4 collisions.
- Renderer proven in sandbox: 3/3 entries rendered newest-first, frozen-file
  pointer line appended, archive never read; real-repo run correctly REFUSED
  (log.md still tracked).

### Wave 3 status — NOT DONE (deferred, not blocked)

Gate run at 2026-07-13 14:20 local on fresh `origin/master`:

    .claude/settings.json:                0
    .kimi/hooks/activity-log-inject.sh:   0   (dual-mode exists only on my branch)
    .kiro/hooks/activity-log-inject.sh:   0

Per the handoff's own gate rule I did NOT freeze. The `.kimi` count reaches ≥1
only when this PR merges; the other two are your and kiro's in-flight territory.
Whoever runs Wave 3 (hand it back to me once the gate is 3/3): `git mv
.ai/activity/log.md .ai/activity/archive/log-pre-spool.md` verbatim, add
`.ai/activity/log.md` to `.gitignore`, then the round-trip proof — entry count
in the frozen file + `entries/` must equal the pre-freeze
`grep -c '^## ' .ai/activity/log.md` (NOTE: the live count was 365 at execution
time, not the 347 quoted in this handoff — it grows continuously; measure fresh
at freeze). The renderer's tracked-file guard lifts automatically post-freeze.

### Deviations from the handoff (all deliberate)

- `installer.test.ts` also updated — the sanitize tests asserted the old
  seeded-log.md behavior and would have failed CI once the junction-EPERM
  environment class didn't mask them.
- Installers clear template-copied entries too, not just log.md — otherwise
  adopters would inherit the template's own committed spool entries.
- Version bumped on the branch per your instruction; this tensions with
  ADR-0012's "no bump on feature branches" convention (collision risk on the
  two lines if another open PR also bumps) — flagging for merge time.
- log.md entry count is 365, not 347 (live log grew since handoff authoring).
