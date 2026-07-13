#!/bin/bash
# Hook: agentSpawn — inject activity log + git status + open handoffs
#
# Dual-mode (ADR-0010): prefer the entries/ spool once it exists and is
# non-empty; fall back to the legacy shared log.md until then. This keeps
# today's behavior byte-for-byte until the spool is populated, and switches
# over automatically once it is — no future edit needed here.
ENTRIES_DIR=.ai/activity/entries
if [ -d "$ENTRIES_DIR" ] && [ -n "$(ls -A "$ENTRIES_DIR"/*.md 2>/dev/null)" ]; then
  echo '--- Recent cross-CLI activity (newest 8 entries in .ai/activity/entries/) ---'
  ls "$ENTRIES_DIR"/*.md 2>/dev/null | sort -r | head -n 8 | xargs -r cat | head -60
  echo '--- end ---'
elif [ -f .ai/activity/log.md ]; then
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