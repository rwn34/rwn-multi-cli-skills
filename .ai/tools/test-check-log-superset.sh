#!/usr/bin/env bash
# test-check-log-superset.sh — prove check-log-superset.sh actually BITES.
# Run from repo root. Exit 0 if all cases pass.
#
# Hermetic: each case builds a throwaway git repo so "origin/main" is controllable.
# Nothing reads or mutates the live activity log.

set -u

ROOT="${1:-$PWD}"
CHECK="$ROOT/.ai/tools/check-log-superset.sh"

pass=0
fail=0

[ -r "$CHECK" ] || { echo "FAIL: checker not found: $CHECK"; exit 1; }
[ -x "$CHECK" ] || chmod +x "$CHECK"

# Build a minimal repo with an origin/main activity log. Echoes repo path.
mkrepo() {
    local d
    d="$(mktemp -d)"
    git -C "$d" init -q -b main 2>/dev/null
    git -C "$d" config user.email "test@example.com"
    git -C "$d" config user.name "test"
    mkdir -p "$d/.ai/activity"

    cat > "$d/.ai/activity/log.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) — claude-code
- Action: main entry A

## 2026-07-17 09:00 (UTC+7) — kimi-cli
- Action: main entry B

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: duplicated legitimately

EOF
    git -C "$d" add . >/dev/null 2>&1
    git -C "$d" commit -q -m "init" --no-verify >/dev/null 2>&1

    # origin/main needs to resolve inside the repo itself for the checker.
    git -C "$d" remote add origin "$d" 2>/dev/null || true
    git -C "$d" config remote.origin.fetch "+refs/heads/main:refs/remotes/origin/main" 2>/dev/null || true
    git -C "$d" fetch origin -q 2>/dev/null || true

    printf '%s' "$d"
}

# expect <want-exit> <case-name> <repo> [needle]
expect() {
    local want="$1" name="$2" d="$3" needle="${4:-}"
    local out rc
    out="$(cd "$d" && bash "$CHECK" .ai/activity/log.md 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
        echo "FAIL: $name — expected exit $want, got $rc"
        echo "$out" | sed 's/^/      /'
        fail=$((fail + 1)); return
    fi
    if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "FAIL: $name — exit $rc as expected, but output lacked: $needle"
        echo "$out" | sed 's/^/      /'
        fail=$((fail + 1)); return
    fi
    echo "PASS: $name"
    pass=$((pass + 1))
}

# expect_file <want-exit> <case-name> <repo> <candidate-file> [needle]
expect_file() {
    local want="$1" name="$2" d="$3" cand="$4" needle="${5:-}"
    local out rc
    out="$(cd "$d" && bash "$CHECK" "$cand" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
        echo "FAIL: $name — expected exit $want, got $rc"
        echo "$out" | sed 's/^/      /'
        fail=$((fail + 1)); return
    fi
    if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "FAIL: $name — exit $rc as expected, but output lacked: $needle"
        echo "$out" | sed 's/^/      /'
        fail=$((fail + 1)); return
    fi
    echo "PASS: $name"
    pass=$((pass + 1))
}

echo "== baseline: candidate identical to main is GREEN =="
d="$(mkrepo)"
expect 0 "identical to main passes" "$d"
rm -rf "$d"

echo "== PR #107 repro: candidate superset of main but subset of working tree =="
d="$(mkrepo)"
# Candidate is the main blob contents (would land as 60/0 additions-only).
cp "$d/.ai/activity/log.md" "$d/candidate.md"
# Working tree gains an uncommitted entry.
cat > "$d/.ai/activity/log.md" <<'EOF'
## 2026-07-17 11:00 (UTC+7) — opencode
- Action: uncommitted on disk only

## 2026-07-17 10:00 (UTC+7) — claude-code
- Action: main entry A

## 2026-07-17 09:00 (UTC+7) — kimi-cli
- Action: main entry B

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: duplicated legitimately

EOF
expect_file 1 "PR #107 repro fails (superset of main, subset of disk)" "$d" "$d/candidate.md" "working tree"
rm -rf "$d"

echo "== candidate drops an entry that exists in main =="
d="$(mkrepo)"
cat > "$d/.ai/activity/log.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) — claude-code
- Action: main entry A

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: duplicated legitimately

EOF
expect 1 "missing main entry is caught" "$d" "origin/main"
rm -rf "$d"

echo "== candidate preserves entries from a KEEP file =="
d="$(mkrepo)"
cat > "$d/.ai/activity/log.md.KEEP-202607171200" <<'EOF'
## 2026-07-17 12:00 (UTC+7) — kiro-cli
- Action: rescued from KEEP

EOF
expect 1 "missing KEEP entry is caught" "$d" "KEEP-202607171200"
rm -rf "$d"

echo "== duplicate header in source does not read as loss =="
d="$(mkrepo)"
# main has 2026-07-15 07:07 once. Add a second legitimate duplicate in working tree.
cat > "$d/.ai/activity/log.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) — claude-code
- Action: main entry A

## 2026-07-17 09:00 (UTC+7) — kimi-cli
- Action: main entry B

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: first duplicate

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: second duplicate

EOF
expect 0 "duplicate source header with single candidate header passes" "$d"
rm -rf "$d"

echo "== additions are always fine (candidate strictly superset) =="
d="$(mkrepo)"
cat > "$d/.ai/activity/log.md" <<'EOF'
## 2026-07-17 15:12 (UTC+7) — kimi-cli
- Action: new entry on disk

## 2026-07-17 11:00 (UTC+7) — opencode
- Action: another new entry

## 2026-07-17 10:00 (UTC+7) — claude-code
- Action: main entry A

## 2026-07-17 09:00 (UTC+7) — kimi-cli
- Action: main entry B

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: duplicated legitimately

EOF
expect 0 "candidate with extra entries passes" "$d"
rm -rf "$d"

echo "== missing backup entry alongside working-tree entry =="
d="$(mkrepo)"
cat > "$d/.ai/activity/log.md.bak" <<'EOF'
## 2026-07-16 14:00 (UTC+7) — opencode
- Action: only in bak

EOF
cat > "$d/.ai/activity/log.md" <<'EOF'
## 2026-07-17 10:00 (UTC+7) — claude-code
- Action: main entry A

## 2026-07-17 09:00 (UTC+7) — kimi-cli
- Action: main entry B

## 2026-07-15 07:07 (UTC+7) — kimi-cli
- Action: duplicated legitimately

EOF
expect 1 "missing backup entry is caught" "$d" "log.md.bak"
rm -rf "$d"

echo "== CLI ergonomics =="
out="$(bash "$CHECK" 2>&1)"; rc=$?
if [ "$rc" -ne 2 ]; then
    echo "FAIL: no argument -> expected exit 2, got $rc"
    fail=$((fail + 1))
else
    echo "PASS: no argument exits 2 with usage"
    pass=$((pass + 1))
fi

out="$(bash "$CHECK" /nonexistent/log.md 2>&1)"; rc=$?
if [ "$rc" -ne 2 ]; then
    echo "FAIL: missing file -> expected exit 2, got $rc"
    fail=$((fail + 1))
else
    echo "PASS: missing file exits 2"
    pass=$((pass + 1))
fi

echo
echo "=============================================="
echo "RESULT: $pass passed, $fail failed"
echo "=============================================="
[ "$fail" -eq 0 ]
