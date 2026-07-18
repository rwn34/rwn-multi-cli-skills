#!/bin/bash
# Inject recent cross-CLI activity into context at turn start.
#
# ADR-0010 dual-mode (transition): prefer the entry spool — newest 8 entry
# files from .ai/activity/entries/ (reverse filename order == newest first,
# filenames are fixed-width UTC). Fall back to the legacy head of
# .ai/activity/log.md while the pre-spool log still exists. The fallback is
# dead code after the freeze; leave it so a pre-migration clone still works.

if ls .ai/activity/entries/*.md >/dev/null 2>&1; then
    echo '--- Recent cross-CLI activity (newest entries from .ai/activity/entries/) ---'
    n=0
    for f in $(ls .ai/activity/entries/*.md | LC_ALL=C sort -r); do
        cat "$f"
        echo
        n=$((n + 1))
        [ "$n" -ge 8 ] && break
    done | head -60
    echo '--- end ---'
elif [ -f .ai/activity/log.md ]; then
    echo '--- Recent cross-CLI activity (top of .ai/activity/log.md) ---'
    head -40 .ai/activity/log.md
    echo '--- end ---'
fi
