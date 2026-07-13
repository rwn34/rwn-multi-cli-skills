#!/usr/bin/env bash
# wt-bootstrap.sh — idempotently set up executor git worktrees for a project,
# implementing the "code plane / coordination plane" topology from
# .ai/research/worktree-multi-project-topology.md (sections 3, 4, 8).
#
# Each executor gets an independent working tree at a SIBLING location
# (<parent>/.wt/<project>/<executor>/) on branch exec/<executor>/init, and its
# .ai/ is replaced with a junction/symlink to the canonical <project>/.ai/ so
# all CLIs share one coordination plane (one log, one handoff queue).
#
# Usage: bash scripts/wt-bootstrap.sh <project-dir> [executor...]
#        (default executors: kiro kimi opencode)
#
# Sourcing this file does nothing — worktrees are created only when invoked.
#
# Requirements: bash, git. Git Bash (Windows) + Linux/macOS compatible.
#   - Windows: directory junctions via `cmd /c mklink /J` (no admin needed).
#   - POSIX:   symlinks via `ln -s`.

set -euo pipefail

# ---------- defaults ----------
DEFAULT_EXECUTORS="kiro kimi opencode"

# ---------- logging ----------
log()  { echo "[wt-bootstrap] $*"; }
warn() { echo "[wt-bootstrap] WARN: $*" >&2; }
err()  { echo "[wt-bootstrap] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------- help ----------
usage() {
  cat <<'EOF'
wt-bootstrap.sh — set up executor git worktrees for a project (idempotent).

Usage:
  bash scripts/wt-bootstrap.sh <project-dir> [executor...]

Arguments:
  <project-dir>  Path to the PRIMARY checkout (holds the real .git + canonical .ai/).
  [executor...]  One or more executor names. Default: kiro kimi opencode.

What it does, per executor:
  1. Create a git worktree at <parent>/.wt/<project>/<executor>/ on branch
     exec/<executor>/init (skipped cleanly if the worktree already exists).
  2. Replace that worktree's .ai/ with a junction (Windows) / symlink (POSIX)
     to the canonical <project-dir>/.ai/. Re-established idempotently. DIES
     LOUD if .ai has degraded into a real directory holding uncommitted
     content (split-brain guard), and verifies the link post-creation.
  3. Add ".ai" to the worktree's .git/info/exclude so the junction is never
     committed.

Safety:
  - Never destroys existing work. If a worktree path exists but is NOT a git
    worktree, the script aborts with a message.
  - Sourcing this file has no side effects.

Options:
  --help, -h     Show this help and exit.
EOF
}

# ---------- platform detection ----------
is_windows() {
  case "$(uname -s 2>/dev/null || echo "${OS:-}")" in
    *MINGW*|*MSYS*|*CYGWIN*|Windows_NT) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- arg parsing ----------
PROJECT_ARG=""
EXECUTORS=""
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
  esac
done

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --*)       die "Unknown flag: $1 (see --help)" ;;
    *)
      if [ -z "$PROJECT_ARG" ]; then
        PROJECT_ARG="$1"
      else
        EXECUTORS="${EXECUTORS:+$EXECUTORS }$1"
      fi
      ;;
  esac
  shift
done

[ -n "$PROJECT_ARG" ] || { usage; die "Missing <project-dir> argument."; }
[ -n "$EXECUTORS" ] || EXECUTORS="$DEFAULT_EXECUTORS"

# ---------- resolve project paths ----------
[ -d "$PROJECT_ARG" ] || die "Project dir not found: $PROJECT_ARG"
PROJECT_DIR="$(cd "$PROJECT_ARG" && pwd)"
git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || die "Not a git repository: $PROJECT_DIR"
[ -d "$PROJECT_DIR/.ai" ] || die "Canonical coordination plane missing: $PROJECT_DIR/.ai"

PROJECT_NAME="$(basename "$PROJECT_DIR")"
PARENT_DIR="$(dirname "$PROJECT_DIR")"
WT_CONTAINER="$PARENT_DIR/.wt/$PROJECT_NAME"

log "Project:    $PROJECT_DIR"
log "Container:  $WT_CONTAINER"
log "Executors:  $EXECUTORS"

# ---------- helpers ----------
# Append ".ai" to a worktree's exclude file. The worktree's .git is a file
# pointing at the real gitdir (.git/worktrees/<name>); resolve it.
exclude_ai() {
  wt_path="$1"
  gitdir="$(git -C "$wt_path" rev-parse --git-dir)"
  case "$gitdir" in
    /*|?:*) : ;;                    # already absolute
    *) gitdir="$wt_path/$gitdir" ;; # relative → anchor to worktree
  esac
  mkdir -p "$gitdir/info"
  exclude_file="$gitdir/info/exclude"
  if ! grep -qxF '.ai' "$exclude_file" 2>/dev/null; then
    echo '.ai' >> "$exclude_file"
  fi
}

# Replace <worktree>/.ai with a junction/symlink to the canonical .ai.
# Idempotent: if a link already exists, recreate it to guarantee the target.
link_ai() {
  wt_path="$1"
  link="$wt_path/.ai"
  if [ -L "$link" ]; then
    rm -f "$link"
  elif [ -d "$link" ] && is_windows && [ -n "$(cmd_islink "$link")" ]; then
    cmd //c rmdir "$(winpath "$link")" >/dev/null 2>&1 || true
  elif [ -e "$link" ]; then
    # A real .ai DIRECTORY where the junction should be. Two cases:
    #  - fresh `git worktree add` checkout: contents exactly match the index
    #    -> safe to replace with the junction (nothing exists only here).
    #  - DEGRADED junction: the link was replaced by a real dir after the last
    #    bootstrap and may hold LIVE coordination-plane state (handoffs,
    #    reports, log entries) that exists NOWHERE else. Replacing it blindly
    #    would silently destroy fleet state and split-brain the plane
    #    (2026-07-12: kimi's .ai degraded unnoticed and was re-junctioned by
    #    hand). Verify clean, else die loud.
    dirty_ai="$(git -C "$wt_path" status --porcelain -- .ai 2>/dev/null || true)"
    if [ -n "$dirty_ai" ]; then
      die "DEGRADED .ai at $link: real directory with uncommitted content, not a junction — refusing to replace it. Inspect by hand:
$dirty_ai"
    fi
    rm -rf "$link"
  fi

  if is_windows; then
    cmd //c mklink //J "$(winpath "$link")" "$(winpath "$PROJECT_DIR/.ai")" >/dev/null \
      || die "mklink /J failed for $link"
  else
    ln -s "$PROJECT_DIR/.ai" "$link" \
      || die "ln -s failed for $link"
  fi

  # Post-condition (fail loud): .ai MUST now be a link into the canonical
  # plane. A real directory here is a coordination-plane split-brain — a CLI
  # silently reading the wrong queue, which is far worse than a failed
  # branch cut.
  if is_windows; then
    [ -n "$(cmd_islink "$link")" ] \
      || die ".ai junction verification failed at $link (not a reparse point after relink)"
  else
    [ -L "$link" ] \
      || die ".ai symlink verification failed at $link (not a symlink after relink)"
  fi
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
cmd_islink() {
  cmd //c dir //a:l "$(dirname "$(winpath "$1")")" 2>/dev/null \
    | grep -i "$(basename "$1")" || true
}

# Reverse-write guard (2026-07-13): mark the stable subset of .ai/ as
# skip-worktree inside this worktree so a git checkout/reset/run in the
# worktree cannot silently rewrite the canonical primary .ai/ through the
# junction. Churn directories (handoffs, log, entries, reports, claims,
# archives) remain writable because they are intentionally coordination-plane
# state and are shared through the junction.
guard_ai_reverse_write() {
  wt_path="$1"
  ( cd "$wt_path" && git ls-tree -r HEAD --name-only -- .ai 2>/dev/null ) | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in
      .ai/activity/log.md)      continue ;;
      .ai/activity/entries/*)   continue ;;
      .ai/handoffs/*)           continue ;;
      .ai/reports/*)            continue ;;
      .ai/*/archive/*)          continue ;;
      .ai/.claim-*.json)        continue ;;
    esac
    git -C "$wt_path" update-index --skip-worktree "$rel" 2>/dev/null || true
  done
}

# Pin the per-worktree committer identity to the executor that owns the tree.
# Worktrees otherwise inherit the shared repo config's user.name — which flips
# with whichever CLI last set it (observed 2026-07-13: 3 of 4 pane worktrees
# carrying claude-code). The ADR-0005 pre-commit gate TRUSTS that identity: a
# kiro commit mislabeled claude-code would inherit claude's cross-territory
# replica exception. Idempotent; re-pinned every run so it also repairs drift.
set_identity() {
  local wt="$1" executor="$2" identity
  case "$executor" in
    kimi)     identity="kimi-cli" ;;
    kiro)     identity="kiro-cli" ;;
    claude)   identity="claude-code" ;;
    opencode) identity="opencode" ;;
    *)        log "warn   $executor — no identity mapping; leaving git user.name as-is"; return 0 ;;
  esac
  git -C "$wt" config --worktree user.name "$identity"
  git -C "$wt" config --worktree user.email "$identity@users.noreply.github.com"
}

# ---------- bootstrap each executor ----------
mkdir -p "$WT_CONTAINER"

# Per-worktree config (used by set_identity) only takes effect when the main
# repo config opts in; make sure fresh clones have it.
git -C "$PROJECT_DIR" config extensions.worktreeConfig true

CREATED=""
SKIPPED=""

for executor in $EXECUTORS; do
  wt_path="$WT_CONTAINER/$executor"
  branch="exec/$executor/init"

  if [ -e "$wt_path" ]; then
    if [ -d "$wt_path" ] && git -C "$wt_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      log "skip   $executor — worktree already present ($wt_path)"
      SKIPPED="${SKIPPED:+$SKIPPED }$executor"
    else
      die "Path exists but is not a git worktree: $wt_path (refusing to touch it)"
    fi
  else
    if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$PROJECT_DIR" worktree add "$wt_path" "$branch" >/dev/null
    else
      git -C "$PROJECT_DIR" worktree add "$wt_path" -b "$branch" >/dev/null
    fi
    log "create $executor — worktree at $wt_path on $branch"
    CREATED="${CREATED:+$CREATED }$executor"
  fi

  # Junction + exclude are re-established every run (idempotent) so they survive
  # `git worktree prune` / branch deletion churn (design §8). Identity is
  # re-pinned too — it repairs drifted trees, not just fresh ones.
  link_ai "$wt_path"
  exclude_ai "$wt_path"
  guard_ai_reverse_write "$wt_path"
  set_identity "$wt_path" "$executor"
done

# ---------- summary ----------
echo
log "Summary:"
log "  created: ${CREATED:-(none)}"
log "  skipped: ${SKIPPED:-(none)}"
log "  .ai junction → $PROJECT_DIR/.ai (re-established for all)"
log "Done."
