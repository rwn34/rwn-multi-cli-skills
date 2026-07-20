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

# Dispatchable actors that own a worktree under .wt/<project>/<actor>.
# Keep in sync with scripts/wt-bootstrap.sh.
HANDOFF_ACTORS="claude claude-cockpit kimi kimi-cockpit kiro opencode"

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

# Check the git worktree list for layouts that break the fleet contract:
#   - nested worktrees under .wt/<project>/.wt/... (usually a bootstrap/install
#     accident that leaves stale branches registered)
#   - registered worktrees whose directory is gone from disk (prunable)
#   - worktrees directly under .wt/<project>/ for actors not in HANDOFF_ACTORS
# Prints one actionable FRAMEWORK line per worktree layout problem and returns
# the count on stdout as a plain integer (callers read it with $(...)).
check_worktree_layout() {
  local root="$1"
  local project_name parent_dir wt_base
  project_name="$(basename "$root")"
  parent_dir="$(dirname "$root")"
  wt_base="$parent_dir/.wt/$project_name"

  local problems=0 wt_path wt_branch line
  while IFS= read -r line; do
    case "$line" in
      worktree*)
        wt_path="${line#worktree }"
        wt_branch=""
        ;;
      branch*)
        wt_branch="${line#branch }"
        ;;
      "")
        [ -n "$wt_path" ] || continue
        case "$wt_path" in
          "$wt_base"|"$wt_base/"*) : ;;
          *) continue ;;
        esac
        [ "$wt_path" != "$root" ] || continue

        local rel="${wt_path#$wt_base/}"
        [ -n "$rel" ] || continue
        local first="${rel%%/*}"
        local is_actor=0 actor
        for actor in $HANDOFF_ACTORS; do
          if [ "$first" = "$actor" ]; then
            is_actor=1
            break
          fi
        done
        if [ "$is_actor" -eq 0 ]; then
          echo "FRAMEWORK: orphaned nested worktree: $wt_path (branch ${wt_branch:-unknown}) — remove with: git -C \"$root\" worktree remove --force \"$wt_path\""
          problems=$((problems + 1))
          continue
        fi
        if [ ! -d "$wt_path" ]; then
          echo "FRAMEWORK: missing worktree directory (registration stale): $wt_path (branch ${wt_branch:-unknown}) — prune with: git -C \"$root\" worktree prune"
          problems=$((problems + 1))
          continue
        fi
        local expected_prefix="exec/$first/"
        if [ -n "$wt_branch" ] && [ "${wt_branch#$expected_prefix}" = "$wt_branch" ]; then
          echo "FRAMEWORK: drifted worktree branch: $wt_path is on '$wt_branch', expected '$expected_prefix*' — investigate before next dispatch"
          problems=$((problems + 1))
        fi
        ;;
    esac
  done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
  echo "$problems"
}

# Stable inode/device identifier for a directory. Used to detect whether a
# worktree's .ai/ is the same physical directory as the canonical .ai/
# (junction/symlink) or an independent snapshot copy.
inode_id() {
  stat -c '%d:%i' "$1" 2>/dev/null || stat -f '%d:%i' "$1" 2>/dev/null || echo ""
}

# S1-4 / ADR-0016: flag worktrees whose .ai/ is still a junction/symlink into
# the canonical coordination plane. Snapshot-copy requires an independent dir.
check_ai_junctions() {
  local root="$1"
  local canon_ai="$root/.ai"
  local problems=0 actor wt_path canon_id wt_id
  canon_id="$(inode_id "$canon_ai")"
  [ -n "$canon_id" ] || return 0
  for actor in $HANDOFF_ACTORS; do
    wt_path="$(dirname "$root")/.wt/$(basename "$root")/$actor"
    [ -d "$wt_path/.ai" ] || continue
    wt_id="$(inode_id "$wt_path/.ai")"
    [ -n "$wt_id" ] || continue
    if [ "$wt_id" = "$canon_id" ]; then
      echo "FRAMEWORK: $wt_path/.ai/ is still a junction/symlink into canonical .ai/ — remove before next dispatch: bash scripts/wt-bootstrap.sh --remove \"$root\" $actor"
      problems=$((problems + 1))
    fi
  done
  echo "$problems"
}

# S2-5: flag worktrees whose HEAD is behind the default remote branch. A stale
# base combined with a junctioned .ai/ caused a near-deletion of canonical .ai/.
check_worktree_freshness() {
  local root="$1"
  local problems=0 actor wt_path base
  base="$(git -C "$root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||')"
  [ -n "$base" ] || base="origin/main"
  git -C "$root" rev-parse --verify --quiet "$base" >/dev/null 2>&1 || return 0
  for actor in $HANDOFF_ACTORS; do
    wt_path="$(dirname "$root")/.wt/$(basename "$root")/$actor"
    [ -d "$wt_path" ] || continue
    git -C "$wt_path" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || continue
    if git -C "$wt_path" merge-base --is-ancestor HEAD "$base" 2>/dev/null && \
       ! git -C "$wt_path" merge-base --is-ancestor "$base" HEAD 2>/dev/null; then
      echo "FRAMEWORK: stale worktree: $wt_path HEAD is behind $base — refresh before next dispatch"
      problems=$((problems + 1))
    fi
  done
  echo "$problems"
}

# S3-1: cheap encoding assertion for shared-state files. Bad encoding makes
# grep-based history lookups silently lie and git treat the file as binary.
# fleet-health is detection-only; it does not repair (dispatch-handoffs.sh does).
check_shared_encoding() {
  local root="$1"
  local problems=0 f out
  for f in "$root/.ai/activity/log.md" "$root/.ai/handoffs/README.md"; do
    [ -f "$f" ] || continue
    out="$(bash "$root/.ai/tools/check-encoding.sh" "$f" 2>&1)" || true
    if [ -n "$out" ]; then
      echo "FRAMEWORK: encoding problem: $f — $out (repair: bash .ai/tools/normalize-encoding.sh \"$f\")"
      problems=$((problems + 1))
    fi
  done
  echo "$problems"
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

  local wt_problems=0 wt_report=""
  wt_report="$(check_worktree_layout "$root")"
  wt_problems="$(printf '%s\n' "$wt_report" | tail -1)"
  wt_report="$(printf '%s\n' "$wt_report" | sed '$d')"

  local junction_report="" junction_problems=0
  junction_report="$(check_ai_junctions "$root")"
  junction_problems="$(printf '%s\n' "$junction_report" | tail -1)"
  junction_report="$(printf '%s\n' "$junction_report" | sed '$d')"

  local freshness_report="" freshness_problems=0
  freshness_report="$(check_worktree_freshness "$root")"
  freshness_problems="$(printf '%s\n' "$freshness_report" | tail -1)"
  freshness_report="$(printf '%s\n' "$freshness_report" | sed '$d')"

  local encoding_report="" encoding_problems=0
  encoding_report="$(check_shared_encoding "$root")"
  encoding_problems="$(printf '%s\n' "$encoding_report" | tail -1)"
  encoding_report="$(printf '%s\n' "$encoding_report" | sed '$d')"

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
  if [ -n "$wt_report" ]; then
    printf '%s\n' "$wt_report"
  fi
  if [ -n "$junction_report" ]; then
    printf '%s\n' "$junction_report"
  fi
  if [ -n "$freshness_report" ]; then
    printf '%s\n' "$freshness_report"
  fi
  if [ -n "$encoding_report" ]; then
    printf '%s\n' "$encoding_report"
  fi
  if [ "$queue_problems" -gt 0 ]; then
    echo "$queue_problems queue dir(s) missing. Run the fix command above."
  fi
  local total_problems=$((bad + queue_problems + wt_problems + junction_problems + freshness_problems + encoding_problems))
  if [ "$total_problems" -gt 0 ]; then
    echo "$total_problems pane(s)/queue dir(s)/worktree(s) need attention (STALL/WEDGED/missing queue dir/orphaned worktree/junctioned .ai/ stale worktree/encoding). Detection only — restarts stay with the owner/claude."
  else
    echo "all panes OK or down-idle."
  fi
  return "$total_problems"
}

out="$(main "$ROOT" 2>&1)"; rc=$?
printf '%s\n' "$out"

# Fail-open on INTERNAL errors: a non-zero main with no STALL/WEDGED/FRAMEWORK
# verdict in its output means the checker itself broke (set -u abort, missing
# util) — that must never gate the fleet.  Queue-dir problems are real health
# findings, not internal errors.
if [ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -qE 'STALL|WEDGED|FRAMEWORK:|orphaned|drifted worktree|missing worktree directory|junction|stale worktree|encoding problem'; then
  echo "fleet-health: internal error (exit $rc) — failing open" >&2
  exit 0
fi
[ "$rc" -gt 0 ] && exit 1
exit 0
