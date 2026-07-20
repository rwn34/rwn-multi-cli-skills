# Example Handoff Chain — Feature with Backend, Frontend, and Staging Deploy

This is a concrete walkthrough of the cockpit/auto workflow defined in
`docs/specs/saja-akun-cli-workflow.md`. It shows the exact status blocks and
filenames for a sample feature.

## Scenario

Add a new `/api/qr` endpoint and a QR-code top-bar widget in the `saja-qr`
project. The feature flows through planning → backend → frontend → peer review
→ final review → staging deploy → cockpit validation.

## Stage 1 — Architecture plan from the cockpit

`claude-cockpit` decides the feature is architectural enough that it should
plan it itself, then hand off to `claude-auto` to turn the plan into a
spec-shaped handoff chain.

**File:** `.ai/handoffs/to-claude/open/202607181530-plan-qr-feature.md`

```markdown
# Plan QR feature endpoint and widget
Status: OPEN
Sender: claude-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-18 22:30 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@a1b2c3d
Evidence: VERIFIED (grep -n "qr" docs/specs/api.md -> no existing QR routes)

## Goal
Design the backend endpoint `/api/qr` and the frontend top-bar widget, then
break the work into auto-dispatchable handoffs for kimai-auto and kiro-auto.

## Current state
- No QR endpoint exists.
- Top-bar component lives at `src/components/TopBar.tsx`.

## Target state
- `docs/specs/qr-feature.md` with API contract and component props.
- Handoffs filed for backend implementation and frontend implementation.

## Steps
1. Write `docs/specs/qr-feature.md`.
2. File `to-kimai-auto/open/202607181600-backend-qr-feature.md`.
3. File `to-kiro-auto/open/202607181700-frontend-qr-feature.md`.

## Verification
- (a) `cat docs/specs/qr-feature.md` shows endpoint + props.
- (b) Both handoff files exist in their queues.

## Report back with
- (a) path to the spec file
- (b) filenames of the two follow-up handoffs

## When complete
Recipient self-retires to `to-claude/done/`.
```

**Result:** `claude-auto` picks it up, writes the spec, and files the next two
handoffs.

---

## Stage 2 — Backend implementation

**File:** `.ai/handoffs/to-kimai/open/202607181600-backend-qr-feature.md`

```markdown
# Implement /api/qr endpoint
Status: OPEN
Sender: claude-auto
Recipient: kimai-auto
Owner: kimai-auto
Created: 2026-07-18 23:00 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@e4f5g6h
Evidence: VERIFIED (cat docs/specs/qr-feature.md -> contract defined)
ReviewBy: kiro-auto

## Goal
Implement the backend endpoint described in `docs/specs/qr-feature.md`.

## Current state
Spec exists; no backend code.

## Target state
- `src/backend/routes/qr.ts` implements `/api/qr`.
- Tests in `tests/unit/backend/qr.test.ts` pass.

## Steps
1. Create `src/backend/routes/qr.ts`.
2. Add route registration in `src/backend/app.ts`.
3. Write tests and run `npm test`.

## Verification
- (a) `npm test -- tests/unit/backend/qr.test.ts` passes.
- (b) `curl http://localhost:3000/api/qr` returns expected payload.

## Report back with
- (a) files touched
- (b) test output pasted

## When complete
Recipient self-retires to `to-kimai/done/` and emits
`to-kiro/review/202607181800-review-backend-qr.md`.
```

**Result:** `kimai-auto` implements, tests, retires to `done/`, and emits a
review handoff.

---

## Stage 3 — Frontend implementation (parallel)

**File:** `.ai/handoffs/to-kiro/open/202607181700-frontend-qr-feature.md`

```markdown
# Implement QR top-bar widget
Status: OPEN
Sender: claude-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-18 23:00 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@e4f5g6h
Evidence: VERIFIED (cat docs/specs/qr-feature.md -> widget spec defined)
ReviewBy: kimai-auto

## Goal
Implement the QR widget in the top bar per `docs/specs/qr-feature.md`.

## Current state
Spec exists; no widget code.

## Target state
- `src/components/QrWidget.tsx` exists.
- `src/components/TopBar.tsx` imports and renders it.

## Steps
1. Create `src/components/QrWidget.tsx`.
2. Update `src/components/TopBar.tsx`.
3. Run frontend tests / lint.

## Verification
- (a) `npm run lint` passes.
- (b) `npm run test:unit -- QrWidget` passes.

## Report back with
- (a) files touched
- (b) lint + test output pasted

## When complete
Recipient self-retires to `to-kiro/done/` and emits
`to-kimai/review/202607181900-review-frontend-qr.md`.
```

**Result:** `kiro-auto` implements, tests, retires, and emits a review handoff.

---

## Stage 4 — Peer review

**File:** `.ai/handoffs/to-kiro/review/202607181800-review-backend-qr.md`

```markdown
# Review backend QR endpoint
Status: OPEN
Sender: kimai-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-18 23:30 (UTC+7)
Auto: yes
Risk: A
Observed-in: exec/kimai/202607181600-backend-qr-feature@i7j8k9l
Evidence: VERIFIED (git log --oneline exec/kimai/... | head -1 -> i7j8k9l)
FinalReview: claude-auto

## Goal
Review the backend implementation for contract compliance and edge cases.

## Steps
1. Read `src/backend/routes/qr.ts` and tests.
2. Run tests.
3. Approve or emit a fix handoff.

## Verification
- (a) `npm test -- tests/unit/backend/qr.test.ts` passes on this worktree.

## Report back with
- (a) review verdict (APPROVED / CHANGES_REQUESTED)
- (b) any fix handoff filename emitted

## When complete
Recipient self-retires to `to-kiro/done/`.
```

**Result:** `kiro-auto` reviews backend, approves. The symmetric review of the
frontend by `kimai-auto` also approves.

---

## Stage 5 — Final review

`claude-auto` final-reviews both implementations once both peer reviews are
retired.

**File:** `.ai/handoffs/to-claude/review/202607182000-final-review-qr.md`

```markdown
# Final review QR feature
Status: OPEN
Sender: claude-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-19 00:00 (UTC+7)
Auto: yes
Risk: B
Observed-in: main@e4f5g6h
Evidence: VERIFIED (
  gh pr view 42 --json state,mergeStateStatus -> "state":"OPEN","mergeStateStatus":"CLEAN"
)
Deploy: yes

## Goal
Final-review the QR feature PR and queue staging deploy.

## Steps
1. Review the combined diff.
2. Ensure CI green.
3. Merge the PR (Tier B, author ≠ final reviewer satisfied by peer reviews).
4. Emit `to-opencode/open/202607182100-deploy-staging-qr.md`.

## Verification
- (a) PR merged to `main`.
- (b) Deploy handoff exists in `to-opencode/open/`.

## Report back with
- (a) merge commit SHA
- (b) deploy handoff filename

## When complete
Recipient self-retires to `to-claude/done/`.
```

**Result:** `claude-auto` merges the PR and files the staging deploy handoff.

---

## Stage 6 — Staging deploy

**File:** `.ai/handoffs/to-opencode/open/202607182100-deploy-staging-qr.md`

```markdown
# Deploy QR feature to staging
Status: OPEN
Sender: claude-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-19 00:30 (UTC+7)
Auto: yes
Risk: B
Observed-in: main@m7n8o9p
Evidence: VERIFIED (gh run list --branch main --limit 1 --json conclusion -> "success")
Gate: owner (staging deploy is Tier B; no hard gate, notify after)
# No Gate-satisfied-by needed for staging; dry-run first, then deploy.
Next: kimi-cockpit

## Goal
Deploy the merged QR feature to the staging environment.

## Steps
1. Dry-run deploy: `bash infra/deploy.sh staging --dry-run`.
2. If clean, deploy: `bash infra/deploy.sh staging`.
3. Write `to-kimai/open/202607182200-validate-staging-qr.md` for cockpit validation.

## Verification
- (a) Dry-run output pasted.
- (b) Deploy command output pasted.
- (c) Staging URL returns 200.

## Report back with
- (a) deploy output
- (b) validation handoff filename

## When complete
Recipient self-retires to `to-opencode/done/`.
```

**Result:** `opencode-auto` deploys to staging and files a validation handoff
back to a cockpit.

---

## Stage 7 — Cockpit validation

**File:** `.ai/handoffs/to-kimai/open/202607182200-validate-staging-qr.md`

```markdown
# Validate QR feature on staging
Status: OPEN
Sender: opencode-auto
Recipient: kimi-cockpit
Owner: kimi-cockpit
Created: 2026-07-19 01:00 (UTC+7)
Auto: no
Risk: C
Observed-in: main@m7n8o9p
Evidence: VERIFIED (curl https://staging.saja-qr.example/api/qr -> 200 OK)

## Goal
Validate the staging deployment and decide whether to request production deploy.

## Steps
1. Open the staging app and verify the QR widget renders.
2. Verify the `/api/qr` endpoint.
3. If good, tell the owner to authorize production deploy.
4. If not, file a fix handoff.

## Verification
- (a) Manual/exploratory test on staging.

## Report back with
- (a) validation result
- (b) owner decision on production deploy

## When complete
Recipient self-retires to `to-kimai/done/`.
```

**Result:** `kimi-cockpit` validates, asks the owner. If the owner authorizes
production deploy, `kimi-cockpit` files `to-opencode/open/202607190100-deploy-production-qr.md`
with `Gate-satisfied-by: owner @ 2026-07-19 01:15 (UTC+7)` and `Relay: kimi-cockpit`.

---

## Stage 8 — Production deploy (Tier C)

**File:** `.ai/handoffs/to-opencode/open/202607190100-deploy-production-qr.md`

```markdown
# Deploy QR feature to production
Status: OPEN
Sender: kimi-cockpit
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-19 01:20 (UTC+7)
Auto: yes
Risk: C
Observed-in: main@m7n8o9p
Evidence: VERIFIED (curl https://staging... -> 200 OK)
Gate: owner
Gate-satisfied-by: owner @ 2026-07-19 01:15 (UTC+7)
Relay: kimi-cockpit

## Goal
Deploy the validated QR feature to production.

## Steps
1. Dry-run: `bash infra/deploy.sh production --dry-run`.
2. Paste dry-run output to the owner.
3. On explicit per-deploy confirmation, deploy.

## Verification
- (a) Dry-run output pasted.
- (b) Production deploy output pasted.
- (c) Production health check passes.

## Report back with
- (a) deploy output
- (b) production health-check result

## When complete
Recipient self-retires to `to-opencode/done/`.
```

**Result:** `opencode-auto` deploys to production after the owner confirms.

---

## Summary of the chain

```text
claude-cockpit
  → to-claude/open/202607181530-plan-qr-feature.md
    → claude-auto (plan + file next handoffs)
      → to-kimai/open/202607181600-backend-qr-feature.md
        → kimai-auto (backend)
          → to-kiro/review/202607181800-review-backend-qr.md
            → kiro-auto (peer review backend)
      → to-kiro/open/202607181700-frontend-qr-feature.md
        → kiro-auto (frontend)
          → to-kimai/review/202607181900-review-frontend-qr.md
            → kimai-auto (peer review frontend)
      → to-claude/review/202607182000-final-review-qr.md
        → claude-auto (merge + deploy handoff)
          → to-opencode/open/202607182100-deploy-staging-qr.md
            → opencode-auto (staging deploy)
              → to-kimai/open/202607182200-validate-staging-qr.md
                → kimi-cockpit (validation + owner gate)
                  → to-opencode/open/202607190100-deploy-production-qr.md
                    → opencode-auto (production deploy)
```
