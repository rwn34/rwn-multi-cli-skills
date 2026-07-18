#!/bin/bash
# check-tier-restatements.sh — assert the hand-maintained tier restatements still
# agree with the operating-prompt SSOT §8. Exit 0 if consistent, 1 on any failure.
# Run from repo root.
#
# WHY THIS EXISTS
# ---------------
# The autonomy-tier table lives in SIX places:
#   1. the SSOT            .ai/instructions/operating-prompt/principles.md §8
#   2-4. three replicas    generated + byte-diffed by check-ssot-drift.sh
#   5. CLAUDE.md                        <- hand-written restatement, NO check
#   6. .claude/agents/orchestrator.md   <- hand-written restatement, NO check
#
# (5) and (6) are PROSE RESTATEMENTS, not replicas — they paraphrase the tiers in
# their own voice, so the byte-for-byte drift checker structurally cannot cover
# them. That gap is not theoretical: both silently drifted through PR #54 and
# would have drifted again in PR #57. This script closes it.
#
# DESIGN — why keywords are anchored on BOTH sides
# ------------------------------------------------
# We do NOT compare bytes (the restatements legitimately reword things). We assert
# that a set of LOAD-BEARING CONCEPTS — the phrases that actually decide who is
# allowed to do what — appear in all three documents.
#
# The subtle part: a keyword table checked only against (5) and (6) would be a
# FAKE check. If someone moved "deploy to STAGING" to Tier C in the SSOT, that
# table would still find the old string in the two files and pass green, while the
# SSOT it is supposed to track had moved out from under it. So every concept is
# asserted on BOTH sides:
#
#   a) it must still be present in the SSOT §8 section  (the SSOT anchor), and
#   b) it must be present in each restatement           (the restatement anchor).
#
# Consequence: moving or deleting a tier item in the SSOT turns this RED until a
# human updates the concept table AND both restatements. That is the whole point —
# the check fails loudly on SSOT movement instead of quietly tracking a stale copy.
#
# Placement assertions additionally pin the two tiers the owner actually gates on:
# staging deploy MUST sit in Tier B, production deploy MUST sit in Tier C. If those
# ever swap in the SSOT, this fires regardless of what the prose says.
#
# It deliberately does NOT assert on incidental prose — only on the keywords above.
# Innocuous rewording of the surrounding sentences will not red the build.

set -u

# Optional first arg: repo root to check (defaults to CWD, so the `gates` and
# check-ssot-drift.sh invocations stay a bare `bash .ai/tools/check-tier-restatements.sh`).
# The override exists so the test suite can point this at a throwaway copy of the
# tree, perturb it, and assert the check goes RED — without ever touching the real
# files. A check nobody has watched fail is not a check.
ROOT="${1:-.}"
cd "$ROOT" || { echo "TIER-RESTATEMENT FAIL: cannot cd to root: $ROOT"; exit 1; }

SSOT=".ai/instructions/operating-prompt/principles.md"
RESTATEMENTS=("CLAUDE.md" ".claude/agents/orchestrator.md")

fails=0
checks=0

fail() { echo "TIER-RESTATEMENT FAIL: $*"; fails=$((fails + 1)); }

for f in "$SSOT" "${RESTATEMENTS[@]}"; do
  [ -f "$f" ] || { echo "TIER-RESTATEMENT FAIL: missing file: $f"; echo "Tier concepts checked: 0, Failures: 1"; exit 1; }
done

# Collapse each document to a single whitespace-normalized line. Both the SSOT and
# CLAUDE.md are hard-wrapped, so a load-bearing phrase such as "commits, pushes,
# branch creation" is routinely split across a newline. Matching without this
# normalization would produce false REDs on nothing but line-wrap.
norm() { tr '\n' ' ' < "$1" | tr -s ' \t'; }

# §8 only, raw lines: from the "## 8." heading to the next "## " heading. Scoping
# to the section is what makes the SSOT anchor meaningful — a stray mention of
# "deploy to STAGING" elsewhere in the SSOT must not satisfy a tier assertion.
section8_raw() {
  awk '/^## 8\./ {inside=1} inside && /^## / && !/^## 8\./ {inside=0} inside' "$SSOT"
}

section8() { section8_raw | tr '\n' ' ' | tr -s ' \t'; }

# A single tier's bullet text within §8: from "- **Tier X" up to the next "- **Tier"
# (or end of section). Used for the placement assertions.
tier_bullet() {
  section8_raw | awk -v t="$1" '
    $0 ~ ("^- \\*\\*Tier " t)      { grab=1; print; next }
    grab && /^- \*\*Tier /         { grab=0 }
    grab                            { print }
  ' | tr '\n' ' ' | tr -s ' \t'
}

S8="$(section8)"
TIER_A="$(tier_bullet A)"
TIER_B="$(tier_bullet B)"
TIER_C="$(tier_bullet C)"

[ -n "$S8" ]     || fail "could not locate section '## 8.' in $SSOT"
[ -n "$TIER_A" ] || fail "could not locate the Tier A bullet in $SSOT §8"
[ -n "$TIER_B" ] || fail "could not locate the Tier B bullet in $SSOT §8"
[ -n "$TIER_C" ] || fail "could not locate the Tier C bullet in $SSOT §8"

# --- concept table -----------------------------------------------------------
# label <TAB> extended-regex (case-insensitive)
#
# Regexes are written to tolerate the three documents' different phrasings of the
# same rule (e.g. the SSOT's "merging to main" vs the restatements' "merging a
# peer-reviewed, CI-green PR to main") while still pinning the load-bearing words.
CONCEPTS=$(cat <<'EOF'
Tier A name	Tier A
Tier B name	Tier B
Tier C name	Tier C
Tier A: commits	commits
Tier A: pushes	pushes
Tier A: branch creation	branch creation
Tier B: merge to main	merg[a-z]*([^.]{0,80} )?main
Tier B: worktree/branch cleanup	worktree[^.]{0,40}(cleanup|hygiene)
Tier B: ADR authorship	ADR authorship or amendment
Tier B: deploy to STAGING	deploy to STAGING
Tier C: deploy to PRODUCTION	deploy to PRODUCTION
Tier C: publish	publish
Tier C: destructive ops on shared history	destructive op[a-z]* on shared history
Tier C: secrets	secrets
Coupling: merge must not auto-deploy	never auto-trigger a deploy
Coupling: staging must not auto-promote	never auto-promote to production
Owner directive 2026-07-12	Committing tree, merge, cleanup, push
EOF
)

# --- assertions --------------------------------------------------------------
S8_NORM="$S8"
declare -a R_NORM
for i in "${!RESTATEMENTS[@]}"; do
  R_NORM[$i]="$(norm "${RESTATEMENTS[$i]}")"
done

while IFS="$(printf '\t')" read -r label re; do
  [ -n "$label" ] && [ -n "$re" ] || continue
  checks=$((checks + 1))

  # (a) SSOT anchor — the concept must still live in §8. If a tier item is moved
  #     or deleted upstream, this fires and the table must be updated with it.
  if ! printf '%s' "$S8_NORM" | grep -Eqi -- "$re"; then
    fail "[$label] not found in $SSOT §8 — the SSOT moved; update this table AND both restatements (regex: $re)"
  fi

  # (b) restatement anchors — both hand-maintained files must carry it too.
  for i in "${!RESTATEMENTS[@]}"; do
    if ! printf '%s' "${R_NORM[$i]}" | grep -Eqi -- "$re"; then
      fail "[$label] missing from ${RESTATEMENTS[$i]} (regex: $re)"
    fi
  done
done <<EOF
$CONCEPTS
EOF

# --- placement assertions ----------------------------------------------------
# The two gates the owner actually cares about must sit in the right tiers in the
# SSOT. A prose-only check would not notice staging silently becoming owner-gated
# (or, worse, production silently becoming fleet-callable).
checks=$((checks + 2))
printf '%s' "$TIER_B" | grep -Eqi -- "deploy to STAGING" \
  || fail "[placement] 'deploy to STAGING' is not in the SSOT §8 Tier B bullet — staging deploy is the fleet's call (Tier B)"
printf '%s' "$TIER_C" | grep -Eqi -- "deploy to PRODUCTION" \
  || fail "[placement] 'deploy to PRODUCTION' is not in the SSOT §8 Tier C bullet — production deploy is the owner's only gate (Tier C)"

echo "Tier concepts checked: $checks, Failures: $fails"
[ "$fails" -eq 0 ] && exit 0 || exit 1
