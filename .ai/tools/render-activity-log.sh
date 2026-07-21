#!/usr/bin/env bash
# render-activity-log.sh — generate a human-readable .ai/activity/log.md view
# from the entry-per-file spool (ADR-0010 Wave-3).
#
# Usage:
#   bash .ai/tools/render-activity-log.sh [project-dir]
#
# Reads .ai/activity/entries/*.md in reverse filename order (newest first),
# concatenates them, and appends a pointer to the frozen pre-spool archive.
# Never reads .ai/activity/archive/**.
#
# The rendered file is a generated view, not a source of truth. It must NOT be
# committed; .gitignore should exclude .ai/activity/log.md.
#
# Safety: while log.md is still git-tracked (the pre-freeze transition), this
# script REFUSES to run — rendering then would clobber the live, shared log,
# which at that point is still the source of truth and has no
# archive/log-pre-spool.md to recover from. The guard lifts by itself once the
# ADR-0010 Wave-3 freeze lands (log.md removed from git and gitignored).

set -u

ROOT="${1:-$PWD}"
ENTRIES_DIR="$ROOT/.ai/activity/entries"
ARCHIVE_DIR="$ROOT/.ai/activity/archive"
OUTPUT="$ROOT/.ai/activity/log.md"
PRE_SPOOL="$ARCHIVE_DIR/log-pre-spool.md"

# Guard: fail closed. In a git worktree, refuse while log.md is tracked. In a
# snapshot copy (which may not be a git worktree), refuse if the pre-spool
# archive does not exist — rendering before the ADR-0010 freeze would clobber
# the live shared log and has no recovery point.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$ROOT" ls-files --error-unmatch .ai/activity/log.md >/dev/null 2>&1; then
        echo "render-activity-log: REFUSING — .ai/activity/log.md is still git-tracked (pre-freeze)." >&2
        exit 1
    fi
fi
if [ ! -f "$PRE_SPOOL" ]; then
    echo "render-activity-log: REFUSING — pre-spool archive not found; ADR-0010 freeze may not have landed." >&2
    exit 1
fi

mkdir -p "$ROOT/.ai/activity"

{
  if [ -d "$ENTRIES_DIR" ]; then
    # Newest entries first: UTC basic ISO filenames sort lexicographically == chronologically.
    find "$ENTRIES_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null \
      | LC_ALL=C sort -z -r \
      | while IFS= read -r -d '' f; do
          cat "$f"
          printf '\n'
        done
  fi

  if [ -f "$PRE_SPOOL" ]; then
    printf -- '\n---\n'
    printf 'Pre-spool history frozen at %s\n' "$PRE_SPOOL"
    printf -- '---\n\n'
  fi
} > "$OUTPUT.new"

mv "$OUTPUT.new" "$OUTPUT"
echo "[render-activity-log] wrote $OUTPUT"
