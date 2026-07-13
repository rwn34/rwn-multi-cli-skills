#!/bin/bash
# reverse-write-detector.sh — detect a git op in a linked worktree writing
# THROUGH the .ai/ directory junction (ADR-0004) and reverting the primary
# checkout's live coordination-plane files to a stale, pre-merge blob.
#
# WHY THIS EXISTS (per .ai/handoffs/to-kiro/done/202607130150-junction-
# reverse-write-guard.md): on 2026-07-13 between ~06:15 and ~07:11,
# .ai/tools/dispatch-handoffs.sh in the PRIMARY checkout was silently
# rewritten to a pre-PR#70 blob while PR #70 was already merged to master.
# Reproduced in a sandbox (see the handoff's Step 1 report): a git command
# that resolves the worktree's *own* index/HEAD against on-disk content
# (`git checkout -- <path>`, `git reset --hard`, `git restore --worktree`,
# `git stash`/`stash pop`, `git clean`) sees the junctioned .ai/ content —
# which is actually the PRIMARY's live state, reached through the junction —
# as if it were the EXECUTOR'S OWN uncommitted edit. "Discarding" that
# phantom edit writes the executor's stale committed blob back through the
# junction onto the primary's real file. This is the opposite of what the
# handoff's own hypothesis named (checkout/merge/rebase onto `master`
# directly) — those are in fact BLOCKED by git's own "branch already
# checked out elsewhere" and "local changes would be overwritten" guards.
# The real hole is that the second guard's textbook resolution — discard the
# apparent local edit — IS the clobber.
#
# WHAT THIS SCRIPT DOES: splits .ai/** into two classes (is_churn() below)
# and, for every tracked file under a stable path (everything NOT churn),
# compares the PRIMARY checkout's on-disk blob hash against three things:
#   1. HEAD's committed blob for that path         -> match = clean, skip
#   2. Any EARLIER commit's blob for that path      -> match = REVERSE-WRITE
#   3. Neither                                      -> a genuine novel edit,
#                                                       not flagged (that's a
#                                                       real local change in
#                                                       progress, indistin-
#                                                       guishable from normal
#                                                       work-in-progress)
#
# WHY CONTENT, NOT `git status` DIRTY/CLEAN (fixed 2026-07-13, per
# .ai/handoffs/to-kiro/open/202607130712-fix-reverse-write-detector-
# discriminator.md): the first version of this script skipped every path
# `git status --porcelain` listed as modified, on the theory that a dirty
# path is "a real local edit in progress, not a reverse-write". That
# reasoning is backwards for exactly the incident this script exists to
# catch: the clobber writes a stale COMMITTED blob into the primary's
# working tree through the junction, and the primary's index does not know
# about it — so `git status` reports that path as modified. Verified
# empirically in a sandbox that reproduces the real mechanism (a git
# worktree junctioned to primary's .ai, branch behind master, `git checkout
# -- .ai` from the worktree): the OLD dirty-skip version printed
# "Reverse-writes: 0" on a live clobber of .ai/tools/dispatch-handoffs.sh.
# The content-based check above uses the real asymmetry — a reverse-write's
# content is not novel, it is byte-identical to something the repo already
# committed and then moved past — and needs no dirty/clean guess at all.
#
# Fail-open, like check-ssot-drift.sh / sync-replicas.sh: a detector that can
# itself take the fleet down is worse than no detector. Never blocks; always
# exits 0. This script is CALLABLE STANDALONE and wired warn-only into
# scripts/git-hooks/post-merge and post-checkout, guarded to run only in the
# PRIMARY checkout (never a linked worktree, and never in CI — a fresh CI
# clone has no junction and no primary/worktree split, so the failure mode
# this script detects cannot occur there; wiring it into CI would also
# false-positive on any PR that legitimately edits a stable .ai/** path,
# since "differs from origin/master, not the tip of this branch's history"
# is exactly what a normal in-flight edit looks like from CI's vantage
# point). See docs/specs/junction-reverse-write-guard.md.
#
# CWD-INDEPENDENCE: $ROOT is resolved by pure string manipulation on $0 —
# strip the trailing "/.ai/tools" two path components — exactly the fix
# .ai/tools/check-ssot-drift.sh and .ai/tools/sync-replicas.sh apply, for the
# identical reason: `cd`-ing into ".ai/tools" and asking git/pwd for the
# physical path resolves the .ai junction and silently measures the PRIMARY
# checkout even when this script was invoked from a worktree. No `cd`, no
# `git rev-parse --show-toplevel` from inside this script's own directory.
#
# Usage:
#   bash .ai/tools/reverse-write-detector.sh [--base <ref>] [--history-depth N]
#     --base <ref>          Compare against this ref's HEAD blob instead of
#                            origin/master (default: origin/master, falling
#                            back to master if no "origin" remote exists —
#                            e.g. a bare sandbox repo).
#     --history-depth N     How many commits of a path's own history to scan
#                            for a matching stale blob (default: 20). Bounds
#                            the per-path cost; a reverse-write is virtually
#                            always the immediately-preceding version, not
#                            something from 50 commits ago.
#
# Output contract:
#   REVERSE-WRITE: <path> (matches blob <sha> from an earlier commit <sha>,
#     not HEAD's <sha> — see 'git log -- <path>')
#   Checked: <N> stable paths, Reverse-writes: <M>
# Exit: ALWAYS 0 (fail-open). Non-zero only on a genuine internal error
#   (unreadable script, unresolvable root) — same fail-closed-on-setup /
#   fail-open-on-check split as the other .ai/tools scripts.

set -u

# ---- resolve $ROOT without ever touching a symlink/junction in the path ----
# $0 arrives in one of three shapes depending on caller:
#   - POSIX absolute:        /home/x/repo/.ai/tools/reverse-write-detector.sh
#   - Windows drive-letter:  C:/Users/x/repo/.ai/tools/reverse-write-detector.sh
#     (this is what `git rev-parse --show-toplevel`-derived paths look like on
#     Git-Bash/MSYS — verified empirically: the git-hooks callers build
#     "$REPO_ROOT/.ai/tools/reverse-write-detector.sh" from that exact output,
#     so this shape is not a rare edge case here, it is the common one)
#   - relative:              .ai/tools/reverse-write-detector.sh (bash .ai/tools/…)
# A bare `/*` case pattern only recognizes the first shape and silently
# mis-resolves the second (prepends $PWD, producing a doubly-rooted, invalid
# path) — caught empirically while wiring this script into scripts/git-hooks/
# post-merge and post-checkout, both of which pass the drive-letter shape.
case "$0" in
  /*|[A-Za-z]:/*|[A-Za-z]:\\*) _self="$0" ;;
  *)                          _self="$PWD/$0" ;;
esac
HERE="$(dirname "$_self")"
ROOT="$(dirname "$(dirname "$HERE")")"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "reverse-write-detector: could not resolve repo root from script path '$0' (fail closed on setup)" >&2
  echo "Checked: 0 stable paths, Reverse-writes: 0"
  exit 1
fi

BASE_REF=""
HISTORY_DEPTH=20
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --history-depth) HISTORY_DEPTH="${2:-20}"; shift 2 ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "reverse-write-detector: unknown argument '$1' (ignored)" >&2; shift ;;
  esac
done

cd "$ROOT" 2>/dev/null || {
  echo "reverse-write-detector: could not enter resolved root '$ROOT' (fail closed on setup)" >&2
  echo "Checked: 0 stable paths, Reverse-writes: 0"
  exit 1
}

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "reverse-write-detector: '$ROOT' is not inside a git working tree (fail-open: nothing to check)" >&2
  echo "Checked: 0 stable paths, Reverse-writes: 0"
  exit 0
}

# ---- resolve the base ref to diff against ----
if [ -z "$BASE_REF" ]; then
  if git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    BASE_REF="origin/master"
  elif git rev-parse --verify --quiet master >/dev/null 2>&1; then
    BASE_REF="master"
  else
    echo "reverse-write-detector: no origin/master or master ref found (fail-open: nothing to check)" >&2
    echo "Checked: 0 stable paths, Reverse-writes: 0"
    exit 0
  fi
fi
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1; then
  echo "reverse-write-detector: base ref '$BASE_REF' does not resolve (fail-open: nothing to check)" >&2
  echo "Checked: 0 stable paths, Reverse-writes: 0"
  exit 0
fi

# Resolve BASE_REF to its commit sha ONCE — it is compared against every
# scanned commit in the per-path history walk below (up to HISTORY_DEPTH
# times per stable path). Re-running `git rev-parse "$BASE_REF"` inside that
# inner loop is a redundant fork per iteration; hoisting it here is a no-op
# behaviorally (BASE_REF does not move mid-scan) and removes up to
# HISTORY_DEPTH wasted forks per path.
base_sha="$(git rev-parse "$BASE_REF" 2>/dev/null)"

# ---- the churn/stable split (ADR-0010's own classification, reused verbatim) ----
# CHURN: legitimately differs from any historical commit at all times. Never
# checked — a churn file "differing from origin/master" is normal operation,
# not a signature of anything.
is_churn() {
  case "$1" in
    .ai/activity/log.md) return 0 ;;
    .ai/activity/entries/*) return 0 ;;
    .ai/handoffs/*) return 0 ;;
    .ai/reports/*) return 0 ;;
    .ai/*/archive/*) return 0 ;;
    .ai/.claim-*.json) return 0 ;;
  esac
  return 1
}

checked=0
hits=0

# List every FILE git currently tracks under .ai/ at the base ref, WITH its
# blob sha in the same call — "<mode> blob <sha>\t<path>" per line. This is
# the "should exist, should match" universe (a path that exists on disk but
# was never committed to origin/master is a different problem, out of scope).
#
# LANDMINE, discovered while building this detector (do not "simplify" this
# back to `git show "$BASE_REF:$path"` per file): Git for Windows' MSYS layer
# path-converts an argument shaped like "<ref>/<segment>:<path/with/slashes>"
# — it saw the FIRST "/" after the ref name as a directory separator and
# mangled "origin/master:.ai/tools/x.sh" into the literal argument
# "origin\master;.ai\tools\x.sh", which git then rejected as an ambiguous
# revision. `git ls-tree` (no colon-joined ref:path token) is immune, and
# `git cat-file`/`git hash-object` below take bare object ids or file paths
# with no ref in the same argument at all — nothing left for MSYS to "fix".
tracked_raw="$(git ls-tree -r "$BASE_REF" -- .ai 2>/dev/null)"
if [ -z "$tracked_raw" ]; then
  echo "reverse-write-detector: '$BASE_REF' has no tracked .ai/ paths (fail-open: nothing to check)" >&2
  echo "Checked: 0 stable paths, Reverse-writes: 0"
  exit 0
fi

while IFS="$(printf '\t')" read -r meta path; do
  [ -n "$path" ] || continue
  # meta = "<mode> blob <sha>" (ls-tree -r never emits tree/commit rows for a
  # -r listing under a path filter, but guard anyway — fail-open, skip).
  head_blob="$(printf '%s' "$meta" | awk '{print $3}')"
  case "$head_blob" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) : ;;
    *) continue ;;
  esac

  if is_churn "$path"; then
    continue
  fi
  checked=$((checked + 1))

  if [ ! -f "$ROOT/$path" ]; then
    # Missing entirely is its own, worse signal, but it is not THIS detector's
    # job (a missing file is caught by check-ssot-drift.sh's MISSING: line
    # for replica paths, or is simply absent — no reverse-write to report).
    continue
  fi

  # On-disk blob hash — content-addressed, no `git status` involved. This is
  # what git would assign if this exact content were staged right now.
  disk_blob="$(git hash-object "$ROOT/$path" 2>/dev/null)" || continue

  if [ "$disk_blob" = "$head_blob" ]; then
    # On-disk content matches the base ref's committed blob exactly — clean,
    # regardless of what `git status` says (a path can be listed as
    # "modified" by line-ending normalization or by being freshly staged
    # with identical content; content-equality is the ground truth here).
    continue
  fi

  # Disk differs from HEAD's blob for this path. Is it a REVERSE-WRITE (disk
  # matches some EARLIER commit's blob for this same path) or a genuine novel
  # edit (disk matches no historical blob at all)?
  history_shas="$(git log --format=%H -n "$HISTORY_DEPTH" -- "$path" 2>/dev/null)"
  [ -n "$history_shas" ] || continue

  found_at=""
  found_blob=""
  while IFS= read -r commit_sha; do
    [ -n "$commit_sha" ] || continue
    [ "$commit_sha" = "$base_sha" ] && continue
    hist_blob="$(git ls-tree "$commit_sha" -- "$path" 2>/dev/null | awk '{print $3}')"
    [ -n "$hist_blob" ] || continue
    [ "$hist_blob" = "$head_blob" ] && continue
    if [ "$hist_blob" = "$disk_blob" ]; then
      found_at="$commit_sha"
      found_blob="$hist_blob"
      break
    fi
  done <<HIST
$history_shas
HIST

  if [ -n "$found_at" ]; then
    short_head="${head_blob:0:12}"
    short_disk="${disk_blob:0:12}"
    short_commit="${found_at:0:12}"
    echo "REVERSE-WRITE: $path (on-disk blob $short_disk matches earlier commit $short_commit, not $BASE_REF's current blob $short_head — see 'git log -- $path')"
    hits=$((hits + 1))
  fi
  # else: disk differs from HEAD and matches no scanned historical blob —
  # a genuine novel local edit in progress. Not flagged (indistinguishable
  # from ordinary work-in-progress; see header rationale).
done <<EOF
$tracked_raw
EOF

echo "Checked: $checked stable paths, Reverse-writes: $hits"
exit 0
