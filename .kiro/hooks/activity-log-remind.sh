#!/bin/bash
# Hook: stop — remind about activity log + unpushed changes
if [ -f .ai/activity/log.md ] && [ -z "$(find .ai/activity/log.md -mmin -60 2>/dev/null)" ]; then
  echo 'REMINDER: .ai/activity/log.md was not updated in this session. If you made substantive changes (file edits, tests run, decisions), prepend an entry before ending.'
fi
DIRTY=$(git status --short 2>/dev/null | grep -v '.ai/activity/log.md')
if [ -n "$DIRTY" ]; then
  echo 'REMINDER: Unpushed changes detected. Delegate to infra-engineer to commit and push.'
fi