#!/bin/bash
# claim-handoff.sh — a COCKPIT takes ownership of a handoff that would
# otherwise belong to the auto pane: flips the handoff's `Auto:` line to `no`
# and writes a per-handoff claim sidecar under .ai/handoffs/.claims/.
#
# The rule (2026-07-13): the `Auto:` tag is the ownership boundary.
#   Auto: yes + Risk A|B  -> owned by the auto pane; a cockpit must not take it.
#   Auto: no, or Risk C   -> owned by the cockpit (human in the loop).
# A cockpit that needs an `Auto: yes` handoff (pane down, quarantined, owner
# waiting live) runs THIS script first, which makes the override explicit,
# race-free, and visible in git history. Inverse: release-handoff.sh.
#
# Staleness semantics are MIRROR-IDENTICAL to the per-handoff claim-lock in
# tools/4ai-panes/pane-runner.ps1 (Test-HandoffClaimed / Claim-Handoff) and to
# .ai/handoffs/.claims/README.md — do not invent a second policy:
#   - same host + dead pid        -> stale, reclaim immediately
#   - claimed_at older than 15min -> stale, reclaim (any host; a foreign-host
#     pid is unverifiable locally, so cross-host trust rests on this window)
#   - unparseable claimed_at      -> trusted (blocks) — fail closed
#   - corrupt/non-JSON sidecar    -> not a claim, reclaimable
# Claim sidecar shape (byte-compatible with pane-runner's Claim-Handoff):
#   {"handoff":"<base>","recipient":"<cli>","owner":"<owner>","pid":N,
#    "host":"<hostname>","claimed_at":"<UTC ISO-8601>"}
#
# Guarantees: atomic (exclusive create / temp+rename), idempotent (re-claiming
# your own claim = no-op, exit 0), fail-closed (any ambiguity = refuse and
# explain, never silently take).
#
# Usage:  bash .ai/tools/claim-handoff.sh <path-to-handoff.md> [--owner <name>]
# Exit:   0 = claimed (or already yours); 1 = refused (held/terminal/ambiguous);
#         2 = usage error.

set -u

STALE_MINUTES=15   # mirrors pane-runner.ps1 $script:HandoffClaimStaleMinutes

die()  { echo "claim-handoff: ERROR: $*" >&2; exit 2; }
refuse() { echo "claim-handoff: REFUSED: $*" >&2; exit 1; }

# -- args --
HANDOFF=""
OWNER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --owner)  OWNER="${2:-}"; [ -n "$OWNER" ] || die "--owner needs a value"; shift ;;
        --owner=*) OWNER="${1#--owner=}"; [ -n "$OWNER" ] || die "--owner needs a value" ;;
        -h|--help) sed -n '1,30p' "$0"; exit 0 ;;
        *) [ -z "$HANDOFF" ] || die "unexpected argument: $1"; HANDOFF="$1" ;;
    esac
    shift
done
[ -n "$HANDOFF" ] || die "usage: claim-handoff.sh <path-to-handoff.md> [--owner <name>]"

# Windows paths arrive with backslashes from PowerShell callers; normalize so
# dirname/basename work (Git Bash accepts C:/... natively).
HANDOFF="${HANDOFF//\\//}"
[ -f "$HANDOFF" ] || die "no such handoff file: $HANDOFF"

# -- derive recipient + claim path by walking up, mirroring --
#    pane-runner.ps1 Get-HandoffClaimDir / Get-HandoffClaimPath:
#    .../.ai/handoffs/to-<recipient>/open/<file> -> .../.ai/handoffs/.claims
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
claims_dir="$handoffs_dir/.claims"
sidecar="$claims_dir/${recipient}__${base}.claim.json"

# Default owner mirrors pane-runner.ps1 Get-DefaultOwner.
if [ -z "$OWNER" ]; then
    case "$recipient" in
        claude)   OWNER="claude-auto" ;;
        kimi)     OWNER="kimi-cli" ;;
        kiro)     OWNER="kiro-cli" ;;
        opencode) OWNER="opencode" ;;
    esac
fi

HOST="$(hostname)"
HOST_LC="$(echo "$HOST" | tr '[:upper:]' '[:lower:]')"

# -- status-block gate: only OPEN handoffs may be claimed (fail closed) --
head20="$(head -20 "$HANDOFF")"
status="$(printf '%s\n' "$head20" | sed -n 's/^[[:space:]]*Status:[[:space:]]*//p' | head -1 | tr -d '\r')"
case "$status" in
    OPEN) ;;
    DONE|BLOCKED) refuse "handoff is Status: $status — terminal states are never claimed" ;;
    *) refuse "handoff status is '$status' (expected OPEN) — refusing rather than guess" ;;
esac

auto_line_count="$(printf '%s\n' "$head20" | grep -c '^[[:space:]]*Auto:')"
auto_val="$(printf '%s\n' "$head20" | sed -n 's/^[[:space:]]*Auto:[[:space:]]*//p' | head -1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
[ "$auto_line_count" -le 1 ] || refuse "ambiguous: $auto_line_count Auto: lines in the status block"

# -- sidecar field extraction (no jq in the fleet image; writers are controlled) --
json_str_field() { # $1=file $2=field
    grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null | head -1 \
        | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}
json_num_field() { # $1=file $2=field
    grep -o "\"$2\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" "$1" 2>/dev/null | head -1 \
        | sed 's/^[^:]*:[[:space:]]*//'
}

# pid_alive — Windows-native probe. NOTE: MSYS2 bash's `kill -0` only sees MSYS
# processes; every real claimant here (pane-runner powershell.exe, CLI binaries)
# is a NATIVE Windows pid, invisible to kill -0. tasklist //FO CSV emits
# "Image","PID",... data rows (or an INFO: line when nothing matches), so an
# exact second-field match is locale-robust. kill -0 stays as a non-Windows
# fallback.
pid_alive() {
    if command -v tasklist >/dev/null 2>&1; then
        case "$(tasklist //FI "PID eq $1" //NH //FO CSV 2>/dev/null)" in
            \"*\",\"$1\",*) return 0 ;;
        esac
        return 1
    fi
    kill -0 "$1" 2>/dev/null
}

# claim_is_live <sidecar> — mirror of pane-runner.ps1 Test-HandoffClaimed.
# Returns 0 if a LIVE/FRESH claim exists, 1 otherwise (absent/corrupt/stale).
claim_is_live() {
    local p="$1"
    [ -f "$p" ] || return 1
    # Corrupt / non-JSON sidecar -> pane-runner's ConvertFrom-Json fails -> null.
    # Tolerate a UTF-8 BOM the way PS Get-Content -Raw does: the '{' of a real
    # sidecar is within the first bytes even behind a BOM.
    head -c 16 "$p" | grep -q '{' || return 1

    local pid host ts same_host
    pid="$(json_num_field "$p" pid)"
    host="$(json_str_field "$p" host)"
    ts="$(json_str_field "$p" claimed_at)"

    same_host=0
    if [ -z "$host" ] || [ "$(echo "$host" | tr '[:upper:]' '[:lower:]')" = "$HOST_LC" ]; then
        same_host=1
    fi
    # pid-liveness is only trusted on our host: same host + dead pid -> stale.
    if [ -n "$pid" ] && [ "$same_host" -eq 1 ]; then
        pid_alive "$pid" || return 1
    fi
    # Time window applies regardless of host.
    if [ -n "$ts" ]; then
        local then_s now_s
        then_s="$(date -u -d "$ts" +%s 2>/dev/null)"
        if [ -n "$then_s" ]; then
            now_s="$(date -u +%s)"
            [ $(( (now_s - then_s) / 60 )) -gt "$STALE_MINUTES" ] && return 1
        fi
        # unparseable ts -> trusted (fail closed), like the PS mirror
    fi
    return 0
}

write_sidecar() { # $1=target path — temp + rename, BOM-less
    local target="$1" tmp
    tmp="$target.tmp.$$"
    printf '%s' "$(sidecar_json)" > "$tmp" || return 1
    mv -f "$tmp" "$target"
}

sidecar_json() {
    printf '{"handoff":"%s","recipient":"%s","owner":"%s","pid":%d,"host":"%s","claimed_at":"%s"}' \
        "$base" "$recipient" "$OWNER" "$$" "$HOST" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# flip_auto <from-regex> <to-value> — rewrite the single Auto: line in the
# status block via temp+rename. Case-class from-regex because PowerShell's
# -match (the pane's gate) is case-insensitive; tolerates a trailing CR so a
# CRLF handoff flips cleanly instead of failing closed.
flip_auto() {
    local from="$1" to="$2" tmp
    tmp="$HANDOFF.tmp.$$"
    sed "1,20 s/^\([[:space:]]*Auto:\\)[[:space:]]*$from\([[:space:]]*\r\{0,1\}\)$/\1 $to\2/" "$HANDOFF" > "$tmp" || return 1
    cmp -s "$tmp" "$HANDOFF" && { rm -f "$tmp"; return 1; }  # nothing changed = flip failed
    mv -f "$tmp" "$HANDOFF"
}

# -- idempotency: our own claim (owner + host) on an already-flipped handoff --
if [ -f "$sidecar" ]; then
    sc_owner="$(json_str_field "$sidecar" owner)"
    sc_host="$(json_str_field "$sidecar" host)"
    sc_host_lc="$(echo "$sc_host" | tr '[:upper:]' '[:lower:]')"
    if [ "$sc_owner" = "$OWNER" ] && { [ -z "$sc_host" ] || [ "$sc_host_lc" = "$HOST_LC" ]; }; then
        if [ "$auto_val" = "no" ]; then
            echo "claim-handoff: already claimed by $OWNER on $HOST and Auto: no — nothing to do."
            exit 0
        fi
        # Our sidecar but Auto still says yes = an interrupted earlier run:
        # complete the flip (fail closed: a LIVE foreign pid below still blocks).
    fi
fi

# -- refuse on a live/fresh claim held by someone else --
if claim_is_live "$sidecar"; then
    sc_owner="$(json_str_field "$sidecar" owner)"
    sc_pid="$(json_num_field "$sidecar" pid)"
    sc_host="$(json_str_field "$sidecar" host)"
    sc_ts="$(json_str_field "$sidecar" claimed_at)"
    refuse "handoff is already claimed by owner='$sc_owner' pid=$sc_pid host='$sc_host' at $sc_ts (live/fresh). If that claim is abandoned, it goes stale after ${STALE_MINUTES}min or on pid death (same host) — never grabbed by force."
fi

# -- acquire: exclusive create (noclobber = O_EXCL); stale file -> reclaim --
mkdir -p "$claims_dir" || die "cannot create claims dir: $claims_dir"
acquired=""
if ( set -o noclobber; sidecar_json > "$sidecar" ) 2>/dev/null; then
    acquired="claimed"
else
    # File exists but was judged stale/corrupt above -> reclaim by overwrite.
    if ! claim_is_live "$sidecar"; then
        write_sidecar "$sidecar" && acquired="reclaimed (stale sidecar overwritten)"
    fi
    # else: lost a race — someone claimed between our check and create.
fi
[ -n "$acquired" ] || refuse "lost a claim race on $base — a live claim appeared while acquiring; re-run to see the holder."

# -- flip Auto: -> no (after the claim is held; roll the claim back on failure) --
if [ "$auto_val" != "no" ]; then
    [ "$auto_line_count" -eq 1 ] || {
        rm -f "$sidecar"
        refuse "no Auto: line in the status block — refusing to guess; rolled back the sidecar. Add an explicit 'Auto: yes' line and retry."
    }
    if ! flip_auto '[Yy][Ee][Ss]' 'no'; then
        rm -f "$sidecar"
        refuse "failed to flip Auto: line to 'no' — rolled back the sidecar; handoff untouched."
    fi
fi

echo "claim-handoff: $acquired: $HANDOFF"
echo "  owner=$OWNER pid=$$ host=$HOST"
echo "  sidecar: $sidecar"
[ "$auto_val" = "no" ] || echo "  Auto: flipped to 'no' — the auto pane will now skip this handoff."
exit 0
