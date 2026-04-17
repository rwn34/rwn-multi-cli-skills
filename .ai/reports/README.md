# `.ai/reports/` — Diagnoser output directory

Diagnoser agents (reviewer, security-auditor, e2e-tester) write structured reports
here. Reports are cross-CLI visible.

## Naming convention

    <agent>-<YYYY-MM-DD>-<slug>.md

Examples:
- `reviewer-2026-04-17-auth-module.md`
- `security-auditor-2026-04-17-dependency-scan.md`
- `e2e-tester-2026-04-17-login-flow.md`

## Who writes here

Only diagnoser agents. Executors do not write reports — they report via their
summary tool return.

## Retention

Reports accumulate. Archive old reports to `.ai/reports/archive/` when the
directory gets noisy. Same protocol as `.ai/activity/archive/`.