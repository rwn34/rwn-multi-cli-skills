# Known framework limitations

Living document. Records runtime/platform quirks that config cannot fix.
Any AI CLI hitting behavior that seems wrong should check here first.

---

## Enforcement reality: hooks are NOT a blanket "hard block" (characterized 2026-07-09)

**Status:** Characterized by the cross-CLI validation campaign 2026-07-09
(`.ai/reports/claude-2026-07-09-validation-rollup.md`). This corrects an
overclaim: the framework previously described per-CLI PreToolUse hooks as a
"hard block" on cross-CLI/source/sensitive writes. **Live testing proved that
is only true in some modes.** Do not rely on hooks as the sole guarantee.

**Proven per-CLI/per-mode matrix (live, not unit-tested):**

| CLI | Interactive | Headless dispatch | Subagent |
|---|---|---|---|
| Claude | ✅ blocks | ✅ blocks | ✅ blocks (hooks inherit) |
| OpenCode | ✅ | ✅ | ✅ (JS plugin fires every tool call) |
| Kimi | ❌ **custom hooks did NOT fire live** (owner pane test 2026-07-09: `.kiro/` write succeeded; only Kimi's NATIVE secret guard blocked `.env`) | ❌ **`kimi -p` runs ZERO hooks** | ❌ prompt-only |
| Kiro | ✅ (needs `--agent orchestrator`; bare chat = hookless default) | ❌ **`--trust-all-tools` makes hooks + `allowedPaths` inert** | ❌ subagent hooks never fire |

**Kimi live-test finding + ROOT CAUSE (2026-07-09):** an owner interactive-pane
test showed a `.kiro/` write succeeding (not blocked). Kimi's own live diagnosis
(17:16) found TWO causes: (1) **stale session** — Kimi caches hook config at
session start; the test pane held config cached from 06:06 and never reloaded,
so the fixed hooks weren't even loaded; (2) the guards had the **python-stub
fail-open** bug (same class fixed in Claude/Kiro). BOTH now fixed: all 5
`.kimi/hooks/*.sh` rewritten python-independent + fail-CLOSED (48/48; manual
stdin tests block `.kiro/`/`.env`/root/destructive; fail-closed on malformed
JSON). **Caveat that persists:** Kimi only (re)loads hook config at session
START — a long-lived pane runs whatever config existed when it launched, so a
config fix requires a fresh Kimi session to take effect. **FRESH-SESSION
RE-TEST (2026-07-09, owner) STILL FAILED:** `.kiro/probe.txt` wrote through;
only `.env` blocked (Kimi's native secret check). So the fail-closed rewrite +
fresh session did NOT restore the block — Kimi's custom config `[[hooks]]`
PreToolUse guards **do not fire for file-write tools** in this setup, period.
**`--yolo` hypothesis REFUTED (owner no-yolo re-test 2026-07-09):** launched
`kimi` WITHOUT `--yolo` (approval prompts active — "Approved for session:
Writing .kiro/probe.txt" fired), and the `.kiro/` write STILL went through. So
it is NOT the yolo flag. Definitive conclusion: **Kimi's config `[[hooks]]`
PreToolUse guards do not fire for the `Write`/`Edit` file tools at all in this
Kimi version — likely Kimi only fires PreToolUse for shell/`Bash`, not file
writes.** This is a Kimi RUNTIME limitation, unfixable from our config; our
entire `.kimi/hooks/*` layer (matcher/python/fail-closed fixes) perfects a
script Kimi never invokes for Write. `.env` is caught only by Kimi's NATIVE
secret check. We STOP here (ADR-0007 non-goal) — per-CLI hooks are unreliable
and, for Kimi file-writes, non-functional. **The git pre-commit backstop (ADR-0005) is the guaranteed net** —
LIVE-PROVEN to reject a `kimi-cli`→`.kiro/` commit ("committer 'kimi-cli' may
not commit this path", exit 1): a bad Kimi write can hit local disk but CANNOT
reach the shared repo. Kimi's native secret guard independently protects `.env`.

**Root causes:**
- **Claude (now FIXED):** hooks parsed JSON via `python3`, which on Windows
  resolves to the Store alias stub (empty stdout, exit 0) → `|| python`
  fallback never fired → path empty → fail-OPEN. Fixed 2026-07-09
  (python-independent sed extraction + fail-CLOSED): commits `588ed9c`
  (write/edit), `c5afd79` (bash). 54/54 incl. python-less regression.
- **Kimi:** `kimi -p` (headless) does not execute hooks at all (verified —
  PreToolUse + SessionStart probes never fired). Interactive mode does.
- **Kiro:** the mandatory headless flag `--trust-all-tools` auto-approves
  path-violation prompts, so `allowedPaths` (an approval policy, not a hard
  deny) and preToolUse hooks are both inert headless. Interactive + a
  configured agent enforce.

**What actually protects the framework:**
1. **Interactive mode:** per-CLI hooks (all four, after the 2026-07-09 fixes).
2. **Headless / trust-all / subagent:** **prompt-level SAFETY RULES** baked
   into each executor's agent prompt (the model refusing) — soft but proven to
   hold in the campaign's adversarial test (Kiro T-K3 PASS).
3. **Universal mechanical net:** the **git pre-commit backstop** (ADR-0005) —
   a repo-level hook that catches bad writes at the commit chokepoint
   regardless of any CLI's runtime hook behavior. This is the only mechanical
   layer that reaches headless/trust-all/hookless runtimes.

**Mitigation / working rule:** treat prompt SAFETY RULES + the git pre-commit
backstop as the real guarantees for unattended/headless work; treat per-CLI
hooks as the interactive-mode + defense-in-depth layer. Never dispatch a
security-sensitive change to a headless Kimi/Kiro session assuming its hooks
will stop a bad write — they won't.

---

## Bash exposure reduction — two residuals it does NOT close (2026-07-12)

**Status:** Open, accepted. Recorded alongside the per-agent shell-command
restriction (`refactorer`, `security-auditor`, `data-migrator` — see
`.ai/instructions/agent-catalog/principles.md`, "Per-agent shell command sets").
Design: `.ai/reports/kiro-2026-07-12-bash-exposure-design.md` (kiro-cli).

That change narrows three agents from "any shell command" to "the commands their
job needs". **Zero agents lost Bash.** It is a real but modest reduction in
*default* blast radius. It is explicitly NOT a fix for either of the following.

### Residual 1 — a restricted Bash is still an evadable Bash (ACCEPTED, NOT CLOSED)

A command-NAME allowlist does not survive an adversarial model. Restricting
`refactorer` to `pytest` does not stop `eval`, `sh -c`, `$(...)`, base64-decoded
commands, or variable-built paths; nor does it stop an allowlisted command being
piped into a non-allowlisted one (`semgrep --json | tee .kimi/evil.md` — the
scanner is permitted, the `tee` is the violation). Kiro's `allowedCommands` is a
name allowlist and adds no fail-closed handling for wrapper constructs.

**Why we are not closing it:** closing it means re-deriving PR #53's `pretool-bash.sh`
§2.3 fail-closed logic inside a *second* enforcement point, keyed on command names
instead of paths. That is the "two surfaces, one rule, nothing keeping them in
lockstep" trap this framework has hit repeatedly. The adversarial case stays with
the guard (Claude) and with prompt-level SAFETY RULES. **Read the restriction as
"take the cheap, real, no-new-surface win" — NOT as "Bash evasion is solved."**

### Residual 2 — Kimi and Kiro subagents do not inherit hooks AT ALL

For Claude subagents, the restriction is a *complement* to the guard: hooks
inherit, so `pretool-bash.sh` is still behind it. **For Kimi and Kiro subagents
there is nothing behind it.** Kiro subagent hooks never fire (see "Kiro CLI —
subagent hook inheritance broken" above, upstream bug #7671); Kimi's PreToolUse
guards do not fire for file-write tools at all and `kimi -p` runs zero hooks (see
"Enforcement reality" above).

So for Kimi/Kiro subagents, **exposure reduction is not a defense-in-depth layer —
it is the ONLY control**, backed only by prompt-level rules and the ADR-0005 git
pre-commit backstop. This is a **platform limitation that no allowlist can fix.**
Kiro's `toolsSettings.execute_bash.allowedCommands` is hard-enforced at the tool
layer (not the hook layer), so it does survive the subagent gap — but it is still
only a command-name allowlist, i.e. Residual 1 applies on top.

**What NOT to do because of this:**
- Do not describe the three restricted agents as "sandboxed" or "locked down".
  They are *narrowed*, and only softly so on Claude and Kimi.
- Do not assume a Claude/Kimi agent's prose command list is enforced. It is not —
  only Kiro's is mechanical. See the enforcement matrix in the agent catalog.

---

## Crush — no hook layer (CLOSED by OpenCode swap, 2026-07-09)

**Status:** CLOSED 2026-07-09. Crush is replaced by OpenCode as the 4th CLI
(ADR-0002 amendment 2026-07-09, owner directive) — the "no hook layer,
prompt-only guardrails" gap this entry documented no longer applies to the
lane. History: documented 2026-07-07 at Crush onboarding; Stage 2 granted
2026-07-08; identity drift in daily `--yolo` use confirmed the gap as a
practical failure and motivated the swap.

**How the gap is closed:** OpenCode's guardrails are mechanical, not
prompt-level — its permission system (`allow`/`ask`/`deny`) removes denied
tools from the model's tool list at the harness level (smoke-test proven
2026-07-09), and the JS plugin `.opencode/plugin/framework-guard.js` provides
worktree-confinement / lane-guard parity with the other CLIs' hook layers.
Per-deploy human confirmation is retained as policy (Tier C) regardless.

**Minor known quirk (OpenCode):** the OpenCode TUI fails under
headless/redirected launches with OpenTUI DLL error 126; it renders correctly
in a real Windows Terminal session (owner-verified 2026-07-09). Headless work
uses `opencode run` and is unaffected. Also: `opencode run` headless with
`edit: "ask"` auto-rejects writes — the dispatcher passes `--auto`; the
framework-guard plugin fires before the permission layer and remains the
mechanical lane barrier.

---

## `.ai/` durability contract (snapshot-copy + per-handoff commits, ADR-0016)

**Status:** Accepted 2026-07-18.

Canonical `.ai/` state is durable because the dispatcher commits it after every
executor sync-back. Executor worktrees receive `.ai/` as an ordinary-file
snapshot, not a junction, so destructive git verbs inside a worktree cannot
follow a symlink and delete the shared coordination plane.

**What is durable:** handoff queue moves, activity-log appends, reports, and
steering changes that have been synced back and committed.

**What is NOT durable:** in-flight changes inside a running executor worktree
that have not yet reached sync-back. A crash between mutation and sync-back
loses that worktree's `.ai/` delta.

**The prepend race:** RESOLVED by ADR-0010 Wave-3 (2026-07-21). The activity
log is now an entry-per-file spool under `.ai/activity/entries/*.md`; each
writer creates a distinct file, so concurrent writes no longer clobber each
other. The rendered `.ai/activity/log.md` is generated by
`bash .ai/tools/render-activity-log.sh` and is gitignored. The encoding repair
in `.ai/tools/check-encoding.sh` remains as defense in depth for shared-state
files.

See `docs/architecture/0016-ai-durability-contract.md` for the full contract.

---

## Executor worktree shows every `.ai/` file as deleted after snapshot removal (ADR-0016)

**Status:** Characterized 2026-07-21.

**What:** After a dispatcher run, the executor worktree may report hundreds of
`.ai/**` paths as deleted (` D` in column 2 of `git status --short`). This looks
like a catastrophic wipe, especially inside a worktree whose canonical `.ai/`
was just snapshotted in.

**Why it is not an incident:** Under ADR-0016 the worktree's `.ai/` is an
ordinary-file snapshot copy, not a junction. `scripts/wt-bootstrap.sh` and
`.ai/tools/sync-ai-state.sh` remove that snapshot by design once the executor
finishes (`safe_rm_rf "$wt_ai"`). Because every `.ai/` file is tracked by git,
removing the snapshot directory leaves git showing every tracked file as
unstaged-deleted. That is the expected arithmetic: the files are gone from the
worktree, but the canonical `.ai/` in the primary checkout is untouched.

**How to tell the difference between this artifact and a real canonical deletion:**

| Signal | Normal ADR-0016 artifact | Real canonical deletion |
|---|---|---|
| `git status` column | Column 2: ` D` (unstaged) | Column 1: `D ` (staged) or untracked leftovers |
| Location | Inside executor worktree only | Primary checkout `.ai/` |
| Canonical files | Still present in primary checkout | Missing from primary checkout |
| Sync-back commits | No mass-deletion commit | Commit with mass `.ai/` deletion |

**What to do:** Do not panic-commit the deletions. If the deletions are only in
the worktree and column 2, the dispatcher has done its job. If you see column-1
deletions in the primary checkout, that is a real incident — stop and
investigate.

**Prevention:** Treat `git status` inside an executor worktree as a post-snapshot
artifact, not as canonical state. Canonical state is authoritative only in the
primary checkout.

---

## Kiro CLI — subagent hook inheritance broken

**Status:** Open. Confirmed empirically 2026-04-19 21:22 by kiro-cli.

**What:** `.kiro/agents/*.json` subagent configs correctly declare a `hooks`
section (wired Wave 4c per handoff 015), but Kiro CLI runtime does NOT fire
those hooks when a subagent performs `fs_write` or `execute_bash`. Hooks only
execute for the main agent (orchestrator) session.

**Repro:**
1. Orchestrator spawns `coder` subagent via the `subagent` tool.
2. Coder runs `fs_write` on `evil.txt` at repo root.
3. Expected: `root-file-guard.sh` fires, blocks the write with exit 2.
4. Observed: file is written, no hook execution.

**Impact on safety layers:**

| Protection | Orchestrator session | Subagent session |
|---|---|---|
| Framework-dir write (`.ai/`, `.kiro/`, `.kimi/`, `.claude/`) | ✓ tool-level `deniedPaths` (enforced by Kiro regardless of hooks) | ✓ tool-level `deniedPaths` |
| Sensitive-file write (`.env*`, `*.key`, `id_rsa*`, `secrets.*`) | ✓ `sensitive-file-guard.sh` | ✗ **not enforced** |
| Root-file policy (ADR-0001 allowlist) | ✓ `root-file-guard.sh` | ✗ **not enforced** |
| Destructive bash (`rm -rf /`, `DROP DATABASE`, `git push --force`) | ✓ `destructive-cmd-guard.sh` | ✗ **not enforced** (for subagents with `execute_bash`) |

**Update (v0.0.27, Claude surface):** the *territorial / sensitive / root* write
dimension for bash write-commands is now **enforced on Claude's Bash tool**.
`.claude/hooks/pretool-bash.sh` extracts each write TARGET (`cp`/`mv`/`install`/
`ln`/`dd`/`tee`/`sed -i` and `>`/`>>`/`>|` redirects) and routes it through the
same `path-policy.sh` classifier as the Write/Edit guard, so a bash write into
`.kimi/**`/`.kiro/**`/`.claude/hooks/**`/`.env`/non-allowlisted root now blocks
(exit 2). This is a **path-target** guarantee and is scoped to statically
parseable commands — `$(...)`, `eval`, `sh -c`, base64/variable-built paths fail
CLOSED as unparseable or remain out of scope. The **destructive-command** row
above (`rm -rf`, `DROP DATABASE`) is a separate dimension and is unchanged; the
Kiro-subagent `execute_bash` gap it describes is likewise unchanged (this fix is
on the Claude hook surface, not Kiro's tool layer).

**Mitigations applied (Wave 4d, handoff to-kiro/017):**

1. **Prompt hardening** — every Kiro subagent prompt carries explicit
   SAFETY RULES that replicate the guard-script logic. LLM self-enforces.
2. **Pattern gap fix** — `sensitive-file-guard.sh` expanded to block
   `secrets.*` + `credentials.*` patterns.
3. **Tool-list review** — confirmed all 10 execute_bash-holding subagents
   genuinely need shell (no removals viable this wave).

**Residual risk:** prompt-level self-enforcement is SOFT. An adversarial or
confused context could still push a subagent into unsafe behavior. A Kiro
runtime fix is the only hard guarantee.

**Project tracking issue:** https://github.com/rwn34/rwn-multi-cli-skills/issues/1 (filed 2026-04-21). Close when Kiro upstream fix is released AND empirical re-verification per handoff 017 passes.

**Upstream bug filed:** https://github.com/kirodotdev/Kiro/issues/7671 (filed 2026-04-21)

**What NOT to do because of this:**
- Do not rely solely on Kiro's hook layer for subagent safety. Combine with
  prompt rules, tool-level `deniedPaths`, and explicit allowedPaths where
  applicable.
- Do not assume hook coverage from orchestrator session extends to subagents.

---

## Code graph index staleness (CodeGraph)

**Status:** Characterized 2026-04-26 by kimi-cli. **Scope reduced 2026-07-09:**
KimiGraph and KiroGraph were removed entirely (owner directive, ADR-0003
amendment — single-graph topology), which also retires the KiroGraph
subagent-hook staleness path below. CodeGraph (Claude) is the only graph.

**What:** CodeGraph maintains a local SQLite index of code symbols. When source
files change, the index must be re-synced. Auto-sync uses an OS file watcher
(FSEvents/inotify/ReadDirectoryChangesW) — agent-agnostic, so subagent writes
are synced too — but watchers can miss changes under load.

**Mitigation:** run `codegraph sync` if results look stale; do not ignore
freshness warnings.

**Acceptance:** Stale index is an advisory failure mode, not a safety issue. The
worst case is wrong code locations in exploration results (LLM can verify by
reading the file). No data loss risk.

*Historical (pre-removal):* KiroGraph's hook-based sync missed Kiro subagent
writes (platform bug #7671); KimiGraph used `fs.watch`. Both tools removed
2026-07-09 — see ADR-0003 amendment.

---

## multi-cli-install v0.0.1 — fixture-only validation (no real-project surface)

**Status:** Characterized 2026-04-27 by claude-code (orchestrator).

**What:** `tools/multi-cli-install/` v0.0.1 (the new Node.js installer at
`npx @rwn34/multi-cli-install`) was validated against fixture projects only —
minimal trees of empty files representing 8 stacks (Next.js App, Next.js Pages,
Vite plain TS, Django, Rails, Rust workspace, Go monorepo, Python with
pyproject). The original adoption plan called for mandatory validation against
3 real-project paths before v1.0.0 publish; the user explicitly accepted
fixture-only validation as a trade-off for ship speed.

**Risk:** Real-world surfaces — large codebases, weird configs, monorepo edge
cases, framework version drift, CI globs that fixtures don't have, custom
tsconfig paths, Cargo workspace member layouts that differ from the fixture,
etc. — won't surface until the first real adopter runs the installer. The
Migration Engine (`src/migration/`) is the highest-risk module: a buggy rule
set on real code corrupts the codebase.

**Mitigation:**
1. The installer requires a clean git working tree before any install (B4 fix
   in `bin/multi-cli-install.ts`) so any failure is recoverable by
   `git reset --hard`.
2. Per-rule-set commits during execute (planned but verify in code) make
   bisect-by-topic possible.
3. The existing `scripts/install-template.sh` bash installer remains available
   as a fallback that's been used in this repo's own bootstrapping.
4. `--dry-run` flag previews all changes without writes — first-run users
   should always use `--dry-run` before a live install.

**Acceptance:** Do NOT publish to npm without at least one real-project
validation. The package can stay at v0.0.1 in this repo as a usable-but-pre-release
tool for adopters willing to accept the risk.

**Tracking:** No upstream issue (this is owner-controlled). When the first real
adopter surfaces a bug, file in this repo's issues and consider it the start of
v0.x → v1.0.0 stabilization.

---

## KiroGraph — `kirograph install` hangs on interactive prompts in non-TTY

**Status:** Characterized 2026-04-26 by kiro-cli during Phase B Part A install.
**RESOLVED BY REMOVAL 2026-07-09:** KiroGraph was removed entirely (owner
directive, ADR-0003 amendment) — this limitation is retired with it. Entry
kept as historical record only.

**What:** `kirograph install` issues interactive prompts for embeddings,
architecture, and caveman-mode opt-ins. In non-TTY contexts (CI, non-interactive
shells, agent runners) those prompts have nothing to read from stdin and hang
indefinitely. MCP config and the 4 auto-sync hooks are written before the hang,
so the install is partially usable.

**Workaround:** run `kirograph init` first (non-interactive — writes config + DB),
then `kirograph install` and accept that it'll hang after writing MCP/hooks —
interrupt it and recreate `.kiro/steering/kirograph.md` manually if needed. This
is the empirical sequence Kiro used during Phase B Part A.

**Cosmetic note:** `package.json` shows version 0.11.0 but `kirograph --version`
reports 0.1.0. Track but don't act.

**Severity:** UX papercut, not a correctness issue. Functional install achievable
via the workaround.

**Tracking:** no upstream issue filed yet — kirograph repo is
`https://github.com/davide-desio-eleva/kirograph`. If we hit this again on a real
adoption, file upstream.

---

## Kimi CLI — bash guards wired into global config

**Status:** Characterized 2026-04-19 22:30 by kimi-cli (handoff 031). Snippet created 2026-04-19 23:30 (handoff 032). **Pasted and wired 2026-04-20.**

**What:** Kimi's 4 bash guard scripts (`.kimi/hooks/root-guard.sh`,
`framework-guard.sh`, `sensitive-guard.sh`, `destructive-guard.sh`) exist,
pass pipe-tests, and are **now registered as active hooks** in
`~/.kimi/config.toml`. They fire alongside the existing `safety-check.ps1`
hook (PowerShell) in parallel — if either exits 2, the operation is blocked.

**Also active:** `safety-check.ps1` (PowerShell). Scope and coverage of this
hook is not fully audited — may overlap with `destructive-guard.sh`.

**Good news — Kimi architecture is simpler than Kiro:**
Hooks in Kimi are *global* (`[[hooks]]` array in `~/.kimi/config.toml`), not
per-agent. One config edit wires them for root agent + subagents + every
session. No Wave 4c equivalent needed.

**Activation step:** restart Kimi Code CLI (or start a fresh session) to pick
up the newly appended `[[hooks]]` blocks.

**Residual unwired hooks:** five convenience hooks exist on disk but are **not**
registered in `~/.kimi/config.toml`:
- `git-status.sh` (SessionStart)
- `handoffs-remind.sh` (SessionStart)
- `activity-log-inject.sh` (UserPromptSubmit)
- `activity-log-remind.sh` (Stop)
- `git-dirty-remind.sh` (Stop)

These are optional — wire them manually if desired.

**Cross-CLI insight:** Kimi exposes `SubagentStart`/`SubagentStop` hook
events that Claude/Kiro may not have. Could inject safety rules at subagent
session start as defense-in-depth. Future consideration.

---

## Claude Code — none known at framework level

Hooks fire correctly for Write/Edit and Bash tools in orchestrator sessions.
Subagent hook behavior not yet empirically verified against evil-file-write
test — pending if Kimi or Kiro test pattern gets extended to Claude.

---

## Handoff numbering race condition

**Status:** Observed 2026-04-19 15:38/16:30. Low-severity INFO.

**What:** When two CLIs independently create a handoff to the same recipient
at nearly the same time, they can pick the same `NNN` number (each computes
`max(existing) + 1` against a stale filesystem snapshot). Observed: Kiro's 026
to Kimi collided with Claude's 026 to Kimi.

**Mitigation in place:** shim-rename (renumber loser + add SUPERSEDED pointer).

**Full fix deferred:** switch to timestamp-based numbering or introduce a
`.ai/handoffs/.claim-lock` file. Not yet implemented.

---

## Concurrent activity-log writes

**Status: RESOLVED by ADR-0010 Wave-3 (2026-07-21).** Historical note: first
observed clobber 2026-07-13, found by claude-code while processing
`to-claude/202607130206-activity-log-daily-rotation`.

**Risk (historical):** four CLIs prepending to `.ai/activity/log.md`
simultaneously clobbered each other's entries. The prepend was a whole-file
rewrite (read → insert at top → write back), so a writer whose read predated
another's write destroyed that entry. No atomic-append guarantee. The loss was
**silent**: no error, no merge conflict.

**Resolution:** the activity log is now an entry-per-file spool under
`.ai/activity/entries/<UTC>-<actor>-<slug>-<rand4>.md`. Each writer creates a
distinct file, so concurrent writes cannot clobber each other. The rendered
`.ai/activity/log.md` is generated by
`bash .ai/tools/render-activity-log.sh` and is gitignored.

**The confirmed incident (evidence, not inference):**

- Commit `9371a40` (kiro-cli, 2026-07-13 09:21) wrote the entry
  `## 2026-07-13 09:20 — kiro-cli` (handoff `202607122215-top-strip-fraction-65-35`,
  PR #73). The blob proves the entry was intact and well-formed at 09:21.
- By ~09:55 the working copy of `log.md` had that **header line deleted** while
  its three body lines (`- Action:` / `- Files:` / `- Decisions:`) survived —
  an orphaned body with no owner. Two CLIs prepended in between (09:42 kiro,
  09:55 claude); one of those whole-file rewrites dropped the line.
- Repaired 2026-07-13 by claude-code by restoring the exact header line from the
  `9371a40` blob (recovered, not reconstructed).

**Why worktrees help now:** under the ADR-0016 snapshot-copy model,
`scripts/wt-bootstrap.sh` no longer junctions `.ai/` into worktrees; the
dispatcher copies a canonical `.ai/` snapshot into the worktree before each
handoff and syncs changes back afterward. With the entry-spool model, each
executor adds files rather than rewriting a shared file, so the sync-back
propagates distinct entry additions instead of whole-log replacements.

**Note on daily rotation** (`.ai/tools/rotate-activity-log.sh`): it cuts the
*read cost* of the rendered log but is not needed for the race fix. The spool
itself is the structural fix.

---

## Annotated tag SHA comparisons — peel before diffing

**Status:** Characterized 2026-05-28 by claude-code (orchestrator) after a false-alarm divergence triggered an unnecessary v0.0.2-pre.4 → pre.5 bump.

**What:** This project's `release.yml` workflow produces **annotated** git tags
(not lightweight). An annotated tag is a separate git object with its own SHA
that contains the tagger + message + a pointer to the wrapped commit. So for
any annotated tag, two SHAs exist:

- The tag-object SHA (returned by `git rev-parse <tag>`, `git ls-remote --tags`,
  and visible in GitHub's API as the tag ref)
- The commit SHA (returned by `git rev-parse <tag>^{}`, visible in `git log`)

These will always differ for annotated tags. They are NOT a divergence.

**The trap:** when sanity-checking a tag across local vs remote, comparing
`git log --oneline -1 main` (commit SHA) against `git ls-remote --tags origin
<tag>` (tag-object SHA) will always show a "mismatch" even on a perfectly
healthy tag. This false alarm cost one cycle (pre.4 was reported as divergent,
pre.5 was cut to sidestep, then forensic investigation showed pre.4 was fine).

**Repro:**
1. `git ls-remote --tags origin v0.0.2-pre.4` → returns `2120ce3...`
2. `git log --oneline -1 v0.0.2-pre.4` → returns `993dc49 chore(activity-log)...`
3. Naive comparison: "DIVERGENCE"
4. `git cat-file -t v0.0.2-pre.4` → `tag` (= annotated, two-SHA model applies)
5. `git rev-parse v0.0.2-pre.4^{}` → `993dc49` (= peeled commit, matches log)
6. No divergence existed.

**Mitigation — what to do when comparing tag SHAs across local/remote:**

1. First check tag type: `git cat-file -t <tag>`. If `commit` → lightweight,
   SHAs compare directly. If `tag` → annotated, you must peel.
2. For annotated tags, always peel before comparing:
   - Local commit:  `git rev-parse <tag>^{}`
   - Remote commit: `git ls-remote refs/tags/<tag>^{} origin` (or peel locally
     after `git fetch origin tag <tag> --no-tags` which fetches the object
     without overwriting the local tag ref)
3. The script in `.ai/tools/check-ssot-drift.sh` is unrelated and unaffected —
   it does not compare tags. This limitation is purely a release-engineer /
   ad-hoc-git-inspection concern.

**Acceptance:** UX papercut for git-inspection workflows. No correctness or
safety risk — tags themselves are healthy. The cost is wasted release cycles
when the false alarm triggers a precautionary version bump.

**What NOT to do because of this:**
- Do not infer "tag divergence" from a single SHA comparison without first
  checking tag type. Annotated tags will always produce two SHAs.
- Do not force-push or delete a tag based on this false-alarm pattern. The
  destructive command may clobber a healthy ref.
- Do not bump a version pre-emptively to "sidestep" the divergence without
  first peeling and re-comparing — the divergence may not exist.

---

## Fleet supervision stops when the machine is off or asleep

**Status:** Accepted limit (owner decision 2026-07-12 — record it, do not solve it). Recorded 2026-07-13 by kimi-cli with the fleet-supervisor build (handoff `to-kimi/202607122130`).

**What:** The OS-level fleet supervisor (`tools/4ai-panes/fleet-supervisor.ps1`, a Windows Task Scheduler task) detects dead pane-runners, alerts the owner, and relaunches the fleet — but only while the machine is running and the user is logged on.

> **The fleet cannot self-heal when the machine is off or asleep.** A Windows scheduled
> task cannot run on a powered-off box — it cannot relaunch the fleet, and it cannot
> even send the alert. Every local supervision mechanism shares this hard boundary.
> True always-available operation would require an always-on host (VPS / cloud runner /
> home server), which drags in secrets handling, cost, and remote-tree topology.
> **Owner decision 2026-07-12: accept this limit for now; record it, do not solve it.**

**Partial mitigation (not a fix):** the supervisor's `-AtLogOn` trigger runs one cycle at user logon, so a fleet that died while the machine was off is detected and relaunched within a minute of the next logon — with the standard backoff/circuit-breaker. What is NOT covered: the offline window itself (no alerts, no consumers, handoffs wait silently), and sleep/hibernate (the task cannot wake the box; `StartWhenAvailable` only catches up after wake).

**What NOT to do because of this:**
- Do not claim the fleet is "always available" or "self-healing" without this qualifier.
- Do not build a cloud/VPS watchdog without an owner decision — that is a different autonomy + secrets posture, explicitly declined for now.

---

## Fleet cannot self-heal when the machine is off or asleep (owner decision 2026-07-12)

**Status:** Accepted boundary — recorded, not solved.

**The limit.** A Windows scheduled task cannot run on a powered-off or asleep
box. The fleet supervisor (`fleet-supervisor.ps1`, registered via Task
Scheduler) can detect dead panes, alert the owner via Telegram, and relaunch
the fleet — but only while the machine is on and the user is logged in. It
cannot relaunch the fleet or even send the alert when the machine is off.

Every local supervision mechanism shares this hard boundary. True
always-available operation would require an always-on host (VPS / cloud
runner / home server), which drags in secrets handling, cost, and remote-tree
topology.

**Owner decision 2026-07-12: accept this limit for now; record it, do not
solve it.**

**What the supervisor DOES cover:** terminal death (PowerShell restart, wt.exe
crash, accidental close) while the machine is on. This is the failure mode
that bit us on 2026-07-12 — four handoffs sat OPEN and unconsumed for over an
hour after a PowerShell restart, with no alert anywhere.

---

## Peer review is a convention, not a mechanical gate (S2-6)

**Status:** Open. Identified in field report 2026-07-16.

**What:** A handoff can carry both `ReviewBy:` and `FinalReview:` headers. The
dispatcher treats them as independent fan-out targets, so peer review and final
review can run concurrently. In practice, final review has often reached its
queue before peer review ran.

**Why it is not mechanically enforced yet:**

- There is no explicit `Depends-on:` field linking a final-review handoff to the
  peer-review handoff it must wait for.
- Matching by filename/slug is heuristic and breaks when a task is reopened or
  superseded.
- The current reconcile step moves `DONE` handoffs to `done/`; it does not
  inspect dependencies.

**Mitigation in effect:**

- The cockpit/auto workflow doc (`docs/specs/saja-akun-cli-workflow.md`) states
  that review is a precondition: the cockpit (or `claude-auto`) must not create
  the final-review handoff until the peer-review handoff is retired to `done/`.
- The activity log is the audit trail: a final-review entry should reference the
  retired peer-review handoff filename.

**Residual risk:** an auto pane can still pick up a final-review handoff while
its peer review is in flight. The worst case is a premature approval. The
pre-commit backstop and CI gates still apply, so a bad merge is mechanically
blocked, but review noise and duplicate final reviews are not.

**What would close this:** add a `Depends-on:` field to handoffs and teach the
dispatcher/reconcile step to hold a handoff until every dependency is retired to
`done/`. That is a protocol + tooling change, not a convention change.

---

## Framework guidance can embed stale point-in-time specifics (S3-2)

**Status:** Open. Identified in field report 2026-07-16.

**What:** Generated or authored guidance (contract files, ADRs, READMEs) often
embeds measurements or specifics that were true when written but drift over time:
file sizes, line counts, route names, "placeholder" IDs, or "this config value is
X". A recipient that verifies the claim against the current repo may conclude the
warning is false and dismiss it.

**Why it is hard to fix generically:**

- Some claims are inherently point-in-time ("the log is ~600 KB").
- Some are project-local specifics that the framework cannot know are stable.
- Re-generating every guidance doc on every change is expensive and noisy.

**Mitigation in effect:**

- Prefer thresholds or re-derivation over frozen numbers. E.g. "read only the
  top window" instead of "the log is ~600 KB".
- When a spec cites a concrete value, also cite the command used to derive it so
  a reader can re-run it.
- The activity log itself is bounded-read guidance: read only the top entries or
  grep for a topic rather than treating the file size claim as authoritative.

**Residual risk:** stale specifics will keep appearing. The discipline is on the
author to re-derive claims and on the reader to verify alarming specifics before
acting on them.

**What would close this:** a CI gate that re-derives every numbered claim in
framework docs and fails when the derivation no longer matches. That is a large
scope and likely overkill; the current accepted limitation is author discipline.

---

## How to add an entry

When you discover a new platform quirk:
1. Give it a clear H2 heading (CLI name or cross-CLI scope).
2. Status, date-confirmed, repro, impact table, mitigations, residual risk.
3. Update this file directly (framework-dir, orchestrator scope).
4. Log to `.ai/activity/log.md` noting the limitation was documented.
5. If it's a BLOCKER for real work, also dispatch a mitigation handoff.
