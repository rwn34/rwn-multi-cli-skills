#!/bin/bash
# check-landed-ssot.sh — verify that LANDED blobs (committed content, not the
# working tree) are consistent across the SSOT source and its replicas.
#
# Working-tree drift checks can be fooled when the working tree is itself stale
# or skip-worktree-hidden; this checker compares the actual blobs in the given
# ref (default HEAD).  For byte-copy replicas the source and destination blobs
# must be identical.  For preamble-carrying SKILL.md replicas the body below the
# SSOT marker must match the source blob.
#
# Usage:
#   bash .ai/tools/check-landed-ssot.sh [REF]
#
# Exit: 0 if all landed pairs are consistent; non-zero otherwise (fail closed).

set -u

: "${SYNC_MD:=.ai/sync.md}"
REF="${1:-HEAD}"

fail() { echo "check-landed-ssot: $*" >&2; exit 1; }

# Read the registry from the LANDED ref, not the working tree: a skip-worktree-stale
# on-disk .ai/sync.md must not shrink or skew the pair set we compare.
sync_blob="$(git ls-tree -r "$REF" -- "$SYNC_MD" | awk '{print $3}')"
[ -n "$sync_blob" ] || fail "registry $SYNC_MD not found in $REF"

# Parse the registry into SOURCE<TAB>DEST pairs (same contract as sync-replicas.sh).
pairs="$(git cat-file -p "$sync_blob" | awk -F'|' '
  /^\|/ {
    src = $2; dst = $3
    if (match(src, /`[^`]+`/)) {
      s = substr(src, RSTART + 1, RLENGTH - 2)
    } else { next }
    if (match(dst, /`[^`]+`/)) {
      d = substr(dst, RSTART + 1, RLENGTH - 2)
    } else {
      print "MALFORMED\t" s > "/dev/stderr"
      malformed = 1; next
    }
    print s "\t" d
  }
  END { if (malformed) exit 3 }
')" || fail "registry malformed: a source→destination row is missing its destination path"

[ -n "$pairs" ] || fail "registry parsed to zero mappings — refusing to run (fail closed)"

git rev-parse --verify --quiet "$REF^{commit}" >/dev/null \
  || fail "ref '$REF' does not resolve to a commit"

# LF-normalize stdin -> stdout (deterministic regardless of host).
normalize_lf() { tr -d '\r'; }

# Extract the body from a preamble-carrying SKILL.md replica: everything after
# the first `<!-- SSOT:` line and the single line immediately after it.  This is
# the exact inverse of sync-replicas.sh's extract_preamble().
extract_body() {
  awk '
    state == 1 {
      if ($0 == "") { state = 2; next }
      state = 2; next
    }
    /^<!-- SSOT:/ { state = 1; next }
    state == 2 { print }
  ' "$1"
}

errors=0
checked=0

while IFS="$(printf '\t')" read -r src dst; do
  [ -n "$src" ] && [ -n "$dst" ] || continue
  checked=$((checked + 1))

  src_blob="$(git ls-tree -r "$REF" -- "$src" | awk '{print $3}')"
  dst_blob="$(git ls-tree -r "$REF" -- "$dst" | awk '{print $3}')"

  if [ -z "$src_blob" ]; then
    echo "MISSING SOURCE: $src not found in $REF"
    errors=$((errors + 1))
    continue
  fi
  if [ -z "$dst_blob" ]; then
    echo "MISSING REPLICA: $dst not found in $REF"
    errors=$((errors + 1))
    continue
  fi

  case "$(basename "$dst")" in
    SKILL.md)
      tmp_src="$(mktemp)"; tmp_body="$(mktemp)"
      git cat-file -p "$src_blob" | normalize_lf > "$tmp_src"
      git cat-file -p "$dst_blob" | normalize_lf | extract_body - > "$tmp_body"
      if ! diff -q "$tmp_src" "$tmp_body" >/dev/null 2>&1; then
        echo "LANDED BODY MISMATCH: $src -> $dst (SKILL.md body does not match SSOT source)"
        errors=$((errors + 1))
      fi
      rm -f "$tmp_src" "$tmp_body"
      ;;
    *)
      if [ "$src_blob" != "$dst_blob" ]; then
        echo "LANDED BLOB MISMATCH: $src ($src_blob) -> $dst ($dst_blob)"
        errors=$((errors + 1))
      fi
      ;;
  esac
done <<EOF
$pairs
EOF

echo "Checked: $checked landed SSOT pairs, Mismatches: $errors"
[ "$errors" -eq 0 ]
