#!/bin/bash
# Hook: agentSpawn — inject activity log + git status + open handoffs
if [ -f .ai/activity/log.md ]; then
  echo '--- Recent cross-CLI activity (top of .ai/activity/log.md) ---'
  head -40 .ai/activity/log.md
  echo '--- end ---'
fi
echo ''
GIT_STATUS=$(git status --short 2>/dev/null | head -20)
if [ -n "$GIT_STATUS" ]; then
  echo '--- Git status at session start ---'
  echo "$GIT_STATUS"
  echo '--- end ---'
fi
echo ''
HANDOFFS=$(ls .ai/handoffs/to-kiro/open/*.md 2>/dev/null)
if [ -n "$HANDOFFS" ]; then
  echo '--- Open handoffs for kiro-cli ---'
  echo "$HANDOFFS"
  echo '--- end ---'
fi