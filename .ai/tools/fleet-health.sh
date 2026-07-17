#!/bin/bash
# fleet-health.sh — fleet pane liveness watchdog (the dead-man's switch).
#
# The pane poll loops live INSIDE each pane: a pane that is dead, wedged, or
# never relaunched stops polling its own queue, and every existing safety net
# (claim reclaim, quarantine) assumed a live poller. This script is the outside
# observer. For each pane CLI it cross-checks the heartbeat sidecar
# (.ai/.heartbeat-<cli>.json, written once per poll cycle by pane-runner.ps1)
# against that CLI's open handoff queue and classifies:
#
#   | heartbeat      | open Auto:yes A/B handoffs | verdict                          |
#   |----------------|----------------------------|----------------------------------|
#   | fresh          | any                        | OK                               |
#   | stale/missing  | 0                          | DOWN (idle) — informational      |
#   | stale/missing  | >= 1                       | STALL — queue with nobody watching |
#   | fresh          | >= 1 unclaimed, age > win  | WEDGED — polling, not picking up |
#
# Freshness policy MIRRORS pane-runner.ps1's claim staleness, it does not
# invent a second one: same 15-minute window ($script:ProjectClaimStaleMinutes
# / HandoffClaimStaleMinutes), same pid/host semantics — a same-host dead pid
# is stale immediately, a foreign-host pid is unverifiable so the time window
# alone decides, an unparseable record fails OPEN (treated fresh: never take
# the fleet down because the health checker choked).
#
# "Qualifying" mirrors the pane's own gate (Get-QualifyingHandoff /
# dispatch-handoffs.sh): Auto: yes AND Status: OPEN AND Risk: A|B, excluding
# actively-quarantined handoffs (the pane deliberately skips those for up to
# QuarantineStaleMinutes = 60 — parked work is not unwatched work).
#
# Usage:   bash .ai/tools/fleet-health.sh [project-dir]   (default: CWD)
# Exit:    0  all panes OK / DOWN (idle), OR an internal error (fail-open)
#          1  at least one STALL or WEDGED — CI/hooks may gate on this
#
# Detection and alerting ONLY. It never kills, restarts, or signals a pane.

set -u

ROOT="${1:-$PWD}"

# Shared freshness window — keep in lockstep with pane-runner.ps1
# $script:ProjectClaimStaleMinutes / $script:HandoffClaimStaleMinutes (15) and
# $script:QuarantineStaleMinutes (60).
STALE_MINUTES=15
QUARANTINE_STALE_MINUTES=60

NOW="$(date +%s)"
LOCAL_HOST="$(hostname)"

# --- tiny helpers ----------------------------------------------------------

str_ieq() {
  [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ]
}

# Extract a JSON string / number field with grep+sed (no jq dependency — this
# runs on the bare fleet box). Empty output = field absent or unparseable.
json_str() {
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 \
    | sed -E "s/^[^\"]*\"[^\"]*\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*$/\1/"
}
json_num() {
  grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" "$2" 2>/dev/null | head -1 \
    | grep -oE '[0-9]+$'
}

# UTC ISO-8601 (yyyy-MM-ddTHH:mm:ssZ, the pane-runner/claim ts format) -> epoch.
# Empty output = unparseable.
ts_epoch() {
  date -u -d "$1" +%s 2>/dev/null
}

# Windows pid liveness from Git Bash. tasklist.exe is the reliable probe —
# Git Bash `kill -0` cannot see native Windows pids. Fail-open: no probe
# available, or an empty/garbled probe result, counts as ALIVE.
pid_alive() {
  local pid="$1" out
  command -v tasklist >/dev/null 2>&1 || return 0
  out="$(tasklist //FI "PID eq $pid" //NH 2>/dev/null)"
  case "$out" in
    *"No tasks"*) return 1 ;;
    "")           return 0 ;;
    *)            return 0 ;;
  esac
}

# --- heartbeat freshness (mirrors Test-ClaimBlocks staleness) ---------------
# Sets HB_STATE=fresh|stale and HB_DETAIL=<human string>.
heartbeat_state() {
  local cli="$1" root="$2"
  local hb="$root/.ai/.heartbeat-${cli}.json"
  if [ ! -f "$hb" ]; then
    HB_STATE=stale; HB_DETAIL="missing"; return
  fi
  local ts pid host
  ts="$(json_str ts "$hb")"; pid="$(json_num pid "$hb")"; host="$(json_str host "$hb")"
  if [ -z "${ts}${pid}${host}" ]; then
    HB_STATE=fresh; HB_DETAIL="unparseable (fail-open)"; return
  fi
  if [ -n "$ts" ]; then
    local ep; ep="$(ts_epoch "$ts")"
    if [ -z "$ep" ]; then
      HB_STATE=fresh; HB_DETAIL="bad ts (fail-open)"; return
    fi
    local age=$(( (NOW - ep) / 60 ))
    if [ "$age" -gt "$STALE_MINUTES" ]; then
      HB_STATE=stale; HB_DETAIL="ts ${age}m ago (> ${STALE_MINUTES}m)"; return
    fi
    HB_DETAIL="ts ${age}m ago"
  else
    HB_DETAIL="no ts"
  fi
  # pid-liveness is only trusted on this host (a foreign pid is meaningless
  # locally) — same carve-out as the claim locks; missing host counts as local.
  local same_host=1
  if [ -n "$host" ] && ! str_ieq "$host" "$LOCAL_HOST"; then same_host=0; fi
  if [ "$same_host" -eq 1 ] && [ -n "$pid" ] && ! pid_alive "$pid"; then
    HB_STATE=stale; HB_DETAIL="${HB_DETAIL}, pid ${pid} dead here"; return
  fi
  HB_STATE=fresh
  if [ "$same_host" -eq 1 ] && [ -n "$pid" ]; then
    HB_DETAIL="${HB_DETAIL}, pid ${pid} live"
  fi
}

# --- the pane's own qualifying gate, mirrored -------------------------------
is_qualifying() {
  local f="$1"
  head -20 "$f" | grep -qiE '^Auto:[[:space:]]*yes'   || return 1
  head -20 "$f" | grep -qiE '^Status:[[:space:]]*OPEN' || return 1
  head -20 "$f" | grep -qiE '^Risk:[[:space:]]*[AB][[:space:]]*$' || return 1
  return 0
}

# Actively quarantined? Mirrors Test-HandoffQuarantined: a quarantined record
# ages out after QUARANTINE_STALE_MINUTES (by quarantined_at, else last_attempt);
# an unparseable stamp STAYS quarantined.
quarantine_active() {
  local cli="$1" f="$2" root="$3"
  local base; base="$(basename "$f" .md)"
  local q="$root/.ai/handoffs/.quarantine/${cli}__${base}.quarantine.json"
  [ -f "$q" ] || return 1
  grep -qE '"quarantined"[[:space:]]*:[[:space:]]*true' "$q" || return 1
  local stamp; stamp="$(json_str quarantined_at "$q")"
  [ -n "$stamp" ] || stamp="$(json_str last_attempt "$q")"
  [ -n "$stamp" ] || return 0
  local ep; ep="$(ts_epoch "$stamp")"
  [ -n "$ep" ] || return 0
  local age=$(( (NOW - ep) / 60 ))
  [ "$age" -le "$QUARANTINE_STALE_MINUTES" ]
}

# Live per-handoff claim? Mirrors Test-HandoffClaimed: same-host dead pid ->
# stale; claimed_at older than the window -> stale; unparseable -> unclaimed.
claim_live() {
  local cli="$1" f="$2" root="$3"
  local base; base="$(basename "$f" .md)"
  local c="$root/.ai/handoffs/.claims/${cli}__${base}.claim.json"
  [ -f "$c" ] || return 1
  local pid host claimed_at
  pid="$(json_num pid "$c")"; host="$(json_str host "$c")"; claimed_at="$(json_str claimed_at "$c")"
  [ -n "${pid}${host}${claimed_at}" ] || return 1
  local same_host=1
  if [ -n "$host" ] && ! str_ieq "$host" "$LOCAL_HOST"; then same_host=0; fi
  if [ "$same_host" -eq 1 ] && [ -n "$pid" ] && ! pid_alive "$pid"; then return 1; fi
  if [ -n "$claimed_at" ]; then
    local ep; ep="$(ts_epoch "$claimed_at")"
    if [ -n "$ep" ]; then
      local age=$(( (NOW - ep) / 60 ))
      [ "$age" -gt "$STALE_MINUTES" ] && return 1
    fi
  fi
  return 0
}

# Age of a handoff in minutes: the Created: status-block line is UTC+7
# wall-clock per the handoff protocol (filename prefix is UTC, Created: is
# UTC+7), so strip the optional `(UTC+7)` annotation and parse it as local.
# Fall back to file mtime.
handoff_age_min() {
  local f="$1" created ep=""
  created="$(head -20 "$f" | grep -m1 -E '^Created:[[:space:]]*' | sed -E 's/^Created:[[:space:]]*//' | sed -E 's/[[:space:]]*\(UTC\+7\)[[:space:]]*$//')"
  [ -n "$created" ] && ep="$(date -d "$created" +%s 2>/dev/null)"
  [ -z "$ep" ] && ep="$(stat -c %Y "$f" 2>/dev/null)"
  [ -z "$ep" ] && { echo ""; return; }
  echo $(( (NOW - ep) / 60 ))
}

# Verify every discovered handoff queue has the required open/review/done
# subdirectories.  Missing dirs are a framework health problem: handoffs have
# nowhere to land.  Emits one clear line per missing dir with the fix command.
check_queue_dirs() {
  local root="$1"
  local missing=0 dir actor
  shopt -s nullglob
  for dir in "$root"/.ai/handoffs/to-*; do
    [ -d "$dir" ] || continue
    actor="$(basename "$dir")"; actor="${actor#to-}"
    for sub in open review done; do
      if [ ! -d "$dir/$sub" ]; then
        echo "FRAMEWORK: missing queue dir: .ai/handoffs/to-$actor/$sub/ — fix: bash scripts/wt-bootstrap.sh \"$root\""
        missing=$((missing + 1))
      fi
    done
  done
  return "$missing"
}

# --- main -------------------------------------------------------------------
# Returns the number of non-OK panes (STALL/WEDGED) plus framework queue-dir
# problems. Never dies on a bad record: every parser above defaults to the
# benign reading.
main() {
  local root="$1"
  if [ ! -d "$root/.ai/handoffs" ]; then
    echo "fleet-health: $root/.ai/handoffs not found — nothing to check (fail-open)"
    return 0
  fi

  local queue_problems=0
  check_queue_dirs "$root" || queue_problems=$?

  echo "fleet-health — $(cd "$root" 2>/dev/null && pwd)"
  echo "window: heartbeat/claim stale > ${STALE_MINUTES}m (mirrors pane-runner.ps1); quarantine retry after ${QUARANTINE_STALE_MINUTES}m"
  printf '%-9s | %-30s | %-5s | %s\n' "CLI" "heartbeat" "queue" "verdict"
  printf -- '----------+--------------------------------+-------+--------\n'

  local bad=0 cli to_dir f
  shopt -s nullglob
  for to_dir in "$root"/.ai/handoffs/to-*; do
    [ -d "$to_dir" ] || continue
    cli="$(basename "$to_dir")"; cli="${cli#to-}"

    heartbeat_state "$cli" "$root"

    local q=0 unclaimed_aged=0 wedge_detail="" age
    for sub in open review; do
      for f in "$to_dir/$sub"/*.md; do
        [ -f "$f" ] || continue
        is_qualifying "$f" || continue
        quarantine_active "$cli" "$f" "$root" && continue
        q=$((q + 1))
        if ! claim_live "$cli" "$f" "$root"; then
          age="$(handoff_age_min "$f")"
          if [ -n "$age" ] && [ "$age" -gt "$STALE_MINUTES" ]; then
            unclaimed_aged=$((unclaimed_aged + 1))
            wedge_detail="$(basename "$f") (${age}m unclaimed)"
          fi
        fi
      done
    done

    local verdict
    if [ "$HB_STATE" = fresh ]; then
      if [ "$unclaimed_aged" -gt 0 ]; then
        verdict="WEDGED — polling but not picking up ($wedge_detail)"; bad=$((bad + 1))
      else
        verdict="OK"
      fi
    else
      if [ "$q" -eq 0 ]; then
        verdict="DOWN (idle)"
      else
        verdict="STALL — ${q} qualifying handoff(s), nobody watching"; bad=$((bad + 1))
      fi
    fi
    printf '%-9s | %-30s | %-5s | %s\n' "$cli" "$HB_DETAIL" "$q" "$verdict"
  done

  echo ""
  if [ "$queue_problems" -gt 0 ]; then
    echo "$queue_problems queue dir(s) missing. Run the fix command above."
  fi
  if [ "$bad" -gt 0 ] || [ "$queue_problems" -gt 0 ]; then
    echo "$((bad + queue_problems)) pane(s)/queue dir(s) need attention (STALL/WEDGED/missing queue dir). Detection only — restarts stay with the owner/claude."
  else
    echo "all panes OK or down-idle."
  fi
  return $((bad + queue_problems))
}

out="$(main "$ROOT" 2>&1)"; rc=$?
printf '%s\n' "$out"

# Fail-open on INTERNAL errors: a non-zero main with no STALL/WEDGED/FRAMEWORK
# verdict in its output means the checker itself broke (set -u abort, missing
# util) — that must never gate the fleet.  Queue-dir problems are real health
# findings, not internal errors.
if [ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -qE 'STALL|WEDGED|FRAMEWORK:'; then
  echo "fleet-health: internal error (exit $rc) — failing open" >&2
  exit 0
fi
[ "$rc" -gt 0 ] && exit 1
exit 0
