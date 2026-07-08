# Known framework limitations

Living document. Records runtime/platform quirks that config cannot fix.
Any AI CLI hitting behavior that seems wrong should check here first.

---

## Crush — no hook layer at all; runs permission-bypassed in daily use

**Status:** Open by design. Documented 2026-07-07 at Crush onboarding (ADR-0002).

**What:** Crush has no pre-tool hook mechanism, no steering channel, and no
subagent roster. In the daily 4AI-panes setup it launches as `crush --yolo`
(see `.ai/research/4ai-panes-integration-notes.md`), so interactive permission
prompts are off too. **Nothing at the tool layer prevents Crush from writing
anywhere.**

**Mitigations:**
1. Prompt-level SAFETY RULES in `CRUSH.md` (root context file, always loaded)
   replicate the guard rules — write scope limited to `.ai/` log/reports/
   handoffs; destructive/deploy/publish commands forbidden; dry-run only.
2. Role containment: ADR-0002 (amended 2026-07-08) gives Crush a general-helper
   + deploy-operator lane — its briefs never require source edits, and every
   mutating deploy command is individually human-confirmed.
3. Custodianship: Claude maintains `CRUSH.md` / `.crush.json`, so Crush's own
   drift can't erode its rules.

**Residual risk:** prompt-level enforcement is SOFT (same class as the Kiro
subagent gap below, but broader). Do not hand Crush tasks whose failure mode
is destructive without a human gate.

**Update 2026-07-08:** Stage 2 GRANTED by owner directive (ADR-0002 amended):
Crush is now general helper + DevOps deployment operator. The compensating
controls, because Crush still has no hook layer: (a) mandatory dry-run before
any mutating deploy command, (b) per-deploy human confirmation — deploys stay
Tier-C hard-gated in the autonomy policy regardless of which CLI executes,
(c) refuse on dirty tree / failing tests, (d) deploy briefs must enumerate the
exact commands Crush may run — no improvisation.

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

## Code graph index staleness (all three CLIs)

**Status:** Characterized 2026-04-26 by kimi-cli.

**What:** CodeGraph, KimiGraph, and KiroGraph all maintain a local SQLite index of
code symbols. When source files change, the index must be re-synced. Each tool has
auto-sync, but with different reliability:

| Tool | Sync mechanism | Subagent writes synced? |
|---|---|---|
| CodeGraph | OS file watcher (FSEvents/inotify/ReadDirectoryChangesW) | Yes (OS-level, agent-agnostic) |
| KimiGraph | OS file watcher (`fs.watch`) | Yes (OS-level, agent-agnostic) |
| KiroGraph | Kiro hooks (`fileEdited`/`fileCreated`/`fileDeleted`/`agentStop`) | **No** — blocked by Kiro subagent hook-inheritance bug |

**Impact:** If a Kiro subagent edits files, KiroGraph's index goes stale silently.
The next `kirograph_context` or `kirograph_search` may return outdated symbol
locations or miss new symbols entirely.

**Mitigation:**
1. Run `kirograph sync` manually after subagent-heavy sessions.
2. All three tools run a pre-query freshness check; if they detect a mismatch,
   some will warn. Do not ignore warnings — run `sync`.
3. For critical refactors, run a full `kirograph index --force` before starting.

**Acceptance:** Stale index is an advisory failure mode, not a safety issue. The
worst case is wrong code locations in exploration results (LLM can verify by
reading the file). No data loss risk.

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

**Status:** Untested (see `.ai/tests/concurrency-test-protocol.md`).

**Risk:** three CLIs prepending to `.ai/activity/log.md` simultaneously could
clobber entries. No atomic-append guarantee.

**Mitigation:** none yet. Run concurrency protocol to characterize actual
behavior before deciding on file-lock vs. lease-based coordination.

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
`git log --oneline -1 master` (commit SHA) against `git ls-remote --tags origin
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

## How to add an entry

When you discover a new platform quirk:
1. Give it a clear H2 heading (CLI name or cross-CLI scope).
2. Status, date-confirmed, repro, impact table, mitigations, residual risk.
3. Update this file directly (framework-dir, orchestrator scope).
4. Log to `.ai/activity/log.md` noting the limitation was documented.
5. If it's a BLOCKER for real work, also dispatch a mitigation handoff.
