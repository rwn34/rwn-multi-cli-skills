# Multi-Subproject Open + AI-Panes Explorer — Options & Design (2026-07-11)

Author: claude-code (read-only research + design). Scope: the owner wants to
"open multiple subprojects at once using **browsing mode** (visual how-to) OR
interactively (**ai-panes explorer using b mode**)." The ask is ambiguous, so
this report surfaces concrete options for BOTH interpretations, a recommendation,
and clarifying questions. No code was changed. Evidence is from
tools/4ai-panes/Selector.ps1 and Launch4Panes.ps1.

---

## 1. What exists today (ground truth)

**Selection is strictly SINGLE-project.** Selector.ps1 builds $menuItems (one row
per dir under $projectsDir = C:\Users\rwn34\Code, plus browse/new/nodir actions),
runs an arrow-key key-loop (Draw-Menu + [Console]::ReadKey), and on Enter sets ONE
$script:selected index, breaks the loop, resolves ONE $targetDir, installs the
framework into it, and splits ONE WT tab into that project's pane fleet. There is
no notion of a set of selected projects. (Selector.ps1 ~475-485 build menu;
~830-879 key loop; ~882-923 single-selection resolve.)

**The pane fleet per project** (default RWN_PANE_LAYOUT=6pane): one composite WT tab
= 2 interactive cockpits (app-Claude top-left, Kimi top-right) over a bottom row of
N self-driving pane-runner.ps1 workers (Selector.ps1 ~1016-1061). 5pane and 4grid
are fallbacks. Everything is emitted as ONE $wtCmd string executed via
cmd.exe /c "wt.exe ...".

**Window targeting:** every WT call uses -w rwn4ai (a *named* window). The first tab
is created by Launch4Panes.ps1 (-w rwn4ai -M, maximized); the selector then
new-tab/split-pane's into that SAME named window. This name is the seam that makes
multi-tab batching trivial (see 2.2).

**Badges already computed** by Get-ProjectBadges (Selector.ps1 ~161-201) — exactly
the "visual information" an explorer would surface:
- framework: [v OK] / [! OLD] / [- none]
- handoffs: [H:n], and when a recipient CLI is absent on this host,
  [H:3 stranded:kimi,opencode].
Plus Get-ProjectInfo (git branch + last-modified) and history "Nm ago".

### The "b mode" ambiguity — two different things named "b"
There are **two** independent "b" concepts in the code, and the owner's phrase could
mean either:

1. **b = the Browse-folder key.** The menu footer literally reads
   " Up/Down  Enter  b:browse  n:new  w:no dir  o:order  q:quit" (Selector.ps1 line
   569). Pressing b opens Show-FolderBrowser — an in-console folder tree rooted at
   $projectsDir, arrow-key navigable, drill in/out (Left/Right), c/Enter to select.
   THIS is a "browsing mode" and is the most literal match for "browsing mode / b
   mode." It currently selects exactly ONE folder.
2. **BARE mode = RWN_PANE_BARE=1.** An env var (Selector.ps1 line 980, $bareMode)
   that swaps every self-driving pane-runner pane for a plain interactive CLI REPL.
   Unrelated to a key press. This is what "bare mode" means in ADR-0008; it is NOT
   bound to the b key.

**Most likely reading:** "browsing mode / b mode" = the **b folder-browser**, and the
owner wants that browser to open *multiple* subfolders at once. "bare mode" is a
separate axis (interactive vs self-driving) and probably not what "b mode" refers to
— but confirm (see Clarifying Questions).

### Windows Terminal capability (the enabling mechanism)
wt.exe accepts **multiple subcommands in one invocation**, separated by ";". Each
new-tab opens a fresh tab; subsequent split-pane commands apply to the
most-recently-focused tab. So N projects x a pane fleet each = one long command
string of new-tab ... ; split-pane ... ; split-pane ... ; new-tab ... ; ...
Alternatively, N separate wt -w <name_i> ... invocations open N distinct **windows**.
Both are available today with zero new dependencies — this is the whole reason
"multiple subprojects at once" is cheap.

---

## 2. Interpretation A — BATCH open multiple subprojects at once

Select several projects, launch each in its own WT **tab** (each tab = a full 6-pane
fleet) inside the one rwn4ai window. (A per-window variant is noted below.)

### 2.1 Selector change: multi-select
Add a toggled selection set on top of the existing menu. Minimal, additive:
- Track $script:marked = @{} (project name -> $true).
- **Space** toggles marked[current].
- Render a checkbox in the project row: [x] when marked, [ ] when not.
- **Enter** with >=1 marked = launch ALL marked (batch). Enter with none marked =
  today's single-launch behavior (backward compatible).
- **a** = mark all visible, **c** = clear marks (optional).

ASCII — the multi-select menu (checkbox column added before the number):

```
+--------------------------------------------------------------------+
| rwn-4AI-panes           (Space=toggle  Enter=launch marked)        |
+--------------------------------------------------------------------+
| Claude[Y] Kiro[Y] Kimi[Y] OpenCode[Y]                              |
|--------------------------------------------------------------------|
| >[x]  1 acme-api        [v OK] [H:2]        main | 3m | 5m ago      |
|  [ ]  2 acme-web        [v OK]              main | 1h              |
|  [x]  3 billing-svc     [! OLD] [H:1 stranded:kimi]  dev | 2h      |
|  [ ]  4 marketing-site  [- none]           main | 2d              |
|  [x]  5 data-pipeline   [v OK] [H:4]        feat/x | 12m           |
|--------------------------------------------------------------------|
| Up/Down Space:mark Enter:launch(3) a:all c:clear b:browse o:order  |
+--------------------------------------------------------------------+
   3 marked -> will open 3 tabs in window "rwn4ai"
```

Resulting multi-tab window (each tab is a full 6-pane fleet):

```
+[ acme-api ][ billing-svc ][ data-pipeline ]-----------------------+  <- WT tabs
| +------------------------+------------------------+               |
| | app-Claude (interactive)| Kimi (interactive)    |   TOP 50%     |
| +-----------+------------+-----------+------------+               |
| | claude-   | kiro-      | kimi-     | opencode-  |   BOTTOM 50%  |
| | auto      | runner     | runner    | runner     |   (fleet)     |
| +-----------+------------+-----------+------------+               |
+-------------------------------------------------------------------+
   tab 1 of 3 shown; tabs 2 & 3 hold the same fleet for their project
```

### 2.2 WT command shape (tabs in one window)
Today one project produces (schematically):
```
wt -w rwn4ai new-tab -d "P" <topClaude> ;
   split-pane -H -s 0.5 -d "P" <runner0> ;
   split-pane -V -s <f> -d "P" <runner1> ; ... ;
   move-focus up ; split-pane -V -s 0.5 -d "P" <topKimi>
```
Batch = concatenate that group per project, new-tab starting each new group:
```
wt -w rwn4ai
   new-tab -d "P1" <topClaude1> ; split-pane -H ... ; ... ; split-pane -V -s 0.5 ... <topKimi1> ;
   new-tab -d "P2" <topClaude2> ; split-pane -H ... ; ... ; split-pane -V -s 0.5 ... <topKimi2> ;
   new-tab -d "P3" <topClaude3> ; split-pane -H ... ; ...
```
Implementation: refactor lines ~1016-1061 into a function Build-FleetTabCmd($targetDir)
returning ONE tab's subcommand string, then
foreach ($p in $marked) { $wtCmd += (sep) + (Build-FleetTabCmd $dir) } and run once.
Install-Framework + Save-History must loop over each marked dir.

Caveat: a very long single wt command line can hit cmd.exe length limits with many
projects x many panes. Mitigation: cap batch size (warn > 4 projects), or use the
per-window variant below which issues one invocation per project.

### 2.3 Per-window variant (each subproject = its own window)
Loop, one invocation per project, unique window name so splits land correctly:
```
foreach ($p in $marked) {
    $win = "rwn4ai_" + ($p -replace '\W','_')
    cmd.exe /c ("wt.exe -w " + $win + " -M " + (Build-FleetTabCmd $dir))
    Start-Sleep -Milliseconds 400
}
```
Tradeoff: N windows = alt-tab between projects (against the original "no alt-tabbing"
goal) but avoids command-length limits and isolates a crash to one window. Tabs (2.2)
keep everything in one window — better matches the tool's founding goal.

---

## 3. Interpretation B — Interactive AI-Panes EXPLORER

An interactive browsing UI to explore subprojects by their live badges (framework
version, open-handoff counts, stranded markers) and drill in / launch. Two sub-forms.

### 3.1 TUI explorer (recommended form of B) — arrow-key tree with live badges
Extend the existing box-drawing UI (reuse Draw-Menu, Get-ProjectBadges,
Show-FolderBrowser) into a two-level tree: top-level project -> expandable subprojects
(nested dirs), each row carrying its own badges. Same rendering engine, new row type +
expand/collapse.

```
+--------------------------------------------------------------------+
| ai-panes explorer          (->/Enter expand  Space mark  L launch) |
+--------------------------------------------------------------------+
| v acme                    [v OK] [H:2]      main | 3m               |
|     - api                 [v OK] [H:2]      main | 3m               |
|     - web                 [v OK]            main | 1h               |
|     - infra               [- none]          main | 5d               |
| > billing-svc             [! OLD] [H:1 stranded:kimi]  dev | 2h     |
| > data-pipeline           [v OK] [H:4]      feat/x | 12m            |
| > marketing-site          [- none]          main | 2d              |
|--------------------------------------------------------------------|
| Up/Down  ->:expand  <-:collapse  Space:mark  L:launch  b:bare  q   |
+--------------------------------------------------------------------+
   Legend: [v OK]=framework current  [! OLD]=pre-marker  [- none]=not installed
           [H:n]=open handoffs   stranded:x=recipient CLI absent on this host
```
- Drill-in launch of ONE row = today's behavior. Space-marking multiple rows here =
  the SAME batch launcher as Interpretation A. So B (TUI) is a superset of A — the
  explorer IS the multi-select menu with an expandable subproject tree.
- "b" in the footer here could bind to a per-launch **bare** toggle (RWN_PANE_BARE) so
  the owner explores and then chooses interactive-bare vs self-driving at launch. This
  is the natural home if "b mode" means bare mode.
- Optional live refresh: re-run badge scans on a timer / on r so handoff counts update
  while browsing. Badge scans are deliberately cheap (2 Test-Path + 1 shallow glob per
  project) so a refresh is affordable.

Effort: moderate. All primitives already exist in Selector.ps1; the work is a row
model with an expanded flag + subfolder enumeration + wiring marks into the batch
launcher. Pure PowerShell, no new dependency.

### 3.2 Browser-based explorer (if "browsing mode" means an actual web browser)
If the owner literally means a **browser** (this environment has claude-in-chrome + a
kimi-webbridge skill), an alternative is a tiny local web UI: a PowerShell/Node process
serves an HTML dashboard of project cards (badges, handoff counts, branch), each with
an "Open fleet" button that shells out to the same wt.exe command. Chrome just renders
it.

Tradeoffs vs the TUI:
- (+) Rich visuals (color, grids, could show handoff file contents, click-through).
- (+) Familiar; screenshots/GIFs easy for "visual information."
- (-) New moving part (a local HTTP server + browser) for a tool whose whole point is
  living inside one WT window; adds a dependency and a process to manage.
- (-) Browser -> wt.exe launch needs a local shell bridge; claude-in-chrome drives a
  browser but does not itself spawn terminals, so you still need the local server to
  execute the WT command.
- Verdict: overkill for v1. The TUI (3.1) reuses everything and stays in-terminal. A
  web explorer is a good *later* option if the owner wants a persistent dashboard.

---

## 4. Recommendation

**Build Interpretation A first (multi-select batch open), as the seed of B's TUI.**
Rationale:
- Highest value-per-effort: the WT multi-new-tab mechanism already exists; the only
  real change is a $marked set + checkbox render + a Build-FleetTabCmd refactor of the
  existing 6-pane block. One focused change to Selector.ps1, no new files/deps.
- It directly delivers "open multiple subprojects at once" and keeps the founding "one
  window, no alt-tab" goal by using tabs, not windows.
- It is a strict superset-compatible step toward the explorer: the same $marked batch
  launcher is what the TUI explorer (3.1) calls. Ship multi-select now; add the
  expandable subproject tree + live-badge refresh as phase 2 to become the full
  "ai-panes explorer."

**Minimal first version (phase 1):**
1. $script:marked = @{}; Space toggles; render [x]/[ ] before the number.
2. Enter: if any marked, loop marked -> Install-Framework + Save-History + append
   Build-FleetTabCmd $dir groups into one $wtCmd; run once via cmd.exe /c. If none
   marked -> unchanged single-launch.
3. Guardrail: warn (don't block) when > 4 marked (command-length / resource sanity);
   offer per-window fallback (2.3) for large batches.
Defer: subproject tree expansion, live refresh, bare-toggle key, web UI.

---

## 5. Clarifying questions for the owner (ask before building)

1. **Batch vs explorer** — Do you want (a) select multiple projects and open each in
   its own WT **tab** at once [Interpretation A], or (b) a persistent **explorer** you
   browse project-by-project (with live badges) and launch from [Interpretation B]?
   (A is the fast win and seeds B — is "both, A first" acceptable?)

2. **"b mode" meaning** — Is "b mode" the existing **b folder-browser** key
   (Show-FolderBrowser), or the **BARE** mode (RWN_PANE_BARE=1, interactive REPLs
   instead of self-driving runners)? They are different axes and change the design.

3. **What is a "subproject"** — nested directories *inside* one project (e.g.
   acme/api, acme/web -> an expandable tree, one .ai/ per subdir?), or just the
   separate top-level folders under C:\Users\rwn34\Code you already see in the menu?
   (Determines whether the tree in 3.1 is needed or the flat multi-select in 2.1
   suffices.)

4. **Tabs vs windows** (if batch) — all subprojects as **tabs in the one rwn4ai
   window** (keeps "no alt-tab", risks command-length with many), or **one window per
   subproject** (isolated, but you alt-tab between them)?
