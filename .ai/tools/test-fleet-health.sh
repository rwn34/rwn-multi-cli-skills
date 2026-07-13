#!/bin/bash
# test-fleet-health.sh — prove fleet-health.sh actually classifies panes right.
# Run from repo root (or pass the repo root as $1). Exit 0 iff all cases pass.
#
# Fixtures are HERMETIC: each case builds a throwaway project root in a temp
# dir (.ai/handoffs/to-<cli>/open + heartbeat/claim/quarantine sidecars) and
# runs the checker against it via its root argument. Nothing here reads or
# mutates the live tree. Timestamp math is fixture-driven (old vs fresh ts),
# never sleeps.
#
# pid-liveness fixtures use two deterministic pids: 4 (System — alive on any
# Windows box, the pid tasklist can always see) and 999999 (never a live pid).

set -u

ROOT="${1:-$PWD}"
CHECK="$ROOT/.ai/tools/fleet-health.sh"
[ -r "$CHECK" ] || { echo "FAIL: checker not found: $CHECK"; exit 1; }

pass=0
fail=0

HOST="$(hostname)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OLD_ISO="$(date -u -d '30 min ago' +%Y-%m-%dT%H:%M:%SZ)"
VERY_OLD_ISO="$(date -u -d '120 min ago' +%Y-%m-%dT%H:%M:%SZ)"
NOW_LOCAL="$(date '+%Y-%m-%d %H:%M')"
OLD_LOCAL="$(date -d '30 min ago' '+%Y-%m-%d %H:%M')"

mkroot() { mktemp -d; }

# mkhandoff <root> <cli> <name> <risk> <created-local>
mkhandoff() {
  local dir="$1/.ai/handoffs/to-$2/open"
  mkdir -p "$dir"
  cat > "$dir/$3.md" <<EOF
# Test handoff $3
Status: OPEN
Sender: claude-code
Recipient: $2
Created: $5
Auto: yes
Risk: $4

## Goal
test
EOF
}

# mkheartbeat <root> <cli> <ts> <pid> <host>
mkheartbeat() {
  mkdir -p "$1/.ai"
  printf '{"project":"fixture","cli":"%s","pid":%s,"host":"%s","ts":"%s","handoff":"idle"}' \
    "$2" "$4" "$5" "$3" > "$1/.ai/.heartbeat-$2.json"
}

# mkclaim <root> <cli> <handoff-name> <claimed_at> <pid> <host>
mkclaim() {
  local dir="$1/.ai/handoffs/.claims"
  mkdir -p "$dir"
  printf '{"handoff":"%s","recipient":"%s","owner":"%s","pid":%s,"host":"%s","claimed_at":"%s"}' \
    "$3" "$2" "$2" "$5" "$6" "$4" > "$dir/$2__$3.claim.json"
}

# mkquarantine <root> <cli> <handoff-name> <quarantined_at>
mkquarantine() {
  local dir="$1/.ai/handoffs/.quarantine"
  mkdir -p "$dir"
  printf '{"handoff":"%s","recipient":"%s","attempts":3,"quarantined":true,"quarantined_at":"%s"}' \
    "$3" "$2" "$4" > "$dir/$2__$3.quarantine.json"
}

# expect <want-exit> <case-name> <fixture-root> [needle-in-output]
expect() {
  local want="$1" name="$2" root="$3" needle="${4:-}"
  local out rc
  out="$(bash "$CHECK" "$root" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL: $name — expected exit $want, got $rc"
    echo "$out" | sed 's/^/      /'
    fail=$((fail + 1)); rm -rf "$root"; return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "FAIL: $name — exit $rc as expected, but output lacked: $needle"
    echo "$out" | sed 's/^/      /'
    fail=$((fail + 1)); rm -rf "$root"; return
  fi
  echo "PASS: $name"
  pass=$((pass + 1))
  rm -rf "$root"
}

# --- 1. STALL: stale heartbeat (30m old, dead same-host pid) + open Auto:yes B.
R="$(mkroot)"
mkhandoff "$R" opencode 202607121900-gates-required-check B "$OLD_LOCAL"
mkheartbeat "$R" opencode "$OLD_ISO" 999999 "$HOST"
expect 1 "stale heartbeat + open Auto:yes B -> STALL, exit 1" "$R" "STALL"

# --- 2. DOWN (idle): stale heartbeat + EMPTY queue -> informational, exit 0.
R="$(mkroot)"
mkdir -p "$R/.ai/handoffs/to-kimi/open"
mkheartbeat "$R" kimi "$OLD_ISO" 999999 "$HOST"
expect 0 "stale heartbeat + empty queue -> DOWN (idle), exit 0" "$R" "DOWN (idle)"

# --- 3. MISSING heartbeat + qualifying handoff -> STALL (missing == stale).
R="$(mkroot)"
mkhandoff "$R" kiro 202607130001-some-work A "$NOW_LOCAL"
expect 1 "missing heartbeat + open handoff -> STALL, exit 1" "$R" "STALL"

# --- 4. OK: fresh heartbeat (live pid 4, this host) + handoff under a LIVE claim.
R="$(mkroot)"
mkhandoff "$R" kimi 202607130002-claimed-work B "$OLD_LOCAL"
mkheartbeat "$R" kimi "$NOW_ISO" 4 "$HOST"
mkclaim "$R" kimi 202607130002-claimed-work "$NOW_ISO" 4 "$HOST"
expect 0 "fresh heartbeat + live-claimed handoff -> OK, exit 0" "$R" "OK"

# --- 5. WEDGED: fresh heartbeat + qualifying handoff unclaimed 30m (> window).
R="$(mkroot)"
mkhandoff "$R" claude 202607130003-ignored-work B "$OLD_LOCAL"
mkheartbeat "$R" claude "$NOW_ISO" 4 "$HOST"
expect 1 "fresh heartbeat + aged unclaimed handoff -> WEDGED, exit 1" "$R" "WEDGED"

# --- 6. Actively-QUARANTINED handoff is not unwatched work (mirrors the pane's
#        own skip): stale heartbeat + quarantined-fresh handoff -> DOWN (idle).
R="$(mkroot)"
mkhandoff "$R" kiro 202607130004-parked B "$OLD_LOCAL"
mkheartbeat "$R" kiro "$OLD_ISO" 999999 "$HOST"
mkquarantine "$R" kiro 202607130004-parked "$NOW_ISO"
expect 0 "quarantined handoff + stale heartbeat -> DOWN (idle), exit 0" "$R" "DOWN (idle)"

# --- 7. Fail-open: a GARBAGE heartbeat file reads as fresh, never as an alarm.
R="$(mkroot)"
mkhandoff "$R" kimi 202607130005-recent B "$NOW_LOCAL"
mkdir -p "$R/.ai"
echo "this is not json at all {{{" > "$R/.ai/.heartbeat-kimi.json"
expect 0 "garbage heartbeat -> fail-open (no STALL), exit 0" "$R" "OK"

# --- 8. Foreign-host heartbeat: pid unverifiable locally, time window alone
#        decides -> fresh ts + recent handoff = OK.
R="$(mkroot)"
mkhandoff "$R" claude 202607130006-remote B "$NOW_LOCAL"
mkheartbeat "$R" claude "$NOW_ISO" 999999 "SOME-OTHER-HOST"
expect 0 "foreign-host fresh heartbeat -> OK, exit 0" "$R" "OK"

# --- 9. EXPIRED quarantine (120m old) re-surfaces as qualifying: the retry is
#        due and nobody is watching -> STALL again.
R="$(mkroot)"
mkhandoff "$R" opencode 202607130007-retry-due B "$OLD_LOCAL"
mkheartbeat "$R" opencode "$OLD_ISO" 999999 "$HOST"
mkquarantine "$R" opencode 202607130007-retry-due "$VERY_OLD_ISO"
expect 1 "expired quarantine + stale heartbeat -> STALL, exit 1" "$R" "STALL"

echo ""
echo "==== fleet-health tests: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]
