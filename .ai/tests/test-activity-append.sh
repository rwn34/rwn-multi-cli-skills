#!/bin/bash
# test-activity-append.sh -- concurrency test for .ai/tools/activity-append.sh.
#
# Executes the never-run .ai/tests/concurrency-test-protocol.md §activity-log
# case: spawn N concurrent appenders at once and assert NONE clobber -- every
# entry plus the pre-existing entry survives, the header is intact, and the file
# is well-formed (exactly one `---` separator, no leftover lock/tmp files).
#
# Run: bash .ai/tests/test-activity-append.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPEND="$SCRIPT_DIR/../tools/activity-append.sh"
[ -f "$APPEND" ] || { echo "FAIL: cannot find activity-append.sh at $APPEND"; exit 1; }

N=8
pass=0
fail=0
check() { # desc, condition-already-evaluated ($1=desc, $2=0/1)
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/.ai/activity"
LOG="$WORK/.ai/activity/log.md"

cat > "$LOG" <<'EOF'
# Activity Log

Newest entries at the top.

---

## 2026-07-09 00:00 -- original
- Action: pre-existing entry that must survive
EOF

# Fire N appenders concurrently (each a distinct entry), all racing the lock.
pids=""
for i in $(seq 1 "$N"); do
    (
        cd "$WORK" || exit 1
        entry="## 2026-07-09 00:0$i -- writer-$i
- Action: concurrent append number $i"
        bash "$APPEND" "$entry" >/dev/null 2>&1
    ) &
    pids="$pids $!"
done
for p in $pids; do wait "$p"; done

# --- assertions ---
# 1. all N entries present
missing=0
for i in $(seq 1 "$N"); do
    grep -q "writer-$i" "$LOG" || missing=$((missing+1))
done
check "all $N concurrent entries survived (none clobbered)" "$([ "$missing" -eq 0 ] && echo 0 || echo 1)"

# 2. pre-existing entry survived
grep -q "original" "$LOG"; check "pre-existing entry survived" "$?"

# 3. header intact
grep -q "^# Activity Log" "$LOG"; check "header line intact" "$?"

# 4. exactly one `---` separator (no header duplication/corruption)
seps="$(grep -c '^---$' "$LOG")"
check "exactly one '---' separator (got $seps)" "$([ "$seps" -eq 1 ] && echo 0 || echo 1)"

# 5. entry count = N + 1 (all '## ' headings)
heads="$(grep -c '^## ' "$LOG")"
check "entry heading count = $((N+1)) (got $heads)" "$([ "$heads" -eq $((N+1)) ] && echo 0 || echo 1)"

# 6. no leftover lock/tmp files
leftovers="$(find "$WORK/.ai/activity" -name 'log.md.lock' -o -name 'log.md.tmp.*' 2>/dev/null | wc -l)"
check "no leftover lock/tmp files (got $leftovers)" "$([ "$leftovers" -eq 0 ] && echo 0 || echo 1)"

echo ""
echo "==== activity-append concurrency test: $pass passed, $fail failed ===="
echo "---- final log body ----"
cat "$LOG"
[ "$fail" -eq 0 ] || exit 1
