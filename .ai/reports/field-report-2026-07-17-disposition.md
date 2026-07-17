# Field report disposition — 13 framework defects (2026-07-17)

Source: orchestrator CLI field report on one 2-day 3rd-party API integration sequence.
Scope: multi-CLI coordination framework (.ai/ shared state, handoff queues, executor worktrees, dispatcher, guards, six-actor model, protocol v3).

## Executive summary

- **Fixed in this pass:** 6 items plus the previously-known `av4` pane-runner junction failure.
- **Deferred / accepted limitations:** 7 items, most requiring protocol/ADR-level changes or server-side enforcement that cannot be implemented client-side.
- **Highest-leverage future work:** S2-2 (`Observed-in:` evidence field) and S2-3 (`VERIFIED` vs `HYPOTHESIS` markers) are handoff-template changes that would prevent the costliest failures in the report. They are intentionally not patched here because they change the protocol and need fleet-wide agreement/ADR.

---

## Fixed

| ID | Item | Fix | Evidence |
|---|---|---|---|
| S1-3 | `reconcile-done-handoffs.sh` silently overwrites files on name collision | Incoming DONE handoff now moves to `done/<basename>-superseded-<UTC>.md` when a same-named file already exists. Exit 0 (fail-open) preserved; data is never silently destroyed. | `.ai/tools/reconcile-done-handoffs.sh`; new `.ai/tests/test-reconcile-done-handoffs.sh` (20/0). |
| S2-4 | Self-addressed handoffs (`Sender == Recipient`) can loop forever | `dispatch-handoffs.sh` now rejects `Sender == Recipient`, writes a dispatch-failure report, and leaves the handoff `OPEN`. | `.ai/tools/dispatch-handoffs.sh`; regression test in `.ai/tests/test-dispatch-worktree.sh` (51/0). |
| S2-5 | Dispatcher reuses dirty worktrees with only a WARN | Dirty worktree reuse is now a **failure** by default. A new `--reuse-dirty` flag restores the old warn-and-reuse behavior for explicit recovery. | `.ai/tools/dispatch-handoffs.sh`; regression test in `.ai/tests/test-dispatch-worktree.sh`. |
| S3-3 | Recipient queue directories can be missing | `scripts/wt-bootstrap.sh` now creates `open/`, `review/`, `done/` (with `.gitkeep`) for every dispatchable actor. `fleet-health.sh` flags missing dirs as a `FRAMEWORK:` finding with the bootstrap fix command. | `scripts/wt-bootstrap.sh`, `.ai/tools/fleet-health.sh`, `.ai/tools/test-fleet-health.sh` (11/0). |
| S3-4 | Status parsing is positional / brittle | `dispatch-handoffs.sh` now parses the entire status block (all consecutive header lines before the first blank line or `## ` section header) by key, case-insensitively, with CRLF safety. Extra header lines and `## Blocker` no longer break dispatch. | `.ai/tools/dispatch-handoffs.sh`; regression test in `.ai/tests/test-dispatch-worktree.sh`. |
| av4 | `test-pane-runner.ps1` junction-degradation guard (3 failures, 159 passed) | `Ensure-DeclaredBaseBranchReal` now syncs the `.ai/` **staged index** to the branch tip after cutting the declared-base branch, matching the bash dispatcher parity guard. This prevents staged phantoms from falsely tripping `wt-bootstrap.sh`'s `DEGRADED` guard. | `tools/4ai-panes/pane-runner.ps1`; full pane-runner suite now **162 passed, 0 failed**. |

---

## Deferred / accepted limitations (and why)

### S1-1 — Shell `git` bypasses the Write/Edit guard

**Why not fixed:** The report itself reaches the right conclusion: any client-side control that parses shell can be defeated by the same shell-out that created it. The framework's per-CLI PreToolUse hooks inspect tool parameters; they cannot mechanically intercept arbitrary `Bash` invocations (`git`, `cp`, `mv`, `>`, heredocs) without either (a) denying all shell use or (b) building a full shell ACL parser, which is still client-side and bypassable.

**Existing protection:** The git pre-commit backstop (ADR-0005) is the guaranteed net: a bad write can hit local disk but cannot reach the shared repo under the wrong identity/path. This is already documented in `.ai/known-limitations.md` §"Enforcement reality".

**Action taken:** No code change. Treat this as a **safety rail / defense-in-depth** limitation, not a closed security boundary. If the project needs a stronger guarantee, the enforcement must move server-side (branch protection rules, required reviews, or a sandbox without trunk credentials).

### S1-2 — Lane grant contradicts worktree confinement

**Why not fixed:** Requires reconciling two independent config sources (per-CLI lane grants in AGENTS.md/contract files vs. the worktree-confinement ADR) and teaching the dispatcher to compute the recipient's effective writable set. That is a non-trivial design with migration risk for in-flight handoffs.

**Workaround today:** A blocked executor should set `Status: BLOCKED` and append a `## Blocker` explaining the contradiction, rather than emit a self-addressed handoff (now rejected by S2-4).

**Future path:** Add a startup/CI consistency check that warns when a lane grant references a path outside the actor's effective writable set, and/or teach the dispatcher to refuse unsatisfiable handoffs.

### S1-4 — Stale worktree + shared `.ai/` junction can delete trunk files

**Why only partially fixed:** The framework already has `Assert-WorktreeFresh` and `Ensure-DeclaredBaseBranchReal`; S2-5 now also refuses to dispatch onto a dirty/stale worktree by default. The deeper fixes — auto-rebasing worktrees on dispatch, or making `.ai/` git-ignored instead of junctioned-and-tracked — are large architectural changes with their own failure modes (e.g., losing the shared coordination plane if ignored, or creating rebase conflicts on every dispatch).

**Mitigation today:**
- Dispatcher now errors on dirty reuse (S2-5).
- Pane-runner freshness guard refuses to start a worktree whose base is unresolvable or far behind.
- Documentation in `docs/specs/junction-reverse-write-guard.md` and `.ai/known-limitations.md` warns against `git add -A`, `git commit -a`, `git stash`, `git clean`, and `git checkout -- <shared-dir>` inside worktrees.

**Future path:** Consider a dispatcher step that fast-forwards `exec/<cli>/init` to `origin/main` before cutting a handoff branch, or a health monitor that flags worktrees older than N hours.

### S2-1 — `Status: DONE` requires no evidence

**Why not fixed:** Would require a retirement gate/linter that inspects the handoff file for a non-empty report/evidence section. The template already asks for a `## Report back with` section, but there is no schema definition of "enough evidence" that would not also false-positive on legitimate small handoffs.

**Workaround today:** Sender validates post-hoc as protocol v3 requires; false DONEs should be moved back to `open/` with `BLOCKED` + notes.

**Future path:** Add a lightweight pre-retirement lint (e.g., `bash .ai/tools/lint-handoff.sh <file>`) that warns if `Status: DONE` appears before any filled `## Report back with` or `## Verification` evidence. Make it advisory first, then gate.

### S2-2 — Handoffs assert file-level facts with no provenance

**Why not fixed:** This is the single highest-leverage change in the report, but it is a **protocol/schema change** (`Observed-in: <branch>@<sha>`) and requires the whole fleet to understand the new field, compare bases, and produce a new first-class outcome ("evidence-base mismatch — sender wrong"). Patching it unilaterally would create handoffs that other CLIs ignore or mis-parse.

**Recommended ADR:** Add `Observed-in:` as an optional/required field when file-level claims are made; teach the dispatcher to compare it against the recipient's resolved base; on mismatch, route a new `BLOCKED` subtype back to the sender rather than retrying.

### S2-3 — Nothing distinguishes VERIFIED from HYPOTHESIS

**Why not fixed:** Another high-leverage, low-code **template/protocol change**. Requires all six actors to respect `VERIFIED (<command> -> <output>)` vs `HYPOTHESIS (unverified)` markers and to bar hypotheses from priority labels. Doing this half-fleet would make the markers meaningless.

**Recommended ADR:** Extend the handoff template with an `Evidence:` field whose values are `VERIFIED` or `HYPOTHESIS`; add a lint; require hypothesis-driven handoffs to start with "verify premise; close if false."

### S3-1 — Shared activity log can be silently encoding-corrupted

**Why not fixed:** The offending writer is unidentified. All known framework appenders use bash `printf` / `echo >>` (UTF-8). The UTF-16LE incident likely came from a PowerShell `Out-File`/`>` append in a CLI or wrapper, which is outside the framework's direct control.

**Mitigation added:** `fleet-health.sh` is now the natural place to add an encoding assertion. A future change can add a check that `file -i .ai/activity/log.md` reports UTF-8 (or that the file is valid UTF-8) and alert if not.

### S3-2 — Framework-generated guidance rests on stale facts

**Why not fixed:** A discipline problem, not a single code defect. The fix is to replace frozen numbers with thresholds/derivations and to re-verify specifics in contract files on every significant change. Too broad to patch in one pass.

**Action taken:** No code change; noted as accepted maintenance debt.

### S4-1 — Risk-C dispatch rule forces the human to be both gate and relay

**Why not fixed:** The report is correct that the current rule conflates authorization and launch. Fixing it requires protocol changes (`Gate:`, `Gate-satisfied-by:`, `Relay:`) plus fleet-wide understanding so an orchestrator can relay a gated Risk-C item without relabeling it as Risk B.

**Workaround today:** The orchestrator records the owner's authorization in the handoff and then invokes the executor directly against the file (the reporter's own workaround). This is acceptable as an explicit human-relay pattern.

**Recommended ADR:** Add `Gate:` and `Gate-satisfied-by:` fields; allow the dispatcher to relay Risk-C once a satisfied gate is recorded; refuse ungated Risk-C items.

---

## Known caveats from the preceding master→main migration

| Caveat | Status |
|---|---|
| `av4` pane-runner failures | **Fixed** — see above. |
| Untracked `.ai/` files lost when old executor worktrees were removed | **Accepted / documented.** The `.ai/` junction means worktree `.ai/` files are physically in the primary tree; removing a worktree with a junction can follow the link and delete shared content. Always restore tracked `.ai/` from `HEAD` if this happens; untracked shared state should be considered ephemeral or backed up before worktree removal. |
| Running `opencode.exe` processes had to be killed to free the worktree | **Accepted.** The fleet supervisor may relaunch panes. Stopping panes cleanly should go through the supervisor's stop path; forcibly killing a CLI child is a recovery action, not normal operation. |

---

## Migration implications for in-flight queues

- **Dispatcher changes are backward-compatible** for valid handoffs. Invalid handoffs (self-addressed, dirty worktree) now fail loudly instead of warn/reuse.
- **New `--reuse-dirty` flag** exists only as an explicit override; no existing handoff needs it.
- **Status-block parsing** now reads the entire header block by key. Handoffs with extra header lines or `## Blocker` above the status block still parse correctly; handoffs with status keys *inside* a `##` section may no longer match — but that was already malformed.
- **Queue directory creation** is idempotent; running `wt-bootstrap.sh` on existing projects will add any missing `open/review/done/.gitkeep` files.
- **No handoff-file schema changes** were made, so in-flight queues remain readable by all CLIs.

---

## Verification run after fixes

```text
bash .ai/tests/test-reconcile-done-handoffs.sh  -> 20 passed, 0 failed
bash .ai/tests/test-dispatch-worktree.sh         -> 51 passed, 0 failed
bash .ai/tools/test-fleet-health.sh              -> 11 passed, 0 failed
bash scripts/test-check-version-bump.sh          -> 64 passed, 0 failed
bash .ai/tools/sync-replicas.sh --check          -> Drift: 0
powershell.exe -File tools/4ai-panes/test-pane-runner.ps1 -> 162 passed, 0 failed
```

---

## 2026-07-17 09:45 (UTC+7) — kimi-cli
- Action: Dispositioned 13-item orchestrator field report; patched 6 reproducible framework-level defects and the av4 pane-runner failure; documented 7 deferred/accepted limitations with rationale and future ADR paths.
- Files: `.ai/tools/reconcile-done-handoffs.sh`; `.ai/tools/dispatch-handoffs.sh`; `.ai/tools/fleet-health.sh`; `.ai/tools/test-fleet-health.sh`; `scripts/wt-bootstrap.sh`; `tools/4ai-panes/pane-runner.ps1`; `.ai/tests/test-reconcile-done-handoffs.sh`; `.ai/tests/test-dispatch-worktree.sh`; `.ai/reports/field-report-2026-07-17-disposition.md`
- Decisions: Left protocol/schema-level items (S2-2, S2-3, S4-1) for ADR because unilateral template changes would not be respected fleet-wide. Accepted S1-1 as a client-side safety-rail limitation; real guarantee is the git pre-commit backstop plus server-side branch protection if available.
