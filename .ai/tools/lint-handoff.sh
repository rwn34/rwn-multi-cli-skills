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
    done
done

if [ "$errors" -eq 0 ]; then
    echo "OK: handoff lint passed"
    exit 0
else
    echo "FAIL: $errors handoff lint error(s)"
    exit 1
fi
