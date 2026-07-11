# Delivery-Awareness Recon (2026-07-11)

Author: claude-code. READ-ONLY verification pass. Scope: exact current state of
gap items **A5, B1, B2, B4** (from `.ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md`)
plus the **Kimi hook duplication / installer idempotency** question, so a
follow-up fixes only what is actually missing.

**Headline:** several of these gaps are already fixed *in the repo SSOT* since
the gap analysis was written — but the fixes have **not propagated to the machine's
global Kimi config**, and two are genuinely still open (Kiro Stop queue-count;
installer legacy-block migration). Details per item.

---

## 1. A5 — Adopter completeness — STATUS: OPEN (partial)

**Does `install-template.sh` copy all ADRs?** No — only ADR-0001.
`scripts/install-template.sh:360` copies exactly one architecture file:

```
copy_file "docs/architecture/0001-root-file-exceptions.md"
```

The repo has **9 ADRs** (`docs/architecture/0001…0009`) plus `TEMPLATE.md`. 0002–0009
are never copied.

**Does it copy the pane-runner/fleet scripts (`tools/4ai-panes`) and `docs/specs`?** No.
Phase 1 (`phase1()`, lines 338–383) copies `.ai/ .claude/ .kimi/ .kiro/ .opencode/
.archive/`, four root files, two CI workflows, `.codegraph/config.json`, and
**only `scripts/git-hooks`** (`wire_git_hooks`, line 379 / 385–400). The explicit
comment at lines 381–382 confirms the rest of `scripts/` is deliberately not copied.
`tools/4ai-panes/` and `docs/specs/` appear nowhere in the script.

### What an adopted project WOULD receive
- `.ai/`, `.claude/`, `.kimi/`, `.kiro/`, `.opencode/`, `.archive/`
- `CLAUDE.md`, `AGENTS.md`, `opencode.json`
- `docs/architecture/0001-root-file-exceptions.md` (only)
- `.github/workflows/framework-check.yml`, `.github/workflows/gates.yml`
- `.codegraph/config.json`, `.mcp.json` (created/merged)
- `scripts/git-hooks/` (+ `core.hooksPath` wired)
- `.ai/config-snippets/kimi-hooks.toml` (inside the copied `.ai/`)

### What an adopted project WOULD NOT receive
- `docs/architecture/0002…0009` + `TEMPLATE.md` (8 ADRs)
- `docs/specs/` (all 4: `4ai-panes-install-sync.md`, `framework-install-drift-check.md`,
  `global-config-tracking.md`, `TEMPLATE.md`)
- `tools/4ai-panes/` entirely (Selector, pane-runner, restart-pane, fleet-clis,
  Launch4Panes, run-pane-supervised, tests) — **no fleet automation at all**
- `scripts/` except `git-hooks/`: notably `scripts/fleet-init.sh`,
  `scripts/sync-4ai-panes-install.ps1`, `new-project.sh`, `wt-bootstrap.sh`,
  `check-version-bump.sh`

### Dangling references in copied artifacts (governance/automation links that break)
1. **ADR cross-refs (only 0001 exists):**
   - `scripts/git-hooks/pre-commit:3,40,71,139,166,191` → ADR-0005, ADR-0003
   - `.kiro/hooks/framework-dir-guard.sh:47` → ADR-0003
   - `.kiro/hooks/worktree-confinement-guard.sh:2,46,53` → ADR-0004
   - `.kiro/hooks/fleet-whitelist-guard.sh:2,54,74` → ADR-0004
   - `.kimi/hooks/worktree-fleet-guard.sh:2,46,54,60,89` → ADR-0004
   - `.claude/hooks/pretool-write-edit.sh:65,71,90,100,106,143,152,177` → ADR-0002/0003/0004
   - Every governance message an adopted project's guard prints cites an ADR
     doc that is not present.
2. **Missing `scripts/fleet-init.sh` (not copied):** referenced by
   `.claude/hooks/pretool-write-edit.sh:123`, `.kiro/hooks/fleet-whitelist-guard.sh:54`,
   `.kimi/hooks/worktree-fleet-guard.sh:76` ("Scaffold the fleet tier first
   (scripts/fleet-init.sh)"). The script won't exist for the adopter.
3. **Missing `scripts/sync-4ai-panes-install.ps1` + `tools/4ai-panes/` + `docs/specs/`:**
   the copied git hooks actively point at them —
   `scripts/git-hooks/post-checkout:21,38,51`, `post-commit:19,25,43,56`,
   `post-merge:11,17,34,47` set `SYNC_SCRIPT="$REPO_ROOT/scripts/sync-4ai-panes-install.ps1"`
   and cite `docs/specs/4ai-panes-install-sync.md`. In an adopted project these
   hooks no-op safely (their `grep -q '^tools/4ai-panes/'` gate never matches
   because that tree doesn't exist), but the SYNC_SCRIPT path and the spec ref dangle.

**Recommended fix:** copy all `docs/architecture/*.md` (change line 360 to a dir
copy of `docs/architecture/`, keeping the phase-3 ADR amend logic pointed at 0001).
Make an explicit product decision on shipping `docs/specs/` + `tools/4ai-panes/` +
`scripts/fleet-init.sh` to adopters: either copy them, or gate/soften the guard
messages and git-hook SYNC_SCRIPT refs so they don't cite files an adopter lacks.
Lowest-effort correctness win: copy the ADRs (they're small, pure docs, and every
guard message references them).

---

## 2. B1 — Kimi inbox listing on session start — STATUS: DONE in SSOT, NOT applied on machine

**Is `handoffs-remind.sh` wired into Kimi?**
- **SSOT snippet** `.ai/config-snippets/kimi-hooks.toml:76–83`: YES — a
  `SessionStart` `[[hooks]]` runs `bash .kimi/hooks/handoffs-remind.sh`.
- **Repo mirror** `.kimi/config.toml:70–77`: YES — same SessionStart entry.
- **Machine global** `~/.kimi-code/config.toml`: **NO.** The installer-appended
  block (lines 111–181, marker `# ADDED BY install-template.sh kimi-hooks (template @ 8ce95af)`)
  is the OLD 4-guard-only snippet — it has no SessionStart entry at all. The
  hand-written block (lines 43–82) also has none.

**Distinction requested (listing vs dispatcher):** Both are in the SSOT now.
- Inbox **LISTING** (human-visible): `handoffs-remind.sh` at SessionStart — snippet lines 76–83.
- Auto-**DISPATCHER** (B3): `dispatch-own-queue.sh` at SessionStart — snippet lines 93–101.

So the gap-analysis note ("wires only the 4 guards — no SessionStart handoff
reminder at all") is **stale**; the SSOT snippet was updated after that report.
`handoffs-remind.sh` itself exists and is correct (`.kimi/hooks/handoffs-remind.sh`,
filters Status:OPEN + Auto:yes + Risk A|B, recursion-guarded).

**Net:** B1 is DONE in the repo. The only remaining defect is that the machine's
global config predates this snippet (see item 5), so on THIS machine Kimi still
has no listing. Fixing item 5 (re-wire the machine to the current snippet) closes
the residual B1 gap. No new code needed for B1 itself.

---

## 3. B2 — Kiro agent pinning — STATUS: DONE

Every programmatic interactive/headless Kiro launch path pins `--agent orchestrator`:

| Path | Line | Command |
|---|---|---|
| Selector.ps1 (interactive) | `tools/4ai-panes/Selector.ps1:53` | `kiro-cli chat --trust-all-tools --agent orchestrator` |
| pane-runner Get-InteractiveCmd | `tools/4ai-panes/pane-runner.ps1:98` | `kiro-cli chat --trust-all-tools --agent orchestrator` |
| pane-runner Get-HeadlessCmd | `tools/4ai-panes/pane-runner.ps1:85` | `kiro-cli chat --no-interactive --trust-all-tools --agent orchestrator` |
| dispatch-handoffs.sh headless | `.ai/tools/dispatch-handoffs.sh:84` | `kiro-cli chat --no-interactive --trust-all-tools --agent orchestrator` |

The dispatcher carries an explicit rationale comment (`dispatch-handoffs.sh:67–71`)
that a bare `kiro-cli chat` runs the built-in default agent which "carries NO
guard hooks," so pinning is mandatory.

**Is bare `kiro-cli chat` reachable anywhere the docs endorse?** No endorsed path.
Every `kiro-cli chat`-without-`--agent` hit in the tree is either (a) prose in
reports/handoffs/activity explicitly describing it as the *unsupported* hookless
default (e.g. `.ai/reports/kiro-cli-2026-07-09-guardfix.md:34`,
`.ai/handoffs/to-kiro/done/202607101901-…:65` "treat a bare `kiro-cli chat` as
unsupported"), or (b) one **stale historical table** in
`.ai/research/4ai-panes-integration-notes.md:38` (`kiro-cli chat --trust-all-tools`,
no `--agent`) — a research note, not a launch instruction a human is told to run.
No README/how-to endorses bare `chat`.

**Recommendation:** nothing required. Optional hygiene: correct or annotate the
stale `4ai-panes-integration-notes.md:38` table row so it doesn't read as a launch
recipe. Selector.ps1:53 already carries a TODO(owner) about the v3-TUI launch
string; that is a separate, tracked concern, not a bare-`chat` regression.

---

## 4. B4 — Kimi/Kiro Stop queue-count reminder — STATUS: Kimi DONE in SSOT / Kiro OPEN

**Baseline (Claude):** `.claude/settings.json:56–63` Stop → `stop-reminder.sh`
(per-queue counts). `.claude/settings.json:39–54` SessionStart → `session-start.sh`
+ `.ai/tools/dispatch-own-queue.sh`.

**Kimi:**
- SSOT `.ai/config-snippets/kimi-hooks.toml:85–91` and repo `.kimi/config.toml:79–85`:
  Stop → `handoff-queue-count.sh`. That script (`.kimi/hooks/handoff-queue-count.sh`)
  is a genuine per-queue **count** reminder (mirrors Claude's stop-reminder "1b":
  iterates `to-*/open`, prints counts + auto-dispatchable hint). → **DONE in SSOT.**
- Machine `~/.kimi-code/config.toml:79–82`: Stop → `activity-log-remind.sh` only
  (an **activity-log nag**, not a queue count — see `.kimi/hooks/activity-log-remind.sh`,
  it just checks whether `log.md` was touched in 60 min). So on the machine Kimi
  has **no** queue reminder. Closed by re-wiring to the current snippet (item 5).

**Kiro:** **OPEN.** `.kiro/hooks/guards.json:72–78` Stop → `activity-log-remind.sh`
— an activity-log nag, **not** a queue-count reminder. Kiro has no Stop or
SessionStart *count* hook. It DOES surface handoffs at SessionStart two ways:
`activity-log-inject.sh` (`guards.json:4–10`) lists `to-kiro/open/*.md`
(`.kiro/hooks/activity-log-inject.sh:16–21`), and `dispatch-own-queue.sh`
(`guards.json:11–17`) lists+dispatches its own queue. But there is **no
turn-end (Stop) queue-count poll** equivalent to Claude's `stop-reminder.sh` /
Kimi's `handoff-queue-count.sh`.

**Answering the explicit sub-question:** the machine's Kimi Stop
`activity-log-remind.sh` is a plain activity-log nag, NOT a queue reminder.

**Recommended fix:** add a Kiro Stop hook that runs a queue-count reminder
(port `handoff-queue-count.sh` to `.kiro/hooks/` and add a `Stop` entry to
`guards.json`). Kimi needs no new code — just the machine re-wire in item 5.

---

## 5. Kimi hook duplication / installer idempotency — STATUS: OPEN (machine dup + installer legacy-block blind spot)

### Current machine state (`~/.kimi-code/config.toml`)
Two overlapping guard blocks:
- **Block 1 (hand/earlier-wired), lines 43–82:** `safety-check.ps1` (Bash),
  `root-guard`, `framework-guard`, **`worktree-fleet-guard`**, `sensitive-guard`,
  `destructive-guard`, plus Stop `activity-log-remind`.
- **Block 2 (installer-appended), lines 111–181:** header
  `# ADDED BY install-template.sh kimi-hooks (template @ 8ce95af)`, then only
  `root-guard`, `framework-guard`, `sensitive-guard`, `destructive-guard`
  (4 guards; **no** worktree-fleet-guard, **no** SessionStart, **no** Stop).

Result: `root-guard`, `framework-guard`, `sensitive-guard`, `destructive-guard`
each fire **twice**.

### (a) Why the append produced duplicates
The block that landed on the machine (`template @ 8ce95af`) was written by an
**older append-once `wire_kimi_hooks`** that guarded on a **whole-block marker**
(`# ADDED BY install-template.sh …`), not on the presence of individual hooks.
Block 1 was already present but does not contain that marker, so the old wire
step saw "my marker is absent" and appended its whole 4-guard block — never
noticing those four guards already existed in Block 1. So: **it checked only a
whole-block marker, not pre-existing individual hooks** → duplication.

### (b) The idempotency bug in the CURRENT installer
The current `wire_kimi_hooks` (`install-template.sh:817–827`) uses
`reconcile_block` (lines 680–737) keyed on **new sentinels**
`# >>> rwn-framework:kimi-hooks >>>` / `# <<< rwn-framework:kimi-hooks <<<`
(the snippet now carries them, `.ai/config-snippets/kimi-hooks.toml:1,102`).
`reconcile_block` only SUPERSEDES when BOTH sentinels are already in the target
(lines 688–693). The machine has **neither sentinel** (its block uses the legacy
`# ADDED BY …` marker). So the next install run takes the CREATE branch
(line 727+) and **appends a THIRD block** — the sentinel scheme is idempotent
only for machines already migrated to sentinels; it is blind to the legacy
append-once block and cannot clean it up.

### (b) Correct complete single hook set for Kimi
Union of all intended hooks. Note the SSOT snippet is itself **missing
`worktree-fleet-guard`** (it still says "4 guards" — `.ai/config-snippets/kimi-hooks.toml:8`),
yet `.kimi/hooks/worktree-fleet-guard.sh` exists and Kiro wires the ADR-0004
equivalent. Kimi is an executor, so it should enforce it too. The correct managed
block = current snippet **plus worktree-fleet-guard**:

PreToolUse (Write|Edit):
1. `root-guard.sh`
2. `framework-guard.sh`
3. `sensitive-guard.sh`
4. **`worktree-fleet-guard.sh`**  ← must be ADDED to the snippet (currently absent)

PreToolUse (Bash):
5. `destructive-guard.sh`

SessionStart:
6. `handoffs-remind.sh` (inbox listing, B1)
7. `dispatch-own-queue.sh` (auto-dispatch, B3)

Stop:
8. `handoff-queue-count.sh` (queue counts, B4)

**Outside** the managed block (personal / not framework-owned): the user's
`safety-check.ps1` Bash hook (snippet doc explicitly says KEEP it). Design call
on `activity-log-remind` at Stop: the snippet dropped it in favor of
`handoff-queue-count`; Kiro keeps the activity nag. If the activity-log nag is
still wanted for Kimi, add a second Stop entry — but that is optional and
separate from the guard dedupe.

### (c) Which current machine block is safe to remove
**Remove Block 2 entirely (lines 111–181, including its `# ADDED BY …` header).**
Every hook in Block 2 is a strict subset of Block 1 (Block 1 additionally has
`safety-check.ps1`, `worktree-fleet-guard`, and Stop `activity-log-remind`), so
deleting Block 2 loses nothing. That resolves the immediate duplication.

To reach the *correct* set (not just dedup), the fuller machine end-state is:
keep `safety-check.ps1` (line 43–47, personal), then replace Block 1's project
guards with one sentinel-fenced managed block = the corrected snippet (guards
1–5 + SessionStart 6–7 + Stop 8). Practically: delete Block 2, then re-run the
fixed installer (below) which will lay down the sentinel block.

### Recommended fixes
1. **Snippet:** add the `worktree-fleet-guard.sh` `[[hooks]]` entry to
   `.ai/config-snippets/kimi-hooks.toml` (and the repo mirror `.kimi/config.toml`);
   update the stale "4 guards" wording. *(NB: the repo `.kimi/config.toml` also
   uses Kiro-style matchers `WriteFile|StrReplaceFile|Shell` instead of Kimi's
   `Write|Edit|Bash` — worth reconciling while touching it, though that file is
   not auto-loaded by Kimi.)*
2. **Installer idempotency:** have `wire_kimi_hooks`/`reconcile_block` also strip
   any legacy `# ADDED BY install-template.sh kimi-hooks` … block before/while
   reconciling the sentinel block, so machines wired pre-sentinel get migrated
   (deduped) instead of gaining a third block.
3. **Machine dedupe (one-time, manual/tooled):** delete lines 111–181 of
   `~/.kimi-code/config.toml`; then re-run the fixed installer to install the
   corrected sentinel block (or hand-paste the corrected snippet).

---

## Prioritized fix list

1. **[HIGH, small] Installer legacy-block migration (item 5b)** — stop the
   installer minting a 3rd Kimi block; strip the legacy `# ADDED BY …` block during
   reconcile. Unblocks getting the machine (and every pre-sentinel adopter) to the
   correct single set.
2. **[HIGH, small] Machine dedupe (item 5c)** — remove `~/.kimi-code/config.toml`
   lines 111–181; re-wire to the current snippet. This single action also closes
   the residual **B1** (Kimi listing) and **B4-Kimi** (Stop queue count) gaps on
   this machine — both already fixed in SSOT, just not applied.
3. **[MED, small] Add `worktree-fleet-guard` to the Kimi snippet (item 5b)** —
   the snippet is missing a guard that exists and applies (ADR-0004). Correctness gap.
4. **[MED, small] Kiro Stop queue-count reminder (B4)** — port
   `handoff-queue-count.sh` to `.kiro/hooks/` + add a `Stop` entry to
   `guards.json`. Only genuinely-open behavioral gap of the four.
5. **[MED] Copy all ADRs in the installer (A5)** — change `install-template.sh:360`
   to copy `docs/architecture/` wholesale; un-dangle every guard's ADR citation.
6. **[LOW, decision] A5 product call** — decide whether `docs/specs/`,
   `tools/4ai-panes/`, `scripts/fleet-init.sh`, `scripts/sync-4ai-panes-install.ps1`
   ship to adopters; otherwise soften the guard messages + git-hook SYNC_SCRIPT
   refs that point at them.
7. **[LOW] B2 hygiene** — annotate the stale bare-`chat` row in
   `.ai/research/4ai-panes-integration-notes.md:38`. B2 is otherwise DONE.

### Already done — skip
- **B1** — SSOT wired (`kimi-hooks.toml:76–83`, `.kimi/config.toml:70–77`). Only
  the machine re-wire (fix #2) remains.
- **B2** — all launch paths pin `--agent orchestrator`; no endorsed bare `chat`.
- **B4 (Kimi)** — SSOT wired (`kimi-hooks.toml:85–91`). Machine re-wire (fix #2) remains.

## Confidence / caveats
- Machine `~/.kimi-code/config.toml` read directly (55xx bytes, quoted lines above);
  the duplicate is real, not inferred.
- Kimi/Kiro hook *runtime* firing was not exercised live (config-location inference,
  same caveat as the gap analysis). File wiring is confirmed by direct read.
- `.migrated-to-kimi-code` marker present (`~/.kimi/.migrated-to-kimi-code`) confirms
  `~/.kimi-code/config.toml` is the live path.
