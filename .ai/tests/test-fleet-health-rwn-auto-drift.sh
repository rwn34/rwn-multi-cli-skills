#!/bin/bash
# test-fleet-health-rwn-auto-drift.sh — verify fleet-health.sh detects drift
# between the repo and the ~/.rwn-auto/rwn-4AI-panes embedded framework install.
#
# Run: bash .ai/tests/test-fleet-health-rwn-auto-drift.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLEET_HEALTH="$REPO_ROOT/.ai/tools/fleet-health.sh"

pass=0
fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi
}

[ -f "$FLEET_HEALTH" ] || { echo "FAIL: cannot find $FLEET_HEALTH"; exit 1; }

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Build a fake repo root with just enough structure for fleet-health.sh.
REPO_FAKE="$WORK/repo"
mkdir -p "$REPO_FAKE/tools/4ai-panes" "$REPO_FAKE/tools/multi-cli-install" "$REPO_FAKE/.ai/handoffs"
printf '%s\n' '# pane runner' > "$REPO_FAKE/tools/4ai-panes/pane-runner.ps1"
printf '%s\n' '{"version": "0.0.52"}' > "$REPO_FAKE/tools/multi-cli-install/package.json"

# Build a matching fake rwn-auto install.
AUTO_FAKE="$WORK/rwn-auto"
mkdir -p "$AUTO_FAKE/.ai" "$AUTO_FAKE/.ai/handoffs"
printf '%s\n' '# pane runner' > "$AUTO_FAKE/pane-runner.ps1"
printf '%s\n' '{"framework_version": "0.0.52"}' > "$AUTO_FAKE/.ai/.framework-version"

# Run fleet-health against the fake repo with the fake rwn-auto path.
run_health() {
    RWN_AUTO_PANES="$AUTO_FAKE" bash "$FLEET_HEALTH" "$REPO_FAKE" 2>&1
}

out=$(run_health)
rc=$?
check "in-sync rwn-auto passes" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "in-sync rwn-auto reports no drift" "$(echo "$out" | grep -qv 'FRAMEWORK:.*rwn-auto' && echo 0 || echo 1)"

# pane-runner.ps1 drift.
printf '%s\n' '# pane runner drifted' > "$AUTO_FAKE/pane-runner.ps1"
out=$(run_health)
rc=$?
check "drifted pane-runner fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "drifted pane-runner names the file" "$(echo "$out" | grep -q 'pane-runner.ps1 differs' && echo 0 || echo 1)"

# Restore pane-runner, drift version.
printf '%s\n' '# pane runner' > "$AUTO_FAKE/pane-runner.ps1"
printf '%s\n' '{"framework_version": "0.0.3"}' > "$AUTO_FAKE/.ai/.framework-version"
out=$(run_health)
rc=$?
check "drifted framework version fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "drifted framework version names mismatch" "$(echo "$out" | grep -q '.framework-version.*differs' && echo 0 || echo 1)"

echo ""
echo "==== fleet-health-rwn-auto-drift suite: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ] || exit 1
