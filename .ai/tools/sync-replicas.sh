#!/bin/bash
# sync-replicas.sh — regenerate every CLI-native replica from its .ai/instructions
# SSOT source, per the registry in .ai/sync.md.
#
# This is the ONE generator AND the ONE drift authority (2026-07-13): it DETECTS
# drift (--check) AND repairs it (default mode). check-ssot-drift.sh is now a
# thin compatibility shim that execs this script's --check mode — a single
# implementation, so the generator and the checker can never disagree (that is
# the whole anti-drift property; see docs/architecture/0005 second amendment).
#
# Registry (.ai/sync.md) is the source→destination map. For each pair:
#   * basename(dest) == SKILL.md  -> preamble-preserving. Keep the existing
#     replica's preamble (frontmatter + provenance comments THROUGH the
#     `<!-- SSOT: ... -->` marker and the one blank line after it) and replace the
#     body below it with the SSOT source.
#   * everything else             -> byte copy of the SSOT source.
#
# Output is LF-normalized unconditionally (deterministic across OS). .gitattributes
# pins *.md to eol=lf so the committed bytes match.
#
# JUNCTION SAFETY (ADR-0004; the 2026-07-12/13 reverse-write incidents): in the
# worktree-per-CLI layout a worktree's .ai/ may be a directory JUNCTION to the
# primary checkout's live .ai/, and a naive write through any link lands OUTSIDE
# the tree it was meant for. Before regenerating IN PLACE this tool:
#   * refuses any registry destination under .ai/ outright — replicas are CLI
#     config, none may live in the coordination plane; and
#   * refuses when any existing ancestor of a write target is a symlink
#     ([ -L ]) or a Windows junction/reparse point (the same `cmd dir /a:l`
#     probe scripts/wt-bootstrap.sh's cmd_islink() uses).
# The guard runs BEFORE any write, so a refusal never leaves a half-regenerated
# tree. --check and --dest-root write only to their explicit sink, never the
# tree, and are not guarded.
#
# SKIP-WORKTREE SOURCE GUARD (ADR-0015 follow-up, 2026-07-17): the same worktree
# layout also sets skip-worktree on .ai/** sources so that git stops trusting
# the working-tree view.  A generator that reads such a source would regenerate
# replicas from the index's stale blob while the commit stat claims an update.
# The generator therefore checks `git ls-files -v <ssot>` for every source and
# aborts if the flag is 'S'.  Clear the bit with `git update-index
# --no-skip-worktree <path>` before regenerating.
#
# Usage:
#   bash .ai/tools/sync-replicas.sh                 # regenerate replicas in place
#   bash .ai/tools/sync-replicas.sh --check         # drift report; exit 1 on drift
#   bash .ai/tools/sync-replicas.sh --dest-root DIR # write under DIR/<dest> instead
#
# stdout: default/--dest-root — one `SOURCE<TAB>DEST` manifest line per generated
#         replica. --check — the drift report (contract inherited from
#         check-ssot-drift.sh; other callers depend on it):
#           DRIFT: <src> -> <dst> (N lines differ)   per drifted replica
#           MISSING: <path>                          per absent file
#           Checked: <N> replicas, Drift: <M>        final summary
# stderr: a human summary; on drift, the copy-pasteable fix.
# Exit: 0 on success; --check exits 0 iff Drift == 0. Non-zero (with a clear
# message) on any error — FAIL CLOSED.

set -u

# Derive the repo root from $0 by pure string manipulation. Do NOT use cd,
# git rev-parse --show-toplevel, or pwd -P: in the worktree-per-CLI layout
# .ai/ is a junction back to the primary checkout and those would resolve to
# the wrong tree. $0 is the path used to invoke this script; stripping the
# known suffix leaves the repo root.
ROOT="${0%.ai/tools/sync-replicas.sh}"
ROOT="${ROOT%/}"
[ -n "$ROOT" ] || ROOT="."

: "${SYNC_MD:=$ROOT/.ai/sync.md}"
DEST_ROOT="$ROOT"
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     CHECK=1; shift ;;
    --dest-root) DEST_ROOT="${2:-}"; [ -n "$DEST_ROOT" ] || { echo "sync-replicas.sh: --dest-root needs a value" >&2; exit 2; }; shift 2 ;;
    -h|--help)   sed -n '2,53p' "$0"; exit 0 ;;
    *)           echo "sync-replicas.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ "$CHECK" = 1 ] && [ "$DEST_ROOT" != "$ROOT" ]; then
  echo "sync-replicas.sh: --check writes to its own temp tree; do not combine with --dest-root" >&2
  exit 2
fi

fail() { echo "sync-replicas.sh: $*" >&2; exit 1; }

[ -r "$SYNC_MD" ] || fail "registry unreadable: $SYNC_MD (fail closed)"

# extract_preamble <replica> — emit exactly the lines that sit ABOVE the body in
# a preamble-carrying replica: everything through the first `<!-- SSOT:` line,
# plus the single blank line immediately after it (only if that next line is
# blank). This is the EXACT INVERSE of the body's replacement below — the two
# halves are described together on purpose so a change to one forces a change
# to the other.
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

# ---- junction / reverse-write guard (in-place regeneration only) -------------
# Probe helpers copied from scripts/wt-bootstrap.sh (is_windows / winpath /
# cmd_islink) — keep them in step with that file; it owns the junction model.

is_windows_host() {
  case "$(uname -s 2>/dev/null || echo "${OS:-}")" in
    *MINGW*|*MSYS*|*CYGWIN*|Windows_NT) return 0 ;;
    *) return 1 ;;
  esac
}

# Convert a Git-Bash POSIX path to a Windows path for cmd.exe.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1" | sed -e 's|^/\([a-zA-Z]\)/|\1:/|' -e 's|/|\\|g'
  fi
}

# Echo non-empty if the Windows dir at $1 is a junction/reparse point.
# dir /a:l lists ONLY reparse points; data lines look like
#   2026/07/13  19:05    <JUNCTION>     skills [C:\...\target]
# so we match the exact link-name column: an attribute tag, then the basename,
# then the bracketed target. A bare substring grep on the raw output (the
# wt-bootstrap.sh original) false-positives when the parent PATH contains the
# basename — probing ".claude/skills" inside a project dir literally named
# "...-skills" matches the "Directory of ..." header line.
cmd_islink() {
  link_name="$(basename "$1")"
  re_name="$(printf '%s' "$link_name" | sed 's/[][\\.^$*]/\\&/g')"
  cmd //c dir //a:l "$(dirname "$(winpath "$1")")" 2>/dev/null \
    | grep -iE "<[A-Z]+> +$re_name( \\[|$)" || true
}

# Refuse in-place regeneration that would write THROUGH a link or into the
# coordination plane. Runs BEFORE any write, so a refusal never leaves a
# half-regenerated tree. Ancestors that do not exist yet cannot be links —
# they are skipped here and created by generate().
guard_in_place_writes() {
  checked_dirs=" "
  while IFS="$(printf '\t')" read -r _gsrc gdst; do
    [ -n "$gdst" ] || continue
    case "$gdst" in
      .ai|.ai/*)
        fail "registry destination '$gdst' is under .ai/ — replicas never live in the coordination plane; refusing (reverse-write guard, ADR-0004)" ;;
    esac
    gdir="$(dirname "$gdst")"
    while [ "$gdir" != "." ] && [ -n "$gdir" ]; do
      case "$checked_dirs" in
        *" $gdir "*) ;;   # already vetted this ancestor for an earlier replica
        *)
          checked_dirs="$checked_dirs$gdir "
          if [ -L "$ROOT/$gdir" ]; then
            fail "write target ancestor '$gdir' is a symlink — refusing to regenerate through it (reverse-write guard, ADR-0004)"
          fi
          if is_windows_host && [ -d "$ROOT/$gdir" ] && [ -n "$(cmd_islink "$ROOT/$gdir")" ]; then
            fail "write target ancestor '$gdir' is a Windows junction/reparse point — refusing to regenerate through it (reverse-write guard, ADR-0004)"
          fi
          ;;
      esac
      gdir="$(dirname "$gdir")"
    done
  done <<EOF
$pairs
EOF
}

# Refuse to read SSOT sources that git has been told to ignore via
# skip-worktree.  In a bootstrapped worktree the reverse-write guard sets this
# bit on .ai/** sources; reading them would regenerate replicas from the index's
# stale view while the commit's stat claims an update.  Fail closed: the fix is
# to clear the bit on the source before trusting it.
guard_skip_worktree_sources() {
  while IFS="$(printf '\t')" read -r gsrc _gdst; do
    [ -n "$gsrc" ] || continue
    local lsout flag
    lsout="$(git -C "$ROOT" ls-files -v "$gsrc" 2>/dev/null)" \
      || fail "SSOT source '$gsrc': skip-worktree probe failed (git ls-files -v). Refusing to regenerate from an untrusted source (fail closed)."
    flag="$(printf '%s\n' "$lsout" | head -n1 | cut -c1)"
    case "$flag" in
      S|s)
        fail "SSOT source '$gsrc' has skip-worktree bit set (git ls-files -v shows '$flag'). The file git is ignoring is the one the generator would read, so regenerating now would launder stale source text into the replicas. Clear the bit before regenerating: git update-index --no-skip-worktree '$gsrc'"
        ;;
    esac
  done <<EOF
$pairs
EOF
}

# ---- the ONE generator -------------------------------------------------------
# generate <dest-root> — write every replica under <dest-root>/<dest> and print
# the `SOURCE<TAB>DEST` manifest (one line per replica) on stdout; a human
# summary goes to stderr.
generate() {
  gen_root="$1"
  guard_skip_worktree_sources
  count=0
  # IFS=tab so paths keep any spaces; read src + dst from each manifest line.
  while IFS="$(printf '\t')" read -r src dst; do
    [ -n "$src" ] && [ -n "$dst" ] || continue
    [ -f "$ROOT/$src" ] || fail "SSOT source missing: $src"

    out="$gen_root/$dst"
    mkdir -p "$(dirname "$out")" || fail "could not create $(dirname "$out")"

    case "$(basename "$dst")" in
      SKILL.md)
        # Preamble comes from the EXISTING committed replica (read at repo-relative
        # $dst even when writing elsewhere), body from the SSOT source. Buffer through
        # a temp file: when regenerating IN PLACE ($out == $dst) a direct `> "$out"`
        # would TRUNCATE the file before extract_preamble reads it, wiping the
        # preamble. Build the full content first, then move it into place.
        [ -f "$ROOT/$dst" ] || fail "preamble-carrying replica missing, cannot preserve preamble: $dst"
        buf="$(mktemp)" || fail "mktemp failed"
        { extract_preamble "$ROOT/$dst"; cat "$ROOT/$src"; } | normalize_lf > "$buf" || { rm -f "$buf"; fail "write failed: $out"; }
        mv "$buf" "$out" || { rm -f "$buf"; fail "write failed: $out"; }
        ;;
      *)
        # src (.ai/instructions/**) and out (a replica) are never the same path, so a
        # direct redirect is safe here.
        normalize_lf < "$ROOT/$src" > "$out" || fail "write failed: $out"
        ;;
    esac

    printf '%s\t%s\n' "$src" "$dst"   # manifest line
    count=$((count + 1))
  done <<EOF
$pairs
EOF

  echo "sync-replicas.sh: regenerated $count replicas into '$gen_root'" >&2
}

# ---- --check: regenerate into a temp tree and diff (the drift authority) ------
if [ "$CHECK" = 1 ]; then
  drift=0
  checked=0

  cfail() { echo "sync-replicas.sh --check: $*" >&2; echo "Checked: $checked replicas, Drift: 1"; exit 1; }

  # Regenerate every replica into a temp tree, capturing the manifest (SRC<TAB>DST
  # per line). The generator reads the registry + sources + committed preambles
  # from ROOT and writes fresh replicas under $tmp/<dst>.
  tmp="$(mktemp -d)" || cfail "mktemp failed"
  gen_err="$(mktemp)"
  manifest="$(generate "$tmp" 2>"$gen_err")" || {
    gen_err_text="$(cat "$gen_err")"
    rm -f "$gen_err"; rm -rf "$tmp"
    if [ -n "$gen_err_text" ]; then
      { echo "sync-replicas.sh --check: generation failed:"; echo "$gen_err_text"; } >&2
    fi
    cfail "generation failed (fail closed)"
  }
  rm -f "$gen_err"

  while IFS="$(printf '\t')" read -r src dst; do
    [ -n "$src" ] && [ -n "$dst" ] || continue
    checked=$((checked + 1))

    if [ ! -f "$ROOT/$src" ]; then
      echo "MISSING: $src"
      drift=$((drift + 1))
      continue
    fi
    if [ ! -f "$ROOT/$dst" ]; then
      echo "MISSING: $dst"
      drift=$((drift + 1))
      continue
    fi
    if [ ! -f "$tmp/$dst" ]; then
      echo "MISSING: $tmp/$dst (generator produced no output for $dst)"
      drift=$((drift + 1))
      continue
    fi

    n=$(diff "$ROOT/$dst" "$tmp/$dst" | grep -c '^[<>]' || true)
    if [ "$n" -ne 0 ]; then
      echo "DRIFT: $src -> $dst ($n lines differ)"
      drift=$((drift + 1))
    fi
  done <<EOF
$manifest
EOF

  rm -rf "$tmp"

  echo "Checked: $checked replicas, Drift: $drift"
  if [ "$drift" -ne 0 ]; then
    {
      echo
      echo "Fix: regenerate the replicas and commit them together with the SSOT change:"
      echo
      echo "  bash .ai/tools/sync-replicas.sh"
      echo
    } >&2
    exit 1
  fi
  exit 0
fi

# ---- default: regenerate ------------------------------------------------------
# In-place regeneration (DEST_ROOT == ROOT) is the mode that can reverse-write
# through a junction — guard it before touching anything. An explicit
# --dest-root is an output sink chosen by the caller (a mktemp dir in every
# in-repo caller), so it is not guarded.
if [ "$DEST_ROOT" = "$ROOT" ]; then
  guard_in_place_writes
fi

generate "$DEST_ROOT"
