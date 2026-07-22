## 2026-07-23 01:30 (UTC+7) - kimi-cockpit
- Action: Deleted all remaining unmerged executor worktree branches (`exec/*`) from local and remote after recording their tip SHAs; confirmed zero open PRs, issues, handoffs, or stray worktrees.
- Files: -
- Decisions: Treated stale exec branches as obsolete after 1-2 weeks of framework iteration; tip SHAs logged to `/tmp/unmerged-exec-branches.txt` before deletion so commits remain reachable via reflog if needed.
