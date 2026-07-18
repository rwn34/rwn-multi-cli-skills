#!/bin/bash
# render-activity-log.sh — render .ai/activity/log.md from the entry spool.
#
# ADR-0010 (docs/architecture/0010-activity-log-entry-spool.md): the activity
# log is an entry-per-file spool. .ai/activity/entries/*.md is the SOURCE OF
# TRUTH; log.md is a generated, gitignored VIEW produced by this script.
#
# Ordering: entry filenames are fixed-width UTC basic form
# (<YYYYMMDDTHHMMSSZ>-<cli>-<slug>-<rand4>.md), so reverse lexicographic
# filename order == reverse chronological order. This script never reads
# .ai/**/archive/** — archived months and the frozen pre-spool log are out of
# the view by construction; the frozen file gets a one-line pointer at the
# bottom of the render.
#
# Safety: while log.md is still git-tracked (the pre-freeze transition), this
# script REFUSES to run — rendering then would clobber the live, shared log.
# After the Wave-3 freeze (log.md gitignored) the guard passes.

set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cd "$root" || exit 1

ENTRIES=".ai/activity/entries"
OUT=".ai/activity/log.md"
FROZEN=".ai/activity/archive/log-pre-spool.md"

if git ls-files --error-unmatch "$OUT" >/dev/null 2>&1; then
    echo "render-activity-log: REFUSING — $OUT is still git-tracked (pre-freeze)." >&2
    echo "  Rendering now would clobber the live shared log. This guard lifts once" >&2
    echo "  the ADR-0010 freeze lands (log.md removed from git and gitignored)." >&2
    exit 1
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/activity-log-render.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT

count=0
{
    echo '<!-- GENERATED FILE — do not edit. Source of truth: .ai/activity/entries/ (ADR-0010).'
    echo '     Regenerate with: bash .ai/tools/render-activity-log.sh -->'
    echo
    if ls "$ENTRIES"/*.md >/dev/null 2>&1; then
        for f in $(ls "$ENTRIES"/*.md | LC_ALL=C sort -r); do
            count=$((count + 1))
            cat "$f"
            echo
        done
    fi
    if [ -f "$FROZEN" ]; then
        echo '---'
        echo
        echo "History before the spool cutover is frozen verbatim in $FROZEN (ADR-0010 §6)."
    fi
} > "$tmp"

mv "$tmp" "$OUT"
trap - EXIT
echo "render-activity-log: rendered $OUT from $count entry file(s)"
