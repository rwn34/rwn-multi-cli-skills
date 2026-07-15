# Surface fleet-health STALL/WEDGED in stop-reminder.sh (ADR-0005 reroute)
Status: DONE
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 10:33
Auto: yes
Risk: A
Base: origin/master
Done: 2026-07-15 10:05

## Resolution
Patch applied by kimi-cli with owner approval. Verified `bash .claude/hooks/stop-reminder.sh` exits 0; fleet-health.sh guard silent when panes healthy/idle (DOWN intentionally not surfaced). Committed on master.

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

## Blocker

**claude-code, 2026-07-14 02:41 — BLOCKED. This is owner-apply-only work; no CLI
can execute it, me included. The reroute reasoning was right but the destination
was wrong.**

Kimi routed this to me because ADR-0005's pre-commit gate bars kimi-cli from
*committing* `.claude/**`. True — but the binding constraint is one layer deeper
and it also applies to me: **`.claude/hooks/` is the enforcement layer and is
owner-apply-only.** My `Edit` on `.claude/hooks/stop-reminder.sh` was refused at
the tool layer, verbatim:

```
PreToolUse:Edit hook error: [bash .claude/hooks/pretool-write-edit.sh]:
BLOCKED by hook: .claude/hooks/ is the enforcement layer — its guard scripts are
never edited via a tool (Write/Edit or a bash write-command), only owner-applied.
This is the self-modification door and it stays shut.
```

That is **Rule 1.5** in `.claude/hooks/lib/path-policy.sh:146-149`, and the
comment above it (lines 141-145) forecloses every workaround I might reach for:

```
# owner-apply-ONLY: no agent (not even Claude) edits its own guards via any
# tool (Write/Edit OR a bash write-command). The Claude harness already
# refuses Write/Edit here; stating it in the shared classifier closes the SAME
# door for the Bash surface (the side-door this fix exists to shut) and for any
# subagent Write/Edit the harness may not cover — one rule, both surfaces.
```

So: not a Write/Edit from me, not a `bash`-surface write, not a delegated
subagent. `classify_path` is shared by both hook surfaces; all three doors are
the same door. Routing this to any other CLI would fail identically — the block
is on the *path*, not on the *actor*. **The patch has to be applied by the owner
by hand.** It is unchanged and still correct; it is reproduced verbatim in "The
patch (exact, tested)" above.

### Second finding: the promised verification cannot fire yet

Step 2 asks me to confirm the hook prints the four-pane STALL block.
**`.ai/tools/fleet-health.sh` does not exist in this worktree** (`Glob
.ai/tools/fleet-health.sh` → no files) — PR #77 has not landed here. The
`[ -f ]` guard therefore makes the new block correctly silent, exactly as the
handoff predicted. Consequence for the owner: after applying the patch, the
expected output is **nothing new** at session end, not the STALL block. The
STALL block only appears once #77 merges and `fleet-health.sh` is on disk. Do
not read the silence as a failed patch.

### What the owner needs to do

1. Apply the diff above by hand to `.claude/hooks/stop-reminder.sh` (it inserts
   Reminder 1c between the open-queues block and the uncommitted-changes block;
   it applies clean against the current file, which is still at the pre-patch
   shape).
2. `bash .claude/hooks/stop-reminder.sh` → must exit 0. Pre-#77 it prints no
   fleet block (see above); post-#77 with panes down it prints the STALL lines.
3. Ping me and I will commit it (committing `.claude/**` is mine; only the *edit*
   is gated) and self-retire this handoff.

Leaving this in `open/` per protocol v3 step 4 — a BLOCKED handoff stays visible.
Re-dispatching it will not help: an auto-dispatched Claude hits the identical
guard. It needs a human hand, not another poll.
