#!/bin/bash
# reconcile-done-handoffs.sh — self-heal a forgotten protocol-v3 self-retire,
# AND kill ghost handoffs (a retired handoff that never lost its open/ copy).
#
# Protocol v3 (2026-07-09) requires a handoff recipient to MOVE its own file
# from .ai/handoffs/to-<cli>/open/ to the sibling done/ dir when it sets
# `Status: DONE`. If it forgets, the file sits in open/ marked DONE — misplaced:
# the dispatcher's OPEN-only gate won't re-dispatch it, but it's in the wrong
# folder and invisible as "done". This script moves any such stray into done/.
#
# Ghost-handoff guard (2026-07-13, handoff 202607131035): a SECOND, distinct
# defect the DONE-in-open check above cannot see — a handoff retired by
# *copying* open/ -> done/ and editing only the done/ copy (rather than
# *moving* the file, as protocol v3 requires) leaves a STALE open/ copy behind
# that still says `Status: OPEN`. That copy is dispatcher-visible forever: it
# re-dispatches a decision that was already closed, silently burning a full
# session's context every time. The DONE-in-open check is blind to this by
# construction — it only ever looks at the open/ copy's OWN content, and this
# ghost's open/ copy says OPEN, not DONE. Rule: the SAME basename existing in
# BOTH open/ and done/ of the same queue is always an error; done/ wins (a
# handoff is only ever retired forward, never backward) — retire the open/
# copy by moving it into done/ as a `.duplicate-<UTC>` sidecar (never silently
# deleted — see rationale below) and log loudly.
#
# Usage (from repo root):
#   bash .ai/tools/reconcile-done-handoffs.sh          # scan ./.ai/handoffs
#   bash .ai/tools/reconcile-done-handoffs.sh <basedir>  # scan <basedir>/.ai/handoffs
#   HANDOFFS_DIR=/tmp/t bash .ai/tools/reconcile-done-handoffs.sh  # override (tests)
#
# Fail-open by contract: always exits 0. Wired into dispatch-handoffs.sh so every
# auto-dispatch cycle self-heals a forgotten self-retire (and any ghost) before
# selecting work. Idempotent: no DONE-in-open and no open/done duplicate ->
# no output, exit 0.

set -u

base="${1:-.}"
handoffs_dir="${HANDOFFS_DIR:-$base/.ai/handoffs}"

for dir in "$handoffs_dir"/to-*/open; do
    [ -d "$dir" ] || continue
    done_dir="$(dirname "$dir")/done"
    for f in "$dir"/*.md; do
        [ -e "$f" ] || continue
        base_name="$(basename "$f")"
        case "$base_name" in
            README.md|template.md) continue ;;
        esac

        # --- Ghost-handoff guard: same basename in BOTH open/ and done/. ---
        # Checked FIRST and independently of the DONE-in-open case below: a
        # ghost's open/ copy can say OPEN (the exact bug) or DONE — either
        # way, a done/ sibling with the same name means open/ is stale and
        # must go. Never silently `rm` a handoff file (delivery-integrity: no
        # silent destruction of what could be the only record of a decision)
        # — move it into done/ as a timestamped `.duplicate-` sidecar instead,
        # so the ghost is retired but nothing is lost if the move is wrong.
        if [ -e "$done_dir/$base_name" ]; then
            mkdir -p "$done_dir" 2>/dev/null
            ts=$(date -u +%Y%m%d%H%M%S)
            sidecar="$done_dir/${base_name%.md}.duplicate-$ts.md"
            if mv "$f" "$sidecar" 2>/dev/null; then
                echo "reconcile-done: GHOST retired -- $f duplicated done/$base_name; open/ copy moved to $sidecar (done/ wins)"
            fi
            continue
        fi

        # --- Existing check: recipient set Status:DONE but forgot to move. ---
        # Header check: first ~10 lines, case-insensitive `Status: DONE`.
        if head -10 "$f" 2>/dev/null | grep -qiE '^Status:[[:space:]]*DONE'; then
            mkdir -p "$done_dir" 2>/dev/null
            if mv "$f" "$done_dir/" 2>/dev/null; then
                echo "reconcile-done: moved $f -> done/ (Status:DONE was left in open/)"
            fi
        fi
    done
done

exit 0
