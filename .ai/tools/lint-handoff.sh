#!/bin/bash
# lint-handoff.sh — cheap integrity checks for protocol v4 handoffs.
#
# Catches the highest-leverage sender-side errors from field report S2:
#   - Status: DONE with no evidence section (S2-1)
#   - Status: IMPOSSIBLE / NOT-A-BUG without a Why section (S2-7)
#   - Evidence: HYPOTHESIS paired with a priority label or Risk: C (S2-3)
#
# Run from repo root, or anywhere inside the repo.
set -u

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
handoffs_dir="${HANDOFFS_DIR:-$root/.ai/handoffs}"
errors=0

# Extract the first occurrence of a header line, case-insensitive on the key.
# Usage: header_value <file> <Key>
header_value() {
    sed -n "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//p" "$1" 2>/dev/null | head -1
}

# Return 0 if the file has a non-empty evidence/report/verification/output section.
has_evidence_section() {
    awk 'BEGIN{IGNORECASE=1}
         /^##[[:space:]]+(Evidence|Report|Verification|Output)/{insec=1; next}
         /^##[[:space:]]+/{insec=0}
         insec && NF {found=1}
         END {exit !found}' "$1" 2>/dev/null
}

# Return 0 if the file has a non-empty Why section (for IMPOSSIBLE/NOT-A-BUG).
has_why_section() {
    awk 'BEGIN{IGNORECASE=1}
         /^##[[:space:]]+Why/{insec=1; next}
         /^##[[:space:]]+/{insec=0}
         insec && NF {found=1}
         END {exit !found}' "$1" 2>/dev/null
}

# Return 0 if the file looks like it carries a priority label.
has_priority_label() {
    awk 'BEGIN{IGNORECASE=1; found=0}
         /^[[:space:]]*Priority[[:space:]]*:/ {found=1}
         /PRIORITY/ {found=1}
         END {exit found ? 0 : 1}' "$1" 2>/dev/null
}

# Return 0 if the body appears to assert file-level facts: mentions an existing
# repo path, a line number, git output, lockfile content, etc.  This is a cheap
# heuristic — false positives are acceptable because Observed-in is cheap to add.
looks_like_file_claim() {
    awk 'BEGIN{IGNORECASE=1; found=0}
         /^##[[:space:]]+/{insec=1; next}
         insec && /(^|[[:space:]])(src\/|lib\/|docs\/|\.ai\/|\.claude\/|\.kimi\/|\.kiro\/|\.opencode\/|infra\/|scripts\/|tools\/|tests\/|package\.json|package-lock\.json|\.gitignore|\.env|lockfile|tsconfig|webpack|Dockerfile|Makefile)[^[:space:]]*/ {found=1}
         insec && /(^|[[:space:]])git[[:space:]]/ {found=1}
         insec && /line[[:space:]]+[0-9]+/ {found=1}
         insec && /@[0-9a-f]{7,40}/ {found=1}
         END {exit found ? 0 : 1}' "$1" 2>/dev/null
}

# Return 0 if the status block has a non-empty Observed-in line.
has_observed_in() {
    [ -n "$(header_value "$1" Observed-in)" ]
}

for dir in "$handoffs_dir"/to-*/open "$handoffs_dir"/to-*/review; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        rel="${f#$handoffs_dir/}"
        status="$(header_value "$f" Status | tr '[:upper:]' '[:lower:]')"
        evidence="$(header_value "$f" Evidence | tr '[:upper:]' '[:lower:]')"
        risk="$(header_value "$f" Risk | tr '[:upper:]' '[:lower:]')"

        if [ "$status" = "done" ] && ! has_evidence_section "$f"; then
            echo "ERROR: $rel — Status: DONE but missing a non-empty Evidence/Report/Verification/Output section"
            errors=$((errors+1))
        fi

        if [ "$status" = "impossible" ] || [ "$status" = "not-a-bug" ]; then
            if ! has_why_section "$f"; then
                echo "ERROR: $rel — Status: ${status^^} requires a non-empty ## Why section with disproof"
                errors=$((errors+1))
            fi
            if ! has_evidence_section "$f"; then
                echo "ERROR: $rel — Status: ${status^^} requires a non-empty Evidence/Report/Verification/Output section"
                errors=$((errors+1))
            fi
        fi

        if [ "$evidence" = "hypothesis" ] && has_priority_label "$f"; then
            echo "ERROR: $rel — Evidence: HYPOTHESIS must not carry a priority label"
            errors=$((errors+1))
        fi

        if [ "$evidence" = "hypothesis" ] && [ "$risk" = "c" ]; then
            echo "ERROR: $rel — Evidence: HYPOTHESIS is not allowed with Risk: C"
            errors=$((errors+1))
        fi

        if [ "$status" = "open" ] && looks_like_file_claim "$f" && ! has_observed_in "$f"; then
            echo "ERROR: $rel — asserts file-level facts but missing Observed-in: <branch>@<sha>"
            errors=$((errors+1))
        fi
    done
done

# Check for the same handoff basename present in more than one state directory
# (open/review/done) under the same recipient queue. A retired handoff must be
# moved, not copied, or it keeps presenting as live work. Duplicates across
# different recipient queues (e.g. a return copied to multiple done/ queues) are
# legitimate and are not flagged.
for recipient_dir in "$handoffs_dir"/to-*; do
    [ -d "$recipient_dir" ] || continue
    unset handoff_locations
    declare -A handoff_locations
    for state_dir in "$recipient_dir"/open "$recipient_dir"/review "$recipient_dir"/done; do
        [ -d "$state_dir" ] || continue
        for f in "$state_dir"/*.md; do
            [ -f "$f" ] || continue
            rel="${f#$handoffs_dir/}"
            bn="$(basename "$f")"
            if [ -v "handoff_locations[$bn]" ]; then
                echo "ERROR: duplicate handoff basename across queue states: $bn"
                echo "  ${handoff_locations[$bn]}"
                echo "  $rel"
                errors=$((errors+1))
            else
                handoff_locations[$bn]="$rel"
            fi
        done
    done
done

if [ "$errors" -eq 0 ]; then
    echo "OK: handoff lint passed"
    exit 0
else
    echo "FAIL: $errors handoff lint error(s)"
    exit 1
fi
