# Parallel-CLI concurrency test protocol

## Why this exists

The multi-CLI framework (Claude Code + Kimi CLI + Kiro CLI) coordinates via
shared files in `.ai/`: the activity log, the handoff queues, SSOT replicas.
The coordination relies entirely on **convention** — there is no file-level
lock, no atomic compare-and-swap, no append-only guarantee from the filesystem.

Three-CLI concurrency is the scariest untested unknown in this framework
(confidence audit 2026-04-19 called it out directly). Every production failure
scenario starts with "what happens if two CLIs do X at the same time?" and we
don't have empirical answers.

This doc is the protocol for getting those answers. It's a **manual runbook** —
not an automated test — because spinning up three concurrent CLI sessions
requires a human operator at three terminals (or three AI agent runtimes).

## What's being tested

| # | Scenario | Concern |
|---|---|---|
| S1 | Activity log — simultaneous prepend | Do entries clobber? Does the file get corrupted? |
| S2 | Handoff queue — simultaneous create | Do handoff numbers collide? (Known: we've seen 026 collide in one session.) |
| S3 | Handoff queue — one CLI reads while another writes | Torn reads? Missed handoffs? |
| S4 | SSOT replica — two CLIs regenerate simultaneously | Last-write-wins? Corruption? |
| S5 | Activity log read while being written | Hook-injection sees inconsistent snapshot? |
| S6 | Session startup — three CLIs start within 1 second | `SessionStart` hooks step on each other? |

## Protocol

### Pre-flight

1. Ensure working tree is clean. `git status` — commit or stash everything.
2. Take a snapshot: `git log -1 --format=%H > /tmp/concurrency-baseline.txt`.
3. Open three terminals. Position them so you can see all three simultaneously.
4. Start all three CLIs in orchestrator mode but do NOT send a prompt yet.

### Scenario S1 — Activity log race

**Setup:** All three CLIs have a prompt ready to send that will end with "now
append a one-line entry to `.ai/activity/log.md` saying 'CONCURRENCY-TEST-S1-<cli>
at <timestamp>'".

**Action:** Press Enter in all three terminals as close to simultaneously as
possible.

**Record:**
- Final `.ai/activity/log.md` — does it contain all three entries?
- Run `git diff .ai/activity/log.md` — any suspicious interleaving (half-entries,
  broken markdown headers)?
- File size sanity — log.md line count should increase by exactly 3 entries
  worth of lines (~10–15 lines).

**Expected behavior (per spec):** All three entries present, in prepend order.
No corruption.

**Plausible failure modes:**
- Two entries overlap at the boundary between prepend chunks.
- One CLI reads stale log, prepends to stale copy, writes back — overwriting
  another CLI's just-prepended entry (last-write-wins on the whole file).
- Markdown `---` separators interleave oddly.

### Scenario S2 — Handoff numbering collision

**Setup:** Each CLI is asked to create a new handoff to a third CLI:
- Claude → `.ai/handoffs/to-kimi/open/NNN-concurrency-test-from-claude.md`
- Kimi → `.ai/handoffs/to-kiro/open/NNN-concurrency-test-from-kimi.md`
- Kiro → `.ai/handoffs/to-claude/open/NNN-concurrency-test-from-kiro.md`

Each CLI determines `NNN` by looking at the highest existing number in the
target dir + 1.

**Action:** All three create their handoff simultaneously. (No collision
expected for S2 because the target dirs differ.)

**Variant S2b:** Two CLIs both create a handoff to `to-kimi/open/` simultaneously.
This reproduces the real collision mode.

**Record:**
- Do both S2b handoffs end up with the same NNN? (If yes: collision confirmed.)
- Does git see two files or one? (Filesystem may allow both names if paths
  differ by slug; if same path: one clobbers the other.)
- Is there a way for the losing CLI to know it lost?

**Expected behavior (per spec):** Either (a) both files exist with same number
(collision, documented known issue, matrix #16 in consolidated audit), or (b)
last-write-wins and one handoff is silently lost.

**Plausible mitigation if failure is bad:** introduce a lock file, or switch
numbering to timestamp-based, or require CLIs to claim numbers via a rename
dance.

### Scenario S3 — Read-during-write

**Setup:** CLI-A is told to write a handoff at path X. CLI-B is told to read
the full `open/` directory of the same recipient.

**Action:** Start them ~0.1s apart (A first). B should ideally try to read
while A's write is in flight.

**Record:**
- Does B see the partial file? (Empty file, truncated content, file not
  existing yet?)
- Does B's subsequent action (e.g., "count open handoffs") return a correct
  count?

**Expected behavior:** Unix-like FS → B sees either the old state (no file)
or the new state (complete file), no torn middle state. Windows NTFS behavior
may differ.

### Scenario S4 — SSOT replica race

**Setup:** Claude and Kimi are both told to regenerate their copy of
`.kimi/steering/orchestrator-pattern.md` from `.ai/instructions/orchestrator-pattern/principles.md`.
(Normally only Kimi would do this — the scenario is synthetic.)

**Action:** Simultaneous.

**Record:** Does the final file match the SSOT? Does anything clobber anything?

**Expected behavior:** Both writes produce the same content (they're reading
the same source), so the race is visible only in the copy mechanism. Should
be benign.

### Scenario S5 — Log read by UserPromptSubmit hook during write

**Setup:** One CLI is actively prepending to the log. Another CLI starts a
new prompt — its `UserPromptSubmit` hook reads `.ai/activity/log.md` to inject
recent entries into the prompt.

**Action:** Have CLI-A do a long action that ends with a log prepend. While
that's happening, submit a prompt in CLI-B.

**Record:**
- Does CLI-B's prompt see the entry CLI-A was in the middle of writing?
- Does CLI-B's hook error or succeed with stale content?

**Expected behavior:** Hook sees either pre-state or post-state (consistent
snapshot). Torn read = bug.

### Scenario S6 — Triple session-start

**Setup:** All three CLIs have just been launched. All three are running their
session-start hooks (Claude's `session-start.sh`, equivalent in Kimi/Kiro).

**Action:** Launch all three within 1 second of each other.

**Record:**
- Do any hooks fail?
- Is `git status` output consistent for all three, or does one see a different
  state?

**Expected behavior:** Read-only session-start hooks don't interfere. If any
session-start hook writes, that's the failure mode.

## Reporting

After running all six scenarios, fill in this table:

| Scenario | Status | Observation | Severity |
|---|---|---|---|
| S1 | PASS / FAIL / SKIP | | |
| S2 | | | |
| S2b | | | |
| S3 | | | |
| S4 | | | |
| S5 | | | |
| S6 | | | |

Severity scale:
- **BLOCKER**: framework is not safe to use with concurrent CLIs until this
  is fixed.
- **WARN**: rare real-world risk; document known limitation or add
  guardrail.
- **INFO**: theoretical only; low practical impact.

Write results to `.ai/tests/concurrency-test-results-YYYY-MM-DD.md` and prepend
an activity log entry summarizing the verdict.

## Cleanup

After the test:
1. `git checkout .ai/activity/log.md` to reset (or keep the test entries —
   operator's choice, mark them as CONCURRENCY-TEST so they're greppable).
2. Delete the test handoffs created in S2/S2b.
3. Delete the regenerated SSOT replicas in S4 (or leave if they're identical
   to SSOT).
4. Commit the test-results doc if results are informative.

## If any scenario is BLOCKER severity

Do not ship the framework for real work until mitigated. Options:
- Add a lock file mechanism in `.ai/` (flock-based on Unix, file-create-with-O_EXCL on Windows).
- Switch handoff numbering to `YYYYMMDD-HHMMSS-<slug>` to avoid collisions.
- Document "never run concurrent CLIs" as a hard rule and enforce via
  startup hook (check for another active session via a `.ai/.session-lock`
  file).

## Open questions this protocol does not answer

- What happens if the filesystem is a network share (e.g., Dropbox, OneDrive,
  iCloud) with eventual-consistency semantics? Not tested here.
- Git worktrees — what if two CLIs operate on different worktrees of the same
  repo? SSOT would live in only one worktree; the others would see stale
  copies until pull/rebase.
- What if one CLI crashes mid-write? No atomic-write guarantee; partial
  content could persist.

These are worth a separate protocol doc once the in-process concurrency
questions are answered.
