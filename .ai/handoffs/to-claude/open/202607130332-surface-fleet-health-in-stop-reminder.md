# Surface fleet-health STALL/WEDGED in stop-reminder.sh (ADR-0005 reroute)
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 10:33
Auto: yes
Risk: A
Base: origin/master

## Why this is with you

The pane-liveness watchdog handoff (`to-kimi/202607130251-pane-liveness-watchdog`,
PR #77) included a `stop-reminder.sh` surfacing block — one line per unwatched
pane at session end, STALL/WEDGED loud, DOWN (idle) deliberately silent (it
would nag every turn end and train the reader to ignore the hook). The block is
written and smoke-tested, but the ADR-0005 pre-commit gate bars kimi-cli from
committing `.claude/**` — this is your territory, so the commit is yours.

## What to do

1. Apply the patch below verbatim (it is `git apply`-clean against master's
   `.claude/hooks/stop-reminder.sh` at 1ca3f03, and inserts Reminder 1c between
   the open-queues block and the uncommitted-changes block — same spot the
   smoke test ran).
2. Verify by execution: `bash .claude/hooks/stop-reminder.sh` must exit 0 and,
   while the fleet still lacks heartbeat files (pre-relaunch), print the
   `ALERT: fleet pane liveness` block listing all four panes STALL. Once the
   panes respawn on the heartbeat runner and queues drain, the block must
   disappear (no alarm on an all-OK fleet). DOWN (idle) panes must never
   appear in it.
3. Commit on master per your records-commit convention (or a tiny PR if you
   prefer the gate to see it), then self-retire this handoff.

Depends on PR #77 (fleet-health.sh must exist on master for the block to fire;
the `[ -f ]` guard makes the hook silent and harmless before it lands, so the
two may merge in either order).

## The patch (exact, tested)

```diff
diff --git a/.claude/hooks/stop-reminder.sh b/.claude/hooks/stop-reminder.sh
index 4a7009e..c0c5730 100644
--- a/.claude/hooks/stop-reminder.sh
+++ b/.claude/hooks/stop-reminder.sh
@@ -29,6 +29,22 @@ if [ -n "$queue_summary" ]; then
     fi
 fi
 
+# --- Reminder 1c: fleet pane liveness (fleet-health.sh dead-man's switch) ---
+# One line per pane whose queue is unwatched. STALL/WEDGED are loud — a human
+# must relaunch/unwedge the pane. DOWN (idle) is deliberately NOT surfaced
+# here: an idle pane down for days would nag at every turn end and train the
+# reader to ignore the hook; it stays visible on demand via fleet-health.sh.
+if [ -f .ai/tools/fleet-health.sh ]; then
+    health_out=$(bash .ai/tools/fleet-health.sh 2>/dev/null)
+    pane_alerts=$(printf '%s\n' "$health_out" | grep -E '\|\s*(STALL|WEDGED)' || true)
+    if [ -n "$pane_alerts" ]; then
+        echo ""
+        echo "ALERT: fleet pane liveness — a handoff queue is unwatched:"
+        printf '%s\n' "$pane_alerts"
+        echo "Run: bash .ai/tools/fleet-health.sh  (detection only — pane restarts stay with the owner)."
+    fi
+fi
+
 # --- Reminder 2: uncommitted changes beyond the activity log ---
 # Filter out the activity log line from git status; if anything else is uncommitted, remind.
 unpushed=$(git status --short 2>/dev/null | grep -vE '\.ai/activity/log\.md$')
```

## Smoke-test evidence (kimi-cli, 2026-07-13 10:19, live repo)

With the patch applied in the kimi-watchdog worktree,
`bash .claude/hooks/stop-reminder.sh` exited 0 and printed, after the usual
open-queues reminder:

```
ALERT: fleet pane liveness — a handoff queue is unwatched:
claude    | missing                        | 2     | STALL — 2 qualifying handoff(s), nobody watching
kimi      | missing                        | 2     | STALL — 2 qualifying handoff(s), nobody watching
kiro      | missing                        | 3     | STALL — 3 qualifying handoff(s), nobody watching
opencode  | missing                        | 1     | STALL — 1 qualifying handoff(s), nobody watching
Run: bash .ai/tools/fleet-health.sh  (detection only — pane restarts stay with the owner).
```
