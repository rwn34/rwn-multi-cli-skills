#!/bin/bash
# release-handoff.sh — inverse of claim-handoff.sh: "I claimed this handoff
# and changed my mind." Flips the handoff's `Auto:` line back to `yes` and
# drops the claim sidecar, so the auto pane owns it again on its next poll.
#
# Same safety bar as claim-handoff.sh:
#   - refuses on terminal states (Status: DONE/BLOCKED)
#   - refuses to drop a sidecar owned by SOMEONE ELSE (owner/host mismatch) —
#     never release another actor's claim (fail closed)
#   - atomic (temp+rename), idempotent (already Auto: yes + no sidecar = no-op)
#
# Usage:  bash .ai/tools/release-handoff.sh <path-to-handoff.md> [--owner <name>]
# Exit:   0 = released (or nothing to release); 1 = refused; 2 = usage error.

set -u

die()  { echo "release-handoff: ERROR: $*" >&2; exit 2; }
refuse() { echo "release-handoff: REFUSED: $*" >&2; exit 1; }

HANDOFF=""
OWNER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --owner)  OWNER="${2:-}"; [ -n "$OWNER" ] || die "--owner needs a value"; shift ;;
        --owner=*) OWNER="${1#--owner=}"; [ -n "$OWNER" ] || die "--owner needs a value" ;;
        -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
        *) [ -z "$HANDOFF" ] || die "unexpected argument: $1"; HANDOFF="$1" ;;
    esac
    shift
done
[ -n "$HANDOFF" ] || die "usage: release-handoff.sh <path-to-handoff.md> [--owner <name>]"

HANDOFF="${HANDOFF//\\//}"
[ -f "$HANDOFF" ] || die "no such handoff file: $HANDOFF"

base="$(basename "$HANDOFF")"; base="${base%.md}"
open_dir="$(dirname "$HANDOFF")"
to_dir="$(dirname "$open_dir")"
handoffs_dir="$(dirname "$to_dir")"
to_name="$(basename "$to_dir")"
case "$to_name" in
    to-*) recipient="${to_name#to-}" ;;
    *)    die "handoff is not under a to-<recipient>/ directory: $HANDOFF" ;;
esac
case "$recipient" in
    claude|kimi|kiro|opencode) ;;
    *) die "unknown recipient '$recipient' (expected claude|kimi|kiro|opencode)" ;;
esac
sidecar="$handoffs_dir/.claims/${recipient}__${base}.claim.json"

# Default owner: these scripts are cockpit-only, so the release is made by the
# interactive cockpit identity.
if [ -z "$OWNER" ]; then
    case "$recipient" in
        claude)   OWNER="claude-cockpit" ;;
        kimi)     OWNER="kimi-cockpit" ;;
    esac
fi

HOST="$(hostname)"
HOST_LC="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"

head20="$(head -20 "$HANDOFF")"
status="$(printf '%s\n' "$head20" | sed -n 's/^[[:space:]]*Status:[[:space:]]*//p' | head -1 | tr -d '\r')"
case "$status" in
    OPEN) ;;
    DONE|BLOCKED) refuse "handoff is Status: $status — nothing to release on a terminal handoff" ;;
    *) refuse "handoff status is '$status' (expected OPEN) — refusing rather than guess" ;;
esac

auto_line_count="$(printf '%s\n' "$head20" | grep -c '^[[:space:]]*Auto:')"
auto_val="$(printf '%s\n' "$head20" | sed -n 's/^[[:space:]]*Auto:[[:space:]]*//p' | head -1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
[ "$auto_line_count" -eq 1 ] || refuse "expected exactly one Auto: line in the status block, found $auto_line_count — refusing to guess"

json_str_field() {
    grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null | head -1 \
        | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}

# -- drop OUR sidecar; refuse to touch anyone else's (fail closed) --
dropped=""
if [ -f "$sidecar" ]; then
    sc_owner="$(json_str_field "$sidecar" owner)"
    sc_host="$(json_str_field "$sidecar" host)"
    sc_host_lc="$(echo "$sc_host" | tr '[:upper:]' '[:lower:]')"
    sc_pid="$(grep -o "\"pid\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" "$sidecar" | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
    if [ "$sc_owner" = "$OWNER" ] && { [ -z "$sc_host" ] || [ "$sc_host_lc" = "$HOST_LC" ]; }; then
        rm -f "$sidecar" || die "cannot remove sidecar: $sidecar"
        dropped="yes"
    else
        refuse "sidecar is owned by owner='$sc_owner' pid=$sc_pid host='$sc_host' — not by '$OWNER' on this host. Never release another actor's claim; have them run release-handoff.sh themselves (or let it go stale)."
    fi
fi

# -- flip Auto: back to yes (temp+rename; preserve trailing CR if present) --
flipped=""
if [ "$auto_val" != "yes" ]; then
    tmp="$HANDOFF.tmp.$$"
    # case-class regex: the pane's -match gate is case-insensitive, so
    # `Auto: NO` was a real claim too; tolerate a trailing CR on CRLF files.
    sed "1,20 s/^\([[:space:]]*Auto:\\)[[:space:]]*[Nn][Oo]\([[:space:]]*\r\{0,1\}\)$/\1 yes\2/" "$HANDOFF" > "$tmp" || die "sed failed on $HANDOFF"
    if cmp -s "$tmp" "$HANDOFF"; then
        rm -f "$tmp"
        die "failed to flip Auto: line back to 'yes' — handoff untouched (sidecar already dropped: $dropped)"
    fi
    mv -f "$tmp" "$HANDOFF"
    flipped="yes"
fi

if [ -z "$dropped" ] && [ -z "$flipped" ]; then
    echo "release-handoff: already Auto: yes with no claim sidecar — nothing to do."
else
    echo "release-handoff: released $HANDOFF"
    [ -n "$dropped" ] && echo "  sidecar removed: $sidecar"
    [ -n "$flipped" ] && echo "  Auto: restored to 'yes' — the auto pane may pick this handoff up again."
fi
exit 0
