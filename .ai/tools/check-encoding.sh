#!/bin/bash
# check-encoding.sh — fail if shared-state files are not UTF-8 (no BOM).
#
# Usage:
#   bash .ai/tools/check-encoding.sh <file>...
# Exit: 0 iff every file is valid UTF-8 without a BOM.
set -u

err=0

for f in "$@"; do
    if [ ! -f "$f" ]; then
        echo "check-encoding: not a file: $f" >&2
        err=1
        continue
    fi

    # Read first 4 bytes to detect BOMs.
    bom="$(head -c 4 "$f" | xxd -p 2>/dev/null || od -An -tx1 -N 4 "$f" | tr -d ' \n')"

    case "$bom" in
        # UTF-16 LE BOM
        fffe*|fffe)
            echo "check-encoding: $f is UTF-16LE (PowerShell Out-File corruption?)" >&2
            err=1
            ;;
        # UTF-16 BE BOM
        feff*)
            echo "check-encoding: $f is UTF-16BE" >&2
            err=1
            ;;
        # UTF-8 BOM
        efbbbf*)
            echo "check-encoding: $f has UTF-8 BOM" >&2
            err=1
            ;;
    esac

    # Validate the file is well-formed UTF-8. UTF-8 BOM is already rejected above,
    # but other invalid byte sequences (e.g. raw 0xFF, cp1252 mojibake leftovers)
    # must also be caught.
    if ! iconv -f UTF-8 -t UTF-8 < "$f" > /dev/null 2>&1; then
        echo "check-encoding: $f contains invalid UTF-8 byte sequences" >&2
        err=1
    fi
done

exit "$err"
