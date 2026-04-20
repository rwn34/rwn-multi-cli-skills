# Review proposed project/ directory structure
Status: DONE
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 20:46

## Goal
Review the proposed `project/` directory structure and give your opinion. The user
wants a neat structure where all project-related files live under `project/`, with
framework dirs (.ai/, .kiro/, .kimi/, .claude/) staying outside. Write feedback to
`.ai/research/project-structure-feedback-kimi.md`.

## The proposed structure

```
rwn-multi-cli-skills/
├── .ai/                          ← multi-CLI framework (outside)
├── .kiro/ .kimi/ .claude/        ← CLI configs (outside)
├── .git/
├── AGENTS.md, CLAUDE.md, README.md
│
└── project/                      ← everything project-related
    ├── src/                      ← source code (app/, lib/, types/)
    ├── tests/                    ← all tests (unit/, integration/, e2e/)
    ├── docs/                     ← documentation (architecture/, api/, guides/)
    ├── assets/                   ← static assets (images/, fonts/, templates/)
    ├── scripts/                  ← automation scripts
    ├── tools/                    ← dev tooling (playwright/, docker/, linters/)
    ├── infra/                    ← IaC (terraform/, k8s/, ci/)
    ├── migrations/               ← database migrations (versions/, seeds/)
    ├── config/                   ← app configuration
    └── vendor/                   ← vendored dependencies
```

Key benefits:
- One boundary: project/ = the product, outside = tooling
- Simplifies agent write scopes (e.g. coder → project/src/**, tester → project/tests/**)
- Tools (Playwright, Docker, linters) under project/tools/, not scattered
- Infra separate from app code

## What to produce
Write `.ai/research/project-structure-feedback-kimi.md` with:
1. What you agree with
2. What you'd change (with reasoning)
3. Any gaps or risks
4. How this affects Kimi's agent configs (path scopes)
5. Alternative concepts if you have a better idea

Keep it concise.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Reviewed project/ structure proposal per handoff 011 from kiro-cli.
    - Files: .ai/research/project-structure-feedback-kimi.md (new)
    - Decisions: <key feedback>

## When complete
User reads all feedback and decides.