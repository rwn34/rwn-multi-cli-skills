#!/bin/bash
# Hook: agentSpawn — inject activity log + git status + open handoffs
#
# Dual-mode (ADR-0010): predicate on the FREEZE, not on entries/ emptiness.
# log.md is authoritative pre-freeze even if entries/ already holds some
# files (e.g. other CLIs' early spool dogfooding) — those entries are stale
# relative to log.md until log.md is git-mv'd to archive (the freeze). Once
# log.md is gone, entries/ becomes authoritative automatically — no future
# edit needed here. See handoff 202607131035-fix-dualmode-predicate.
if [ -f .ai/activity/log.md ]; then
  echo '--- Recent cross-CLI activity (top of .ai/activity/log.md) ---'
  head -40 .ai/activity/log.md
  echo '--- end ---'
else
  ENTRIES_DIR=.ai/activity/entries
  echo '--- Recent cross-CLI activity (newest 8 entries in .ai/activity/entries/) ---'
  ls "$ENTRIES_DIR"/*.md 2>/dev/null | sort -r | head -n 8 | xargs -r cat | head -60
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