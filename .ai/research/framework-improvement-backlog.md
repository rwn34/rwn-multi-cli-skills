# Framework improvement backlog — owner lived-experience (3-month use)

**Source:** owner feedback 2026-07-09 after ~3 months running the multi-cli
framework across ~7 concurrent projects. Durable record so these aren't lost;
each has a proposed approach for a later session. Priority sits in ADR-0007's
P2/P3 band unless noted. NONE are built yet.

---

## 1. Handoff state model is too coarse (open/ vs done/)

**Pain:** a handoff being actively worked looks identical to an untouched one
(both in `to-<cli>/open/`), and `done/` doesn't distinguish "done" from "done,
needs review." Observed today: `Status: PARTIAL`/`BLOCKED` hacks, handoffs
sitting in `open/` mid-work, and a double-processing race (two Kiro instances
grabbed the same open handoff at 13:58/14:02).

**Owner idea:** directories `open → ongoing → review → done`.

**Claude's take (two options to choose between later):**
- **Option A (dirs):** add `ongoing/` + `review/` for a 4-state flow. Clear,
  but more file moves and every tool (dispatcher, stop-reminder, badges) must
  learn 4 states.
- **Option B (lighter, recommended):** keep `open/` + `done/` dirs, but (a)
  formalize the `Status:` enum already in use — `OPEN → CLAIMED → ONGOING →
  REVIEW → DONE` — and (b) add a **claim marker** (who claimed it + timestamp)
  written atomically on pickup. This solves BOTH the visibility gap AND the
  double-processing race with far less churn, and it's the same claim-lock the
  P1 pane-watcher needs anyway. Synergy: build once, serve both.
- Decision deferred to owner; B is my lean. Likely a small ADR (handoff
  protocol v3) + dispatcher/tooling update.

## 2. Root stays messy + no home for one-time scripts

**Pain:** ADR-0001 forbids loose root files, and `scripts/`/`tools/` are for
committed tooling — so a throwaway/one-off script has nowhere to live without
either polluting `scripts/` or fighting the root guard. (Related: today we kept
manually cleaning probe files, lockfile churn, `.ai/tmp-*` — all symptoms of no
sanctioned scratch space.)

**Claude's proposed fix:** a **gitignored scratch dir** — e.g. `.scratch/`
(dot-dir, exempt from the root loose-file rule by nature) or `scripts/tmp/` —
added to `.gitignore`, documented in ADR-0001 as the sanctioned home for
one-off/ephemeral scripts and probe artifacts. Never committed, never touches
root, never pollutes `scripts/`. Cheap, high daily-quality-of-life payoff.

## 3. Crash recovery — reopening ~7 projects is painful

**Pain:** the 4AI-panes launcher opens ONE project (4 panes) per invocation. If
PowerShell/Windows Terminal is force-closed or crashes, restoring 7 projects
means re-launching and picking one project at a time — tedious and error-prone.

**Owner idea:** multi-select projects in browse mode + open them sequentially.

**Claude's take (build both, layered):**
- **Multi-select** in the selector (space toggles, enter opens all selected,
  each in its own WT tab) — the owner's ask; ad-hoc bulk open.
- **Session/workspace restore (stronger):** the launcher records the current
  SET of open projects to a `.4pane-session` file; offer **"restore last
  session"** on start → reopens all N projects at once. One action brings the
  whole workspace back after a crash. `.4pane-history` already tracks recents;
  extend it to a session concept.
- Pure `Selector.ps1`/`Launch4Panes.ps1` work; no framework-core changes.

## 4. Share live context to another CLI within one project

**Pain:** cross-CLI sharing today is via `.ai/` (activity log, handoffs,
reports) — good for tasks/records, but heavyweight for "here's what I just
figured out, continue it." No lightweight live-context handoff.

**Claude's proposed approach:**
- A **lightweight context-note** channel distinct from task-handoffs: e.g.
  `.ai/context/<from>-to-<to>-<slug>.md` (or a `share-context` helper) that
  snapshots the sender's current understanding for the target CLI to read on
  next turn — no task semantics, no done/ lifecycle, just shared working state.
- Surfacing: the P1 pane-watcher can flag "new shared context from <cli>" in
  the target's pane so it's noticed live.
- Keep it SEPARATE from handoffs (which stay task-oriented) to avoid overloading
  the handoff queue.

## 5. [HIGH VALUE] Auto-continuation + auto-handoff-execution (kill the manual relay)

**Pain (the biggest daily friction):** the owner constantly has to type
"continue" (especially Kimi, which pauses at its ~100 multi-step limit) or
"check and execute handoff" to push work to the next CLI in the same project.
This makes the human the RELAY between steps and between CLIs — the exact
opposite of the framework's stated principle ("the human is a gate, not a
relay"). It's the #1 time-waster.

**Two sub-needs (both solved by an enhanced P1 pane-watcher):**
- **(a) Auto-continue on step/tool-limit:** a pane-runner wrapper detects when a
  CLI paused due to a step/tool cap (exit signal / known output pattern) and
  auto-sends "continue" until the CLI signals REAL completion (handoff moved to
  done / explicit "task complete") — bounded by a max-continues safety cap to
  avoid runaway loops/credit burn. Kimi is the priority case.
- **(b) Auto-execute handoffs (cross-CLI flow):** the P1 per-pane watcher polls
  its `to-<cli>/open/` queue and RUNS new `Auto:yes`/Risk-A|B handoffs in-pane
  automatically (Risk-C still waits for the human gate) — so a handoff Claude
  writes to Kimi is picked up and executed by Kimi's pane with no typing, and
  when Kimi writes a follow-up handoff to Kiro, Kiro's watcher chains it. Work
  flows Claude→Kimi→Kiro→OpenCode automatically and VISIBLY.

**Why this is the keystone:** it's the same P1 pane-watcher build, extended from
"visible dispatch" to "self-driving fleet." It resolves the owner's original
visible-pane ask (#P1) AND #5(a) auto-continue AND #5(b) auto-handoff — one
build, three pains gone. **This is what makes the framework feel finished.**

**Guardrails (must-haves):** max-continues cap + real done-signal (no infinite
loops); honor the Risk gate (Risk-C never auto-runs); the per-project claim-lock
from #1 (no double-processing); a visible "auto-continuing (n/max)" banner so the
owner can see + interrupt. Credit-burn awareness — cap is load-bearing.

**Elevates P1 from "nice UX" to "the point of the framework."** Build #1's
claim-lock + #5 together AS the P1 pane-watcher.

---

## 6. [RISK, not feature] Cost/usage observability

**Why:** once P1 (#5) makes the fleet self-drive with auto-continue across ~28
sessions, token/credit spend goes opaque. Owner is cost-conscious. Need a simple
per-CLI/per-project token+credit log + a "spend" view, ideally BEFORE unattended
auto-continue runs. Build on the existing `zai-usage` skill. Pairs with the
auto-continue MAX-cap as the two cost controls.

## 7. [RISK, not feature] Concurrency safety of shared `.ai/` files

**Why:** OBSERVED today — two kiro instances clobbered an activity-log header
(one overwrote the other's entry) and two grabbed the same handoff (13:58/14:02).
`.ai/tests/concurrency-test-protocol.md` exists but was NEVER run. A self-driving
fleet (P1) writing to shared `.ai/activity/log.md` + handoff queues across 28
sessions makes lost/corrupted writes a real integrity risk. Fixes: a prepend-only
atomic activity-log helper (or per-CLI activity shards merged for reads) + the
per-project claim-lock (#1) for handoffs + actually RUN the concurrency test.
Do this alongside/inside the P1 build — self-driving without it will corrupt
shared state.

## 8. [SECURITY, found 2026-07-10] Plaintext GitHub PAT in global Kiro config

**Found:** while cleaning Kiro startup noise, kiro flagged that
`~/.kiro/settings/mcp.json` stored a **plaintext GitHub Personal Access Token**
in the `github` MCP server's `env`. The config-side exposure was removed
2026-07-10 (owner approved deleting the `github` MCP server entirely — token no
longer in the LIVE config). **OPEN owner action:** the live token is still valid on
GitHub until revoked — owner chose "deal with it later" (2026-07-10). Rotate it:
revoke on GitHub → issue a new one → if GitHub MCP is ever re-added to any CLI,
reference it via env var, never inline plaintext.

**The token still exists in cleartext in three places** (found during cleanup):
`~/.kiro/settings/mcp.json.bak-20260710` (backup) and — the bigger surface —
`~/.kiro/sessions/` transcripts (**931 matches** across ~65 append-only history
files; the PAT is already captured there). Removing it from config does NOT
invalidate it — rotation is the only real fix. **Systemic risk flagged by the
coder:** `~/.kiro/sessions/` is an unbounded, unencrypted store that accumulates
ANY secret ever pasted into a Kiro session — it becomes the real secret-leak
surface long before config does. Consider a session-retention/scrub policy
(separate follow-up). After rotation, owner may delete the two backup dirs
(`agents.bak-20260710`, `agents-backup-20260710`) + `mcp.json.bak-20260710`.

---

## STANCE: stop ideating, start building (owner check-in 2026-07-09)
The backlog is now sufficient. Further FEATURE brainstorming = backlog debt, not
value. Discipline (per ADR-0007): the highest-value "enhancement" is to USE the
framework (build P1) and let REAL friction drive the next item — today's four
latent bugs were all found by exercising it, not imagining features. Resist
adding: more CLIs, more enforcement layers, more per-CLI parity (surface-area
trap). Before GROWING the framework, run the #CLI-count analysis (is 4 even
right?). Recommended: land the merge → build P1 (+ the #1 claim-lock, #7
concurrency safety it requires) → real use → reassess.

## Suggested sequencing (relative to ADR-0007 roadmap)
- #2 (scratch dir) — trivial, do anytime; immediate daily-quality win.
- **#5 + #1 (auto-continue/auto-handoff + claim-lock) = the P1 pane-watcher
  build — TOP PRIORITY. This is the keystone that makes the fleet self-driving
  and stops the owner being the relay. Everything else is secondary to this.**
- #3 (session restore + multi-select) — launcher enhancement, bundle with P1.
- #4 (context-share) — P3; design once P1 pane visibility exists to surface it.
