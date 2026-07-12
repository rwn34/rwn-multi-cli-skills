# 10. Activity Log as an Entry-per-File Spool

## Status

Accepted (owner-approved 2026-07-11)

This ADR **closes the follow-up that ADR-0004's Amendment (2026-07-11)
explicitly scoped out**: "The activity-log write race (above) needs its own
decision. Track it against `.ai/known-limitations.md` § 'Concurrent
activity-log writes'. **Still open**." This is that decision.

It **supersedes the write protocol** — not the content format — stated in
`.ai/instructions/operating-prompt/principles.md` §7 and replicated in all four
CLI contracts ("prepend one activity-log entry"). Entries are now **written**,
never **prepended**.

## Context

### The race

`.ai/activity/log.md` is a single file that **all four CLIs write to**. The
write is a whole-file rewrite: a CLI reads the file, places its entry at the
top, and writes the entire file back. Two CLIs overlapping means the second
writer's `read` predates the first writer's `write`, and the second `write`
destroys the first entry.

The loss is **silent**. There is no error, no merge conflict, no reflog trace,
and — unlike SSOT replica drift, which `.ai/tools/check-ssot-drift.sh` detects
after the fact — **no gate that could ever detect it.** A clobbered log entry is
indistinguishable from an entry that was never written. The activity log is the
framework's only cross-CLI audit trail, and it is the one shared file with no
integrity check.

### Worktrees do not fix this, and cannot

ADR-0004 gives each CLI its own git worktree, which converts code-plane
collisions into honest merge conflicts. It gives the **coordination plane zero
isolation, by design**: `scripts/wt-bootstrap.sh`'s `link_ai()` junctions every
worktree's `.ai/` (`mklink /J`) to the **one canonical `.ai/`** in the primary
checkout. `.ai/activity/log.md` is therefore the *same inode* in every worktree.
Concurrent prepends race exactly as they did before worktrees existed. ADR-0004
says so itself and declines to fix it.

### Why now

The framework survived the 2026-07-11 near-miss (ADR-0004, "Context — the
2026-07-11 near-miss") **by luck**: the concurrent commits happened to touch
disjoint files. `.ai/activity/log.md` was named in that incident's own writeup
as "the obvious candidate" for a real loss. Meanwhile operating-prompt SSOT §14
(delegation economics) makes **parallel cross-CLI dispatch the normal case** —
"if it warrants a subagent, it warrants a handoff." Collision probability is
rising, not falling.

### A serializing writer was already built, and nobody calls it

`.ai/tools/activity-append.sh` exists today (mkdir lock, stale-lock reclaim,
atomic temp-file + rename), with a concurrency test at
`.ai/tests/test-activity-append.sh`. It was written for exactly this hazard
(framework-improvement-backlog #7).

**It has zero callers.** No contract, hook, dispatcher, pane-runner, or agent
config invokes it. All four CLI contracts still instruct the model, in prose, to
*prepend to the file*. This is the decisive evidence in the alternatives
analysis below: a serializing tool protects only the writers that choose to call
it, and our writers are LLMs following prose.

## Decision

**One file per entry. Each CLI writes its own new file and never rewrites a
shared one.**

```
.ai/activity/entries/20260711T222901Z-kiro-cli-dispatch-worktree-a3f9.md
.ai/activity/entries/20260711T222417Z-kimi-cli-sync-s14-7c10.md
.ai/activity/entries/20260711T153512Z-claude-code-delegation-economics-b2e5.md
```

`.ai/activity/log.md` **stops being a source of truth** and becomes a generated,
gitignored view. The race becomes structurally impossible: a unique filename
means no shared write, which means no lock, which means no clobber — on every
OS, in every runtime, including the hookless and headless ones where our
enforcement layer does not reach.

### 1. Filename scheme

    .ai/activity/entries/<YYYYMMDDTHHMMSSZ>-<cli-identity>-<slug>-<rand4>.md

- **Timestamp: UTC, second precision, ISO-8601 basic form.**
- **`<cli-identity>`:** the logging identity (`claude-code`, `claude-auto`,
  `kimi-cli`, `kiro-cli`, `opencode`) — the same value that appears in the entry
  heading.
- **`<slug>`:** short kebab-case topic, for humans skimming `ls`.
- **`<rand4>`:** four lowercase hex characters, freshly random per entry.

**Why UTC, and how the repo's two conventions are reconciled.** The repo
currently uses UTC for *filenames* (`.ai/handoffs/**` — `YYYYMMDDHHMM`, per
`.ai/handoffs/README.md` and CLAUDE.md) and local wall-clock for *human-facing
headings* (`## YYYY-MM-DD HH:MM — <cli>`). That is not an inconsistency to be
broken by fiat; it is a split by **purpose**, and we make it explicit:

> **Filenames are machine sort keys and are always UTC. Headings are human
> annotations and stay local wall-clock.**

Entry filenames therefore follow the existing handoff convention (UTC), and the
entry *body* keeps its current `## YYYY-MM-DD HH:MM — <cli>` local-time heading
verbatim, so a rendered `log.md` reads exactly as it does today. Fixed-width
UTC basic form means **lexicographic filename order == chronological order**,
which is what makes the renderer a plain `sort -r`.

**Why second precision *and* a random suffix.** Second precision alone is not
enough. Two *seats of the same CLI* run concurrently by design — ADR-0009 puts
an interactive Claude and a `claude-auto` worker in the fleet, and its
Amendment (2026-07-10) does the same for Kimi (interactive top cockpit +
`kimi-auto` bottom worker). Identity alone does not separate them if a seat logs
under the same identity string. The 4-hex suffix removes the entire class of
reasoning for 5 characters. It is deliberately **not** a pid and **not** an
atomic-create loop: entries are written by an LLM calling its `Write`/`fs_write`
tool, which has no `O_EXCL`, so collision-freedom must live in the *name*, not
in the write call.

### 2. `log.md` is generated and gitignored — it is NOT committed

`.ai/activity/log.md` is removed from git, added to `.gitignore`, and produced
on demand by a new `.ai/tools/render-activity-log.sh` (concatenate
`.ai/activity/entries/*.md` in reverse filename order; never read
`.ai/activity/archive/**`).

**Committing the rendered view would reintroduce the bug this ADR exists to
fix.** If `log.md` stays tracked, then every CLI that regenerates it produces a
whole-file rewrite of a shared tracked file — and with worktree-per-CLI, four
CLIs on four branches each commit a *different* full-file render (each seeing
only the entries that existed when it rendered). Merging those is a conflict on
every parallel branch at best, and a stale view that silently drops entries at
worst. The shared-write hazard would move from the working tree into git.

**What breaks, honestly:**

- **Nothing load-bearing** — but only because the hook is being changed with it
  (item 3). Today's `UserPromptSubmit` injection depends on `log.md` existing;
  after this ADR it depends on `entries/` instead.
- **`log.md` is no longer browsable on GitHub as one file.** The audit trail is
  browsable as `.ai/activity/entries/` (still committed, still complete, still
  ordered by filename). Reviewers lose "open one file, read the story"; they
  gain "each entry is its own reviewable blob in the diff."
- **A fresh clone has no `log.md`** until someone runs the renderer. Acceptable:
  every consumer that *needs* the data reads `entries/` directly.
- **A rendered `log.md` can be stale** relative to `entries/`. This is why it is
  not committed and why nothing depends on it.

### 3. The `UserPromptSubmit` hook reads `entries/`, not `log.md`

The injection of recent activity into every CLI's context is load-bearing and
must keep working. Today it is an **inline shell command in
`.claude/settings.json`** (not a hook script):

    if [ -f .ai/activity/log.md ]; then echo '--- Recent cross-CLI activity (top of .ai/activity/log.md) ---'; head -40 .ai/activity/log.md; echo '--- end ---'; fi

with byte-identical logic duplicated in `.kimi/hooks/activity-log-inject.sh` and
`.kiro/hooks/activity-log-inject.sh` (`head -40 .ai/activity/log.md`).

All three become: **list the N newest files in `.ai/activity/entries/`
(reverse-sorted by name), cat them, cap the output.** Concretely — the newest
entries are the lexicographically last filenames:

    ls .ai/activity/entries/*.md 2>/dev/null | sort -r | head -n 8 | xargs -r cat | head -60

This is *strictly better* than today: the hook reads the source of truth rather
than a rendered artifact that can lag it, and "the newest 8 entries" is a
sharper context budget than "the first 40 lines", which today truncates
mid-entry whenever an entry is long (several current entries exceed 40 lines on
their own — the injection is already lossy).

### 4. Ordering guarantee — it changes, and it is weaker in one specific way

Today's rule (CLAUDE.md, the `log.md` header, `.ai/activity/archive/README.md`):
*"prepend order is the authoritative sequencing across CLIs; timestamps are
annotations."*

With a spool **there is no prepend order** — no shared file exists to prepend
to, so no write-arrival sequence is observable. The new rule is:

> **Sort order is filename order, i.e. UTC timestamp order. It is best-effort
> chronological, not causal.**

Plainly: entries written by CLIs whose clocks disagree will sort by their
(disagreeing) clocks. In practice all four CLIs run as processes on **one
machine with one clock**, so this is *more* reliable than the old rule, not
less — the old "authoritative prepend order" was in any case a fiction under a
last-writer-wins race, since a clobbered entry has no order at all. But the
guarantee is weaker in one honest respect: **we no longer have any notion of
write-arrival order**, and if the fleet ever spans machines (the `.fleet/` tier
of ADR-0004), clock skew will reorder entries with nothing to appeal to.

### 5. Archival becomes `git mv`

The archive protocol (`.ai/activity/archive/README.md`) today *rewrites*
`log.md`: cut entries out, regroup them by day, append to `YYYY-MM.md`. That is
itself a whole-file rewrite of the shared file — an archive run racing a live
CLI is the same clobber.

With a spool, archiving is a **move, with no content transformation**:

    git mv .ai/activity/entries/202604*.md .ai/activity/archive/2026-04/

- Archive layout becomes **one directory per month** (`archive/YYYY-MM/`)
  holding the entry files verbatim, replacing the one-file-per-month
  `YYYY-MM.md` rollup.
- Triggers are unchanged in spirit; the size threshold restates as an entry
  count (e.g. > 150 files in `entries/`) rather than "log.md > 500 lines".
- The renderer and all three injection hooks read `entries/` only, so the
  existing "do not read `.ai/**/archive/`" rule (CLAUDE.md) is enforced by
  construction rather than by discipline.
- **Entries are never edited, only moved.** "Never rewrite prior entries" stops
  being an honor-system rule and becomes a physical property of the layout.

### 6. Migration of the existing log — FREEZE, do not split

`.ai/activity/log.md` (the current file, in full) is moved verbatim to:

    .ai/activity/archive/log-pre-spool.md

One `git mv`, **zero content transformation**. Entries written from the cutover
forward go to `entries/`. The renderer appends a one-line pointer to the frozen
file at the bottom of `log.md`.

**Recommendation: freeze. Do not mechanically split the history into entry
files.** Reasons:

- The existing log is **not reliably machine-parseable**. Entries vary from 3
  lines to 20+; several contain multi-line `Action:` blocks with their own
  bullet lists, embedded backticks, colons, and `##`-adjacent content. The only
  delimiter is the `## YYYY-MM-DD HH:MM — <cli>` heading, and a splitter that
  gets one boundary wrong silently welds two entries together or truncates one.
- **The upside is zero.** Nobody needs a 2026-04 entry as an individually
  addressable file. The value of the spool is in *future concurrent writes*, and
  a frozen file delivers that identically to a split one.
- **A bad split is worse than a clean freeze** — it corrupts the project's only
  audit trail, in the one operation whose whole purpose is protecting that trail.
  Git would still hold the original, but a corrupted trail that *looks* intact is
  precisely the failure mode this ADR was written to eliminate.

Consequence accepted: history lives in two shapes — a frozen prose file for
everything before the cutover, a spool for everything after. That seam is
permanent, visible, and cheap.

## Consequences

### What this fixes

- **The write race, structurally.** Unique filename ⇒ no shared write ⇒ no lock
  needed ⇒ no clobber. This holds on every OS and in **every runtime**,
  including the ones where our hook layer is known not to fire (Kimi headless,
  Kiro `--trust-all-tools`, all subagents — see `.ai/known-limitations.md`). It
  is not an enforcement rule that a CLI can fail to obey; it is the absence of a
  shared resource.
- **Immutability by construction.** An entry file is written once and thereafter
  only moved. "Never rewrite prior entries" becomes a physical property.
- **Git-level parallelism.** Two CLIs on two branches adding two different files
  never conflict. Today, two CLIs both editing `log.md` on two branches conflict
  *at best*, and clobber *at worst*.
- **The injection hook reads the source of truth** instead of a rendered
  artifact, removing a staleness class that exists today.
- Closes `.ai/known-limitations.md` § "Concurrent activity-log writes"
  (currently *"Mitigation: none yet"*) and the corresponding open follow-up in
  ADR-0004's amendment.

### What it costs

The write protocol is stated in prose in **four CLI contracts, one SSOT, three
SSOT replicas, three injection hooks, two reminder-hook families, two
enforcement allowlists, two installers, and the archive protocol.** Every one of
them must change. **A missed file means a CLI keeps writing to `log.md` and its
entries vanish from the view** — silently, which is the exact failure class this
ADR exists to remove. The complete list is the Migration checklist below.

Two of those are **hard blockers, not documentation**:

- `scripts/git-hooks/pre-commit` matches OpenCode's writable lane as the **exact
  string** `.ai/activity/log.md` (`case "$p" in .ai/activity/log.md|.ai/reports/*|.ai/handoffs/*)`).
- `.opencode/plugin/framework-guard.js` does the same (`rel === ".ai/activity/log.md"`).

Until both learn `.ai/activity/entries/*`, **OpenCode cannot write or commit an
entry at all** — its write is blocked by the plugin and its commit is rejected by
the hook. Ship these two in the same commit as the contract change, or OpenCode
goes silent on day one.

Other costs:

- **Directory growth.** `entries/` accumulates one file per substantive action
  across four CLIs. Archival (now a `git mv`) is the release valve, and it must
  actually be run; nothing reaps automatically.
- **Two shapes of history** across the freeze seam (§6).
- **Reading the log is now a render or a directory listing**, not `cat one file`.

### What it does NOT fix — be explicit

- **Clock skew.** Entries sort by their writers' UTC clocks. Cross-machine skew
  (the `.fleet/` tier) reorders entries, and this ADR gives no better answer than
  today's — it gives a *worse* one in that "prepend order is authoritative" is
  gone (§4).
- **Wrong entries.** A CLI can still write a false, vague, or overclaiming
  entry. That is `self-grep-verify`'s job, not this ADR's.
- **Missing entries.** A CLI that simply forgets to log still leaves no trace.
  The `Stop`-hook reminders remain the only backstop, and they are advisory.
- **Rendered-view staleness.** `log.md` can lag `entries/`. Mitigated by making
  it uncommitted and depended-on by nothing — not by making it correct.
- **The handoff numbering race** (`.ai/known-limitations.md`) — a separate,
  still-open collision on `.ai/handoffs/**`. This ADR's filename scheme is a
  ready-made template for fixing it, but does not fix it.
- **Anything in the code plane.** This is a coordination-plane decision only.

## Alternatives considered

- **(A) A lock-based append helper.** An `mkdir`-lock + atomic-rename writer
  (`.ai/tools/activity-append.sh`), with the per-CLI `PreToolUse` hooks blocking
  direct edits to `log.md` so that every writer is forced through the tool.
  **Rejected — and this is not a hypothetical rejection: the tool already
  exists, and it has zero callers.** `.ai/tools/activity-append.sh` was built for
  this exact hazard, is tested (`.ai/tests/test-activity-append.sh`), and is
  invoked by nothing — no contract, hook, dispatcher, pane-runner, or agent
  config. Every contract still tells the model to prepend to the file directly.
  That is the whole argument: a serializing writer protects only the writers who
  call it, and our writers are LLMs following prose. The "force it with hooks"
  half of the design fails for the same reason ADR-0005 exists —
  `.ai/known-limitations.md` proves per-CLI `PreToolUse` hooks **do not fire** for
  Kimi (any mode, for file writes), for Kiro under `--trust-all-tools`, or for
  subagents in several runtimes. We would be mandating a chokepoint we cannot
  enforce. It also *serializes* rather than *eliminates*: it adds a stale-lock
  failure mode when a CLI dies mid-write (the script's own `kill -0` reclaim path
  is itself a heuristic), and it leaves the file a shared mutable resource.
  **A design that requires everyone to cooperate is strictly worse than a design
  where nobody can interfere.**

- **(B) Status quo, with the SSOT drift gate as the smoke alarm.**
  **Rejected — there is no gate for the activity log.** `check-ssot-drift.sh`
  compares SSOT sources against their replicas; the log has no SSOT and no
  replica, so nothing compares it against anything. This is the *entire point*: a
  clobbered log entry is undetectable after the fact, by any tool we have or
  could easily build. ADR-0004's amendment already rejected this same argument
  for the code plane, where at least the reflog exists. Here, not even that.

- **(C) Per-CLI log shards** — `log-claude.md`, `log-kimi.md`, `log-kiro.md`,
  `log-opencode.md`; each CLI prepends only to its own file, and readers merge.
  **Rejected.** It does not actually eliminate the shared write: **two seats of
  the same CLI run concurrently by design** (ADR-0009: `claude-code` +
  `claude-auto`; Amendment 2026-07-10: interactive Kimi + `kimi-auto`), so two
  processes still rewrite one shard. It shrinks the race window without closing
  it — the worst kind of fix, because it makes the remaining race rarer and
  therefore harder to believe in. And it forces every reader (and the injection
  hook) into an N-way chronological merge anyway, which is the spool's work
  without the spool's guarantee.

## Migration checklist

Every file that must change. Grouped by consequence-if-missed. **This ADR is the
decision only — the migration is a separate task.**

### Blockers — a CLI cannot log at all until these land

| File | Change |
|---|---|
| `scripts/git-hooks/pre-commit` | OpenCode lane whitelist (~L96): exact match `.ai/activity/log.md` → add `.ai/activity/entries/*` (and `.ai/activity/archive/*`). Without this OpenCode's commit is **rejected**. |
| `.opencode/plugin/framework-guard.js` | Lane check (~L84): `rel === ".ai/activity/log.md"` → accept `.ai/activity/entries/**`. Also the `LANE` message string (~L24) and the header comment (~L4). Without this OpenCode's **write is blocked**. |
| `scripts/git-hooks/test-pre-commit.sh` | L69/L75/L132 assert the old path is allowed; add entries-path cases. |
| `.opencode/plugin/test-guard.mjs` | L48 asserts `write(".ai/activity/log.md")` is allowed; update. |

### Protocol — the SSOT and its replicas (drift-gated; must move together)

| File | Change |
|---|---|
| `.ai/instructions/operating-prompt/principles.md` | §7 "prepend one activity-log entry" → "write one entry file"; the §3 state table row (L24) `Activity log \| .ai/activity/log.md` → `.ai/activity/entries/`. |
| `.claude/skills/operating-prompt/SKILL.md` | Replica (body only) — L31, L119. |
| `.kimi/steering/operating-prompt.md` | Replica — L24, L112. |
| `.kiro/steering/operating-prompt.md` | Replica — L24, L112. |

Run `.ai/tools/check-ssot-drift.sh` after; CI drift stays red until all three
replicas land.

### The four CLI contracts (all state the prepend rule)

| File | Change |
|---|---|
| `CLAUDE.md` | § "Cross-CLI activity log" (L51+) — the prepend rule, the timestamp rule, the archive note (L104). |
| `AGENTS.md` | L20 ("append-only cross-CLI activity ledger"), L38, L82. |
| `.opencode/contract.md` | L56 (writable-paths list — **must** name `entries/`), L94 (§ Cross-CLI activity log). |
| `.kimi/steering/00-ai-contract.md` | L14 § heading + body. *(Kimi's territory — hand off, do not edit directly.)* |
| `.kiro/steering/00-ai-contract.md` | L13 § heading + body. *(Kiro's territory — hand off, do not edit directly.)* |

### Hooks — injection (load-bearing) and reminders

| File | Change |
|---|---|
| `.claude/settings.json` | `UserPromptSubmit` is an **inline command** (L34), not a script: `head -40 .ai/activity/log.md` → read newest N files from `entries/`. |
| `.kimi/hooks/activity-log-inject.sh` | L4-6 same change. |
| `.kiro/hooks/activity-log-inject.sh` | L3-5 same change. |
| `.claude/hooks/stop-reminder.sh` | L8-9: `find .ai/activity/log.md -mmin -60` → freshest file in `entries/`. |
| `.kimi/hooks/activity-log-remind.sh` | L4-5 same. |
| `.kiro/hooks/activity-log-remind.sh` | L7-8 same; **and L32** `git status \| grep -v '.ai/activity/log.md'` → exclude `entries/`. |
| `.kimi/hooks/git-dirty-remind.sh` | L8-9: same "is the only change the log?" exclusion. |
| `.claude/hooks/README.md` | Table row describing `stop-reminder.sh`. |
| `.kimi/hooks/README.md` | L19 (inject-hook row). |

### Tools

| File | Change |
|---|---|
| `.ai/tools/render-activity-log.sh` | **New.** `entries/` → `log.md`, reverse filename order, skips `archive/`. |
| `.ai/tools/activity-append.sh` | **Delete** (superseded; zero callers today). |
| `.ai/tests/test-activity-append.sh` | **Delete** with it, or repoint at the new writer. |
| `.gitignore` | Add `.ai/activity/log.md`. |
| `.ai/tools/dispatch-handoffs.sh` | L103 prompt string: "prepend an activity-log entry" → "write an activity-log entry". Cosmetic but it is the instruction every dispatched CLI receives. |
| `tools/4ai-panes/pane-runner.ps1` | L501, L506 — same prompt-string wording. |

### Installers (adopters get the old layout until these change)

| File | Change |
|---|---|
| `scripts/install-template.sh` | `write_clean_activity_log()` (L509-533) writes a `log.md` with the *old* header and `track ".ai/activity/log.md"` → must create `.ai/activity/entries/.gitkeep` instead. |
| `tools/multi-cli-install/src/installer/sanitize.ts` | L36 pushes `.ai/activity/log.md` into `modified`. |
| `tools/multi-cli-install/test/upgrade-phase-a.test.ts` | L210, L226 fixture + assertion on that path. |
| `tools/multi-cli-install/package.json` | Version bump (framework content changed — `scripts/check-version-bump.sh`). |
| `scripts/fleet-init.sh` | L173-204 create a fleet-level `activity/log.md`. **Decide explicitly**: bring `.fleet/` to the spool too, or leave it single-file and say why (the fleet log has exactly one writer per project, so the race does not apply — but the divergence should be a deliberate, documented choice, not an oversight). |

### Docs and state

| File | Change |
|---|---|
| `.ai/activity/archive/README.md` | Rewrite the archival protocol: `git mv` of entry files into `archive/YYYY-MM/`; drop the cut-and-regroup steps; drop the "prepend order authoritative" timestamp note. |
| `.ai/known-limitations.md` | § "Concurrent activity-log writes" — currently *"Mitigation: none yet"*. Mark **resolved by ADR-0010**, structurally. |
| `docs/architecture/0004-worktree-multi-project-topology.md` | Amendment § Follow-ups — the "activity-log write race … **Still open**" bullet is now closed by this ADR. |
| `.ai/tests/concurrency-test-protocol.md` | Its Scenario 1 *is* the log race (L42-50, L129, L184). Either retire it as moot or repoint it to prove the spool under concurrency. |
| `README.md` | L49, L512 (tree diagram), **L585** ("Concurrency is characterized but not tested… known race potential") — that caveat becomes false. |
| `docs/guides/contributing.md` | L88 (prepend rule). |
| `.ai/sync.md` | L159-186 — the clone recipe resets `log.md` in both the bash and PowerShell variants. |
| `.claude/agents/orchestrator.md` | L95 ("Prepend to `.ai/activity/log.md`"). |
| `.kiro/agents/*.json` | 12 agent configs reference the activity log in their prompts. *(Kiro's territory — hand off.)* |
| `CHANGELOG.md` | Changed: activity log is now an entry-per-file spool; `log.md` is a generated view. |
| `.ai/activity/log.md` → `.ai/activity/archive/log-pre-spool.md` | The freeze (§6). Verbatim `git mv`, no content transformation. |

### Order of operations

1. Blockers + tools + hooks + `.gitignore` (one commit — the spool must be
   *writable and readable* before anything is told to use it).
2. The freeze (`git mv` of `log.md`).
3. SSOT + Claude/OpenCode contracts; hand off `.kimi/**` and `.kiro/**` to their
   owners (their territory — the pre-commit cross-CLI guard blocks reaching in,
   except for the `.ai/sync.md`-registered SSOT replicas per ADR-0005).
4. Installers + version bump.
5. Docs, `known-limitations`, ADR-0004 follow-up closure.

## References

- `docs/architecture/0004-worktree-multi-project-topology.md` — Amendment
  (2026-07-11) scopes this race **out** and names it as the unfixed follow-up
  ("the highest-risk shared file in the framework"). This ADR is that follow-up.
- `docs/architecture/0005-commit-governance-backstop.md` — the pre-commit hook
  whose OpenCode whitelist hardcodes the log path.
- `docs/architecture/0009-operator-over-fleet-topology.md` + Amendment
  (2026-07-10) — the two-seats-per-CLI topology that defeats per-CLI shards
  (Alternative C) and motivates the filename's random suffix.
- `.ai/known-limitations.md` § "Concurrent activity-log writes" — the open
  limitation this closes; § "Enforcement reality" — why a hook-enforced
  chokepoint (Alternative A) is not enforceable.
- `.ai/instructions/operating-prompt/principles.md` §7 (cross-CLI continuity),
  §14 (delegation economics — why parallel dispatch is now normal).
- `.ai/tools/activity-append.sh`, `.ai/tests/test-activity-append.sh` — the
  built-and-uncalled serializing writer that Alternative A would have adopted.
- `.ai/activity/archive/README.md` — the archival protocol this ADR replaces.
- `.ai/research/framework-improvement-backlog.md` #7 — concurrency safety.
