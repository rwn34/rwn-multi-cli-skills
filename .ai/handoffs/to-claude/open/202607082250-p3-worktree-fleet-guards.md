# P3 — Worktree/fleet hook guards + commit fleet scripts (ADR-0004)
Status: OPEN
Sender: claude-code
Recipient: claude-code
Created: 2026-07-08 22:50
Auto: yes
Risk: B

## Goal
Finish the worktree + multi-project topology (ADR-0004, renumbered from 0002 on
2026-07-08): add the two hook guards the ADR promises, and get the two orphaned
scripts committed. This completes the workstream orphaned by the lost
2026-07-07 continuation handoff.

## Current state
- `docs/architecture/0004-worktree-multi-project-topology.md` — accepted ADR (untracked).
- `.ai/research/worktree-multi-project-topology.md` — design doc (untracked).
- `scripts/fleet-init.sh`, `scripts/wt-bootstrap.sh` — written, `bash -n` clean
  (verified 2026-07-08), NOT invoked against a real project yet, uncommitted.
- `.claude/hooks/pretool-write-edit.sh` — has NO worktree-confinement or
  fleet-whitelist guard yet (ADR §Enforcement promises both).

## Target state
1. `pretool-write-edit.sh` gains: (a) worktree confinement — an executor
   worktree session may write only under its own `.wt/<project>/<name>/` +
   the junctioned `.ai/`; (b) fleet whitelist — block writes to
   `.fleet/handoffs/to-X/` unless registry `talks_to` includes X.
2. `.claude/hooks/test_hooks.sh` gains cases for both guards (keep all
   existing tests passing).
3. Kimi/Kiro parity handoffs written to their queues (Risk B, Auto yes).
4. Both scripts + ADR + research doc committed on a feature branch via
   infra-engineer (Tier A).
5. Runtime smoke test: run `wt-bootstrap.sh` against a scratch clone (NOT this
   repo) and paste the summary output — delivery-integrity requires execution
   evidence, `bash -n` is not enough.

## Steps
1. Read ADR-0004 §Enforcement + the research doc §6.
2. Design guard logic (note: detect "am I in a worktree" via `git rev-parse
   --git-common-dir` != `--git-dir`).
3. Edit hook + tests (orchestrator-direct, .claude/ scope), run suite.
4. Write Kimi/Kiro parity handoffs.
5. Delegate scratch-clone smoke test + commit to infra-engineer.

## Verification
- (a) `bash .claude/hooks/test_hooks.sh` all-pass, pasted.
- (b) `wt-bootstrap.sh` smoke-test output on a scratch repo, pasted.
- (c) grep evidence of both guards in the hook.

## Next step / future note
After this: P4 automation (dispatcher polling) benefits from worktrees because
headless executors can run concurrently without collisions. Breaks first:
`link_ai()`'s Windows junction detection if Git-for-Windows changes `cygpath`
behavior — the smoke test will catch it.

## Report back with
- (a) hook diff summary + test suite output
- (b) smoke test output
- (c) commit SHA on the feature branch
