#!/bin/bash
# check-ssot-drift.sh — verify CLI-native replicas match .ai/instructions/ sources.
# Exit 0 if all synced, 1 if any drift. Run from repo root.
#
# HOW IT WORKS (ADR-0005 second amendment, 2026-07-12): this checker does NOT
# re-implement the source→replica transformation. It invokes the ONE generator,
# .ai/tools/sync-replicas.sh, into a throwaway dest-root and diffs the committed
# replicas against that fresh output. Same code for generate + check => the two
# can never disagree, which is the whole point. The generator owns the registry
# parse (.ai/sync.md), the preamble rule, and LF normalization; the checker only
# diffs and tallies.
#
# Output contract (unchanged, other callers depend on it):
#   DRIFT: <src> -> <dst> (N lines differ)   per drifted replica
#   MISSING: <path>                          per absent file
#   Checked: <N> replicas, Drift: <M>        final summary
# Exit 0 iff Drift == 0.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GEN="$HERE/sync-replicas.sh"

drift=0
checked=0

fail() { echo "check-ssot-drift: $*" >&2; echo "Checked: $checked replicas, Drift: 1"; exit 1; }

[ -r "$GEN" ] || fail "generator missing: $GEN"

# Regenerate every replica into a temp tree, capturing the manifest (SRC<TAB>DST
# per line). The generator reads the registry + sources + committed preambles from
# the CWD (repo root) and writes fresh replicas under $tmp/<dst>.
tmp="$(mktemp -d)" || fail "mktemp failed"
manifest="$(bash "$GEN" --dest-root "$tmp" 2>/dev/null)" || { rm -rf "$tmp"; fail "generator failed (fail closed)"; }

while IFS="$(printf '\t')" read -r src dst; do
  [ -n "$src" ] && [ -n "$dst" ] || continue
  checked=$((checked + 1))

  if [ ! -f "$src" ]; then
    echo "MISSING: $src"
    drift=$((drift + 1))
    continue
  fi
  if [ ! -f "$dst" ]; then
    echo "MISSING: $dst"
    drift=$((drift + 1))
    continue
  fi
  if [ ! -f "$tmp/$dst" ]; then
    echo "MISSING: $tmp/$dst (generator produced no output for $dst)"
    drift=$((drift + 1))
    continue
  fi

  n=$(diff "$dst" "$tmp/$dst" | grep -c '^[<>]' || true)
  if [ "$n" -ne 0 ]; then
    echo "DRIFT: $src -> $dst ($n lines differ)"
    drift=$((drift + 1))
  fi
done <<EOF
$manifest
EOF

rm -rf "$tmp"

echo "Checked: $checked replicas, Drift: $drift"
[ "$drift" -eq 0 ] && exit 0 || exit 1
