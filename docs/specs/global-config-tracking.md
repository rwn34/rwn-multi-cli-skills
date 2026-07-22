# Global CLI Config Tracking — Spec

## Summary

Each CLI in this framework reads load-bearing configuration from **user-global,
non-version-controlled files outside the repo** — Kimi from
`~/.kimi-code/config.toml` (hooks) and `~/.kimi/mcp.json` (MCP servers), Kiro from
`~/.kiro/settings/*` + `~/.kiro/agents/*`, Claude from `~/.claude/*`. These files
drift per-machine with **no repo guard**, and the one existing wire step
(`wire_kimi_hooks` in `scripts/install-template.sh`) is **append-once by marker**,
so it cannot propagate a changed snippet to an already-wired machine. This spec
generalizes that single wire step into a **reconcile mechanism**: tracked SSOT
snippets under `.ai/config-snippets/`, each a marker-delimited (or, for JSON,
key-managed) BLOCK the framework owns; an idempotent reconcile that *supersedes*
the block content on every run (create if absent, prune dead entries); and a
machine-level drift check that runs at session/launch time, since global files
live off the repo and off CI runners.

## Motivation

Two audiences feel this: the framework maintainer (`claude` as fleet git
operator) and any human who reinstalls or opens the framework on a fresh machine.

**Global config drifts silently, with no repo guard — the concrete incident.**
This is gap **D3** in the 2026-07-11 framework/panes gap analysis, and it bit hard
in the 2026-07-10/11 session: `~/.kimi/mcp.json` still registered the
`kimigraph`, `kirograph`, and `codegraph` MCP servers that **ADR-0003 removed**
(2026-07-09), producing a startup error on *every* terminal that launched Kimi.
Nothing in the repo tracks that file, so nothing caught the staleness; it was
fixed only by a **manual, per-machine edit** (blanking `~/.kimi/mcp.json`) — the
exact "manual edit as the only recovery" failure D3 names. A fresh machine or a
reinstall silently re-introduces the same dead global config, because the source
of truth for "which servers should be registered" lives nowhere the installer can
reconcile against.

**The one existing wire step can't update itself.** `wire_kimi_hooks`
(`install-template.sh` lines 681-713) appends `.ai/config-snippets/kimi-hooks.toml`
to `~/.kimi-code/config.toml` guarded by a marker — and its own header comment
(lines 676-680) documents the limitation verbatim:

```
# A4 note: this is APPEND-ONCE by marker. On update (UPDATE_MODE=1) it sees the
# existing marker and skips — it does NOT reconcile a changed snippet into the
# already-wired block. ...
# TODO(A4-followup): reconcile ~/.kimi-code/config.toml block on snippet change
```

So an already-wired machine keeps a **stale hook block forever** — a snippet
change (a new guard, a fixed path, a removed hook) never lands on re-run. This
spec resolves that `TODO(A4-followup)` and generalizes it to every managed global
file.

**Related install incidents (context, fixed elsewhere).** A2 (Kimi hooks wired to
the wrong path / never wired) and A3 (`.mcp.json` wired with a bare `codegraph`
command) are separate gaps already being addressed in `install-template.sh`; they
share D3's root cause — *global config wiring has no reconcile-and-verify loop*.
This spec is the general mechanism those point-fixes are special cases of.

## Non-goals

- **Owning the entire global file.** The framework manages only a delimited BLOCK
  (marker-fenced for text, key-scoped for JSON). Everything a user puts *outside*
  the block — their own hooks, their own MCP servers, their personal settings — is
  never read, rewritten, or deleted. Owning the whole file is rejected
  Alternative (b).
- **Syncing user-personal settings.** Theme, model choice, editor prefs, API keys,
  and any non-framework config in these files are the user's, not the framework's.
  The managed block is scoped to *framework-policy* concerns only (guards, handoff
  reminders, the framework's MCP server set).
- **Live cross-machine sync.** This is not a settings-sync service. Each machine
  reconciles its own global files against the tracked SSOT at install/launch time;
  there is no daemon, no cloud state, no push between machines.
- **Secrets management.** Managed blocks never contain tokens, keys, or
  credentials — those stay in the user's own out-of-block config and in
  environment variables (security-standards: never commit secrets).
- **Replacing the in-repo drift-check.** `docs/specs/framework-install-drift-check.md`
  covers *in-repo* framework-file drift (version-compare at launch). This spec is
  its **global-config analogue** and reuses the same launch-time, warn-only,
  never-auto-mutate posture — it does not modify that in-repo check.

## Design

### API / interface

**1. Tracked SSOT snippets (`.ai/config-snippets/`).**

One snippet per CLI-global concern, each a self-contained block the framework
owns. Existing today (verified):

- `.ai/config-snippets/kimi-hooks.toml` — Kimi's 4 guards + SessionStart handoff
  reminder + Stop queue-count (wired into `~/.kimi-code/config.toml`).
- `.ai/config-snippets/kiro-v3-permissions.yaml` — Kiro user-scope permissions
  (owner-installed into `~/.kiro/settings/permissions.yaml`; see the cross-CLI
  territory note — the framework cannot auto-wire this).

New under this spec:

- `.ai/config-snippets/mcp-servers.json` — the framework-managed MCP server set
  (currently just `codegraph` in npx form; `kimigraph`/`kirograph`/`codegraph`
  legacy-binary entries are *managed-and-deprecated*, i.e. reconcile removes
  them). Reconciled into each per-user MCP file (`~/.kimi/mcp.json`, and any other
  per-CLI MCP config the framework manages).

**2. The marker-block contract (text files: TOML / YAML / any comment-bearing
format).**

Every managed text block is fenced by a BEGIN/END sentinel pair on their own
lines, using the target file's native comment character:

```
# >>> rwn-multi-cli-framework: <block-id> (managed block — do not edit inside) >>>
<current SSOT snippet contents>
# <<< rwn-multi-cli-framework: <block-id> <<<
```

- `<block-id>` names the concern (`kimi-hooks`, `kiro-permissions`, …) so multiple
  managed blocks can coexist in one file, each reconciled independently.
- Content **between** the sentinels is framework-owned and replaced wholesale on
  reconcile. Content **outside** the sentinels is never touched — read-only to the
  reconcile step.
- The sentinels supersede the current bare marker
  (`# ADDED BY install-template.sh kimi-hooks (template @ <sha>)`,
  `install-template.sh` line 15 + 686): the bare marker has only a *start*, so the
  code can find the block's beginning but not its end, which is exactly why
  today's wire step can only append, never replace. A paired BEGIN/END is the
  minimal change that makes supersede possible.

**3. The reconcile wire step (generalizing `wire_kimi_hooks`).**

`reconcile_block <target-file> <block-id> <snippet-file>` (bash; a PowerShell
sibling for PS-native paths — see Dependencies):

```
reconcile_block(target, block_id, snippet):
  if DRY_RUN: log the planned supersede/create; return
  ensure parent dir exists; create target (empty) if absent
  read target, preserving its existing encoding + line endings (see Data)
  if a BEGIN/END pair for block_id exists:
     replace everything between (and including) the sentinels with
       BEGIN + current snippet + END           # SUPERSEDE — the fix for append-once
  else:
     append (on a fresh line)  BEGIN + current snippet + END   # CREATE
  write atomically: temp file in same dir -> fsync -> rename over target
  never touch bytes outside the block
```

Key properties, contrasted with the current step:

| Property | `wire_kimi_hooks` (today) | `reconcile_block` (this spec) |
|---|---|---|
| Already-wired machine, changed snippet | skips (stale block persists) | supersedes (block updated) |
| Block boundary | start marker only | BEGIN + END pair |
| Write | append `>>` | atomic temp + rename |
| Dead entries | never removed | removed on supersede (whole block replaced) |
| User content outside block | preserved | preserved (unchanged) |

**4. The MCP key-managed contract (JSON files: no comment syntax).**

`~/.kimi/mcp.json` (and peers) are JSON — they **cannot carry comment sentinels**,
so the marker-block contract does not apply. Instead the framework maintains a
**manifest of managed server keys** and reconciles structurally:

```
reconcile_mcp(target_json, managed_snippet_json, managed_keys, deprecated_keys):
  parse target JSON  (fail-closed: on parse error, warn + skip, never corrupt)
  servers = target.mcpServers (or {})
  for key in managed_keys:      servers[key] = managed_snippet.mcpServers[key]   # set/overwrite
  for key in deprecated_keys:   servers.pop(key, None)                           # PRUNE dead servers
  # keys NOT in managed_keys ∪ deprecated_keys are the user's — never touched
  write atomically
```

- `managed_keys` = `["codegraph"]` (current framework server set).
- `deprecated_keys` = `["kimigraph", "kirograph"]` (ADR-0003-removed per-CLI
  graphs) **plus** any prior-form `codegraph` entry the reconcile overwrites with
  the correct npx form. This is what would have auto-cleaned the D3 incident: a
  reinstall *removes* the dead servers instead of leaving (or re-adding) them.
- This is the structural analogue of the marker block: "the framework owns these
  keys, the user owns the rest." It reuses the JSON-merge pattern already in
  `wire_mcp` (`install-template.sh` lines 611-668, python-parser path) — extended
  from merge-if-absent to set-and-prune.

**5. The drift / verify check (companion to the in-repo drift-check + D1 gate).**

Two tiers, because global files are off the repo and off CI runners:

- **CI tier (SSOT self-consistency only).** CI *cannot* see a contributor's
  `~/.kimi-code/config.toml`. What it *can* verify is that the tracked snippets are
  themselves well-formed and internally consistent: each snippet parses (valid
  TOML/YAML/JSON), each declares a `<block-id>`, and the MCP `managed_keys` /
  `deprecated_keys` sets are disjoint. This slots alongside the D1 `gates.yml`
  version-bump gate — a snippet change that isn't accompanied by a framework
  version bump is the same discipline failure D1 describes.
- **Machine tier (actual drift, at launch/session-start).** The only place real
  drift is observable is on the machine that holds the global files. A launch-time
  check (tied to the pane launcher `Selector.ps1` / a per-CLI SessionStart hook)
  compares each managed block in the live global file against the current SSOT
  snippet and emits a **warn-only** message naming the file and the reconcile
  command — never auto-mutating, matching the warn-only posture of
  `framework-install-drift-check.md`. For MCP, the check flags the presence of any
  `deprecated_keys` server (the D3 startup-error class) even before a full
  reconcile runs.

### Data

**Per-CLI global-config inventory** — which files each CLI reads, and which parts
the framework manages vs. leaves to the user:

| CLI | Global file(s) | Framework-managed part | User-owned part | Wiring path |
|---|---|---|---|---|
| Kimi | `~/.kimi-code/config.toml` | `kimi-hooks` marker block (guards + handoff hooks) | all other hooks, model/UI settings, `safety-check.ps1` hook | installer wires directly (as today) |
| Kimi | `~/.kimi/mcp.json` | managed server keys (`codegraph`); prune `kimigraph`/`kirograph` | any user-added MCP servers | installer reconciles directly |
| Kiro | `~/.kiro/settings/permissions.yaml` | `kiro-permissions` block (mirrors `.kiro/agents/*.md` rules) | user's own permission rules, other settings | **owner-manual / handoff only** (see territory note) |
| Kiro | `~/.kiro/agents/*` | none in v1 (repo-portable `.kiro/agents/*.md` frontmatter is the SSOT) | everything | n/a (open question) |
| Claude | `~/.claude/*` (`settings.json`, …) | **none in v1** — Claude is self-contained in the project's `.claude/settings.json` | everything | n/a (open question) |

The inventory's asymmetry is deliberate: **Kimi + MCP are the confirmed
drift-and-inert surfaces** (A2/A3/D3), and are where v1 pays off. Kiro and Claude
are listed for completeness but carry no auto-wired managed block in v1 (see Open
questions).

**Marker/sentinel format (text).** Stored inline as shown in §2. The
`<block-id>` and the `(managed block — do not edit inside)` human note are part of
the sentinel line so a user opening the file understands the boundary. The
`template @ <sha>` provenance the current marker carries (line 686) moves onto the
BEGIN sentinel as a trailing annotation, preserving traceability of which template
commit last reconciled the block.

**Encoding / line-ending discipline (load-bearing — PS-vs-bash writers).** These
global files are written by *both* worlds: the bash installer (`>>`, LF, no BOM)
and PowerShell launch/session hooks (`Set-Content`/`Out-File` can emit UTF-8 **with
BOM** and CRLF by default). Reconcile MUST:

- **Detect and preserve** the target file's existing encoding and dominant line
  ending; never inject a BOM *mid-file* (a BOM is only ever valid at byte 0, and a
  reconcile that rewrites an interior block must not introduce one). Mirrors the
  byte-exact copy discipline in `4ai-panes-install-sync.md` (§UX/behavior — "no
  `Get-Content`/`Set-Content` round-trip that would rewrite line endings or add a
  BOM").
- On the PowerShell side, write with an explicit **UTF-8 (no BOM)** encoder and
  the file's detected newline, not the `Out-File` defaults.
- For TOML/YAML this is cosmetic-but-important (a stray BOM can break strict
  parsers); for the JSON MCP files a mid-file BOM or a leading BOM after a
  non-BOM-aware writer can make `ConvertFrom-Json` / `json.load` throw — which the
  reconcile treats as fail-closed (warn + skip), so a botched encoding degrades to
  "not updated," never "corrupted."

**Atomic write.** Every reconcile writes to a temp file in the target's own
directory, then renames over the target (same-dir rename is atomic on Windows and
POSIX). A crash mid-write never leaves a truncated global config where the CLI
would load it. Same pattern as ADR-0008's atomic activity-log write and the
sync-script's temp-then-move (`4ai-panes-install-sync.md` §Failure handling).

### UX / behavior

- **Fresh machine / first install:** each managed block is *created* in its target
  global file (dir + file created if absent), exactly as `wire_kimi_hooks` does
  today — but now with BEGIN/END sentinels so future runs can supersede.
- **Re-install / update on an already-wired machine:** each managed block is
  *superseded* with the current SSOT snippet. A changed guard, a fixed path, a new
  handoff hook, or a removed hook now actually propagates — resolving the
  append-once `TODO(A4-followup)`. This is the single biggest behavior change.
- **MCP reconcile on the D3 machine:** `kimigraph`/`kirograph` (and any legacy
  bare-`codegraph`) entries are *removed*; the correct npx `codegraph` is set. The
  every-terminal startup error the session hit does not recur after one reinstall.
- **User content is never disturbed:** a user's own hooks, servers, and settings
  outside the managed block/keys survive every reconcile byte-for-byte.
- **Drift warning at launch (machine tier):** if a live global block differs from
  the SSOT snippet (or a deprecated MCP server is present), a yellow warn names the
  file + the reconcile command, then launch continues — advisory, never blocking,
  never auto-mutating. Matches `framework-install-drift-check.md`'s posture.
- **CI (SSOT tier):** a malformed snippet, a missing `<block-id>`, or overlapping
  managed/deprecated key sets fails the check; a live machine's drift can *not* be
  seen by CI and is explicitly out of CI's reach.
- **`--dry-run`:** logs the planned create/supersede/prune per target and touches
  nothing (mirrors `wire_kimi_hooks`'s existing dry-run at line 693).
- **Idempotent:** running reconcile twice back-to-back is a no-op the second time
  (the block already equals the SSOT); the drift check then reports clean.

### Dependencies

- **`.ai/config-snippets/` SSOT + framework-version discipline (process
  dependency).** The drift check is only as good as the version/hash it compares.
  A snippet change without a `tools/multi-cli-install/package.json` version bump
  ships undetected on already-wired machines — the same D1 discipline the in-repo
  drift-check depends on. Enforcement is an Open question.
- **`reconcile_block` (bash) + a PowerShell sibling.** The bash form runs in the
  installer (Git-Bash on Windows). The launch-time drift check and any
  PowerShell-initiated reconcile need a PS implementation that shares the sentinel
  format and the encoding discipline. As in `4ai-panes-install-sync.md`, the
  allowlist/format is the single source of truth; two implementations must not
  fork it.
- **A JSON parser for the MCP path.** `wire_mcp` already uses a python parser when
  available and warns-and-skips otherwise (lines 641-667). Reconcile reuses that:
  no python (or no PS `ConvertFrom-Json`) ⇒ warn + skip, never a hand-rolled JSON
  edit that could corrupt the file.
- **PowerShell 5.1+ / Git-Bash** — already framework prerequisites; no new
  third-party libraries.
- **Session-start / launch hook surface** — the machine-tier check binds to the
  per-CLI SessionStart hooks (Kimi's `handoffs-remind.sh` sibling) and/or
  `Selector.ps1`'s launch path. Those surfaces exist; this spec adds a check to
  them, it does not create a new daemon.

### Cross-CLI territory (call-out)

`~/.kimi*` and `~/.kiro*` are **those CLIs' own domains**, and this framework's
custodianship (CLAUDE.md, ADR-0001) is over *OpenCode's* files, not Kimi's/Kiro's.
Two different postures result:

- **Kimi (`~/.kimi-code/`, `~/.kimi/mcp.json`): installer wires directly.** This is
  what `wire_kimi_hooks` already does — the installer appends to Kimi's global
  config today. Reconcile keeps that direct-write posture (it is mechanical,
  low-risk, marker/key-scoped, and idempotent). No handoff needed.
- **Kiro (`~/.kiro/settings/*`): owner-manual, NOT auto-wired.** The
  `kiro-v3-permissions.yaml` snippet header is explicit: Kiro v3 *hardcodes a DENY
  on agent writes to `~/.kiro/settings/`*, so **no agent (including the installer
  running as one) can place it** — "the OWNER must place it by hand." Reconcile
  therefore cannot own Kiro's user-scope file; the mechanism for Kiro is: ship the
  snippet + a drift check that *warns* + owner applies (or a `to-` handoff that
  instructs the owner). Auto-wiring Kiro is blocked by Kiro's own guard, and this
  spec must not pretend otherwise.

This asymmetry (installer-wires-Kimi vs. owner-wires-Kiro) is a first-class part
of the design, not an oversight.

## Alternatives considered

- **(a) Status quo — manual per-machine edits.** Keep global config untracked and
  fix drift by hand. **Rejected: this is the D3 incident.** The dead
  `kimigraph`/`kirograph`/`codegraph` servers in `~/.kimi/mcp.json` broke every
  terminal and were recoverable only by a manual blank-and-edit, with a reinstall
  free to re-introduce them. Human memory is not a reconcile loop.
- **(b) Framework owns the entire global file.** Have the installer write/overwrite
  the whole `~/.kimi-code/config.toml` (etc.) from a template. **Rejected: it
  clobbers the user's own config** — their `safety-check.ps1` hook (which
  `kimi-hooks.toml`'s header explicitly says to KEEP), their personal servers,
  their settings. The whole point of a marker/key-scoped block is to co-exist with
  user content; owning the file destroys it.
- **(c) Symlink the global file to a repo copy.** Point `~/.kimi-code/config.toml`
  at a repo-tracked file so drift is structurally impossible. **Rejected for the
  same reasons `4ai-panes-install-sync.md` rejected its symlink alternative (c):**
  (1) Windows symlink/junction creation can require elevation or Developer Mode;
  (2) it forces the *entire* file to be framework-owned (collapsing back into
  Alternative (b) — the user can no longer keep private out-of-block config); (3)
  it couples a per-user, per-machine path into repo-tracked content, and different
  machines legitimately differ (the migrated-vs-unmigrated `~/.kimi` vs
  `~/.kimi-code` path split is itself a machine-level difference). Marker/key
  reconcile is permission-free, preserves user content, and tolerates per-machine
  path differences.

## Open questions

- **How is the machine-tier drift check triggered without CI reach?** CI can't see
  a machine's global files, so drift detection must run at launch/session-start on
  the actual machine. Candidate hosts: `Selector.ps1`'s launch path (warns before
  splitting panes, alongside the in-repo drift-check), and/or a per-CLI
  SessionStart hook. Which surface(s), and whether the check offers a one-key
  "reconcile now" vs. warn-only, is unresolved. Owner: framework maintainer.
- **Per-CLI wiring ownership: direct-write vs. handoff.** Kimi is installer-wired
  today; Kiro *cannot* be agent-wired (hardcoded deny) and must be owner-manual or
  handoff-driven. Should the installer emit a `to-` handoff (or a printed
  owner-action block) for the Kiro/Claude cases it cannot wire itself, so the gap
  is surfaced rather than silent?
- **Do Kiro and Claude even need managed global blocks in v1, or only Kimi + MCP?**
  Kiro's repo-portable `.kiro/agents/*.md` frontmatter is already the enforcement
  SSOT (the user-scope `permissions.yaml` is "belt to that suspenders"), and Claude
  is self-contained in the project's `.claude/settings.json`. v1 may reasonably
  ship **only** the Kimi-hooks + MCP reconcile (the confirmed drift surfaces) and
  defer Kiro/Claude managed blocks until a concrete drift incident justifies them.
- **How is the SSOT-version discipline enforced?** Same open question as
  `framework-install-drift-check.md`: a `gates.yml` check that fails a PR changing
  `.ai/config-snippets/**` without a framework version bump, vs. convention +
  reviewer diligence. (D1.)
- **MCP file location across CLIs.** The D3 incident was `~/.kimi/mcp.json`, but
  MCP config location is per-CLI and per-version (project-scoped `.mcp.json` vs.
  user-global `~/.kimi/mcp.json` vs. others). The reconcile needs an authoritative
  list of per-user MCP file paths to manage; enumerating them (and keeping that
  list current as CLIs change) is unresolved.

## References

- `docs/specs/TEMPLATE.md` — the spec section structure this document follows.
- `.ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md` — gap **D3**
  (global CLI configs aren't version-controlled; the `~/.kimi/mcp.json` dead-server
  issue), and the related **A2** (Kimi hooks wired to the wrong / no path) and
  **A3** (`.mcp.json` bare `codegraph` command) install incidents this mechanism
  generalizes.
- `scripts/install-template.sh` — `wire_kimi_hooks` (lines 681-713, the
  append-once step generalized here) and its `A4 note` + `TODO(A4-followup)`
  (lines 676-680); `wire_mcp` (lines 611-668, the JSON-merge pattern the MCP
  reconcile extends); the bare `MARKER="# ADDED BY install-template.sh"` (line 15)
  the BEGIN/END sentinel supersedes; `TEMPLATE_SHA` provenance (lines 128, 686);
  phase3 wiring (lines 863-867).
- `.ai/config-snippets/kimi-hooks.toml` — the existing tracked SSOT snippet
  (Kimi's 4 guards + SessionStart handoff reminder + Stop queue-count) reconciled
  into `~/.kimi-code/config.toml`; its header documents `safety-check.ps1`
  coexistence (user content that must be preserved) and the `~/.kimi-code/` vs
  `~/.kimi/` path split.
- `.ai/config-snippets/kiro-v3-permissions.yaml` — the Kiro user-scope snippet;
  its header establishes that Kiro v3 hardcodes a DENY on agent writes to
  `~/.kiro/settings/`, so the framework *cannot* auto-wire Kiro (cross-CLI
  territory note).
- `docs/specs/framework-install-drift-check.md` — sibling spec: the **in-repo**
  framework-file drift check (warn-only, launch-time, never-auto-mutate). This
  spec is its **global-config analogue** and reuses that posture; its D1
  version-bump-discipline open question applies here too.
- `docs/specs/4ai-panes-install-sync.md` — sibling spec: file-scoped sync of the
  executable launcher install. Source of the atomic temp-then-rename write pattern
  and the byte-exact / no-BOM / preserve-EOL discipline reused in this spec's
  encoding section; also the source of the rejected symlink Alternative (c)
  reasoning.
- `docs/architecture/0003-code-graph-rationalization.md` — removed the per-CLI
  `kimigraph`/`kirograph` graphs (2026-07-09); basis for the MCP reconcile's
  `deprecated_keys` prune set (the D3 dead servers).
- `docs/architecture/0008-self-driving-fleet-pane-runner.md` — the atomic
  temp-file + rename write pattern reused for reconcile's atomic write.
- `CLAUDE.md` — the AI Contract: `.ai/instructions/` is SSOT, custodianship
  boundaries (Claude custodies OpenCode's files, not Kimi's/Kiro's), and the
  cross-CLI handoff protocol referenced in the wiring-ownership open question.
