#!/usr/bin/env bash
# check-log-superset.sh — verify a candidate log.md would not DROP any activity-log
# entries that already exist in origin/main, the working tree, or a backup/KEEP file.
#
# The activity log is prepend-order and its timestamps are annotations, so comparing
# line counts or diff stats against `main` is structurally blind to uncommitted
# entries on disk. This check compares the SET of `^## ` entry headers.
#
# Usage: bash .ai/tools/check-log-superset.sh <candidate>
# Exit: 0 iff <candidate> is a strict superset of every source's entry-header set.
#       Non-zero and lists the verbatim lost headers per source on failure.

set -u

candidate="${1:-}"
if [ -z "$candidate" ]; then
    echo "LOG-SUPERSET FAIL: missing candidate argument" >&2
    echo "Usage: bash .ai/tools/check-log-superset.sh <path-to-candidate-log.md>" >&2
    exit 2
fi
if [ ! -r "$candidate" ]; then
    echo "LOG-SUPERSET FAIL: candidate not readable: $candidate" >&2
    exit 2
fi

# Entry headers are the authoritative identity of a log entry (ADR-0010).
# Sort -u deduplicates legitimate repeated headers (e.g. same actor twice in one
# minute) so a duplicate in a source does not read as a loss.
extract_headers() { grep '^## ' "$1" 2>/dev/null | sort -u; }
extract_blob_headers() { git cat-file -p "$1" 2>/dev/null | grep '^## ' | sort -u; }

candidate_headers="$(extract_headers "$candidate")"
if [ -z "$candidate_headers" ]; then
    echo "LOG-SUPERSET FAIL: candidate has no '## ' entry headers: $candidate" >&2
    exit 2
fi

fails=0

# Report headers present in <source> but missing from <candidate>.
# Args: source_label source_headers_file
check_source() {
    local label="$1" src_file="$2"
    [ -s "$src_file" ] || return 0
    local missing
    missing="$(comm -23 "$src_file" <(printf '%s\n' "$candidate_headers"))"
    if [ -n "$missing" ]; then
        echo "LOG-SUPERSET FAIL: candidate is missing entries from $label" >&2
        printf '%s\n' "$missing" | sed 's/^/  /' >&2
        fails=$((fails + 1))
    fi
}

workdir="$(mktemp -d)" || { echo "LOG-SUPERSET FAIL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$workdir"' EXIT

# Source 1: origin/main blob (avoid "git show ref:path" — MSYS mangles colon args).
main_blob=""
if git rev-parse --verify origin/main >/dev/null 2>&1; then
    main_blob="$(git ls-tree origin/main -- .ai/activity/log.md 2>/dev/null | awk '{print $3}')"
fi
if [ -n "$main_blob" ]; then
    extract_blob_headers "$main_blob" > "$workdir/main.headers"
    check_source "origin/main (.ai/activity/log.md)" "$workdir/main.headers"
fi

# Source 2: current working-tree log.md.
if [ -r ".ai/activity/log.md" ]; then
    extract_headers ".ai/activity/log.md" > "$workdir/wt.headers"
    check_source "working tree (.ai/activity/log.md)" "$workdir/wt.headers"
fi

# Source 3: any backup / KEEP files.
shopt -s nullglob
for bak in .ai/activity/log.md.bak .ai/activity/log.md.KEEP*; do
    [ -r "$bak" ] || continue
    base="$(basename "$bak")"
    extract_headers "$bak" > "$workdir/$base.headers"
    check_source "backup ($bak)" "$workdir/$base.headers"
done
shopt -u nullglob

if [ "$fails" -gt 0 ]; then
    echo "LOG-SUPERSET FAIL: $fails source(s) would lose entries if this candidate landed." >&2
    echo "Add the missing entries to the candidate (the log is append-only)." >&2
    exit 1
fi

echo "LOG-SUPERSET OK: candidate contains every entry header from origin/main, working tree, and backups."
exit 0
