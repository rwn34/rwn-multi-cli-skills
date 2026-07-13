# rwn 4AI Panes

> **Goal:** One maximized Windows Terminal window with 4 vertical panes — Claude, Kiro, Kimi, OpenCode — no alt-tabbing.

---

## Provenance & Canonical Source

Imported **2026-07-08** from the standalone [rwn-4AI-panes](https://github.com/rwn34/rwn-4AI-panes) repo (local checkout `master` @ `06c5d84`) into this framework repo. **`tools/4ai-panes/` is now the canonical source** — the external repo is a read-only mirror pending archive.

Two per-project **Selector badges** were added at import (`Get-ProjectBadges` in `Selector.ps1`), shown on each project row in the menu:

| Badge | Meaning |
|-------|---------|
| `[v SRC]` | This dir **is** the framework source repo (`$frameworkRepo`, override with `RWN_FRAMEWORK_REPO`). |
| `[v OK]` | `.ai/.framework-version` marker present — current framework install. |
| `[! OLD]` | `.ai/` exists but no version marker — pre-marker install. |
| `[- none]` | No `.ai/` folder — framework not installed in that project. |
| `[H:<n>]` | *n* open cross-CLI handoffs (count of `*.md` files under `.ai/handoffs/to-*/open/`). Hidden when *n* = 0. |

Exactly one of the four framework-version badges appears per project; `[H:<n>]` is appended only when open handoffs exist (including on `[v SRC]`). Badge checks are deliberately cheap (two `Test-Path` calls + one shallow glob per project) — any error in a broken project dir yields an empty/partial badge, never a crash.

**Why `[v SRC]` exists:** the `.ai/.framework-version` marker is written *by* the installer *into* target projects. The framework source repo never carries one — its own version is `tools/multi-cli-install/package.json` `.version` — so it used to badge itself `[! OLD]`, i.e. the framework reported itself stale against itself. The selector now canonicalizes both paths (absolute, trailing-slash- and case-insensitive) and badges the source repo `[v SRC]` instead.

Role policy for the four panes (who does what across Claude/Kiro/Kimi/OpenCode) is owned by [`docs/architecture/0002-cli-role-topology.md`](../../docs/architecture/0002-cli-role-topology.md) in this repo (amended 2026-07-08; OpenCode replaces Crush 2026-07-09).

---

## 1. What This Does

Creates a **Start Menu shortcut** called **"rwn 4AI Panes"** that opens a Windows Terminal window in two phases:

**Phase 1 — Full-screen selector:**
- Interactive project selector (box-drawing menu, arrow-key navigation)

**Phase 2 — After selecting a project, the pane splits into four:**
- Claude (`claude --dangerously-skip-permissions`)
- Kiro (`kiro-cli chat --trust-all-tools`)
- Kimi (`kimi --yolo`)
- OpenCode (`opencode` — no --yolo equivalent; permissions + framework-guard plugin govern)

**Default layout:**

```
+----------+----------+----------+----------+
|          |          |          |          |
| Claude   | Kiro     | Kimi     | OpenCode |
|          |          |          |          |
|          |          |          |          |
+----------+----------+----------+----------+
   25%        25%        25%        25%
```

All CLI panes open with the selected project as working directory. If a CLI is not installed, that pane is skipped automatically. Pane order can be customized with the `o` key.

### Self-driving panes (ADR-0008)

Each pane launches **`pane-runner.ps1`** — a per-pane supervisor loop — rather than a bare CLI. The runner polls that project's `.ai/handoffs/to-<cli>/open/` inbox (filesystem only, zero tokens), and on a qualifying handoff (`Auto: yes` + `Risk: A|B`) it runs the CLI headless, auto-continues while the handoff stays `OPEN` (up to `-MaxContinues`, default 5), and releases a per-project claim-lock when the handoff moves to `done/`. Risk-C handoffs are never auto-run. Press **`p`** in a pane to pause the loop and drop to the interactive CLI; **Ctrl-C** stops the runner.

**Plain REPL fallback:** set `RWN_PANE_BARE=1` before launching (or select "Open without directory") to get the old bare-CLI behavior in every pane. See [`docs/architecture/0008-self-driving-fleet-pane-runner.md`](../../docs/architecture/0008-self-driving-fleet-pane-runner.md).

### Restarting a pane

Each pane runs an **independent** self-driving runner (`pane-runner.ps1`) — its own process and its own claim-lock — so panes are isolated from one another. The loop is **self-healing**: each iteration is wrapped in try/catch, so a failed handoff or CLI run logs `ALERT ... recovering, still polling` and keeps polling instead of exiting. One bad handoff won't take the pane down.

Two things still drop a pane to a bare prompt: pressing **Ctrl-C** (the runner banner's **stop**) or the runner exiting. From the banner, **`p`** = pause (drop to the interactive CLI, exit it to resume) and **Ctrl-C** = stop. To re-enter the runner loop in that pane, run:

```powershell
restart-pane.ps1              # no args: reuses $env:RWN_PANE_CLI for this pane
restart-pane.ps1 -Cli kimi    # or name the CLI explicitly (claude|kimi|kiro|opencode)
```

`restart-pane.ps1` is **pane-local** — it restarts only this pane's CLI and never affects the other panes. Inside a pane launched by `pane-runner.ps1`, `RWN_PANE_CLI` is already stamped in the shell, so no `-Cli` argument is needed; pass `-Cli` only when starting a runner in a pane where that env var is not set.

### Poison-pill quarantine

Self-healing keeps the pane *alive*, but a single handoff that fails **every** time would otherwise be retried forever — re-claimed on each poll, ALERT-spamming the pane and burning tokens. To stop that, the runner counts consecutive failures **per handoff**. A handoff that keeps failing to reach `done/` — whether it MAXED (still `OPEN` after the `-MaxContinues` cap) or threw on every iteration — is **quarantined** after `MaxHandoffAttempts` (default `3`) consecutive failures.

Once a handoff is quarantined, `Get-QualifyingHandoff` **skips it** and the runner keeps polling **other** handoffs. One bad handoff can neither stall the pane nor spam alerts — the loud `== QUARANTINE [cli] <file> after N failed attempts -- skipping ... ==` line is logged **once** at the threshold, then the handoff is silently ignored.

The marker is a durable sidecar under `.ai/handoffs/.quarantine/`, named `<recipient>__<handoff-basename>.quarantine.json` (recipient = `claude|kimi|kiro|opencode`). It is gitignored exactly like the `.claims` sidecars — never commit one. The JSON tracks `attempts`, the `quarantined` flag, first/last attempt timestamps, and `last_error`. See [`.ai/handoffs/.quarantine/README.md`](../../.ai/handoffs/.quarantine/README.md) for the full contract.

- **Clears automatically** when the handoff finally reaches `done/`.
- **Clear manually** (un-quarantine) by **deleting** the sidecar after you fix or unblock the handoff — the runner re-attempts it on the next poll.
- **Known limitation:** there is no automatic staleness expiry yet. A handoff you fix *in place* without clearing its sidecar stays skipped until you delete the sidecar (or it moves to `done/`).

### Fleet supervisor (OS-level, survives terminal death)

`fleet-supervisor.ps1` runs as a **Windows Task Scheduler** task (registered via `install-fleet-supervisor.ps1`) — one level ABOVE `run-pane-supervised.ps1`. It survives terminal death (PowerShell restart, wt.exe crash) because it doesn't depend on any terminal being open.

Each pane-runner writes a **persistent heartbeat file** to `%LOCALAPPDATA%\rwn-auto\fleet-heartbeat\<project>__<cli>.json` on every poll — outside the repo to avoid `.ai/` churn. The supervisor reads these heartbeats and classifies each pane:

- **L1 (liveness):** heartbeat file exists AND timestamp is fresh (< 90s). A stale or missing heartbeat means the pane (or terminal) is dead.
- **L2 (capability):** the heartbeat carries the outcome of the pane's last CLI invocation. `auth_failure` or `quota_exceeded` with ≥3 consecutive failures means the CLI is alive but **cannot do work** (dead API key, exhausted quota, provider down).

Actions:

| Condition | Action |
|---|---|
| All panes healthy | Nothing |
| ALIVE + NOT CAPABLE | **Alert only** (Telegram, names the CLI + reason). NEVER relaunches — a dead API key isn't fixed by restarting the process. |
| DEAD + open handoffs | **Alert + relaunch** (opens a new wt tab with pane-runners for the project) |
| DEAD + empty queue | **Alert only** (deduped, once per incident) |

Safety: exponential backoff (1→2→4→8→16 min) + max-attempts circuit breaker (default 5) on relaunch; alert dedupe on state transition; a live fleet is **never** relaunched (false-positive guard).

```powershell
# Register (run once):
powershell -File install-fleet-supervisor.ps1
# Remove:
powershell -File uninstall-fleet-supervisor.ps1
```

**Hard boundary:** the supervisor cannot run when the machine is off or asleep. See `.ai/known-limitations.md`.

### Launch pacing (why launches no longer land scrambled)

Windows Terminal applies a chained `wt` command (`new-tab … ; split-pane … ; split-pane …`) against **whatever pane is focused when it gets there**. Firing one invocation with dozens of subcommands — which is what marking ~7 projects used to do — makes WT race itself and the layout comes out shuffled.

The selector now **paces** every fleet launch:

- **One `wt` invocation per project tab** in a batch (never one packed invocation), fired sequentially.
- **One `wt` invocation per pane stage** inside a tab (`new-tab`, then each `split-pane` / `move-focus` separately).

Every stage still targets the same `-w rwn4ai` window and acts on the same active pane the chained form would have acted on, so **the layout is identical — only the timing changes**. Titles (`--title`), working dirs (`-d`) and window (`-w rwn4ai`) are byte-identical to the chained form.

Two env knobs tune the pacing:

| Env var | Default | Meaning |
|---------|---------|---------|
| `RWN_4AI_PANE_DELAY_MS` | `250` | Milliseconds between pane stages **within** one project's tab. |
| `RWN_4AI_TAB_DELAY_MS` | `1200` | Milliseconds between project tabs in a **batch** launch. |

Setting a knob to **`0` restores the legacy atomic single-invocation behavior for that dimension** — the escape hatch if staging ever misbehaves on a machine:

- `RWN_4AI_PANE_DELAY_MS=0` — each project's whole tab ships as one chained `wt` call.
- `RWN_4AI_TAB_DELAY_MS=0` — the **whole batch** ships as one chained `wt` call (a single invocation cannot be pane-staged, so this makes the panes atomic too). This is exactly the old behavior, including its ~8191-char Windows command-line ceiling; the selector warns if an invocation exceeds the 7000-char safe limit.

Non-numeric, negative or empty values fall back to the default — a bad env var never crashes the launcher.

```powershell
$env:RWN_4AI_PANE_DELAY_MS = 400    # slower machine: give WT more time per split
$env:RWN_4AI_TAB_DELAY_MS  = 0      # opt back into the legacy one-shot batch
```

---

## 2. Files

| File | Purpose |
|------|---------|
| `Launch4Panes.ps1` | Entry point. Launches wt.exe with the selector as a single full-screen pane. Auto-closes after launch. |
| `Selector.ps1` | Interactive box-drawing menu. Handles project selection, layout customization, and dynamic pane splitting. Also auto-installs the AI framework into the selected project (`Install-Framework`, see §6). After splitting, this pane becomes the first CLI in the layout. Each pane launches `pane-runner.ps1` unless `RWN_PANE_BARE` is set or no project dir is chosen. |
| `pane-runner.ps1` | Per-pane self-driving supervisor loop (ADR-0008): polls this project's handoff inbox, runs the CLI headless on qualifying handoffs, auto-continues past step caps (MAX 5), and holds a per-project claim-lock. Quarantines a handoff after repeated failures (default 3) so a poison pill can't stall the pane. `-Cli`, `-ProjectDir`, `-MaxContinues`, `-PollSeconds`. |
| `restart-pane.ps1` | Manual respawn: re-enters **this** pane's `pane-runner.ps1` loop after a Ctrl-C or exit dropped it to a bare prompt. Pane-local — it relaunches only this pane's CLI and never touches the other panes (each pane is its own process + claim-lock). `-Cli` defaults to `$env:RWN_PANE_CLI` (stamped by `pane-runner.ps1`), so with no arguments it restarts the correct CLI in the current pane. Also `-ProjectDir`, `-Owner`, `-MaxContinues`, `-PollSeconds`. |
| `test-pane-runner.ps1` | Pester-free harness for `pane-runner.ps1` decision logic (mock CLI, no real launch). Run: `powershell -File test-pane-runner.ps1`. |
| `test-selector-e2e.ps1` | Pester-free harness for `Selector.ps1`: real `Install-Framework` runs into a temp sandbox, plus badge resolution (`[v SRC]`/`[v OK]`/`[! OLD]`/`[- none]`) and the launch plan (staged emission == legacy atomic chain, N projects -> N tab launches, delay knobs). Asserts on the constructed `wt` command/stage arrays — never launches Windows Terminal. Run: `powershell -File test-selector-e2e.ps1`. |
| `fleet-supervisor.ps1` | OS-level fleet supervisor (Windows Task Scheduler). Detects dead pane-runners via persistent heartbeat files (L1 liveness + L2 capability), alerts the owner via Telegram, and relaunches the fleet. Exponential backoff + circuit breaker + alert dedupe. See [Fleet supervisor](#fleet-supervisor-os-level-survives-terminal-death) above. |
| `install-fleet-supervisor.ps1` | Registers the fleet supervisor as a scheduled task ("run only when user is logged on" + Interactive, so it CAN open wt panes). Scripted + reversible. `-IntervalMinutes` (default 1), `-WhatIf` to preview. |
| `uninstall-fleet-supervisor.ps1` | Removes the fleet supervisor scheduled task. `-WhatIf` to preview. |
| `test-fleet-supervisor.ps1` | Pester-free harness for `fleet-supervisor.ps1` (33 tests: liveness, false-positive guard, down+handoffs, down+empty-queue, alive-but-not-capable, backoff/circuit-breaker, alert dedupe, install/uninstall). Run: `powershell -File test-fleet-supervisor.ps1`. |
| `test-pane-supervisor.ps1` | Pester-free harness for `run-pane-supervised.ps1` (stub-driven: respawn, give-up, healthy-run reset, backoff schedule). Run: `powershell -File test-pane-supervisor.ps1`. |
| `install-framework.log` | Generated at runtime next to the scripts by `Install-Framework` — an append-only trace of each framework install attempt (source, git state, installer exit codes, fallback copies). Not committed. |
| `Launch4Panes.vbs` | VBS wrapper. Opens the PS1 from Start Menu without leaving a lingering window. |
| `icon.ico` | Custom icon for the Start Menu shortcut (dark theme, 4 colored bars). |
| `.gitignore` | Ignores `.4pane-history`, `.4pane-layout`, and `*.tmp`. |

> **Not in this dir:** `scripts/sync-4ai-panes-install.ps1` lives in the repo's top-level `scripts/`, **not** in `tools/4ai-panes/`. It is the install-sync engine (see [§3.2](#32-install)) and is **not** one of the allowlisted tool files it copies — it is never installed into `~/.rwn-auto/rwn-4AI-panes`.

---

## 3. Setup

### 3.1 Prerequisites

- **Windows 10/11**
- **Windows Terminal** (`wt.exe`) — install from Microsoft Store
- **PowerShell 5.1+**
- Optional: `claude` on PATH
- Optional: `kiro-cli` on PATH
- Optional: `kimi` on PATH
- Optional: `opencode` on PATH

### 3.2 Install

1. **First install only (bootstrap)** — copy the tool from `tools/4ai-panes/` in this repo (the canonical source — see [Provenance & Canonical Source](#provenance--canonical-source)):
```powershell
Copy-Item -Recurse <path-to>\rwn-multi-cli-skills\tools\4ai-panes C:\Users\<you>\.rwn-auto\rwn-4AI-panes
```
   The old standalone [rwn-4AI-panes](https://github.com/rwn34/rwn-4AI-panes) GitHub repo is a read-only mirror pending archive — do not clone or install from it.

   **After first install, the executable copy is kept in lockstep automatically** — do **not** re-run this recursive copy to update. Any `git merge` / `git pull` / branch checkout that touches `tools/4ai-panes/**` fires `scripts/git-hooks/post-merge` (and `post-checkout`), which runs `scripts/sync-4ai-panes-install.ps1` to byte-sync **only** the nine allowlisted tool files. The embedded framework (`.ai/`, `.claude/`, `.git/`, …) and runtime state (`.4pane-history`, `install-framework.log`, …) inside the install are never touched. See [`docs/specs/4ai-panes-install-sync.md`](../../docs/specs/4ai-panes-install-sync.md).

   **Manual escape hatch** — to force a sync (or preview drift) yourself:
```powershell
powershell -NoProfile -File scripts/sync-4ai-panes-install.ps1 [-DryRun]
```
   Set `RWN_AUTO_INSTALL_DIR` to point the sync at a non-default install location (otherwise it targets `~/.rwn-auto/rwn-4AI-panes`).

2. **Configure your projects folder** — edit `$projectsDir` in `Selector.ps1`:
```powershell
$projectsDir = "C:\Users\<you>\Code"
```

3. **Create the Start Menu shortcut** — run in PowerShell:
```powershell
$shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\rwn 4AI Panes.lnk"
$target = "C:\Users\<you>\.rwn-auto\rwn-4AI-panes\Launch4Panes.vbs"
$icon = "C:\Users\<you>\.rwn-auto\rwn-4AI-panes\icon.ico"

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = $target
$Shortcut.WorkingDirectory = "C:\Users\<you>\.rwn-auto\rwn-4AI-panes"
$Shortcut.IconLocation = $icon
$Shortcut.Save()
Write-Host "Shortcut created at: $shortcutPath"
```

4. Press **Start**, type **"rwn 4AI Panes"**, click it.

---

## 4. How to Use

1. Start Menu → **rwn 4AI Panes**
2. A maximized Windows Terminal opens with the selector
3. Use the selector to pick a project:
   - **Up/Down arrows** — navigate
   - **Enter** — select
   - **Number keys (1-9)** — quick jump
   - **n** — create new project
   - **b** — browse for a folder
   - **w** — open without directory
   - **o** — open pane order picker (rearrange CLIs)
   - **q** — quit
   - **PageUp/PageDown** — scroll through pages
   - **Home/End** — jump to top/bottom
   - **Escape** — quit
4. After selecting, the pane splits into 4 (one per detected CLI)
5. All four panes are now running — start coding

### Pane Order Picker

Press **o** in the project selector to open the layout picker:

```
+----------------------------------------------+
| Pane Order (Up/Down to reorder, Enter confirm)|
+----------------------------------------------+
| > 1. Claude                                   |
|   2. Kiro                                     |
|   3. Kimi                                     |
|   4. OpenCode                                 |
+----------------------------------------------+
| Up/Down:select  s/S:swap up/down  Enter:save  |
+----------------------------------------------+
```

- **Up/Down arrows** — select a CLI
- **s** — swap selected CLI with the one below it
- **S** (Shift+s) — swap selected CLI with the one above it
- **Enter** — save layout and return to project selector
- **Escape** — cancel and return

The layout is saved to `.4pane-layout` and persists between launches.

### Menu Items

| Item | Behavior |
|------|----------|
| **Project names** | Opens all CLIs in that project folder. Shows git branch + last modified time. |
| **`[>] Browse folder...`** | Opens an in-console folder browser rooted at `$projectsDir` (also reachable via the **b** key). Pick any subfolder as the working directory; the choice is saved to history. |
| **`[+] New project...`** | Prompts for a name, creates the folder, then launches. |
| **`[*] Open without directory`** | Launches CLIs with no working directory. |

---

## 5. How It Works Internally

### 5.1 Launch Flow

```
User clicks shortcut
  -> Launch4Panes.vbs (VBS wrapper, invisible, no lingering window)
    -> Launch4Panes.ps1 (PowerShell)
      -> wt.exe -w rwn4ai -M
          Pane 1 (100%): powershell -> Selector.ps1
      -> Stop-Process (kills the launcher PowerShell)
```

### 5.2 Pane Split Math

After the user picks a project in the selector:

```
Starting: Selector(100%)
  Split 1 (from selector pane):
    Pane2 takes 75% of selector -> Pane1=25%, Pane2=75%
    -> Claude(25%) | Kiro(75%)

  Split 2 (from Pane2):
    Pane3 takes 66.67% of Pane2 -> Pane2=25%, Pane3=50%
    -> Claude(25%) | Kiro(25%) | Kimi(50%)

  Split 3 (from Pane3):
    Pane4 takes 50% of Pane3 -> Pane3=25%, Pane4=25%
    -> Claude(25%) | Kiro(25%) | Kimi(25%) | OpenCode(25%)
```

The `-s` flag in `wt.exe split-pane` means "new pane takes this fraction of the **current** pane." Three sequential splits yield 4 equal 25% columns. The split order follows the saved layout — first CLI stays in the original pane, remaining CLIs split off to the right.

### 5.3 Selector Pane Becomes First CLI

After splitting, the selector's PowerShell pane is reused — it clears the menu and launches the first CLI in the layout. No pane is wasted.

### 5.4 Window Naming

The `-w rwn4ai` flag names the Windows Terminal window "rwn4ai". The selector uses this name to target splits into the correct window (`-w rwn4ai split-pane`). This prevents splits from landing in wrong windows if you have multiple wt.exe instances open.

### 5.5 CLI Auto-Detection

At startup, the selector checks for each CLI on PATH:

```powershell
$cliDefs["Claude"] = @{ detect = "claude"; ... }
$cliDefs["Kiro"]   = @{ detect = "kiro-cli"; ... }
$cliDefs["Kimi"]   = @{ detect = "kimi"; ... }
$cliDefs["OpenCode"] = @{ detect = "opencode"; ... }
```

Missing CLIs are skipped — their pane simply doesn't appear. The status bar shows the current layout with availability: `Claude[Y] Kiro[Y] Kimi[Y] OpenCode[Y]` (green if all found, yellow if some missing).

---

## 6. Key Behaviors

| Behavior | Detail |
|----------|--------|
| **4-column layout** | Equal 25% each via three sequential `split-pane` calls. |
| **Maximized** | `-M` flag passed to `wt.exe`. |
| **Auto-close launcher** | `Stop-Process -Id $PID` kills the launcher PowerShell immediately. |
| **History** | Last 5 opened projects remembered and shown at top. Stored in `.4pane-history`. |
| **Layout persistence** | Pane order saved in `.4pane-layout`. Press `o` to change. |
| **Dot-folder exclusion** | Folders starting with `.` are hidden from the menu. |
| **Project info** | Shows git branch and last modified time per project. |
| **Time-ago format** | History shows relative time: "now", "5m", "2h", "1d", "3d". |
| **Pagination** | Projects paginated if list exceeds console height. Page indicator shown. |
| **Box-drawing UI** | `+----+` borders, `>` cursor, color-coded items (yellow=selected, white=project, dark cyan=action). |
| **Framework auto-install** | After selection (before pane split), `Install-Framework` injects the AI framework into the chosen project via `scripts/install-template.sh` (Git Bash), copying core template files directly as a fallback and stamping `.ai/.framework-version`. Template source is `$frameworkRepo` (this repo), falling back to the launcher's own directory if that path is missing or incomplete. Skipped when the marker already exists or the project's git tree is dirty; every attempt is traced to `install-framework.log`, and failures never block the launch. |

---

## 7. File Formats

### History (`.4pane-history`)

JSON, stored alongside scripts:

```json
[
    {
        "project": "my-app",
        "timestamp": "2026-04-18T23:45:00"
    },
    {
        "project": "website",
        "timestamp": "2026-04-18T22:10:33"
    }
]
```

- Max 5 entries (newest first)
- Duplicates are removed (re-selected project moves to top)
- Only real project selections are saved (not "new project" or "no directory")

### Layout (`.4pane-layout`)

JSON array of CLI names in pane order (left to right):

```json
["Claude", "Kiro", "Kimi", "OpenCode"]
```

- Defaults to `["Claude", "Kiro", "Kimi", "OpenCode"]` if file is missing or invalid
- Only installed CLIs are activated; unavailable ones are skipped at runtime

---

## 8. Customization

### Change the projects directory
Edit `$projectsDir` in `Selector.ps1`:
```powershell
$projectsDir = "D:\Projects"
```

### Change CLI commands
Edit the `$cliDefs` table at the top of `Selector.ps1`:
```powershell
$cliDefs["Claude"] = @{ detect = "claude"; cmd = "claude --safe-mode" }
```

### Change pane order
Press **o** in the selector menu, or edit `.4pane-layout` directly.

### Add or remove a CLI
Edit the `$cliDefs` ordered dictionary in `Selector.ps1`. Each entry needs a `detect` command (for PATH checking) and a `cmd` (the full launch command).

---

## 9. Troubleshooting

| Problem | Fix |
|---------|-----|
| Nothing happens when clicking shortcut | The VBS file may be empty. Verify `Launch4Panes.vbs` is not 0 bytes. |
| `wt.exe` not found | Install **Windows Terminal** from the Microsoft Store. |
| Window opens but no selector | Check that `Selector.ps1` exists in the same folder as `Launch4Panes.ps1`. |
| Pane splits are wrong sizes | The `-s` values are sensitive. `0.75`, `0.6667`, `0.5` for 4 equal panes. Adjust carefully. |
| Splits go to wrong window | The `-w rwn4ai` window name targets a specific wt window. Close all wt instances and retry. |
| CLI pane is missing | That CLI isn't on PATH. Install it or check `Get-Command <cli-name>`. |
| Menu looks garbled | Box-drawing characters need a monospace font in Windows Terminal settings. |
| Double PowerShell tab | Windows Terminal may be your default terminal. The `Stop-Process` line auto-closes it. |
| `0x80070002` errors | Wrong argument quoting to `wt.exe`. The fix is `cmd.exe /c` wrapping. |
| Menu exits immediately on keypress | Running in a non-interactive context. Must run via wt.exe, not `powershell -File` directly in some shells. |

---

## 10. Dependencies

- **Windows 10/11**
- **Windows Terminal** (`wt.exe`) — from Microsoft Store
- **PowerShell 5.1+**
- **Git** (optional — for branch display in menu)
- Optional: `claude` CLI on PATH
- Optional: `kiro-cli` CLI on PATH
- Optional: `kimi` CLI on PATH
- Optional: `opencode` CLI on PATH

---

*End of spec. Copy from `tools/4ai-panes/` in this repo, configure paths, create shortcut, done.*
