#!/bin/bash
# notify.sh — fleet Telegram notifications for the HEADLESS bash dispatch path.
#
# The bash sibling of tools/4ai-panes/notify.ps1 (which serves the interactive
# PowerShell pane-runner loop). Before this file, auto-dispatched handoffs run
# via .ai/tools/dispatch-handoffs.sh were SILENT — only the pane-runner notified.
# This closes that coverage gap so a headless pick-up / finish / failure reaches
# the owner's Telegram topic just like a live pane would.
#
# Sourceable AND runnable:
#   source .ai/tools/notify.sh            # then call fleet_notify ...
#   bash   .ai/tools/notify.sh picked <project> <handoff> <cli> <owner>
#
# Design contract (mirrors notify.ps1 exactly so the two paths interoperate):
#   - ABSOLUTELY FAIL-OPEN. A notify failure must NEVER break the caller. Every
#     path returns 0; a curl/config/throttle hiccup is swallowed.
#   - Feature OFF by default: if bot_token OR chat_id is unresolved from either
#     source, fleet_notify returns 0 without sending (no error).
#   - Config resolution: ENV VARS FIRST (RWN_TELEGRAM_BOT_TOKEN /
#     RWN_TELEGRAM_CHAT_ID / RWN_TELEGRAM_THREAD_ID), then fall back to the
#     gitignored, outside-repo file ~/.rwn-auto/notify.json (.telegram.bot_token
#     / .chat_id / .thread_id) for any piece still missing. Token never in-repo.
#   - Shared throttle file .ai/handoffs/.claims/.fleet-notify-throttle.json
#     (60s dedup on kind|project|handoff) is the SAME file notify.ps1 writes, so
#     the bash and PS paths do not double-send. Fail-open: any read/write error
#     -> SEND (never suppress-on-error).
#   - 5s curl timeout so a slow network can't stall a dispatch.
#
# ASCII-only source: the Telegram emoji are built at runtime from Unicode code
# points via printf '\U....', never embedded as literal non-ASCII bytes.

# Resolve the notify script's own directory (works sourced or executed) so the
# throttle path is stable regardless of the caller's cwd.
_FN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_FN_THROTTLE="$_FN_DIR/../handoffs/.claims/.fleet-notify-throttle.json"
_FN_THROTTLE_SECONDS=60

# Read one string from .telegram.<key> in the given notify.json. jq if present,
# else python3, else a conservative grep/sed. Never fails hard (prints "" on any
# problem). Echoes the value (or empty).
_fleet_json_get() {
    local file="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.telegram[$k] // empty' "$file" 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    t = d.get("telegram") or {}
    v = t.get(sys.argv[2])
    print(v if v is not None else "")
except Exception:
    print("")
PY
    else
        grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
            | head -1 | sed -E 's/.*"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true
    fi
}

# Resolve config into FN_BOT_TOKEN / FN_CHAT_ID / FN_THREAD_ID (env wins; the
# outside-repo notify.json fills any still-missing piece). Returns 0 when
# bot_token AND chat_id are both resolved (feature on), 1 otherwise. Never throws.
_fleet_resolve_config() {
    FN_BOT_TOKEN="${RWN_TELEGRAM_BOT_TOKEN:-}"
    FN_CHAT_ID="${RWN_TELEGRAM_CHAT_ID:-}"
    FN_THREAD_ID="${RWN_TELEGRAM_THREAD_ID:-}"

    if [ -z "$FN_BOT_TOKEN" ] || [ -z "$FN_CHAT_ID" ] || [ -z "$FN_THREAD_ID" ]; then
        local cfg="$HOME/.rwn-auto/notify.json"
        if [ -f "$cfg" ]; then
            [ -z "$FN_BOT_TOKEN" ] && FN_BOT_TOKEN="$(_fleet_json_get "$cfg" bot_token)"
            [ -z "$FN_CHAT_ID" ]   && FN_CHAT_ID="$(_fleet_json_get "$cfg" chat_id)"
            [ -z "$FN_THREAD_ID" ] && FN_THREAD_ID="$(_fleet_json_get "$cfg" thread_id)"
        fi
    fi

    [ -n "$FN_BOT_TOKEN" ] && [ -n "$FN_CHAT_ID" ]
}

# Throttle decision via python3 (read-modify-write of the shared JSON map). Prints
# SUPPRESS (already sent within the window) or SEND. FULLY fail-open: a missing
# file, corrupt JSON, or any exception -> SEND (never suppress-on-error). On SEND
# it records a fresh UTC timestamp and prunes entries older than 5 windows, writing
# atomically (temp + os.replace, compact JSON) to mirror notify.ps1's writer.
_fleet_throttle_py() {
    python3 - "$1" "$2" "$3" "$4" <<'PY' 2>/dev/null || echo SEND
import json, os, sys, datetime
path, key, window, now_iso = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

def parse(ts):
    return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc)

now = parse(now_iso)
m = {}
try:
    with open(path) as f:
        raw = f.read().strip()
    if raw:
        for k, v in json.loads(raw).items():
            try:
                m[k] = parse(v)
            except Exception:
                pass
except FileNotFoundError:
    m = {}
except Exception:
    # Corrupt/unreadable -> fail-open SEND (do not record).
    print("SEND")
    sys.exit(0)

last = m.get(key)
if last and (now - last).total_seconds() < window:
    print("SUPPRESS")
    sys.exit(0)

# SEND: record + prune + write atomically (write errors are swallowed).
m[key] = now
cutoff = now - datetime.timedelta(seconds=5 * window)
out = {k: v.strftime("%Y-%m-%dT%H:%M:%SZ") for k, v in m.items() if v >= cutoff}
try:
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    os.replace(tmp, path)
except Exception:
    pass
print("SEND")
PY
}

# Decide whether a notification keyed "$1" is throttled. Returns 0 = SUPPRESS,
# 1 = SEND. Window <= 0 disables throttling (always SEND). Requires python3 for
# the shared cross-process map; without it we fail-open (always SEND) rather than
# risk suppressing a real alert. Never throws.
_fleet_throttled() {
    local key="$1"
    [ "$_FN_THROTTLE_SECONDS" -le 0 ] && return 1
    command -v python3 >/dev/null 2>&1 || return 1
    local now_iso decision
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    [ -n "$now_iso" ] || return 1
    decision="$(_fleet_throttle_py "$_FN_THROTTLE" "$key" "$_FN_THROTTLE_SECONDS" "$now_iso")"
    [ "$decision" = "SUPPRESS" ] && return 0
    return 1
}

# Post a fleet event to the configured Telegram topic. Fail-open no-op if the
# feature is off (unresolved token/chat_id) or throttled. Always returns 0.
#   $1 kind    picked | done | alert
#   $2 project short project name (repo basename)
#   $3 handoff handoff basename (no .md)
#   $4 cli     recipient CLI key (claude|kimi|kiro|opencode) — reserved/context
#   $5 owner   that CLI's identity string (e.g. claude-auto, kiro-cli)
fleet_notify() {
    local kind="$1" project="$2" handoff="$3" cli="$4" owner="$5"

    _fleet_resolve_config || return 0
    [ -n "$FN_BOT_TOKEN" ] && [ -n "$FN_CHAT_ID" ] || return 0

    # Throttle: suppress an identical kind|project|handoff sent within the window.
    if _fleet_throttled "$kind|$project|$handoff"; then
        return 0
    fi

    # Emoji built at runtime from their UTF-8 byte sequences (printf '\xHH') so
    # this source stays ASCII-only. MSYS bash printf lacks the '\U' code-point
    # escape, so the bytes are spelled out directly:
    #   picked = robot   U+1F916 -> F0 9F A4 96
    #   done   = check   U+2705  -> E2 9C 85
    #   alert  = warning U+26A0  -> E2 9A A0
    # Two-line Markdown: *bold* project leads line 1; owner + `code` handoff line 2.
    local emoji text nl
    nl=$'\n'
    case "$kind" in
        picked)
            emoji="$(printf '\xf0\x9f\xa4\x96')"
            text="$emoji *$project*$nl$owner picked up \`$handoff\`" ;;
        done)
            emoji="$(printf '\xe2\x9c\x85')"
            text="$emoji *$project*$nl$owner finished \`$handoff\`" ;;
        alert)
            emoji="$(printf '\xe2\x9a\xa0')"
            text="$emoji *$project* -- needs a human$nl$owner ALERT on \`$handoff\`" ;;
        *)
            emoji=""
            text="*$project*$nl$owner \`$handoff\`" ;;
    esac

    # Build curl argv as an array so newlines/special chars in the payload are
    # never re-split. --data-urlencode form-encodes each field (Telegram accepts
    # application/x-www-form-urlencoded on sendMessage).
    local -a curl_args
    curl_args=(-s --max-time 5
        --data-urlencode "chat_id=$FN_CHAT_ID"
        --data-urlencode "text=$text"
        --data-urlencode "parse_mode=Markdown")
    [ -n "$FN_THREAD_ID" ] && curl_args+=(--data-urlencode "message_thread_id=$FN_THREAD_ID")
    curl_args+=("https://api.telegram.org/bot$FN_BOT_TOKEN/sendMessage")

    # Any curl failure (incl. curl missing) -> return 0 silently. Fail-open.
    curl "${curl_args[@]}" >/dev/null 2>&1 || true
    return 0
}

# Runnable form: `bash notify.sh <kind> <project> <handoff> <cli> <owner>`.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    fleet_notify "$@"
fi
