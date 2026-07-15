# Example Handoff Chain: Checkout Flow

This is a concrete, file-by-file walkthrough of a feature that flows through the
six-actor cockpit/auto workflow. The project is `saja-akun`; the feature is
"add email + password checkout flow."

All filenames use the UTC timestamp convention (`YYYYMMDDHHMM-slug.md`).

## Stage 0 — Cockpit asks for architecture

`claude-cockpit` decides the feature needs a spec, so it writes:

**File:** `.ai/handoffs/to-claude/open/202607152200-design-checkout-flow.md`

```markdown
# Design checkout flow (email + password)
Status: OPEN
Sender: claude-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-15 22:00
Auto: yes
Risk: B
Next: kimai-auto,kiro-auto

## Goal
Design the checkout flow for saja-akun: user enters email + password, backend
validates and creates the account, frontend shows success/error states.

## Deliverables
1. ADR or spec in `docs/specs/checkout-flow.md`.
2. API contract in `docs/api/checkout.md`.
3. UI mock description in `docs/ui/checkout.md`.

## Verification
- [ ] Spec reviewed by claude-cockpit before implementation handoffs are emitted.

## Next step
After spec is approved, emit implementation handoffs to `kimai-auto` (backend)
and `kiro-auto` (frontend) in parallel.
```

Why `Auto: yes`? The spec work is reversible, routine design work (Risk B) and
can run headlessly in `claude-auto`.

---

## Stage 1 — Auto planner writes the spec

`claude-auto` picks up the handoff, writes the spec, and self-retires.

**File moved to:** `.ai/handoffs/to-claude/done/202607152200-design-checkout-flow.md`

```markdown
# Design checkout flow (email + password)
Status: DONE
Sender: claude-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-15 22:00
Completed: 2026-07-15 22:25
Auto: yes
Risk: B
Next: kimai-auto,kiro-auto

## Resolution
Wrote `docs/specs/checkout-flow.md`, `docs/api/checkout.md`, and
`docs/ui/checkout.md`. Spec approved by claude-auto internal review.

## Touched
- docs/specs/checkout-flow.md
- docs/api/checkout.md
- docs/ui/checkout.md
```

`claude-auto` also emits two implementation handoffs because the original
handoff had `Next: kimai-auto,kiro-auto`.

---

## Stage 2 — Parallel implementation

### Backend handoff

**File:** `.ai/handoffs/to-kimi/open/202607152300-implement-checkout-api.md`

```markdown
# Implement checkout API
Status: OPEN
Sender: claude-auto
Recipient: kimai-auto
Owner: kimai-auto
Created: 2026-07-15 23:00
Auto: yes
Risk: B
ReviewBy: kiro

## Goal
Implement the backend API described in `docs/api/checkout.md`.

## Steps
1. Add `POST /api/checkout` route in `src/routes/checkout.ts`.
2. Add zod schema in `src/schemas/checkout.ts`.
3. Add service logic in `src/services/checkout.ts`.
4. Write unit tests in `tests/unit/services/checkout.test.ts`.

## Verification
- [ ] `npm run test:unit` passes.
- [ ] `npm run typecheck` passes.
```

### Frontend handoff

**File:** `.ai/handoffs/to-kiro/open/202607152300-implement-checkout-ui.md`

```markdown
# Implement checkout UI
Status: OPEN
Sender: claude-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-15 23:00
Auto: yes
Risk: B
ReviewBy: kimi

## Goal
Implement the checkout UI described in `docs/ui/checkout.md`.

## Steps
1. Add `CheckoutForm` component in `src/components/CheckoutForm.tsx`.
2. Wire it to `POST /api/checkout`.
3. Add unit tests in `tests/unit/components/CheckoutForm.test.tsx`.

## Verification
- [ ] `npm run test:unit` passes.
- [ ] `npm run lint` passes.
```

`kimai-auto` and `kiro-auto` pick these up in parallel.

---

## Stage 3 — Peer review

`kimai-auto` finishes the backend and self-retires. Because its handoff had
`ReviewBy: kiro`, it emits:

**File:** `.ai/handoffs/to-kiro/review/202607160100-review-checkout-api.md`

```markdown
# Review: checkout API implementation
Status: OPEN
Sender: kimai-auto
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-16 01:00
Auto: yes
Risk: B
FinalReview: claude
ReviewOf: 202607152300-implement-checkout-api.md

## Goal
Review kimai-auto's backend implementation against `docs/api/checkout.md`.

## Verification
- [ ] Read the original handoff and touched files.
- [ ] Run `npm run test:unit` and `npm run typecheck`.
- [ ] If approved, emit final-review handoff to claude-auto.
```

Symmetrically, `kiro-auto` finishes the frontend and emits:

**File:** `.ai/handoffs/to-kimi/review/202607160100-review-checkout-ui.md`

```markdown
# Review: checkout UI implementation
Status: OPEN
Sender: kiro-auto
Recipient: kimai-auto
Owner: kimai-auto
Created: 2026-07-16 01:00
Auto: yes
Risk: B
FinalReview: claude
ReviewOf: 202607152300-implement-checkout-ui.md

## Goal
Review kiro-auto's frontend implementation against `docs/ui/checkout.md`.
```

---

## Stage 4 — Final review

`kiro-auto` approves the backend review handoff and, because it had
`FinalReview: claude`, emits:

**File:** `.ai/handoffs/to-claude/review/202607160200-final-review-checkout-api.md`

```markdown
# Final review: checkout API
Status: OPEN
Sender: kiro-auto
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-16 02:00
Auto: yes
Risk: B
Deploy: yes
ReviewOf: 202607152300-implement-checkout-api.md

## Goal
Final review of the checkout API before deploy.

## Verification
- [ ] Confirm peer review passed.
- [ ] Confirm CI checks are green.
- [ ] If approved, emit deploy handoff to opencode-auto.
```

`kimai-auto` does the same for the frontend, emitting:

**File:** `.ai/handoffs/to-claude/review/202607160200-final-review-checkout-ui.md`

`claude-auto` reviews both. It can merge them into one deploy handoff or emit
two deploy handoffs. In this example it emits one combined deploy handoff.

---

## Stage 5 — Deploy

`claude-auto` emits:

**File:** `.ai/handoffs/to-opencode/open/202607160300-deploy-checkout-flow.md`

```markdown
# Deploy checkout flow
Status: OPEN
Sender: claude-auto
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-16 03:00
Auto: yes
Risk: B

## Goal
Deploy the checkout flow to staging.

## Steps
1. Run dry-run deploy.
2. Verify tests pass.
3. Deploy to staging.
4. Verify staging health.

## Verification
- [ ] Staging URL returns 200.
- [ ] Smoke test passes.

## Next step
If staging is green and production deploy is wanted, emit a Risk-C handoff to
`claude-cockpit` or `kimai-cockpit` for owner confirmation.
```

`opencode-auto` deploys to staging and self-retires to
`.ai/handoffs/to-opencode/done/202607160300-deploy-checkout-flow.md`.

---

## Stage 6 — Back to cockpit for final state read

`claude-cockpit` checks the chain:

```bash
bash .ai/tools/fleet-health.sh
bash .ai/tools/dispatch-handoffs.sh
ls .ai/handoffs/to-*/done/20260716*
head -40 .ai/activity/log.md
```

Seeing all handoffs in `done/` and a clean fleet health report, the cockpit
reports to the owner: "Checkout flow implemented, reviewed, and deployed to
staging."

If production deploy is required, `claude-cockpit` writes:

**File:** `.ai/handoffs/to-opencode/open/202607160400-deploy-checkout-prod.md`

```markdown
# Deploy checkout flow to production
Status: OPEN
Sender: claude-cockpit
Recipient: opencode-auto
Owner: opencode-cockpit
Created: 2026-07-16 04:00
Auto: no
Risk: C

## Goal
Deploy the checkout flow to production after explicit owner confirmation.

## Steps
1. Confirm owner approval.
2. Run dry-run deploy.
3. Deploy to production.
4. Verify production health.
```

`Auto: no` + `Risk: C` means this never auto-dispatches. The cockpit relays it
to `opencode-auto` manually after the owner confirms.

---

## Summary of files created

```
.ai/handoffs/
├── to-claude/
│   ├── done/202607152200-design-checkout-flow.md
│   └── review/202607160200-final-review-checkout-api.md
│   └── review/202607160200-final-review-checkout-ui.md
├── to-kimi/
│   ├── done/202607152300-implement-checkout-api.md
│   └── review/202607160100-review-checkout-ui.md
├── to-kiro/
│   ├── done/202607152300-implement-checkout-ui.md
│   └── review/202607160100-review-checkout-api.md
└── to-opencode/
    ├── done/202607160300-deploy-checkout-flow.md
    └── open/202607160400-deploy-checkout-prod.md   # Risk C, waits for cockpit
```
