# rwn 4AI Panes

> **Goal:** One maximized Windows Terminal window with 4 vertical panes — Claude, Kiro, Kimi, OpenCode — no alt-tabbing.

---

## Provenance & Canonical Source

Imported **2026-07-08** from the standalone [rwn-4AI-panes](https://github.com/rwn34/rwn-4AI-panes) repo (local checkout `master` @ `06c5d84`) into this framework repo. **`tools/4ai-panes/` is now the canonical source** — the external repo is a read-only mirror pending archive.

Two per-project **Selector badges** were added at import (`Get-ProjectBadges` in `Selector.ps1`), shown on each project row in the menu:

| Badge | Meaning |
|-------|---------|
| `[v OK]` | `.ai/.framework-version` marker present — current framework install. |
| `[! OLD]` | `.ai/` exists but no version marker — pre-marker install. |
| `[- none]` | No `.ai/` folder — framework not installed in that project. |
| `[H:<n>]` | *n* open cross-CLI handoffs (count of `*.md` files under `.ai/handoffs/to-*/open/`). Hidden when *n* = 0. |

Exactly one of the three framework-version badges appears per project; `[H:<n>]` is appended only when open handoffs exist. Badge checks are deliberately cheap (two `Test-Path` calls + one shallow glob per project) — any error in a broken project dir yields an empty/partial badge, never a crash.

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

---

## 2. Files

| File | Purpose |
|------|---------|
| `Launch4Panes.ps1` | Entry point. Launches wt.exe with the selector as a single full-screen pane. Auto-closes after launch. |
| `Selector.ps1` | Interactive box-drawing menu. Handles project selection, layout customization, and dynamic pane splitting. Also auto-installs the AI framework into the selected project (`Install-Framework`, see §6). After splitting, this pane becomes the first CLI in the layout. |
| `install-framework.log` | Generated at runtime next to the scripts by `Install-Framework` — an append-only trace of each framework install attempt (source, git state, installer exit codes, fallback copies). Not committed. |
| `Launch4Panes.vbs` | VBS wrapper. Opens the PS1 from Start Menu without leaving a lingering window. |
| `icon.ico` | Custom icon for the Start Menu shortcut (dark theme, 4 colored bars). |
| `.gitignore` | Ignores `.4pane-history`, `.4pane-layout`, and `*.tmp`. |

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

1. Copy the tool from `tools/4ai-panes/` in this repo (the canonical source — see [Provenance & Canonical Source](#provenance--canonical-source)):
```powershell
Copy-Item -Recurse <path-to>\rwn-multi-cli-skills\tools\4ai-panes C:\Users\<you>\.rwn-auto\rwn-4AI-panes
```
   The old standalone [rwn-4AI-panes](https://github.com/rwn34/rwn-4AI-panes) GitHub repo is a read-only mirror pending archive — do not clone or install from it.

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
