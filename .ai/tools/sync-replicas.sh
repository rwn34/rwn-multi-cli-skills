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
# Usage:
#   bash .ai/tools/sync-replicas.sh                 # regenerate replicas in place
#   bash .ai/tools/sync-replicas.sh --dest-root DIR # write under DIR/<dest> instead
#
# stdout: one `SOURCE<TAB>DEST` line per generated replica (the manifest that
#         check-ssot-drift.sh consumes). stderr: a human summary.
# Exit: 0 on success; non-zero (with a clear message) on any error — FAIL CLOSED.

set -u

: "${SYNC_MD:=.ai/sync.md}"
DEST_ROOT="."

while [ $# -gt 0 ]; do
  case "$1" in
    --dest-root) DEST_ROOT="${2:-}"; [ -n "$DEST_ROOT" ] || { echo "sync-replicas.sh: --dest-root needs a value" >&2; exit 2; }; shift 2 ;;
    -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
    *)           echo "sync-replicas.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

fail() { echo "sync-replicas.sh: $*" >&2; exit 1; }

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
  [ -f "$src" ] || fail "SSOT source missing: $src"

  out="$DEST_ROOT/$dst"
  mkdir -p "$(dirname "$out")" || fail "could not create $(dirname "$out")"

  case "$(basename "$dst")" in
    SKILL.md)
      # Preamble comes from the EXISTING committed replica (read at repo-relative
      # $dst even when writing elsewhere), body from the SSOT source. Buffer through
      # a temp file: when regenerating IN PLACE ($out == $dst) a direct `> "$out"`
      # would TRUNCATE the file before extract_preamble reads it, wiping the
      # preamble. Build the full content first, then move it into place.
      [ -f "$dst" ] || fail "preamble-carrying replica missing, cannot preserve preamble: $dst"
      buf="$(mktemp)" || fail "mktemp failed"
      { extract_preamble "$dst"; cat "$src"; } | normalize_lf > "$buf" || { rm -f "$buf"; fail "write failed: $out"; }
      mv "$buf" "$out" || { rm -f "$buf"; fail "write failed: $out"; }
      ;;
    *)
      # src (.ai/instructions/**) and out (a replica) are never the same path, so a
      # direct redirect is safe here.
      normalize_lf < "$src" > "$out" || fail "write failed: $out"
      ;;
  esac

  printf '%s\t%s\n' "$src" "$dst"   # manifest line for check-ssot-drift.sh
  count=$((count + 1))
done <<EOF
$pairs
EOF

echo "sync-replicas.sh: regenerated $count replicas into '$DEST_ROOT'" >&2
exit 0
