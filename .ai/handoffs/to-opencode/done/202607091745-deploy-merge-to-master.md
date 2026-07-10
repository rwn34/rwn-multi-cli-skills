# DEPLOY BRIEF — run pre-merge gates + no-ff merge to master
Status: OPEN — DONE (superseded by master merge b5024c2 2026-07-09)
Sender: claude-code
Recipient: opencode
Created: 2026-07-09 17:45
Auto: no
Risk: C

<!-- Auto: no / Risk: C — this is a Tier-C release (merge to master). Owner
     relays it to OpenCode and confirms the merge per Stage-2 condition #2.
     Claude's session is in "don't ask mode" and cannot execute bash/node/npx,
     so it cannot run the gates; OpenCode (Stage-2 deploy operator, ADR-0002)
     executes them in its own permission context. -->

## Why
Owner-approved merge of `claude/project-overview-pn5l4e` → `master` (the full
2026-07-09 workstream: OpenCode swap, graph removal, hook fail-open fixes, git
pre-commit backstop ADR-0005, Kiro v3 groundwork ADR-0006, target architecture
ADR-0007, honest enforcement docs). Claude's release-engineer verified
preconditions but ABORTED at the gates — its session denies `bash`/`node`/`npx`.
You have shell; run the gates, and if ALL green, execute the merge. This is your
Stage-2 deploy lane.

## Stage-2 conditions (honor all)
1. Run ONLY the commands enumerated below — do not improvise.
2. REFUSE if the working tree is dirty (except `.claude/settings.local.json`,
   which is expected local env) or if ANY gate is red/unrunnable.
3. Paste real output for every gate — an unrun gate is NOT a green gate.
4. If any gate fails, ABORT before the merge and report — do not `--no-verify`,
   do not force anything.

## Guard-still-works check (do this FIRST — verifies today's config change)
`opencode.json` permission was just changed `ask`→`allow` (frictionless), on the
premise that the `framework-guard.js` plugin enforces INDEPENDENTLY of the
permission prompt. PROVE that's still true before anything else: attempt to write
a file `src/oc-guard-verify.txt` (content: x). It MUST be **BLOCKED by
framework-guard** (out-of-lane). If it is blocked → the plugin still guards under
`allow`; proceed. If the write SUCCEEDS → the config change broke enforcement:
ABORT everything, report loudly, and do NOT merge. (Clean up the file if created.)

## Preconditions (verify, paste)
- `git fetch origin`
- `git rev-parse --abbrev-ref HEAD` → expect `claude/project-overview-pn5l4e`
- `git status --porcelain` → clean EXCEPT possibly `.claude/settings.local.json`
- Feature branch == `origin/claude/project-overview-pn5l4e` (ahead/behind 0/0)
- `master` == `origin/master` (should be `86cf0d8`)

## Gates (run each; ALL must be green — paste each result line)
```
bash .ai/tools/check-ssot-drift.sh                 # expect: Checked: 24 replicas, Drift: 0
bash .claude/hooks/test_hooks.sh                    # expect: PASS 54/54 (>=54)
bash .kimi/hooks/test_hooks.sh                      # expect: PASS: 48/48
bash .kiro/hooks/test_hooks.sh                      # expect: PASS: 39/39 (>=39)
node .opencode/plugin/test-guard.mjs               # expect: PASS 45 / FAIL 0
cd tools/multi-cli-install && npx tsc --noEmit && npx vitest run; cd ../..
    # tsc: exit 0. vitest KNOWN profile: ~80 passed / 3 failed (git-not-on-PATH
    # env failures) + pack suite env fail. ANYTHING WORSE than that = RED = abort.
```

## Merge (only if ALL gates green)
```
git checkout master
git pull --ff-only origin master
git merge --no-ff claude/project-overview-pn5l4e -m "merge: OpenCode swap + graph removal + hook fail-open fixes + git backstop (ADR-0005) + Kiro v3 groundwork (ADR-0006) + target architecture (ADR-0007) + honest enforcement docs"
git push origin master
git ls-remote origin master        # must equal: git rev-parse master
git checkout claude/project-overview-pn5l4e
```
NO tag, NO publish, NO version bump. (If `git merge` is rejected by any hook,
STOP and paste the message — do not bypass.)

## Report back with
Prepend an activity-log entry (identity `opencode`). Report:
- each gate's pasted result line
- the merge commit hash + `ls-remote == rev-parse` confirmation
- rollback command: `git revert -m 1 <merge-hash>`
- confirmation you returned to the feature branch
Set this handoff Status: DONE + move to `to-opencode/done/`.
