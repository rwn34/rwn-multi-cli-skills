# Framework + Terminal-Panes Gap Analysis (2026-07-11)

Author: claude-code. Scope: why "handoffs don't work when I open an existing
project," plus the broader framework/pane gaps worth covering. Sources: two
read-only surveys (handoff-delivery pipeline; install/update completeness) +
gaps surfaced live during the 2026-07-10/11 session. Severity is rated for the
owner's stated pain: *handoffs/rules silently not applied in an onboarded
project*.

## The one-paragraph diagnosis

There is **no always-on handoff delivery**. Delivery happens ONLY via three
opt-in paths: (1) a `pane-runner.ps1` poller — but only while a 4AI-panes runner
pane is alive for that recipient; (2) Claude's `Stop` hook nag — Claude only;
(3) a **manually**-run `dispatch-handoffs.sh`. Open an existing project and just
start Kimi or Kiro interactively and **none of these run** — a `to-kimi`/
`to-kiro` handoff is delivered to no one. Worse, the install flow that is
supposed to wire those mechanisms (a) **may never even commit** (the installer's
own commit is blocked by the ADR-0005 guard it just wired), and (b) **never
wires Kimi's hooks at all** — and the docs point at the wrong Kimi config file.
So the framework is frequently *half-applied*, and even when applied, most CLIs
are deaf to handoffs unless launched through the panes with the right flags.

---

## THEME A — The install doesn't reliably LAND or fully WIRE

**A1 [CRITICAL] The installer's own commit is structurally blocked by the guard it wires.**
`install-template.sh` phase1 wires `core.hooksPath -> scripts/git-hooks` (the
ADR-0005 pre-commit backstop), then phase5 runs a plain `git commit` with **no
`--no-verify`** and never sets a committer identity. The pre-commit territory
rule blocks *any* single committer from committing the full `.claude/ + .kimi/ +
.kiro/ + .opencode/` payload (unknown identity → fail-closed blocks all; even
`claude-code` still can't commit `.kimi/`+`.kiro/`). Result: `set -e` aborts →
**files copied to the working tree but the adopt-commit never lands = half-
applied framework.** This is the mechanical root of "the structure/rules aren't
applied." Evidence: `install-template.sh` phase1 hooks-wire + phase5 commit;
`scripts/git-hooks/pre-commit` committer→`unknown` fail-closed.
Fix: the installer is the trusted template author — its bootstrap commit should
use `git commit --no-verify` (or set an allowed identity + split commits).

**A2 [HIGH] Kimi's hooks are never activated, and the installer prints the WRONG path.**
Kimi loads hooks from a **user-global** config, and the installer only *copies*
`.kimi/` files — it has no step that appends the hook block to that global
config. Worse, the printed instruction + README say `~/.kimi/config.toml`, but
Kimi actually reads **`~/.kimi-code/config.toml`** (per the snippet's own SSOT
header, Kimi test `t48`, and the `~/.kimi/.migrated-to-kimi-code` marker present
on this machine). So even a diligent adopter wires guards into a file Kimi
doesn't read → **Kimi enforces no rules and never notices handoffs.** Claude
(self-contained `settings.json`) and Kiro (`guards.json`) auto-wire by copy;
**Kimi is the odd one out and silently inert.** This is the likeliest direct
cause of the owner's Kimi-handoff failures.
Fix: correct the path to `~/.kimi-code/config.toml` everywhere; have the
installer append the snippet itself (idempotent, marker-guarded).

**A3 [HIGH] `.mcp.json` is wired with a bare `codegraph` command that doesn't exist on a fresh machine.**
`wire_mcp` writes `"command": "codegraph"`, but CodeGraph is an npx package
(`.ai/instructions/code-graphs/principles.md`: `npx @colbymchenry/codegraph`) —
there is no global `codegraph` binary. This reintroduces the exact "codegraph is
not recognized" error class (the same one that plagued Kimi) in every adopted
project. Fix: emit `"command":"npx","args":["-y","@colbymchenry/codegraph","serve","--mcp"]`,
or check/require a global install.

**A4 [HIGH for update] Re-running the installer DESTROYS live cross-CLI state.**
There is no safe update mode: `copy_dir ".ai"` does `rm -rf "$TARGET/.ai"` then
re-copies the template's empty `.ai`; `write_clean_activity_log` unconditionally
blanks `.ai/activity/log.md`; phase2 wipes `open/`+`done/` handoffs and reports.
So "updating" an onboarded project erases in-flight handoffs and all activity
history — the very state handoffs depend on. Fix: an explicit update mode that
preserves `.ai/activity/`, `.ai/handoffs/*/{open,done}`, `.ai/reports/` and only
refreshes instruction/config files. (This is the safe substrate the drift-check
in PR #5 points at — right now that "adopt" action is destructive.)

**A5 [MED] Framework-critical files referenced by copied artifacts aren't copied.**
Only ADR-0001 is copied, but the copied hooks/rules cite ADR-0002..0009 (pre-
commit cites 0003/0004/0005; Kiro guards cite 0001/0004; 23 `.ai/instructions/`
files cross-reference them) → every governance link in an adopted project
dangles. `docs/specs/`, `scripts/sync-4ai-panes-install.ps1`, and the pane-
runner/fleet scripts (ADR-0008/0009) also aren't copied — an adopted project has
handoff *files* but none of the fleet automation. Fix: copy all
`docs/architecture/*.md`; decide explicitly whether specs + pane runner ship to
adopters.

---

## THEME B — Handoff delivery is entirely opt-in (no always-on path)

**B1 [HIGH] Interactive Kimi has zero handoff awareness even when "wired."**
`handoffs-remind.sh` exists but is flagged NOT WIRED; the paste-ready Kimi
config block wires only the 4 guards — **no SessionStart handoff reminder at
all**. So even a fully-wired Kimi never lists `to-kimi/open/`. Fix: add a
SessionStart `[[hooks]]` entry for `handoffs-remind.sh` to the block + installer
output.

**B2 [HIGH] Kiro sees handoffs only under a pinned agent, not bare `chat`.**
Kiro's inbox surfacing (`activity-log-inject.sh`) is wired per-agent
(`agentSpawn`) + `SessionStart` in `guards.json`; a bare `kiro-cli chat` runs the
built-in default agent with none of these (the dispatcher comments confirm it).
Selector pins `--agent orchestrator`, but a hand-started Kiro won't. Fix:
require/pin the agent in every interactive launch path; treat bare `chat` as
unsupported.

**B3 [HIGH] `dispatch-handoffs.sh` is never automatic.**
Cron/cloud dispatch is deliberately NOT configured; the only triggers are
Claude's Stop-hook *suggestion* and a manual `/loop` needing an already-running
Claude. Nothing runs it on project open. Risk-A/B `to-kimi`/`to-kiro`/
`to-opencode` handoffs sit forever unless a Claude session is open AND someone
acts on the nag. Fix (highest leverage): a per-CLI SessionStart hook that (a)
lists that CLI's `open/` inbox and (b) runs `dispatch-handoffs.sh` for its own
queue — wired by the installer, not by manual paste.

**B4 [MED] Only Claude gets a Stop-time queue reminder.**
`stop-reminder.sh` (per-queue counts + auto-dispatchable list) is wired solely in
Claude's `settings.json Stop`. Kimi/Kiro Stop hooks are unwired and don't mention
handoffs. Non-Claude awareness depends entirely on pane-runner polling. Fix:
give Kimi/Kiro an equivalent SessionStart/Stop queue-count reminder.

**B5 [MED] The default 6-pane cockpits don't poll.**
Top-left Claude + top-right Kimi launch bare (no runner: "no poll"). Only the
bottom row runs runners. Delivery to Kimi relies on it *also* being a bottom
column; a degraded layout (Kimi absent, fewer columns) can leave `to-kimi` with
no poller. Fix: ensure every recipient CLI has ≥1 runner pane, or give cockpit
panes the reminder hook.

**B6 [MED] No delivery at all when the recipient isn't running.**
`dispatch-handoffs.sh` skips a CLI not on PATH (silent); `Get-QualifyingHandoff`
only runs inside a live runner loop. Pane never opened / runner crashed / CLI
absent → the handoff sits in `open/` with no actor and no alert (the failure-
report path only fires on non-zero *exec* exits, not on "nobody tried"). Fix: a
standing check (SessionStart or a Selector badge) that flags OPEN handoffs whose
recipient has no live consumer.

---

## THEME C — Reliability / edge cases

**C1 [LOW-MED] Quarantine sidecars hide a handoff indefinitely (no age-out).**
A handoff that MAXED for a transient reason stays `quarantined:true` and invisible
to all pollers until `done/` or manual deletion. (Session follow-up already
flagged this.) Fix: age-out like claims (staleness window), and surface
quarantined counts in the Stop/selector reminder.

**C2 [LOW] Per-project claim lacks host/time guard and isn't gitignored.**
`Test-ClaimBlocks` checks only pid-liveness — no host check, no time window — and
`.ai/.claim-<cli>.json` is NOT in `.gitignore` (only `.ai/handoffs/.claims/*` is).
If ever committed, a pid collision on another machine blocks the whole project
queue with no escape. Fix: gitignore `.ai/.claim-*.json`; add host + time-window
to `Test-ClaimBlocks`.

**C3 [LOW] "Done = file moved to done/" is a soft convention treated as a hard signal.**
A recipient that finishes but forgets to move the file is scored MAXED →
eventually quarantined despite success, then re-dispatched. Not cheaply machine-
enforceable; note it's load-bearing.

---

## THEME D — Framework / pane hygiene (from the session)

- **D1 [MED] Version-bump discipline unenforced.** The new drift check (PR #5)
  goes silent if framework content changes without bumping
  `tools/multi-cli-install/package.json`. Fix: a `gates.yml` check that fails a
  PR touching framework paths without a version bump.
- **D2 [MED] Repo→install sync only fires on merge/checkout.** Same-branch edits
  leave `~/.rwn-auto` stale until a manual `sync-4ai-panes-install.ps1`. Fix:
  a `post-commit` hook, or a Selector startup staleness check.
- **D3 [MED] Global CLI configs aren't version-controlled.** `~/.kimi(-code)/`,
  `~/.kiro/`, `~/.claude/` drift per-machine with no repo guard (the
  `~/.kimi/mcp.json` dead-server issue was exactly this). Fix: ship the intended
  global configs as tracked snippets + an idempotent wire step + a check.
- **D4 [LOW] Sync + CLI-list duplication.** The 4-CLI ValidateSet is duplicated in
  `pane-runner.ps1` + `restart-pane.ps1`; the sync allowlist count is hand-
  mirrored in prose. Fix: single source each.
- **D5 [MED] The pane-runner's real CLI-invocation core isn't unit-tested.** The
  tests mock `$script:InvokeCli`, which is why the stderr-crash slipped through.
  Fix: a test that exercises the real invoke path against a stderr-writing child.

---

## Recommended attack order (highest leverage first)

The owner's pain ("handoffs don't work in existing projects") is fixed fastest by:

1. **A1** — installer bootstrap commit uses `--no-verify` (so the framework
   actually LANDS). *Small, unblocks everything.*
2. **A2 + B1 + B3** — wire Kimi's hooks to the correct `~/.kimi-code/` path AND
   add a SessionStart hook (per CLI) that lists the inbox + runs the dispatcher
   for its own queue. *This is the "handoffs get noticed without the panes" fix —
   the single biggest behavioral win.*
3. **A3** — fix the `codegraph` MCP command to npx form. *Kills a recurring
   startup-error class.*
4. **A4** — a non-destructive installer update mode. *Makes the drift-check's
   "adopt" action safe to run.*
5. **B2 / B4 / B5 / B6** — pin Kiro's agent, give Kimi/Kiro queue reminders,
   guarantee a runner per recipient, flag consumer-less handoffs.
6. **A5, C1–C3, D1–D5** — cross-reference completeness, quarantine age-out,
   claim hardening, and hygiene.

Items 1–3 are small, mechanical, and independently shippable; each is a
meaningful reduction in "handoffs silently go nowhere." Recommend a single
follow-up PR for A1+A2+A3 (the "make install land + Kimi actually wired + MCP
correct" batch), then a second for B1+B3 (the always-noticed delivery hook).

## Caveats / confidence

- Kiro's runtime auto-load of `guards.json` and Claude's of `settings.json` were
  inferred from config location (wired-by-copy), not confirmed by a live CLI run.
- Exact Kimi global-config path (`~/.kimi-code/config.toml`) is asserted by the
  snippet SSOT + test t48 + the migration marker; a behavioral Kimi run would
  confirm.
- All file:line evidence is from the two surveys' read of the tree at commit
  ~`5c87c10`.
