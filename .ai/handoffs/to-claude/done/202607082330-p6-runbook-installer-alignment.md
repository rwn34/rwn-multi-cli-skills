# P6 — Upgrade runbook + installer alignment (stale-fleet layers 2-3)
Status: DONE (2026-07-09 — see closure note)

<!-- CLOSURE 2026-07-09: all steps executed (activity log 00:15 entry has the
     full evidence). Follow-ups spun out for the Phase-B session:
     1. Extract a SHARED framework-file-list module — sync-assets.ts,
        copy-framework.ts, manifest.ts each carry a parallel FRAMEWORK_FILES
        list; CRUSH.md was missing from ALL THREE until today (silent drift).
     2. CI tripwire: grep for hardcoded framework versions (0\.0\.[0-9]
        outside package.json/CHANGELOG) — two were found+fixed today
        (Selector.ps1, install-template.sh); the next one should be caught
        mechanically.
     3. End-to-end upgrade-over-existing-install coverage (tester's riskiest
        untested area — where silent adopter data loss would first appear).
        This IS Phase B's entry test.
     4. Run the suite once where cmd children have git/npm on PATH — the
        pack.test.ts tarball regression suite provides zero protection in
        this environment (4th environmental casualty, same PATH root cause).
     5. Owner answers plan §12 questions before Phases B-F start.
     6. .crush.json manifest classification (framework-owned vs
        adopter-may-extend) to be decided when Phase B diffing lands. -->

Sender: claude-code
Recipient: claude-code
Created: 2026-07-08 23:30
Auto: yes
Risk: B

## Goal
Close the stale-fleet gap (layers 2-3 of the coverage plan from
done/202607071330-fleet-upgrade-continuation.md): projects with older
framework installs behave on OLD rules when opened via 4AI-panes — worst case
is a Crush pane running `--yolo` with no CRUSH.md at all. Layer 1 (Selector
badge) lives in the P5 handoff.

## Current state
- No `docs/guides/framework-upgrade-runbook.md` exists.
- `tools/multi-cli-install/` violates ADR-0003 (`src/.../wire-mcp.ts` wires
  all 3 graph servers to all 4 CLIs) and its assets predate: CRUSH.md,
  operating-prompt SSOT, hook Rule 2.5, AND the entire 2026-07-08 rebuild
  (delivery-integrity SSOT, autonomy tiers, handoff protocol v2 with Risk
  field, amended ADR-0002 role lanes, 24 drift pairs).
- `--upgrade` mode: planned in `.ai/research/framework-upgrade-mode-plan.md`
  (Phases A-F), not implemented. Phase A = `.ai/.framework-version` marker.
- Battle-tested upgrade lessons from the 4AI-panes repo upgrade (2026-07-07):
  (a) Rule 2.5 probes must target a project-source path (e.g.
  `docs/hook-probe.tmp`), NOT `.ai/` — writable by everyone, proves nothing;
  (b) `.ai/known-limitations.md` must be in the copy list (was missed);
  (c) write `.ai/.framework-version` at the end.

## Target state
1. `docs/guides/framework-upgrade-runbook.md` — generic procedure:
   sync-template → preserve runtime state → copy → adapt → verify, embedding
   the three lessons above. Delegate to doc-writer; verify every path/command
   against the current tree.
2. Installer assets re-synced to the post-rebuild framework;
   `wire-mcp.ts` fixed per ADR-0003 (each CLI gets at most its own graph;
   Crush gets none). Delegate coder + tester. Gates: existing vitest suite
   green (83+ tests), `tsc --noEmit`, drift 24/0, hooks 32/32.
3. `--upgrade` Phase A implemented (version marker + manifest at install
   end) per the research plan §11 — the plan's 6 open questions (§12) go to
   the owner BEFORE Phases B-F, which stay out of scope here.

## Steps
0. infra-engineer (small, do first): fix `.github/workflows/framework-check.yml`
   — its `paths-ignore: '**/*.md'` (both triggers) exempts markdown-only
   changes from CI, but the SSOT drift checker's entire domain IS .md
   replicas, so replica drift ships unchecked (found 2026-07-08 while
   verifying the merge pipeline). Remove the paths-ignore blocks (the suite
   is seconds-cheap; no filter needed). Separately: recommend the owner
   enable GitHub branch protection on master requiring `framework-check` —
   settings-page action, owner-only.
1. doc-writer: runbook (content above + research plan references).
2. coder: wire-mcp.ts ADR-0003 fix; re-run `scripts/sync-assets.ts`.
3. tester: full installer suite + a fixture install asserting the new assets
   (CRUSH.md present, delivery-integrity SSOT present, Risk field in
   template.md, only own-graph MCP wiring).
4. coder: Phase A (manifest.ts + version.ts per plan §10-11).
5. infra-engineer: commit per-topic on a feature branch (Tier A).

## Verification
- (a) vitest + tsc outputs pasted; (b) fixture-install tree grep evidence
  (CRUSH.md, delivery-integrity, Risk: field); (c) `.ai/.framework-version`
  present in a fresh fixture install.

## Next step / future note
After Phase A ships, every new install becomes upgradeable — then Phases B-F
(detector/planner/merger/executor) unlock lazy fleet-wide upgrades. Breaks
first: any future SSOT addition that forgets to update the installer assets —
the fixture-install grep test in step 3 is the tripwire; keep extending it.

## Report back with
- (a) runbook path + section list, (b) gate outputs, (c) commit SHAs
