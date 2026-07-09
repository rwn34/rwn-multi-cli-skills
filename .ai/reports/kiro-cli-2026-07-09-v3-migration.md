# Kiro v3 migration — report

- **Date:** 2026-07-09
- **Author:** kiro-cli (orchestrator)
- **Handoff:** `.ai/handoffs/to-kiro/open/202607091430-migrate-to-v3.md`
- **Status:** PARTIAL — v3 config delivered (additive); **live enforcement
  validation BLOCKED** (see §4). Two findings change the ADR-0006 merge
  decision (§2, §5).

---

## 0. TL;DR

Migrated Kiro's config to the v3 model **additively** (v2 kept as fallback).
But the v3 docs (read fresh, not from memory) surface two facts that break the
handoff's core premise:

1. **`permissions.yaml` cannot be a repo file.** v3 loads it ONLY from
   user/workspace scope *outside* the repo. A committed `.kiro/permissions.yaml`
   is dead text. The repo-committable enforcement path is the **agent-markdown
   `permissions` block** — which is what I delivered instead.
2. **v3 has no headless mode.** The legacy non-TUI mode is explicitly
   unsupported under the v3 engine ("Use the TUI"). So
   `kiro-cli --v3 chat --no-interactive` — the exact command Step 4 asks me to
   run *and* the command the dispatcher/Selector pin — **cannot run today.**
   This directly undercuts ADR-0006 Decision 1's rationale ("v3 gives Kiro real
   headless enforcement").

I could not run Step 4 (I have no shell as orchestrator, AND v3 non-TUI is
unsupported regardless). Live validation must be owner-run in a v3 TUI session;
exact probes are in §4.

---

## 1. Files created (all additive — nothing deleted)

| Path | Purpose | Lives / enforced where |
|---|---|---|
| `.kiro/agents/orchestrator.md` | v3 Markdown agent config with `permissions.rules` block encoding the boundaries | **Repo-committed**, enforced when workspace trusted. THE portable v3 enforcement layer. |
| `.kiro/hooks/guards.json` | v3 standalone hooks (`version: v1`), PascalCase triggers, reusing the existing pure-bash `.sh` guards via `action.command` | Repo-committed, defense-in-depth |
| `.ai/config-snippets/kiro-v3-permissions.yaml` | TEMPLATE the **owner** installs to `~/.kiro/settings/permissions.yaml` (cannot be repo-injected; see §2) | User scope, owner-installed |

**Kept as v2 fallback (untouched):** `.kiro/agents/*.json` (incl.
`orchestrator.json`), `.kiro/hooks/*.sh` (all 6 fail-CLOSED guards + activity
scripts). Per the ADDITIVE constraint — bridge not burned.

### `permissions.rules` content summary (agent-md + user-scope template)
Same boundaries as the v2 `.sh` guards, expressed as capability rules
(deny > ask > allow):
- **deny `fs_write`** to `.claude/**`, `.kimi/**`, `.opencode/**`,
  `.codegraph/**`, `.kimigraph/**`, `.kirograph/**` (+ `**/` variants for
  absolute paths).
- **deny `fs_write`/`fs_read`** to sensitive files (`.env*`, `*.key`, `*.pem`,
  `id_rsa*`, `id_ed25519*`, `secrets.*`, `credentials*`, `.aws/`, `.ssh/`).
- **deny `fs_write` `match: "*"`** (single path component = repo-root files
  only) `exclude:` the ADR-0001 allowlist → unlisted root files blocked.
- **deny `shell`** `rm -rf *`, force-push, `git reset --hard*`, `DROP DATABASE`,
  `TRUNCATE` (v3 splits compound commands per sub-command before matching).
- **allow `fs_write`** to `.kiro/**` + `.ai/**` (orchestrator lane; the
  user-scope template additionally allows project-source dirs for executor
  subagents).

---

## 2. FINDING A (critical) — permissions.yaml is not repo-injectable

Source: <https://kiro.dev/docs/cli/v3/permissions> "Where rules live".

Grep-verified evidence (fetched doc, verbatim):
> Workspace permissions are stored **per-user outside the repository** at
> `~/.kiro/workspace-roots/<hash(workspaceRoot)>/`. A cloned repo cannot inject
> permission rules.

The two valid locations are `~/.kiro/settings/permissions.yaml` (user) and
`~/.kiro/workspace-roots/<hash>/permissions.yaml` (workspace, per-user). Neither
is in-repo. Furthermore, the hardcoded Kiro scope **always denies** agent writes
to `~/.kiro/settings/` — so I cannot install it for the owner even to the global
path. The owner must place it by hand (install steps are in the snippet header).

**Consequence for the handoff Step 1 ("Create `permissions.yaml` as the PRIMARY
deliverable"):** a repo `permissions.yaml` would never load. I substituted the
correct repo-committable equivalent — the agent-md `permissions` block — plus a
user-scope template. This is a deliberate deviation from the literal step,
surfaced per delivery-integrity.

---

## 3. FINDING B (critical) — v3 does not support headless / non-TUI

Source: <https://kiro.dev/docs/cli/v3/> "Known gaps".

Grep-verified evidence (fetched doc, verbatim):
> **Classic mode not supported** — The legacy non-TUI mode (`kiro-cli chat`
> without the TUI) does not support the v3 engine. Use the TUI.

`--no-interactive` headless dispatch IS the non-TUI classic mode. Therefore:
- Step 4's `kiro-cli --v3 chat --no-interactive --agent orchestrator` cannot
  run under v3 today.
- The dispatcher (`dispatch-handoffs.sh`) and the 4AI-panes Selector pin
  `kiro-cli --v3` for **headless** dispatch — that combination is currently
  **non-functional** (v3 + headless is unsupported).
- ADR-0006 Decision 1's premise — "v3 replaces `--trust-all-tools` with
  `permissions.yaml`, finally giving Kiro real *headless* enforcement" — does
  not hold *yet*: v3 enforces in the **TUI**, but there is no headless surface
  to enforce in. This is exactly the "if v3 STILL can't enforce headless, report
  that plainly — it changes the merge decision" case the handoff anticipated.

---

## 4. Step 4 live validation — NOT RUN (blocked)

Two independent blockers:
1. I am the orchestrator — **no shell tool** (cannot invoke `kiro-cli` or
   `git status`).
2. Even a shell-capable lane cannot validate v3 headless: v3 non-TUI is
   unsupported (§3). A `--no-interactive` probe would fail to start, not
   demonstrate enforcement.

**No enforcement evidence for (a)/(b)/(c) can honestly be produced by me.** Not
faking it. The validation must be **owner-run in an interactive v3 TUI**:

```
kiro-cli --v3            # launches the v3 TUI (trust the workspace when prompted)
# then, at the prompt, in order:
# (a) "Write the text 'x' to .claude/probe.txt"      -> expect DENY (agent-md permissions + guards.json)
# (b) "Run: rm -rf /tmp/kiro-probe && echo done"     -> expect DENY (destructive shell rule)
# (c) "Write 'ok' to .ai/probe.tmp"                  -> expect ALLOW
# After: `git status` should show ONLY .ai/probe.tmp (a/b left nothing behind). Delete the probe.
```

If (a) is NOT denied in the TUI, the agent-md `permissions` block isn't being
read — check that v3 didn't ignore `.kiro/agents/orchestrator.md` due to the
name collision noted in §6.

---

## 5. Corrected v3 headless invocation (for claude-code / dispatcher)

There is **no working v3 headless invocation** as of the 2026-06-17 v3 docs.
Options for claude-code to decide (all Tier B/C — not mine to execute):
- **Keep headless dispatch on v2** (`kiro-cli chat --no-interactive` +
  `--trust-all-tools`) with the ADR-0005 git pre-commit backstop as the
  mechanical floor, until v3 ships a headless surface. This preserves the fleet
  headless-by-default model (ADR-0006 Decision 2) at the cost of v2's weaker
  in-session enforcement (backstop still catches bad *commits*).
- **Revisit ADR-0006 Decision 1's "additive/headless" framing** — v3's
  enforcement win is real but currently **TUI-only**. The dispatcher/Selector
  `--v3` pin (commit `52b31fa`) should be reverted for the headless dispatch
  path, or gated behind "interactive only", until the gap closes.

Recommend claude-code fold this into ADR-0006 (it's still being drafted) before
merge.

---

## 6. Risks / next step / what breaks first

- **Agent name collision (watch):** both `.kiro/agents/orchestrator.json` (v2)
  and `.kiro/agents/orchestrator.md` (v3) now define agent `orchestrator`. The
  v3 docs say JSON and Markdown are equivalent formats — so under the v3 engine
  the two files may collide on the same name. Untested (no v3 TUI run here). If
  v3 errors or silently picks one, the owner should confirm which loads (TUI
  probe §4) and, if needed, retire `orchestrator.json` once v3 is validated
  (that retirement is the v2-fallback removal already gated by ADR-0006 —
  don't do it this handoff).
- **v3 tool-name matcher (watch):** `guards.json` PreToolUse matchers use
  `fs_write|str_replace|write` / `shell|execute_bash|bash` to hedge across the
  v2→v3 tool-name rename. The exact v3 write/shell tool names weren't in the
  docs; confirm in the TUI (a blocked (a)/(b) probe confirms the matcher fired).
- **`.kiro/hooks/**` is "always ask" in v3's hardcoded scope** — writing these
  files will itself prompt in the TUI; expected, one-time.
- **Next step:** owner runs the §4 TUI validation and installs the §2
  permissions template; claude-code decides the §5 dispatcher question and
  updates ADR-0006. **What breaks first:** the headless dispatch lane for Kiro —
  it is currently pinned to `--v3` (non-functional headless) per §3; that pin
  should change before the next headless Kiro dispatch is attempted.
