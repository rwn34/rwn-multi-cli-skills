# Update stop-reminder.sh to surface review/ handoff queues
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-15 18:38
Auto: yes
Risk: A
Base: origin/master

<!--
Filename: 202607151137-update-stop-reminder-for-review-queues.md (UTC)
This change touches .claude/hooks/ (Claude's territory) so it is routed to you.
Owner previously approved git apply for the related 202607130332 patch.
-->

## Goal

Update `.claude/hooks/stop-reminder.sh` so the end-of-session reminder counts and
surfaces both `open/` and `review/` handoff queues. This matches the new
multi-stage review pipeline implemented in commit b1526b1.

## Why this is with you

The file lives under `.claude/hooks/` — cross-CLI territory per ADR-0005. The
kimi-cli commit for the rest of the review pipeline (pane-runner, dispatcher,
fleet-health, reconciler, docs) was intentionally committed without this file.

## What to do

1. Apply the patch below verbatim to `.claude/hooks/stop-reminder.sh`.
   It applies clean against the current file at `c0c5730`.
2. Verify: `bash .claude/hooks/stop-reminder.sh` exits 0.
3. If you have an open handoff queue, confirm the reminder now prints both
   `open:N` and `review:N` counts.
4. Commit the change on master, then self-retire this handoff.

## The patch (exact)

```diff
diff --git a/.claude/hooks/stop-reminder.sh b/.claude/hooks/stop-reminder.sh
index c0c5730..0793cc7 100644
--- a/.claude/hooks/stop-reminder.sh
+++ b/.claude/hooks/stop-reminder.sh
@@ -9,19 +9,23 @@ if [ -f .ai/activity/log.md ] && [ -z "$(find .ai/activity/log.md -mmin -60 2>/d
     echo "REMINDER: .ai/activity/log.md was not updated in this session. If you made substantive changes (file edits, tests run, decisions), prepend an entry before ending."
 fi
 
-# --- Reminder 1b: open handoff queues (P4 polling — every session end is a poll point) ---
+# --- Reminder 1b: open + review handoff queues (P4 polling — every session end is a poll point) ---
 # Per-queue counts driven by the to-* glob (never a hardcoded CLI list).
 queue_summary=""
-for q in .ai/handoffs/to-*/open; do
-    [ -d "$q" ] || continue
-    n=$(ls "$q"/*.md 2>/dev/null | wc -l | tr -d ' ')
-    [ "$n" -gt 0 ] && queue_summary="${queue_summary}  $(basename "$(dirname "$q")"): $n open"$'\n'
+for to_dir in .ai/handoffs/to-*; do
+    [ -d "$to_dir" ] || continue
+    open_n=$(ls "$to_dir"/open/*.md 2>/dev/null | wc -l | tr -d ' ')
+    review_n=$(ls "$to_dir"/review/*.md 2>/dev/null | wc -l | tr -d ' ')
+    parts=""
+    [ "$open_n" -gt 0 ] && parts="${parts}open:$open_n "
+    [ "$review_n" -gt 0 ] && parts="${parts}review:$review_n "
+    [ -n "$parts" ] && queue_summary="${queue_summary}  $(basename "$to_dir"): $parts"$'\n'
 done
 if [ -n "$queue_summary" ]; then
     echo ""
-    echo "REMINDER: open handoffs by queue:"
+    echo "REMINDER: handoffs by queue:"
     printf '%s' "$queue_summary"
-    auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' .ai/handoffs/to-*/open/*.md 2>/dev/null)
+    auto_pending=$(grep -liE '^Auto:[[:space:]]*yes' .ai/handoffs/to-*/open/*.md .ai/handoffs/to-*/review/*.md 2>/dev/null)
     if [ -n "$auto_pending" ]; then
         echo "Auto-dispatchable (Risk A/B will launch, Risk C will HOLD):"
         echo "$auto_pending" | head -5
```

## Verification

- [ ] `bash .claude/hooks/stop-reminder.sh` returns exit 0.
- [ ] With at least one `.md` handoff in any `to-*/review/` directory, the
      reminder prints `review:N` for that queue.

## Next step / future note

Once applied, the stop-reminder hook will stay in sync with the pane-runner and
dispatcher review-queue support landed in b1526b1. Future queue additions should
update this hook, the dispatcher, and fleet-health together.

## Activity log template

    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Applied stop-reminder.sh patch per handoff 202607151137-update-stop-reminder-for-review-queues.md to surface review/ queues.
    - Files: .claude/hooks/stop-reminder.sh
    - Decisions: —

## Report back with

- (a) Confirmation that `bash .claude/hooks/stop-reminder.sh` exits 0.
- (b) A one-line sample of the updated reminder output when a review/ queue is non-empty.

## When complete (protocol v3)

Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-claude/done/` yourself once the patch is applied, verified, and
committed. If blocked, leave the file in `open/`, change Status to `BLOCKED`, and
append a `## Blocker` section with verbatim error messages.
