#!/bin/bash
# sync-replicas.sh — regenerate every CLI-native replica from its .ai/instructions
# SSOT source, per the registry in .ai/sync.md.
#
# This is the ONE generator. check-ssot-drift.sh does NOT re-implement the
# transformation — it calls THIS script into a temp dest-root and diffs. Same
# code => the checker and the generator can never disagree (that is the whole
# anti-drift property; see docs/architecture/0005 second amendment).
#
# Registry (.ai/sync.md) is the source→destination map. For each pair:
#   * basename(dest) == SKILL.md  -> preamble-preserving. Keep the existing
#     replica's preamble (frontmatter + provenance comments THROUGH the
#     `<!-- SSOT: ... -->` marker and the one blank line after it) and replace the
#     body below it with the SSOT source. This is the EXACT INVERSE of
#     check-ssot-drift.sh's strip_preamble — the two are described together on
#     purpose so a change to one forces a change to the other.
#   * everything else            -> byte copy of the SSOT source.
#
# Output is LF-normalized unconditionally (deterministic across OS). .gitattributes
# pins *.md to eol=lf so the committed bytes match.
#
# CWD-INDEPENDENCE (2026-07-13, drift-checker-cwd-false-pass fix): all paths
# ($SYNC_MD, every source, every destination) are resolved against $ROOT — the
# directory two levels above THIS SCRIPT FILE (i.e. ".ai/tools/<this>.sh" ->
# strip "/.ai/tools") — never against the caller's current directory.
#
# Root is derived by PURE STRING manipulation on $0, deliberately WITHOUT `cd`
# or any operation that resolves symlinks (no `cd ... && pwd`, no `pwd -P`, no
# `git rev-parse --show-toplevel` run FROM inside this script's own directory).
# That distinction is load-bearing: in the framework's worktree-per-CLI layout
# (ADR-0004), each worktree's `.ai/` is a directory JUNCTION to the ONE
# canonical `.ai/` in the primary checkout. `cd`-ing into ".ai/tools" and then
# asking for the physical path (or asking git for the toplevel FROM there)
# resolves the junction and lands you back in the PRIMARY checkout — not the
# worktree the script was actually invoked from. That was the second half of
# the bug this fix closes: the first (obvious) fix attempt, `cd
# "$(dirname "$0")" && git rev-parse --show-toplevel`, silently reproduces the
# exact false-pass this script exists to prevent, because it still ends up
# measuring the primary checkout whenever it's invoked via the junction. Pure
# string arithmetic on $0's path never touches the filesystem, so it can't be
# fooled by a symlink/junction in the middle of the path.
#
# Previously the script trusted CWD, so invoking it (or check-ssot-drift.sh,
# which calls it) by absolute path from a different directory/worktree silently
# regenerated and diffed against WHATEVER REPO the CWD happened to be — a false
# pass hiding genuine drift in the caller's own tree. See
# .ai/handoffs/to-kiro/done/202607122030-drift-checker-cwd-false-pass.md.
#
# Usage:
#   bash .ai/tools/sync-replicas.sh                 # regenerate replicas in place
#   bash .ai/tools/sync-replicas.sh --dest-root DIR # write under DIR/<dest> instead
#                                                    # (relative DIR is resolved
#                                                    # against the CALLER's CWD,
#                                                    # not $ROOT — it's an output
#                                                    # sink, not a repo path)
#
# stdout: one `SOURCE<TAB>DEST` line per generated replica (the manifest that
#         check-ssot-drift.sh consumes) — SOURCE/DEST are $ROOT-relative, exactly
#         as before. stderr: a human summary.
# Exit: 0 on success; non-zero (with a clear message) on any error — FAIL CLOSED.

set -u

fail() { echo "sync-replicas.sh: $*" >&2; exit 1; }

# Resolve $0 to an absolute path WITHOUT touching the filesystem (string-only —
# no `cd`, no symlink resolution). $0 is either already absolute, or relative
# to $PWD (bash never invokes a script via a bare basename lookup on PATH for
# `bash <path>` / `./<path>` forms, both of which are how this tool is called).
case "$0" in
  /*) _self="$0" ;;
  *)  _self="$PWD/$0" ;;
esac
HERE="$(dirname "$_self")"
# $HERE is always "<root>/.ai/tools" by construction (this file lives there) —
# strip the two trailing components lexically. No `cd`, no `git`, no symlink
# ever enters the resolution, so a junctioned .ai/ cannot redirect it.
ROOT="$(dirname "$(dirname "$HERE")")"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || fail "could not resolve repo root from script path '$0' (fail closed)"

: "${SYNC_MD:="$ROOT/.ai/sync.md"}"
DEST_ROOT="$ROOT"

while [ $# -gt 0 ]; do
  case "$1" in
    --dest-root) DEST_ROOT="${2:-}"; [ -n "$DEST_ROOT" ] || { echo "sync-replicas.sh: --dest-root needs a value" >&2; exit 2; }; shift 2 ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *)           echo "sync-replicas.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

[ -r "$SYNC_MD" ] || fail "registry unreadable: $SYNC_MD (fail closed)"

# extract_preamble <replica> — emit exactly the lines strip_preamble() in
# check-ssot-drift.sh REMOVES: everything through the first `<!-- SSOT:` line, plus
# the single blank line immediately after it (only if that next line is blank).
# Keep this in lockstep with strip_preamble — they are inverse halves of one rule.
extract_preamble() {
  awk '
    done_flag { next }
    state == 1 {                 # the line immediately after the SSOT marker
      if ($0 == "") print ""     # include the one blank separator, nothing more
      done_flag = 1
      next
    }
    { print }                    # part of the preamble — emit it
    /^<!-- SSOT:/ { state = 1 }  # marker printed above; body starts after this
  ' "$1"
}

# LF-normalize stdin -> stdout (strip CR; deterministic regardless of host).
normalize_lf() { tr -d '\r'; }

# Parse the registry into `SOURCE<TAB>DEST` pairs. A table row is `| col1 | col2 |`.
# We treat a row as a mapping iff col1 holds a backtick-quoted path; if it does,
# col2 MUST also hold one or the registry is malformed -> fail closed. The header
# ("Source"/"Destination") and separator (`---`) rows have no backticks and are
# skipped. The destination cell may carry trailing prose in parens; we take the
# FIRST backtick-quoted token as the path.
pairs="$(awk -F'|' '
  /^\|/ {
    src = $2; dst = $3
    if (match(src, /`[^`]+`/)) {
      s = substr(src, RSTART + 1, RLENGTH - 2)
    } else { next }                              # col1 has no path -> not a mapping row
    if (match(dst, /`[^`]+`/)) {
      d = substr(dst, RSTART + 1, RLENGTH - 2)
    } else {
      print "MALFORMED\t" s > "/dev/stderr"      # source path but no dest -> malformed
      malformed = 1; next
    }
    print s "\t" d
  }
  END { if (malformed) exit 3 }
' "$SYNC_MD")" || fail "registry malformed: a source→destination row is missing its destination path"

[ -n "$pairs" ] || fail "registry parsed to zero mappings — refusing to run (fail closed)"

count=0
# IFS=tab so paths keep any spaces; read src + dst from each manifest line.
while IFS="$(printf '\t')" read -r src dst; do
  [ -n "$src" ] && [ -n "$dst" ] || continue

  # $src/$dst from the registry are ROOT-relative strings (e.g.
  # ".ai/instructions/...", ".kiro/steering/..."). Resolve them against $ROOT —
  # never against CWD — so the generator is correct no matter where it is
  # invoked from. $out (the write target) honors --dest-root, which is an
  # output sink and intentionally CWD-relative when given as a relative path.
  root_src="$ROOT/$src"
  root_dst="$ROOT/$dst"
  [ -f "$root_src" ] || fail "SSOT source missing: $root_src"

  out="$DEST_ROOT/$dst"
  mkdir -p "$(dirname "$out")" || fail "could not create $(dirname "$out")"

  case "$(basename "$dst")" in
    SKILL.md)
      # Preamble comes from the EXISTING COMMITTED replica at $ROOT/$dst (never
      # CWD-relative $dst, and never $out — when regenerating in place $out ==
      # $root_dst, but when writing to --dest-root the preamble must still come
      # from the real repo, not from a possibly-absent path under DEST_ROOT).
      # Body comes from the SSOT source. Buffer through a temp file: when
      # regenerating IN PLACE ($out == $root_dst) a direct `> "$out"` would
      # TRUNCATE the file before extract_preamble reads it, wiping the preamble.
      [ -f "$root_dst" ] || fail "preamble-carrying replica missing, cannot preserve preamble: $root_dst"
      buf="$(mktemp)" || fail "mktemp failed"
      { extract_preamble "$root_dst"; cat "$root_src"; } | normalize_lf > "$buf" || { rm -f "$buf"; fail "write failed: $out"; }
      mv "$buf" "$out" || { rm -f "$buf"; fail "write failed: $out"; }
      ;;
    *)
      # root_src (.ai/instructions/**) and out (a replica) are never the same
      # path, so a direct redirect is safe here.
      normalize_lf < "$root_src" > "$out" || fail "write failed: $out"
      ;;
  esac

  printf '%s\t%s\n' "$src" "$dst"   # manifest line for check-ssot-drift.sh (ROOT-relative, unchanged format)
  count=$((count + 1))
done <<EOF
$pairs
EOF

echo "sync-replicas.sh: regenerated $count replicas from '$ROOT' into '$DEST_ROOT'" >&2
exit 0
