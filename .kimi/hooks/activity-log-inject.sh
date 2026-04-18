#!/bin/bash
# Inject top of .ai/activity/log.md into context at turn start

if [ -f .ai/activity/log.md ]; then
    echo '--- Recent cross-CLI activity (top of .ai/activity/log.md) ---'
    head -40 .ai/activity/log.md
    echo '--- end ---'
fi
