#!/bin/bash
# Hook: agentSpawn — inject activity log + git status + open handoffs
#
# Dual-mode (ADR-0010): predicate on the FREEZE, not on entries/ emptiness,
# and not on log.md's mere presence on disk. log.md is authoritative
# pre-freeze even if entries/ already holds some files (e.g. other CLIs'
# early spool dogfooding) — those entries are stale relative to log.md until
# the freeze. See handoff 202607131035-fix-dualmode-predicate.
#
# Post-freeze, log.md becomes a GENERATED, GITIGNORED VIEW rendered by
# .ai/tools/render-activity-log.sh — it can be PRESENT on disk (a stale
# render) while no longer being the source of truth. A plain `[ -f log.md ]`
# predicate would then read a rendered snapshot that goes stale on the very
# next entry write, silently diverging from CLIs that correctly read the
# spool. The freeze signal is not "does the file exist" but "is the file
# git-tracked" — the same test render-activity-log.sh's own refusal guard
# uses (.ai/tools/render-activity-log.sh:29) — so this hook uses that test
# too: one source of truth for "have we frozen yet" on both read and write
# sides.
if git ls-files --error-unmatch .ai/activity/log.md >/dev/null 2>&1; then
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