# Self-grep-verify

A discipline for grounding claims of completed work in the actual working tree.
Applies equally to all three CLIs (Claude Code, Kimi CLI, Kiro CLI).

The defect this defends against is **junior-engineer optimism**, not
hallucination. The CLI implements something, glances at it, thinks it looks
right, reports done. The work exists and is approximately correct, but the
claims overstate completeness — "wrapped 3 sites in try/catch" when only 2 were
wrapped, "added 5 columns via migration" when only 1 ALTER landed, "alias logic
handles fragment + query + path" when the query split never happened. Each of
these has burned a downstream project; each was preventable by re-reading the
tree before writing the report.

## The rule

For any claim of completed work, before publishing the claim:

1. Run `rg` (or `grep`) against the working tree for the construct you say you
   added, changed, or removed.
2. Paste 1–3 matching lines next to the claim, with file path and line number.
3. If grep returns nothing where you expected something, **fix the code, don't
   fudge the report.**

The grep output is the evidence. The claim without the evidence is an
assertion; the claim with the evidence is a fact.

## Scope tiers

Enforcement is asymmetric. The discipline is strongest where the cost of being
wrong is highest.

### Tier 1 — Completion handoffs (strict)

Every concrete claim in a `.ai/handoffs/to-<other>/open/` completion report
MUST carry a grep-verified snippet. Handoffs land work that another CLI will
build on, deploy from, or sign off — the receiving CLI cannot read minds, only
files. Handoffs without snippets are reviewed at the same skepticism level as
no claims made: the recipient re-greps and treats the work as unverified until
they confirm it themselves.

Handoff templates may add a `Grep-verified evidence` block per claim. Even
without a template field, paste the evidence inline under each claim.

### Tier 2 — Activity log entries (medium)

Entries in `.ai/activity/log.md` that claim file changes should name the
touched paths and, when claiming a specific construct landed, include a grep
snippet or the resulting line. Lighter than handoffs because activity entries
are summary-level and prepended in bulk — but readers (humans and other CLIs)
still use them to reconstruct what happened, so the same drift rules apply.

### Tier 3 — In-chat statements (honor-based)

When telling the user "I fixed X" or "added Y", prefer to ground it in the
actual line: "at line 47 of `foo.js` you'll see the new guard." Soft
expectation, no enforcement mechanism — the user is right there and will push
back if the diff doesn't match the claim. The discipline is to not get into
the habit of fuzzy summaries, because the habit leaks into Tier 1 and Tier 2
where it costs more.

## What counts as a concrete claim

Things that need a grep snippet:

- "Added column `X` to table `Y`" — grep the migration file
- "Wrapped N call sites in try/catch" — grep should return N matches
- "Added `compareEnabled` to the effect deps array" — grep the deps line
- "All 5 migrations applied" — grep migration filenames or list `migrations/`
- "Renamed `oldFn` to `newFn` across the codebase" — grep should return zero
  hits for `oldFn` and at least one for `newFn`
- "Removed the deprecated handler" — grep should return zero hits

Things that do **not** need a grep snippet:

- Process descriptions ("ran the test suite", "checked the lint output")
- Subjective statements ("the refactor looks cleaner now")
- Counts of files read or queries made
- Decisions and rationale ("chose option B because…")

If the claim is verifiable by re-reading the tree, it needs the snippet. If
it's about what the CLI did rather than what now exists, it doesn't.

## The grep mechanic

Pattern: **claim → command → output → next claim.**

Worked example. Claim being made: *"F1 fix landed: `applyAlias` now splits on
`?` and `/` before the `VALID_TABS.includes` check."*

    $ rg -n "VALID_TABS.includes" src/router/alias.ts
    src/router/alias.ts:47:  const base = raw.split(/[?#/]/)[0];
    src/router/alias.ts:48:  if (VALID_TABS.includes(base)) return base;

Two lines, file path, line numbers — that's the evidence. Paste it directly
under the claim. The reader can see the split happened on line 47 before the
check on line 48; the claim is grounded.

For multi-site claims, show the count too:

    $ rg -cn "try \{" src/api/handlers.ts
    src/api/handlers.ts:3

Three try blocks. If the claim was "wrapped 3 sites", the count matches; if
the claim was "wrapped 4 sites", stop and go fix the fourth one before writing
the report.

## When grep returns nothing

You expected a match and got none. The claim is wrong. Two valid responses:

1. **Fix the code** so the construct exists, then re-grep and paste the now-real
   evidence.
2. **Rewrite the claim** to match reality ("attempted but blocked by X",
   "partially done — 2 of 3 sites wrapped").

The invalid response is to keep the claim and skip the snippet. That is the
exact failure mode this discipline exists to prevent.

## Asymmetric enforcement — why

| Tier | Reader | Drift detection | Enforcement |
|---|---|---|---|
| Handoffs | Another CLI | Mechanical re-grep | Strict |
| Activity log | Humans + CLIs (later) | Post-hoc audit | Medium |
| Chat | The user, live | Real-time pushback | Soft |

Handoffs are mechanically checkable — the receiving CLI runs the same commands
and sees the same output (or doesn't). Activity log entries are checkable but
usually aren't checked until something breaks. Chat is interactive: the user
catches drift in real time, so the cost of an unverified claim is a follow-up
question rather than a deployed bug.

This asymmetry is the point. The discipline scales to the cost of being wrong.

## Cost

About 3 minutes per completion handoff — one grep per concrete claim, paste
the output, move on. In exchange: a recurring defect class disappears. Every
"this looks done but isn't" handoff we've audited would have been caught by a
single grep before the report was written.

Worth it.

## Companion docs

- `AGENTS.md` — cross-CLI handoff protocol overview
- `.ai/handoffs/README.md` — handoff queue lifecycle and ownership rules
- `.ai/handoffs/template.md` — handoff file shape; the "Report back with"
  section is where grep-verified evidence belongs
- `.ai/instructions/karpathy-guidelines/principles.md` — the broader "surface
  assumptions, define verifiable success criteria" framing this rule extends

---

**This rule is working if:** completion handoffs carry grep snippets next to
their claims, downstream CLIs stop discovering broken work after the handoff
was marked done, and the phrase "wait, let me re-grep" appears before reports
go out rather than after they're acted on.
