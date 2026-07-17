#!/usr/bin/env bash
# checkpoint-ai.sh — mechanical checkpoint commit for the coordination plane.
#
# The shared .ai/ state (handoff queues, activity log, reports, claims) lives in
# the working tree and is one accidental `git clean` / `rm` away from amnesia.
# This script makes a signless, mechanical commit of any .ai/ changes so the
# state is recoverable from git history.
#
# Usage:
#   bash .ai/tools/checkpoint-ai.sh                 # checkpoint current repo
#   bash .ai/tools/checkpoint-ai.sh <project-dir>   # checkpoint another project
#   bash .ai/tools/checkpoint-ai.sh --dry-run       # preview what would commit
#
# Safety:
#   - Only commits paths under .ai/.
#   - Refuses to run inside a linked git worktree (junction hazard: a worktree
#     sees canonical .ai/ changes as its own modifications).
#   - Refuses if the working tree has non-.ai/ uncommitted changes, to avoid
#     bundling unrelated work into a mechanical checkpoint.
#   - Requires a clean git identity.
#   - Idempotent: no .ai/ changes -> no commit.
#
# Designed to be called manually, from a git hook, or from a scheduler.
set -euo pipefail

DRY_RUN=false
PROJECT_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    --dry-run) DRY_RUN=true ; shift ;;
    --*) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *)
      if [ -z "$PROJECT_DIR" ]; then
        PROJECT_DIR="$1"
      else
        echo "ERROR: only one project dir allowed" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(pwd)"
cd "$PROJECT_DIR" || { echo "ERROR: cannot cd to $PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(pwd)"

log()  { echo "[checkpoint-ai] $*"; }
err()  { echo "[checkpoint-ai] ERROR: $*" >&2; }
warn() { echo "[checkpoint-ai] WARN: $*" >&2; }

# ---------- provenance guard: primary checkout only ----------
git_dir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" || { err "not a git repository: $PROJECT_DIR"; exit 1; }
git_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { err "cannot resolve git common dir"; exit 1; }
if [ "$git_dir" != "$git_common" ]; then
  err "refusing to run in a linked worktree ($git_dir != $git_common) — checkpoints must happen in the primary checkout"
  exit 1
fi

# ---------- identity guard ----------
identity="$(git config user.name 2>/dev/null || true)"
if [ -z "$identity" ]; then
  err "git user.name is not set; set it before checkpointing"
  exit 1
fi

# ---------- check for non-.ai/ uncommitted changes ----------
non_ai_changes="$(git status --porcelain | grep -v '^.. \.ai/' || true)"
if [ -n "$non_ai_changes" ]; then
  err "refusing to checkpoint while non-.ai/ changes are present:\n$non_ai_changes"
  err "commit or stash unrelated work first"
  exit 1
fi

# ---------- check for .ai/ changes ----------
ai_changes="$(git status --porcelain -- .ai 2>/dev/null || true)"
if [ -z "$ai_changes" ]; then
  log "no .ai/ changes to checkpoint"
  exit 0
fi

# ---------- dry-run preview ----------
if [ "$DRY_RUN" = true ]; then
  log "would checkpoint the following .ai/ changes:"
  echo "$ai_changes" | sed 's/^/  /'
  exit 0
fi

# ---------- commit ----------
stamp="$(date +'%Y-%m-%d %H:%M')"
branch="$(git branch --show-current 2>/dev/null || echo 'HEAD')"
git add -- .ai
git commit -m "checkpoint(.ai): coordination state

Mechanical checkpoint of .ai/ shared state.
- Branch: $branch
- Time: $stamp (UTC+7)
- Identity: $identity

No semantic review required; this commit exists only to make the coordination
plane recoverable from git history." --no-verify

log "checkpoint committed on $branch at $stamp (UTC+7)"
