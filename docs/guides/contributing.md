# Contributing

Thanks for considering a contribution. This guide covers the practical bits:
how to file issues, how to submit PRs, branch and commit conventions, and
where to find the coding rules.

The canonical version of this guide lives here at `docs/guides/contributing.md`.
A short `CONTRIBUTING.md` at the repo root is allowed for GitHub's auto-link
UX (see `docs/architecture/0001-root-file-exceptions.md`); if both exist, this
file wins.

## Filing issues

Use the templates under `.github/ISSUE_TEMPLATE/`:

- `bug_report.md` — reproducible problems; include environment, repro steps,
  expected vs actual.
- `feature_request.md` — proposals; include motivation and alternatives
  considered.

If neither template fits, open a blank issue and say so in the first line.

## Submitting pull requests

1. Fork / branch from `master`.
2. Make the change. Keep the diff scoped — one concern per PR.
3. Fill in `.github/pull_request_template.md` when you open the PR
   (GitHub loads it automatically). The checklist there is the minimum bar.
4. Link the issue the PR closes, if any (`Closes #123`).

Reviewers look for: scoped diff, clear motivation, tests where they apply, docs
updated alongside code.

## Branch naming

Suggested shape until the project formalizes one:

    <type>/<short-slug>

Where `<type>` is one of:

- `feat` — new user-facing capability
- `fix` — bug fix
- `chore` — tooling, deps, non-code housekeeping
- `docs` — documentation only
- `refactor` — internal change, no behavior difference

Examples: `feat/orchestrator-handoffs`, `fix/hook-root-allowlist`,
`docs/contributing-guide`.

## Commit messages

Recommended, not mandatory: [Conventional Commits](https://www.conventionalcommits.org).

    <type>(<scope>): <subject>

    <body — why, not what>

Why recommend it: it plays well with changelog tooling (release-please,
semantic-release) if the project adopts automated releases later, and the
`<type>` prefix matches the branch-naming scheme above. Not enforced — a clear
plain-English message is fine if Conventional Commits feels like overhead for
the change in front of you.

## Coding standards

Project-specific coding rules live under `docs/standards/`. Start there before
submitting non-trivial code. If a rule you need isn't written down, flag it in
the PR — that's a missing standard, not a license to freestyle.

## Code of conduct

All contributors are expected to follow `CODE_OF_CONDUCT.md` (Contributor
Covenant v2.1). Report concerns via the contact listed there.

## Working with the AI CLIs

This project is developed with three AI CLIs in the loop: **Claude Code**,
**Kimi CLI**, and **Kiro CLI**. They share state through `.ai/` and coordinate
via an orchestrator-delegation pattern — the orchestrator reads broadly and
routes mutations to specialized subagents.

If you're contributing and one of the CLIs is involved:

- Canonical AI instructions live in `.ai/instructions/`. CLI-native folders
  (`.claude/`, `.kimi/`, `.kiro/`) hold replicas generated via `.ai/sync.md`.
  Edit the canonical version, then re-sync — don't edit replicas directly.
- The cross-CLI activity log is `.ai/activity/log.md`. Each CLI prepends an
  entry after substantive work; read recent entries before starting new work.
- Root-file creation is gated by ADR-0001
  (`docs/architecture/0001-root-file-exceptions.md`). New root files require
  ADR amendment.

For the bigger picture see `.ai/README.md` and
`docs/architecture/0001-root-file-exceptions.md`.
