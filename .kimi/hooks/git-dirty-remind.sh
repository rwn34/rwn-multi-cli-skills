#!/bin/bash
# Hook 7: Unpushed changes reminder at stop
# Remind if there are uncommitted changes beyond just the activity log
#
# ADR-0010: the activity log is the entry spool .ai/activity/entries/ (log.md
# is a generated view). Uncommitted entry files are expected mid-work and are
# excluded from this reminder alongside the legacy log.md.

if git rev-parse --git-dir > /dev/null 2>&1; then
    STATUS=$(git status --short 2>/dev/null)
    if [ -n "$STATUS" ]; then
        # Check if the only change is the activity log (spool entries or legacy log.md)
        NON_LOG=$(echo "$STATUS" | grep -v "activity/log.md" | grep -v "\.ai/activity/log\.md" | grep -v "\.ai/activity/entries/" || true)
        if [ -n "$NON_LOG" ]; then
            echo "REMINDER: Uncommitted changes detected beyond activity log. Consider committing or delegating to infra-engineer."
            echo "$STATUS"
        fi
    fi
fi
