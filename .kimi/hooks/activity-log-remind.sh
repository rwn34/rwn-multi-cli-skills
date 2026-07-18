#!/bin/bash
# Remind to write an activity-log entry if none was written in the last 60 minutes.
#
# ADR-0010 dual-mode (transition): freshness is the newest entry file in
# .ai/activity/entries/ when the spool has any; otherwise the legacy
# .ai/activity/log.md. The fallback is dead code after the freeze; leave it so
# a pre-migration clone still works.

NEWEST=$(ls -t .ai/activity/entries/*.md 2>/dev/null | head -n 1)
STALE=""
if [ -n "$NEWEST" ]; then
    [ -z "$(find "$NEWEST" -mmin -60 2>/dev/null)" ] && STALE=1
elif [ -f .ai/activity/log.md ]; then
    [ -z "$(find .ai/activity/log.md -mmin -60 2>/dev/null)" ] && STALE=1
fi

if [ -n "$STALE" ]; then
    echo 'REMINDER: no activity-log entry written in the last 60 minutes. If you made substantive changes (file edits, tests run, decisions), write an entry file in .ai/activity/entries/ before ending.'
fi
