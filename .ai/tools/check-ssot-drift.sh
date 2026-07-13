#!/bin/bash
# check-ssot-drift.sh — verify CLI-native replicas match .ai/instructions/ sources.
# Exit 0 if all synced, 1 if any drift. Callable from anywhere — see below.
#
# HOW IT WORKS (ADR-0005 second amendment, 2026-07-12): this checker does NOT
# re-implement the source→replica transformation. It invokes the ONE generator,
# .ai/tools/sync-replicas.sh, into a throwaway dest-root and diffs the committed
# replicas against that fresh output. Same code for generate + check => the two
# can never disagree, which is the whole point. The generator owns the registry
# parse (.ai/sync.md), the preamble rule, and LF normalization; the checker only
# diffs and tallies.
#
# CWD-INDEPENDENCE (2026-07-13, drift-checker-cwd-false-pass fix): $ROOT is
# resolved by PURE STRING manipulation on $0 (strip the trailing "/.ai/tools"
# two components) — deliberately WITHOUT `cd` or `git rev-parse` run from this
# script's own directory. That distinction matters: in the framework's
# worktree-per-CLI layout (ADR-0004), each worktree's `.ai/` is a directory
# JUNCTION to the ONE canonical `.ai/` in the primary checkout. `cd`-ing into
# ".ai/tools" and asking git (or `pwd -P`) for the real path resolves the
# junction and lands back in the PRIMARY checkout — not the worktree this
# script was invoked from. That was the actual defect: an earlier fix attempt
# using `cd "$HERE" && git rev-parse --show-toplevel` silently reproduced the
# exact false-pass this script exists to catch, because it still measured the
# primary checkout whenever reached via the junction. Pure path-string
# arithmetic never touches the filesystem, so a symlink/junction in the middle
# of the path can't redirect it. Every committed replica path in the diff loop
# is read from $ROOT/<path> — never a bare CWD-relative path.
#
# Previously this script diffed "$dst" (relative to CWD) against "$tmp/$dst"
# (the fresh regen), so invoking it by absolute path from a DIFFERENT
# repo/worktree silently diffed against THAT OTHER repo's replicas — a false
# "Drift: 0" that never looked at the tree the caller actually cared about.
# Both this checker and the generator it calls now derive $ROOT the identical
# way, so there is exactly one resolution rule, not two. See
# .ai/handoffs/to-kiro/done/202607122030-drift-checker-cwd-false-pass.md.
#
# Output contract (unchanged, other callers depend on it):
#   DRIFT: <src> -> <dst> (N lines differ)   per drifted replica
#   MISSING: <path>                          per absent file
#   Checked: <N> replicas, Drift: <M>        final summary
# Exit 0 iff Drift == 0.

set -u

# Resolve $0 to an absolute path WITHOUT touching the filesystem (string-only —
# no `cd`, no symlink resolution).
case "$0" in
  /*) _self="$0" ;;
  *)  _self="$PWD/$0" ;;
esac
HERE="$(dirname "$_self")"
GEN="$HERE/sync-replicas.sh"

drift=0
checked=0

fail() { echo "check-ssot-drift: $*" >&2; echo "Checked: $checked replicas, Drift: 1"; exit 1; }

[ -r "$GEN" ] || fail "generator missing: $GEN"

# $ROOT: same lexical derivation the generator uses (strip "/.ai/tools" from
# $0's own path) — the checker's notion of "the repo" can never disagree with
# the generator's, and neither ever resolves the .ai junction.
ROOT="$(dirname "$(dirname "$HERE")")"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || fail "could not resolve repo root from script path '$0' (fail closed)"

# Regenerate every replica into a temp tree, capturing the manifest (SRC<TAB>DST
# per line, ROOT-relative). The generator resolves the registry + sources +
# committed preambles against $ROOT (never CWD) and writes fresh replicas under
# $tmp/<dst>.
tmp="$(mktemp -d)" || fail "mktemp failed"
manifest="$(bash "$GEN" --dest-root "$tmp" 2>/dev/null)" || { rm -rf "$tmp"; fail "generator failed (fail closed)"; }

while IFS="$(printf '\t')" read -r src dst; do
  [ -n "$src" ] && [ -n "$dst" ] || continue
  checked=$((checked + 1))

  root_src="$ROOT/$src"
  root_dst="$ROOT/$dst"

  if [ ! -f "$root_src" ]; then
    echo "MISSING: $root_src"
    drift=$((drift + 1))
    continue
  fi
  if [ ! -f "$root_dst" ]; then
    echo "MISSING: $root_dst"
    drift=$((drift + 1))
    continue
  fi
  if [ ! -f "$tmp/$dst" ]; then
    echo "MISSING: $tmp/$dst (generator produced no output for $dst)"
    drift=$((drift + 1))
    continue
  fi

  n=$(diff "$root_dst" "$tmp/$dst" | grep -c '^[<>]' || true)
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
