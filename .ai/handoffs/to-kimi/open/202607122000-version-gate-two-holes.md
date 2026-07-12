# check-version-bump.sh — close two remaining holes
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-12 20:00
Auto: yes
Risk: B
Base: origin/master

## Goal
Two holes in `scripts/check-version-bump.sh`, both self-reported honestly by the agents
that touched it. Both are the SAME failure class this project has hit all session —
**"two surfaces, one rule, nothing keeping them in lockstep."** Close both in one PR
(they live in the same script; separate PRs would conflict).

Master is at `0.0.31`. The gate is now a **push-mode detective check** (ADR-0012:
feature branches do NOT bump the version; the release-engineer assigns it at merge).
The suite is at **64 assertions** — do not weaken any of them.

---

## Hole 1 — `is_versioned` is a hand-maintained restatement
`is_versioned()` is a denylist-then-allowlist `case` statement that lists which paths
count as "versioned framework content" (i.e. shipped to adopters, so a change must bump
the version or adopter drift-detection goes silent).

**But it is restated by hand, independently of what the installer ACTUALLY ships.**
`scripts/install-template.sh` (and/or the Node installer's manifests in
`tools/multi-cli-install/`) is the real source of truth for what reaches an adopter.

**The first real failure:** someone adds a file the installer copies, forgets to add it
to `is_versioned`, and it ships to adopters **with no version bump** — so every adopter's
drift-detection stays silent about a change they DID receive. That is exactly the bug
this whole gate exists to prevent, arriving through the gate's own blind spot.

**Target:** derive the versioned-path set FROM the installer's actual ship manifest
rather than restating it. Investigate `scripts/install-template.sh` +
`tools/multi-cli-install/scripts/sync-assets.ts` + `src/installer/copy-framework.ts`
(Kimi added `.opencode/` to those manifests in PR #49 — you know this code).
- If a single machine-readable manifest exists, key off it.
- If the ship list is spread across two files, DO NOT invent a third surface — instead
  add a **check that asserts `is_versioned`'s allowlist and the installer's ship list
  agree**, failing loudly on divergence. (Same shape as the `LANE:BEGIN/END` doc↔guard
  check and the SSOT drift check. That pattern works; reuse it.)
- Keep the **denylist** (runtime/generated paths like `.claude/settings.local.json`)
  — that part is legitimately hand-curated.
Say which approach you chose and why.

---

## Hole 2 — the CHANGELOG gate catches EMPTY, not WRONG
PR #59 (merged, `c3ed473`) added a substantive-content check: a `## [x.y.z]` section
must have real bullets, not be empty or a `TODO` placeholder. Good.

**Still open:** it does NOT prove the bullets **describe the PR that bumped the
version**. Under a parallel merge train the first symptom of a botched promotion is a
version heading whose bullets belong to a **different PR**. That is *wrong content*, and
the current gate passes it.

**The tractable fix (proposed by the PR #59 author — it's a good one):** the push-mode
gate has BOTH master tips (`BASE` and `HEAD`). So it can:
- diff `## [Unreleased]` across `BASE...HEAD`, and
- assert that the new `## [x.y.z]` section's content **came from** the `[Unreleased]`
  bullets that disappeared in that same push.

That converts an unverifiable semantic claim ("do these bullets describe this PR?") into
a **mechanical** one ("did the promoted bullets come from the Unreleased section that
just emptied?"). Implement that.

**Be honest about what it still does NOT close** and say so in the script header + your
report — e.g. a release-engineer who promotes the *right* bullets but also hand-edits
them, or a PR that never added Unreleased bullets in the first place. Do not overclaim.

---

## Constraints
- **Do NOT bump `package.json`** (ADR-0012 is live — confirm: master's `gates.yml`
  version-bump step is `if: github.event_name == 'push'`). Bullets go under
  `## [Unreleased]`.
- **Note the irony you'll hit:** `scripts/check-version-bump.sh` is itself NOT in
  `is_versioned` (it's CI-side, not shipped to adopters), so your own PR likely owes no
  bump. That's correct — but *verify* it rather than assuming, and say what you found.
- All **64** existing assertions must still pass. Extend the suite for both fixes,
  including a proof each new check can actually go **RED** (a check that cannot fail is
  not a check — perturb, show red, revert, paste it).
- Fail closed on anything unparseable.
- Do NOT touch: `.claude/agents/orchestrator.md`, `.ai/tools/check-ssot-drift.sh`,
  `.ai/instructions/agent-catalog/principles.md`, `.claude/agents/{refactorer,security-auditor,data-migrator}.md`,
  `.ai/known-limitations.md` — other work is live on those.
- **Commit any `.ai/` artifact you create BEFORE your worktree goes away.** An
  uncommitted report does not exist — a design doc was destroyed exactly this way
  tonight (see `.ai/reports/kiro-2026-07-12-bash-exposure-design.md`'s provenance note).

## Verify (execute, paste)
- Full `scripts/test-check-version-bump.sh` output (64 + your new cases, 0 failed).
- The RED proof for BOTH new checks (perturb → red → revert).
- A live demo of Hole 1: add a path to the installer's ship list without allowlisting
  it → the new check FAILS.
- A live demo of Hole 2: promote bullets that did NOT come from `[Unreleased]` → FAIL;
  promote ones that did → PASS.
- `bash .ai/tools/check-ssot-drift.sh` → Drift 0.

## Deliverable
Branch `exec/kimi/version-gate-two-holes` cut from `origin/master`. Push, open a PR.
Route peer review to **KIRO**. Do NOT merge (Kiro reviews first; then the fleet merges
— merge to main is Tier B now, the owner does not gate it).

## Report back with
- which approach you chose for Hole 1 and why
- full test output + both RED proofs, verbatim
- what each fix still does NOT close (stated plainly, not hand-waved)
- PR URL

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kimi/done/`.
