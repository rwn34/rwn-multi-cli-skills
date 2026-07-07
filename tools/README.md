# tools/
Dev tooling configurations.

- `playwright/` — browser automation setup
- `linters/` — eslint, prettier, etc.
- `multi-cli-install/` — single-command installer for this multi-CLI AI
  coordination framework. npm package `@rwn34/multi-cli-install` (bin:
  `multi-cli-install`). TypeScript/ESM, built with `tsc`, tested with vitest,
  Node >=18. Stamps the framework into a target project through an
  inspect → strategy → migration → patcher → installer pipeline; modes:
  `--inspect-only`, `--dry-run`, `--new`, plain install, and `--refresh-context`.