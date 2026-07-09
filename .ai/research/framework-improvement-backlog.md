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

---

## Suggested sequencing (relative to ADR-0007 roadmap)
- #2 (scratch dir) — trivial, do anytime; immediate daily-quality win.
- #1 (handoff states + claim-lock) — build WITH the P1 pane-watcher (shared
  claim-lock); ADR the protocol change.
- #3 (session restore + multi-select) — launcher enhancement, P1-adjacent.
- #4 (context-share) — P3; design once P1 pane visibility exists to surface it.
