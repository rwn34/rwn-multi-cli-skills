#!/bin/bash
# activity-append.sh -- atomic prepend-only writer for .ai/activity/log.md.
#
# The activity log is shared mutable state: multiple CLIs prepend entries
# concurrently. Two CLIs writing the header at once clobbered an entry on
# 2026-07-09 (framework-improvement-backlog #7). This helper serializes writes
# with an mkdir lock (portable everywhere -- flock is absent on Git-Bash for
# Windows) and commits with an atomic temp-file + rename, so a new entry is
# inserted just below the header's `---` separator without ever racing another
# writer or truncating the file.
#
# Usage:
#   .ai/tools/activity-append.sh "## 2026-07-09 21:30 -- claude-code
#   - Action: did the thing
#   - Files: path
#   - Decisions: -"
#
#   printf '%s\n' "$entry" | .ai/tools/activity-append.sh   # entry on stdin
#
# The entry is prepended verbatim as the newest block. Newest stays at top.

set -u

LOG_REL=".ai/activity/log.md"
LOCK_WAIT_SECONDS=15

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage 0

# Locate the log relative to the repo root (walk up until .ai/activity/log.md).
find_log() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/$LOG_REL" ]; then
            printf '%s' "$dir/$LOG_REL"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

LOG="$(find_log)" || { echo "activity-append: cannot find $LOG_REL above $PWD" >&2; exit 1; }

# Read the entry: first non-flag arg, else stdin.
if [ "$#" -gt 0 ] && [ -n "${1:-}" ]; then
    ENTRY="$1"
else
    ENTRY="$(cat)"
fi
# Trim trailing whitespace/newlines from the entry block.
ENTRY="$(printf '%s' "$ENTRY" | sed -e 's/[[:space:]]*$//')"
[ -n "$ENTRY" ] || { echo "activity-append: empty entry, nothing to write" >&2; exit 1; }

LOCK="$LOG.lock"

# --- acquire mkdir lock (atomic create), with stale-lock reclaim ---
acquire() {
    local waited=0
    while ! mkdir "$LOCK" 2>/dev/null; do
        # Stale-lock recovery: if the holder pid is dead, break the lock.
        if [ -f "$LOCK/pid" ]; then
            local holder
            holder="$(cat "$LOCK/pid" 2>/dev/null)"
            if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
                rm -rf "$LOCK"
                continue
            fi
        fi
        sleep 0.2
        waited=$((waited + 1))
        if [ "$waited" -ge $((LOCK_WAIT_SECONDS * 5)) ]; then
            echo "activity-append: timed out waiting for lock $LOCK" >&2
            return 1
        fi
    done
    echo "$$" > "$LOCK/pid"
    return 0
}

acquire || exit 1
trap 'rm -rf "$LOCK"' EXIT

# --- build new content: insert ENTRY just after the header's first `---` ---
TMP="$LOG.tmp.$$"
# awk splits at the first line that is exactly `---`; everything up to and
# including it is the header. The entry is placed after a blank line, then the
# rest of the file (which already begins with its own blank line) follows.
awk -v entry="$ENTRY" '
    BEGIN { inserted = 0 }
    {
        if (!inserted && $0 == "---") {
            print $0
            print ""
            print entry
            inserted = 1
            next
        }
        print $0
    }
    END {
        # Fallback: no `---` header separator found -> prepend nothing here;
        # handled below by the exit status check.
        if (!inserted) exit 3
    }
' "$LOG" > "$TMP"
awk_rc=$?

if [ "$awk_rc" -eq 3 ]; then
    # No header separator: prepend entry at the very top instead.
    { printf '%s\n\n' "$ENTRY"; cat "$LOG"; } > "$TMP"
elif [ "$awk_rc" -ne 0 ]; then
    rm -f "$TMP"
    echo "activity-append: awk failed (rc=$awk_rc)" >&2
    exit 1
fi

# --- atomic commit ---
mv -f "$TMP" "$LOG"
echo "activity-append: prepended entry to $LOG"
