#!/usr/bin/env bash
# wt-bootstrap.sh — idempotently set up executor git worktrees for a project,
# implementing the "code plane / coordination plane" topology from
# .ai/research/worktree-multi-project-topology.md (sections 3, 4, 8).
#
# Each executor gets an independent working tree at a SIBLING location
# (<parent>/.wt/<project>/<executor>/) on branch exec/<executor>/init.
# The shared .ai/ coordination plane is NO LONGER a junction/symlink into the
# worktree (ADR-0004 replaced by ADR-0016 snapshot-copy model). Instead, the
# dispatcher copies a canonical .ai/ snapshot into the worktree before each
# handoff and syncs changes back afterward. wt-bootstrap.sh only ensures the
# worktree exists; it never mounts .ai/.
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

# All dispatchable actors that need a handoff queue tree.  Keep in sync with
# .ai/handoffs/README.md (six-actor model) and .ai/tools/fleet-health.sh.
# kimi-executor and kiro-executor are live in this repo (have open handoffs).
HANDOFF_ACTORS="claude claude-cockpit kimi kimi-cockpit kimi-executor kiro kiro-executor opencode"

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
  bash scripts/wt-bootstrap.sh --remove <project-dir> [executor...]

Arguments:
  <project-dir>  Path to the PRIMARY checkout (holds the real .git + canonical .ai/).
  [executor...]  One or more executor names. Default: kiro kimi opencode.

What it does, per executor:
  1. Create a git worktree at <parent>/.wt/<project>/<executor>/ on branch
     exec/<executor>/init (skipped cleanly if the worktree already exists).
  2. Add ".ai" to the worktree's .git/info/exclude so the snapshot-copy .ai/
     (populated by the dispatcher before each handoff) is never committed.
  3. Pin a per-worktree git identity so commits carry the executor's name.

With --remove:
  Remove one or more executor worktrees. Because .ai/ is now an ordinary
  directory (not a junction), removal is a normal git worktree remove.

Safety:
  - Never destroys existing work. If a worktree path exists but is NOT a git
    worktree, the script aborts with a message.
  - With --remove, refuses to act if the worktree's .ai/ is still a junction.
  - Sourcing this file has no side effects.

Options:
  --help, -h     Show this help and exit.
  --remove       Remove the named executor worktrees safely.
EOF
}

# Ensure the shared coordination-plane handoff queue directories exist for every
# configured actor.  This is shared state (all worktrees junction to the same
# .ai/), so it is repaired once per bootstrap run, not once per executor.
# .gitkeep files are touched so the empty subdirectories are stable even on a
# fresh clone where bootstrap has not yet run.
ensure_handoff_queues() {
  local base="$1/.ai/handoffs"
  for actor in $HANDOFF_ACTORS; do
    for sub in open review done; do
      mkdir -p "$base/to-$actor/$sub"
      touch "$base/to-$actor/$sub/.gitkeep"
    done
  done
}

# ---------- arg parsing ----------
PROJECT_ARG=""
EXECUTORS=""
REMOVE_MODE=false

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
  esac
done

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --remove)  REMOVE_MODE=true ;;
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

# Shared handoff queue structure must exist before any worktree is created;
# dispatchers and health checks assume every actor has open/review/done dirs.
ensure_handoff_queues "$PROJECT_DIR"

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

# Remove a path that may be a symlink or Windows junction/reparse point WITHOUT
# following it. Falls back to rm -rf for ordinary directories/files. This is the
# belt-and-suspenders guard against the ADR-0004 reverse-write hazard: if a
# worktree's .ai/ is still a junction/symlink to the canonical coordination plane,
# `rm -rf` would follow it and destroy shared state.
safe_unlink_or_remove() {
  local path="$1"
  [ -e "$path" ] || return 0

  # POSIX symlink: rm removes the link, not the target.
  if [ -L "$path" ]; then
    rm -f "$path"
    return 0
  fi

  # Windows junction / reparse point: do NOT follow it.
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      local winpath
      winpath="$(cygpath -w "$path" 2>/dev/null || echo "$path")"
      if powershell -NoProfile -Command "try { \$p = Get-Item -Path '$winpath' -Force -ErrorAction Stop; exit [int](-not (\$p.Attributes -match 'ReparsePoint')) } catch { exit 1 }" 2>/dev/null; then
        # It's a reparse point; remove the junction/symlink only.
        if cmd //c "rmdir \"$winpath\"" >/dev/null 2>&1; then
          return 0
        fi
        if powershell -NoProfile -Command "Remove-Item -Path '$winpath' -Force -ErrorAction Stop" 2>/dev/null; then
          return 0
        fi
        die "Could not safely remove Windows reparse point: $path"
      fi
      ;;
  esac

  # Ordinary directory/file.
  rm -rf "$path"
}

# Remove a single executor worktree. With .ai/ now an ordinary directory (not a
# junction), this is a normal git worktree remove. We still remove the worktree's
# .ai/ first as a belt-and-suspenders guard against any future re-introduction of
# a junction, but under the snapshot-copy model it is always an ordinary dir.
remove_worktree() {
  local executor="$1" wt_path="$2" branch="$3"

  if [ ! -e "$wt_path" ]; then
    log "skip   $executor — worktree does not exist ($wt_path)"
    return 0
  fi

  if [ ! -d "$wt_path" ] || ! git -C "$wt_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Path exists but is not a git worktree: $wt_path (refusing to remove it)"
  fi

  # Belt-and-suspenders: remove the worktree's .ai/ BEFORE git worktree remove.
  # Under the snapshot-copy model this is an ordinary directory; under the old
  # junction model this would have been fatal. safe_unlink_or_remove ensures that
  # even if .ai/ is still a junction/symlink, we unlink it rather than following it.
  safe_unlink_or_remove "$wt_path/.ai"

  git -C "$PROJECT_DIR" worktree remove --force "$wt_path" \
    || die "git worktree remove failed for $wt_path"
  log "remove $executor — worktree removed ($wt_path)"

  # Clean up the init branch if it still exists and is fully merged to HEAD.
  if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
    if git -C "$PROJECT_DIR" merge-base --is-ancestor "$branch" HEAD 2>/dev/null; then
      git -C "$PROJECT_DIR" branch -d "$branch" >/dev/null 2>&1 \
        && log "prune  $executor — deleted merged branch $branch"
    else
      warn "$executor — branch $branch is not merged; left intact"
    fi
  fi
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

# ---------- remove mode ----------
if [ "$REMOVE_MODE" = true ]; then
  REMOVED=""
  SKIPPED=""
  for executor in $EXECUTORS; do
    wt_path="$WT_CONTAINER/$executor"
    branch="exec/$executor/init"
    if [ -e "$wt_path" ]; then
      remove_worktree "$executor" "$wt_path" "$branch"
      REMOVED="${REMOVED:+$REMOVED }$executor"
    else
      log "skip   $executor — worktree does not exist ($wt_path)"
      SKIPPED="${SKIPPED:+$SKIPPED }$executor"
    fi
  done
  echo
  log "Summary:"
  log "  removed: ${REMOVED:-(none)}"
  log "  skipped: ${SKIPPED:-(none)}"
  log "Done."
  exit 0
fi

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

  # Exclude .ai/ so the dispatcher's snapshot copy is never committed from the
  # worktree. Identity is re-pinned every run so drifted trees are repaired.
  exclude_ai "$wt_path"
  set_identity "$wt_path" "$executor"
done

# ---------- summary ----------
echo
log "Summary:"
log "  created: ${CREATED:-(none)}"
log "  skipped: ${SKIPPED:-(none)}"
log "  .ai excluded from worktree (snapshot-copy model; dispatcher populates it)"
log "Done."
