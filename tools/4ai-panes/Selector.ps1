# Selector.ps1 - Interactive project selector for rwn-4AI-panes
# Phase 1: Box-drawing menu with arrow-key navigation
# Phase 2: Splits into 4 panes: Claude | Kiro | Kimi | OpenCode

$ErrorActionPreference = "SilentlyContinue"

# Refresh process PATH from user environment in case the parent process (e.g. Windows Terminal) has a stale PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$procPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
if ($userPath -and $procPath) {
    $missing = @($userPath -split ';' | Where-Object { $_ -and ($procPath -notlike "*$_*") })
    if ($missing.Count -gt 0) {
        [Environment]::SetEnvironmentVariable('Path', "$procPath;$userPath", 'Process')
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectsDir = "C:\Users\rwn34\Code"
$historyFile = Join-Path $scriptDir ".4pane-history"
$layoutFile = Join-Path $scriptDir ".4pane-layout"
$wtExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
$frameworkRepo = if ($env:RWN_FRAMEWORK_REPO) { $env:RWN_FRAMEWORK_REPO } else { "C:/Users/rwn34/Code/rwn-multi-cli-skills" }

# ── Per-tab pane layout (ADR-0009 operator-over-fleet) ── OWNER-TWEAKABLE ──
# RWN_PANE_LAYOUT selects the WT tab layout built per project:
#   '6pane' (default/unset) = TOP row (~50% tall) holding 2 side-by-side NON-polling
#                             interactive cockpits (top-left app-Claude/claude-code,
#                             top-right bare Kimi) OVER a BOTTOM row of 4 self-driving
#                             pane-runner workers (incl. auto-Claude). 2-over-4 fleet.
#   '5pane'                 = fallback: TOP full-width ~50% strip running bare
#                             interactive Claude only + BOTTOM 4 self-driving workers.
#   '4grid'                 = legacy 4-pane grid (instant fallback if the new WT
#                             split misbehaves on this machine).
$paneLayoutMode = if ($env:RWN_PANE_LAYOUT) { $env:RWN_PANE_LAYOUT } else { '6pane' }
# Top ROW height as a fraction of the tab (0.50 = 50%, now holding 2 operators).
# Bottom region (the 4-column fleet) = 1 - this.
$topStripFraction = 0.50

# ── CLI Definitions ──
# Each CLI: name, detection command, launch command
$cliDefs = [ordered]@{}
$cliDefs["Claude"] = @{ detect = "claude"; cmd = "claude --dangerously-skip-permissions" }
$cliDefs["Kiro"]   = @{ detect = "kiro-cli"; cmd = "kiro-cli chat --trust-all-tools --agent orchestrator" }  # v2 interactive form (enforces mechanically in interactive mode per rollup 2026-07-09); --agent pins the hook-bearing orchestrator, bare `chat` runs the hookless built-in default (T-K2). TODO(owner): confirm the v3-TUI launch string that ALSO carries --agent. Evidence 2026-07-09 (kiro-cli-chat 2.12.0): canonical `kiro-cli --v3` (per v3 docs) REJECTS --agent ("error: unexpected argument '--agent'; Usage: kiro-cli.exe --v3"); `--v3 chat` WITHOUT --tui is the classic non-TUI mode the docs say does NOT support v3 (silent v2 fallback); `kiro-cli --v3 chat --tui --agent orchestrator` parses but engine-engagement unverifiable without a TTY. Left on working v2 until owner confirms the v3-TUI string in a live session.
$cliDefs["Kimi"]   = @{ detect = "kimi"; cmd = "kimi --yolo" }
$cliDefs["OpenCode"] = @{ detect = "opencode"; cmd = "opencode --agent opencode" }  # --agent pins the contract-carrying agent (TUI accepts --agent, verified 2026-07-09); no --yolo equivalent — permissions + framework-guard plugin govern (ADR-0002 amendment 2026-07-09)

$cliAvailable = @{}
foreach ($name in $cliDefs.Keys) {
    $cliAvailable[$name] = [bool](Get-Command $cliDefs[$name].detect -ErrorAction SilentlyContinue)
}

$anyAvailable = $false
foreach ($name in $cliAvailable.Keys) {
    if ($cliAvailable[$name]) { $anyAvailable = $true; break }
}
if (-not $anyAvailable) {
    Write-Host "No code CLIs found (claude, kiro-cli, kimi, opencode)." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Stop-Process -Id $PID
}

# ── Layout Management ──
function Get-Layout {
    if (Test-Path $layoutFile) {
        try {
            $raw = Get-Content $layoutFile -Raw | ConvertFrom-Json
            if ($raw -is [array] -and $raw.Count -gt 0) {
                $valid = $true
                foreach ($item in $raw) {
                    if (-not $cliDefs.Contains($item)) { $valid = $false; break }
                }
                if ($valid) { return @($raw) }
            }
        } catch {}
    }
    return @("Claude", "Kiro", "Kimi", "OpenCode")
}

function Save-Layout($layout) {
    ConvertTo-Json -InputObject $layout | Set-Content $layoutFile
}

# ── Project Functions ──
function Get-Projects {
    if (Test-Path $projectsDir) {
        Get-ChildItem -Path $projectsDir -Directory |
            Where-Object { $_.Name -notmatch '^\.' } |
            Select-Object -ExpandProperty Name | Sort-Object
    } else {
        @()
    }
}

function Get-History {
    if (Test-Path $historyFile) {
        try {
            $raw = Get-Content $historyFile -Raw | ConvertFrom-Json
            if ($raw -is [array]) { return $raw }
            if ($raw) { return @($raw) }
            return @()
        } catch { return @() }
    }
    return @()
}

function Save-History($project) {
    $history = @(Get-History)
    $entry = [PSCustomObject]@{
        project = $project
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $history = $history | Where-Object { $_.project -ne $project }
    $history = @($entry) + $history
    $history = $history | Select-Object -First 5
    ConvertTo-Json -InputObject $history | Set-Content $historyFile
}

function Format-TimeAgo($timestamp) {
    try {
        $dt = [datetime]::Parse($timestamp)
        $diff = [datetime]::Now - $dt
        if ($diff.TotalMinutes -lt 1) { return "now" }
        if ($diff.TotalMinutes -lt 60) { return "$([math]::Floor($diff.TotalMinutes))m" }
        if ($diff.TotalHours -lt 24) { return "$([math]::Floor($diff.TotalHours))h" }
        if ($diff.TotalDays -lt 2) { return "1d" }
        return "$([math]::Floor($diff.TotalDays))d"
    } catch { return "" }
}

function Get-ProjectInfo($project) {
    $dir = Join-Path $projectsDir $project
    $branch = $null
    try { $branch = & git -C $dir branch --show-current 2>$null } catch {}

    $modified = (Get-Item $dir -ErrorAction SilentlyContinue).LastWriteTime
    if ($modified) {
        $ago = [datetime]::Now - $modified
        $timeStr = if ($ago.TotalMinutes -lt 60) { "$([math]::Floor($ago.TotalMinutes))m" }
                   elseif ($ago.TotalHours -lt 24) { "$([math]::Floor($ago.TotalHours))h" }
                   else { "$([math]::Floor($ago.TotalDays))d" }
    } else { $timeStr = "" }

    $parts = @()
    if ($branch) { $parts += $branch }
    if ($timeStr) { $parts += $timeStr }
    return $parts -join " "
}

# Per-project status badges shown in the menu row:
#   framework-version: [v OK] = .ai/.framework-version present (current install)
#                      [! OLD] = .ai/ exists but no version marker (pre-marker install)
#                      [- none] = no .ai/ (framework not installed)
#   handoff queue:     [H:<n>] = n open cross-CLI handoffs (.ai/handoffs/to-*/open/*.md),
#                      hidden when n = 0
# Cheap on purpose: two Test-Path calls + one shallow glob per project; any error
# in a broken project dir yields an empty/partial badge, never a crash.
function Get-ProjectBadges($project) {
    $badges = @()
    try {
        $dir = Join-Path $projectsDir $project
        $aiDir = Join-Path $dir ".ai"
        if (Test-Path (Join-Path $aiDir ".framework-version")) { $badges += "[v OK]" }
        elseif (Test-Path $aiDir) { $badges += "[! OLD]" }
        else { $badges += "[- none]" }

        $handoffCount = 0
        $handoffRoot = Join-Path $aiDir "handoffs"
        if (Test-Path $handoffRoot) {
            Get-ChildItem -Path $handoffRoot -Directory -Filter "to-*" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $openDir = Join-Path $_.FullName "open"
                    $handoffCount += @(Get-ChildItem -Path $openDir -Filter "*.md" -File -ErrorAction SilentlyContinue).Count
                }
        }
        if ($handoffCount -gt 0) { $badges += "[H:$handoffCount]" }
    } catch {}
    return $badges -join " "
}

function Find-Bash {
    $onPath = Get-Command bash -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($p in @("C:\Program Files\Git\bin\bash.exe", "C:\Program Files (x86)\Git\bin\bash.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# Warn-only framework drift check. Compares the project's recorded framework
# version (.ai/.framework-version) against the template SSOT
# (tools/multi-cli-install/package.json). Emits a yellow WARNING with the adopt
# command only when the project trails the template. NEVER throws, NEVER mutates:
# any read/parse failure stays silent so a broken marker cannot break launch.
function Test-FrameworkDrift {
    param($ProjVersionFile, $TemplatePkgJson, $AdoptCmd)
    try {
        $projVer = ([version](Get-Content $ProjVersionFile -Raw |
            ConvertFrom-Json).framework_version)
        $tmplVer = ([version](Get-Content $TemplatePkgJson -Raw |
            ConvertFrom-Json).version)
    } catch { return }                      # unparseable / missing => silent
    if ($null -eq $projVer -or $null -eq $tmplVer) { return }
    if ($projVer -lt $tmplVer) {
        Write-Host "Framework drift: project is v$projVer, template is v$tmplVer." `
            -ForegroundColor Yellow
        Write-Host "  To adopt updates: $AdoptCmd" -ForegroundColor Yellow
        Write-Host "  (lands on an isolated 'ai-template-install' branch to review before merging)" `
            -ForegroundColor Yellow
    }
    # projVer >= tmplVer, or equal, or any error => no output.
}

function Install-Framework($targetDir) {
    if ([string]::IsNullOrWhiteSpace($targetDir)) { return }

    $logFile = Join-Path $scriptDir "install-framework.log"
    function Write-InstallLog($msg) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] $msg" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
    Write-InstallLog "=== Install-Framework start ==="
    Write-InstallLog "targetDir: $targetDir"

    $fwMarker = Join-Path $targetDir ".ai\.framework-version"
    Write-InstallLog "framework marker exists: $(Test-Path $fwMarker)"
    if (Test-Path $fwMarker) {
        # Warn-only drift check: resolve the template source the same way the
        # install path does, compare recorded version vs template SSOT, print an
        # advisory adopt command if the project trails. Never auto-updates.
        $src = if ((Test-Path $frameworkRepo) -and (Test-Path (Join-Path $frameworkRepo '.ai'))) {
            $frameworkRepo
        } elseif (Test-Path (Join-Path $scriptDir '.ai')) { $scriptDir } else { $null }

        if ($src) {
            $adopt = "bash $src/scripts/install-template.sh $targetDir"
            Test-FrameworkDrift `
                -ProjVersionFile $fwMarker `
                -TemplatePkgJson (Join-Path $src 'tools/multi-cli-install/package.json') `
                -AdoptCmd $adopt
        }
        Write-InstallLog "Framework marker exists; ran drift check (warn-only), skipping install"
        return
    }

    # Determine the framework template source. Prefer the configured repo,
    # but fall back to the launcher directory if the repo is missing or empty,
    # so the script can still self-inject even when the external repo path
    # is unavailable.
    $fwSource = $null
    if ((Test-Path $frameworkRepo) -and (Test-Path (Join-Path $frameworkRepo '.ai'))) {
        $fwSource = $frameworkRepo
    } elseif (Test-Path (Join-Path $scriptDir '.ai')) {
        $fwSource = $scriptDir
        Write-InstallLog "frameworkRepo unavailable or incomplete; using scriptDir as template source"
    }
    Write-InstallLog "fwSource: $fwSource"

    if (-not $fwSource) {
        Write-Host "Framework template source not found; skipping framework install" -ForegroundColor Yellow
        Write-InstallLog "Skipped: no framework template source"
        return
    }

    $bashExe = Find-Bash
    Write-InstallLog "bashExe: $bashExe"
    if (-not $bashExe) {
        Write-Host "Git Bash not found; will try direct template copy fallback" -ForegroundColor Yellow
        Write-InstallLog "Git Bash not found; proceeding to fallback copy"
    }

    $hadCommits = $false
    $gitExists = Test-Path (Join-Path $targetDir ".git")
    Write-InstallLog ".git exists: $gitExists"
    if ($gitExists) {
        & git -C $targetDir rev-parse HEAD 2>$null | Out-Null
        $hadCommits = ($LASTEXITCODE -eq 0)
        Write-InstallLog "rev-parse HEAD exit: $LASTEXITCODE, hadCommits: $hadCommits"
    } else {
        Write-InstallLog "Running git init"
        & git -C $targetDir init | Out-Null
        Write-InstallLog "git init exit: $LASTEXITCODE"
    }
    if (-not $hadCommits) {
        # Newly-initialized repos often lack user identity; set a local one so
        # the initial commit and the installer's commit both succeed.
        & git -C $targetDir config user.email "ai-framework@local" 2>$null | Out-Null
        & git -C $targetDir config user.name "AI Framework Installer" 2>$null | Out-Null
        & git -C $targetDir add -A 2>$null | Out-Null
        Write-InstallLog "git add exit: $LASTEXITCODE"
        & git -C $targetDir commit --allow-empty -m "init" 2>$null | Out-Null
        Write-InstallLog "git commit exit: $LASTEXITCODE"
    } else {
        $dirty = & git -C $targetDir status --porcelain 2>$null
        Write-InstallLog "git status porcelein length: $($dirty.Length)"
        if ($dirty) {
            Write-Host "Project has uncommitted changes; skipping framework install to avoid sweeping them into the install commit. Commit/stash and re-open to adopt." -ForegroundColor Yellow
            Write-InstallLog "Skipped: dirty working tree"
            return
        }
    }

    $bashTarget = $targetDir -replace '\\', '/'
    $installer = "$fwSource/scripts/install-template.sh"
    $name = Split-Path $targetDir -Leaf
    Write-InstallLog "installer: $installer"
    Write-InstallLog "bashTarget: $bashTarget"
    if ($bashExe) {
        try {
            $output = & $bashExe $installer $bashTarget 2>&1
            Write-InstallLog "installer exit code: $LASTEXITCODE"
            Write-InstallLog "installer output length: $($output.Length)"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Framework installed into $name" -ForegroundColor Green
                Write-InstallLog "Success"
            } else {
                Write-Host "Framework install failed (continuing to launch):" -ForegroundColor Yellow
                Write-Host ($output | Out-String) -ForegroundColor Yellow
                Write-InstallLog "FAILED"
                Write-InstallLog ($output | Out-String)
            }
        } catch {
            Write-Host "Framework install errored (continuing to launch): $_" -ForegroundColor Yellow
            Write-InstallLog "ERROR: $_"
        }
    }
    $templateItems = @(
        '.ai',
        '.claude',
        '.kimi',
        '.kiro',
        '.archive',
        'CLAUDE.md',
        'AGENTS.md',
        '.opencode',
        'opencode.json',
        '.mcp.json.example',
        'docs/architecture/0001-root-file-exceptions.md',
        'docs/architecture/0002-cli-role-topology.md',
        'docs/architecture/0003-code-graph-rationalization.md',
        '.github/workflows/framework-check.yml',
        '.github/workflows/gates.yml',
        '.codegraph/config.json'
    )
    $missingItems = @($templateItems | Where-Object { -not (Test-Path (Join-Path $targetDir $_)) })
    Write-InstallLog "post-install missing items: $($missingItems -join ', ')"

    # Fallback: if the installer didn't create all required items (failed early,
    # missing git, verification failed before copy, etc.), copy the core template
    # files ourselves so the selected folder is never left incomplete.
    if ($missingItems.Count -gt 0) {
        Write-Host "Framework install incomplete; injecting missing template files directly..." -ForegroundColor Yellow
        Write-InstallLog "Fallback: copying core framework template files"
        foreach ($item in $templateItems) {
            $src = Join-Path $fwSource $item
            $dst = Join-Path $targetDir $item
            if (-not (Test-Path $src)) {
                Write-InstallLog "Fallback skip (source missing): $item"
                continue
            }
            try {
                if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
                if (Test-Path $src -PathType Container) {
                    Copy-Item -Path $src -Destination $dst -Recurse -Force
                } else {
                    $parent = Split-Path -Parent $dst
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -Path $src -Destination $dst -Force
                }
                Write-InstallLog "Fallback copied: $item"
            } catch {
                Write-InstallLog "Fallback failed to copy ${item}: $_"
            }
        }

        # Reset the activity log to the clean template header so it doesn't
        # contain the template repo's history.
        $activityLog = Join-Path $targetDir '.ai\activity\log.md'
        if (Test-Path $activityLog) {
            $cleanHeader = @(
                '# Activity Log',
                '',
                'Newest entries at the top. Each CLI prepends an entry after completing substantive work.',
                '',
                '**Timestamp rule:** the `HH:MM` in each entry heading is local wall-clock time at the',
                'moment of prepending (i.e. when the work finished, not when it started). CLIs on',
                'different local clocks may produce timestamps that don''t sort monotonically;',
                '**prepend order is the authoritative sequencing**, timestamps are annotations.',
                '',
                '**Archive:** older entries live in `.ai/activity/archive/YYYY-MM.md` (one file per',
                'calendar month). See `.ai/activity/archive/README.md` for the rollover protocol.',
                '',
                '---',
                ''
            ) -join "`r`n"
            $cleanHeader | Set-Content -Path $activityLog -Encoding utf8 -NoNewline
            Write-InstallLog "Fallback reset activity log"
        }

        # Stamp a minimal framework version marker. Resolve the version from the
        # framework repo's installer package.json at runtime; fall back to the
        # last-known literal only if it is unreadable.
        try {
            $fwVersion = '0.0.5'
            try {
                $pkgPath = Join-Path $frameworkRepo 'tools/multi-cli-install/package.json'
                $pkgVersion = (Get-Content $pkgPath -Raw -ErrorAction Stop | ConvertFrom-Json).version
                if ($pkgVersion) { $fwVersion = $pkgVersion }
            } catch {
                Write-InstallLog "Fallback could not read installer package.json; using literal $fwVersion"
            }
            $markerDir = Join-Path $targetDir '.ai'
            if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
            $markerPath = Join-Path $markerDir '.framework-version'
            $markerJson = @{
                framework_version = $fwVersion
                installer_name = 'Selector.ps1 fallback'
                installer_version = $fwVersion
                installed_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                upgrade_history = @()
            } | ConvertTo-Json -Depth 3
            $markerJson | Set-Content -Path $markerPath -Encoding utf8
            Write-InstallLog "Fallback wrote .ai/.framework-version"
        } catch {
            Write-InstallLog "Fallback failed to write marker: $_"
        }

        Write-Host "Framework files injected into $name" -ForegroundColor Green
    }

    Write-InstallLog "=== Install-Framework end ==="
}

# ── Build Menu Items ──
$allProjects = Get-Projects
$history = Get-History

$ordered = [System.Collections.ArrayList]::new()
$seen = @{}
foreach ($h in $history) {
    if (($allProjects -contains $h.project) -and -not $seen.ContainsKey($h.project)) {
        [void]$ordered.Add($h.project)
        $seen[$h.project] = $true
    }
}
foreach ($p in $allProjects) {
    if (-not $seen.ContainsKey($p)) {
        [void]$ordered.Add($p)
        $seen[$p] = $true
    }
}

$menuItems = [System.Collections.ArrayList]::new()
foreach ($p in $ordered) {
    $info = Get-ProjectInfo -project $p
    $histEntry = $history | Where-Object { $_.project -eq $p } | Select-Object -First 1
    $ago = if ($histEntry) { Format-TimeAgo -timestamp $histEntry.timestamp } else { "" }
    $badges = Get-ProjectBadges -project $p
    [void]$menuItems.Add(@{ name = $p; info = $info; lastUsed = $ago; badges = $badges; type = 'project' })
}
[void]$menuItems.Add(@{ name = '[>] Browse folder...'; info = ''; lastUsed = ''; type = 'browse' })
[void]$menuItems.Add(@{ name = '[+] New project...'; info = ''; lastUsed = ''; type = 'new' })
[void]$menuItems.Add(@{ name = '[*] Open without directory'; info = ''; lastUsed = ''; type = 'nodir' })

# ── Interactive Menu ──
$script:selected = 0
$script:pageOffset = 0
$script:pageSize = [Math]::Max(3, [Console]::WindowHeight - 13)

function Draw-Menu {
    $conW = [Console]::WindowWidth
    $boxW = [Math]::Max(40, [Math]::Min(72, $conW - 2))
    $innerW = $boxW - 2

    if ($script:selected -lt $script:pageOffset) { $script:pageOffset = $script:selected }
    if ($script:selected -ge $script:pageOffset + $script:pageSize) {
        $script:pageOffset = $script:selected - $script:pageSize + 1
    }

    $visibleCount = [Math]::Min($script:pageSize, $menuItems.Count - $script:pageOffset)

    Clear-Host

    Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan
    $title = " rwn-4AI-panes"
    Write-Host ("|" + $title.PadRight($innerW) + "|") -ForegroundColor Cyan
    Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

    # CLI status
    $layout = Get-Layout
    $statusParts = @()
    foreach ($name in $layout) {
        $avail = if ($cliAvailable[$name]) { "Y" } else { "N" }
        $statusParts += "$name[$avail]"
    }
    $allOK = $true
    foreach ($name in $layout) {
        if (-not $cliAvailable[$name]) { $allOK = $false; break }
    }
    $statusColor = if ($allOK) { "Green" } else { "Yellow" }
    $status = " " + ($statusParts -join " ")
    Write-Host ("|" + $status.PadRight($innerW) + "|") -ForegroundColor $statusColor

    # Separator
    Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray

    # Items
    for ($i = 0; $i -lt $visibleCount; $i++) {
        $idx = $script:pageOffset + $i
        $item = $menuItems[$idx]
        $isSel = ($idx -eq $script:selected)

        if ($item.type -eq 'project') {
            $marker = if ($isSel) { " >" } else { "  " }
            $num = "$($idx + 1)".PadLeft(2)
            $namePart = "$marker $num $($item.name)"
            if ($item.badges) { $namePart += " $($item.badges)" }

            $infoParts = @()
            if ($item.info) { $infoParts += $item.info }
            if ($item.lastUsed) { $infoParts += "$($item.lastUsed) ago" }
            $infoStr = $infoParts -join " | "

            $spaceForInfo = $innerW - $namePart.Length - 1
            if ($spaceForInfo -gt 8 -and $infoStr.Length -gt 0) {
                if ($infoStr.Length -gt $spaceForInfo) {
                    $infoStr = $infoStr.Substring(0, $spaceForInfo - 2) + ".."
                }
                $line = $namePart + " " + $infoStr.PadLeft($spaceForInfo - 1)
            } else {
                $line = $namePart
            }

            if ($line.Length -gt $innerW) { $line = $line.Substring(0, $innerW) }
            $color = if ($isSel) { "Yellow" } else { "White" }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        } else {
            $marker = if ($isSel) { " >" } else { "  " }
            $line = "$marker $($item.name)"
            $color = if ($isSel) { "Yellow" } else { "DarkCyan" }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        }
    }

    # Footer
    Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray
    $footer = " Up/Down  Enter  b:browse  n:new  w:no dir  o:order  q:quit"
    if ($footer.Length -gt $innerW) { $footer = $footer.Substring(0, $innerW) }
    Write-Host ("|" + $footer.PadRight($innerW) + "|") -ForegroundColor DarkGray
    Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

    if ($menuItems.Count -gt $script:pageSize) {
        $totalPages = [Math]::Ceiling($menuItems.Count / $script:pageSize)
        $currentPage = [Math]::Floor($script:pageOffset / $script:pageSize) + 1
        Write-Host " Page $currentPage/$totalPages ($($menuItems.Count) items)" -ForegroundColor DarkGray
    }
}

function Show-LayoutPicker {
    $layout = Get-Layout
    $available = @($layout | Where-Object { $cliAvailable[$_] })
    if ($available.Count -lt 2) {
        Write-Host "Need at least 2 CLIs to rearrange." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    $pickSel = 0
    $done = $false
    while (-not $done) {
        Clear-Host
        $conW = [Console]::WindowWidth
        $boxW = [Math]::Max(40, [Math]::Min(72, $conW - 2))
        $innerW = $boxW - 2

        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Magenta
        Write-Host ("|" + " Pane Order (Up/Down to reorder, Enter to confirm)".PadRight($innerW) + "|") -ForegroundColor Magenta
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Magenta

        for ($i = 0; $i -lt $available.Count; $i++) {
            $marker = if ($i -eq $pickSel) { ">" } else { " " }
            $paneNum = $i + 1
            $avail = if ($cliAvailable[$available[$i]]) { "" } else { " (not installed)" }
            $line = " $marker $paneNum. $($available[$i])$avail"
            $color = if ($i -eq $pickSel) { "Yellow" } else { "White" }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        }

        Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray
        $helpLine = " Up/Down:select  s/S:swap up/down  Enter:save  Esc:cancel"
        if ($helpLine.Length -gt $innerW) { $helpLine = $helpLine.Substring(0, $innerW) }
        Write-Host ("|" + $helpLine.PadRight($innerW) + "|") -ForegroundColor DarkGray
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Magenta

        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $pickSel = [Math]::Max(0, $pickSel - 1) }
            'DownArrow' { $pickSel = [Math]::Min($available.Count - 1, $pickSel + 1) }
            'Enter'     { $done = $true }
            'Escape'    { return }
            default {
                $ch = $key.KeyChar
                if ($ch -eq 's') {
                    if ($pickSel -lt $available.Count - 1) {
                        $tmp = $available[$pickSel]
                        $available[$pickSel] = $available[$pickSel + 1]
                        $available[$pickSel + 1] = $tmp
                        $pickSel++
                    }
                }
                elseif ($ch -eq 'S') {
                    if ($pickSel -gt 0) {
                        $tmp = $available[$pickSel]
                        $available[$pickSel] = $available[$pickSel - 1]
                        $available[$pickSel - 1] = $tmp
                        $pickSel--
                    }
                }
            }
        }
    }

    Save-Layout -layout $available
}

# ── Folder Browser ──
function Show-FolderBrowser {
    param([string]$Root = $projectsDir)

    $current = Resolve-Path $Root -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path
    if (-not $current -or -not (Test-Path $current -PathType Container)) {
        $current = $PSScriptRoot
    }

    function Get-BrowserItems($path) {
        $list = [System.Collections.ArrayList]::new()
        [void]$list.Add([PSCustomObject]@{ name = './'; path = $path; type = 'current' })

        $canGoUpLocal = ($path -ne $projectsDir) -and
            ($path.StartsWith($projectsDir, [System.StringComparison]::OrdinalIgnoreCase))
        if ($canGoUpLocal) {
            $parent = Split-Path -Parent $path
            [void]$list.Add([PSCustomObject]@{ name = '../'; path = $parent; type = 'parent' })
        }

        try {
            Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name |
                ForEach-Object {
                    [void]$list.Add([PSCustomObject]@{
                        name = $_.Name + '/'
                        path = $_.FullName
                        type = 'dir'
                    })
                }
        } catch {}

        return $list
    }

    function Get-FirstSubfolderIndex($list) {
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i].type -eq 'dir') { return $i }
        }
        return -1
    }

    $initialItems = Get-BrowserItems -path $current
    $initialFirstSub = Get-FirstSubfolderIndex -list $initialItems
    $sel = if ($initialFirstSub -ge 0) { $initialFirstSub } else { 0 }
    $pageOffset = 0
    $pageSize = [Math]::Max(3, [Console]::WindowHeight - 13)
    $done = $false
    $cancel = $false

    while (-not $done) {
        $items = Get-BrowserItems -path $current
        $canGoUp = ($current -ne $projectsDir) -and
            ($current.StartsWith($projectsDir, [System.StringComparison]::OrdinalIgnoreCase))

        if ($sel -lt 0) { $sel = 0 }
        if ($sel -ge $items.Count) { $sel = [Math]::Max(0, $items.Count - 1) }
        if ($sel -lt $pageOffset) { $pageOffset = $sel }
        if ($sel -ge $pageOffset + $pageSize) { $pageOffset = $sel - $pageSize + 1 }

        $visibleCount = [Math]::Min($pageSize, $items.Count - $pageOffset)

        $conW = [Console]::WindowWidth
        $boxW = [Math]::Max(40, [Math]::Min(72, $conW - 2))
        $innerW = $boxW - 2

        Clear-Host
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan
        Write-Host ("|" + " Browse Folder".PadRight($innerW) + "|") -ForegroundColor Cyan
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

        $pathLine = " " + $current
        if ($pathLine.Length -gt $innerW) { $pathLine = $pathLine.Substring(0, $innerW - 3) + "..." }
        Write-Host ("|" + $pathLine.PadRight($innerW) + "|") -ForegroundColor DarkGray
        Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray

        for ($i = 0; $i -lt $visibleCount; $i++) {
            $idx = $pageOffset + $i
            $item = $items[$idx]
            $isSel = ($idx -eq $sel)
            $marker = if ($isSel) { ">" } else { " " }
            $line = " $marker $($item.name)"
            $color = if ($isSel) { "Yellow" } else { "White" }
            if ($item.type -eq 'parent') { $color = if ($isSel) { "Yellow" } else { "DarkGray" } }
            elseif ($item.type -eq 'current') { $color = if ($isSel) { "Yellow" } else { "Green" } }
            Write-Host ("|" + $line.PadRight($innerW) + "|") -ForegroundColor $color
        }

        for ($i = $visibleCount; $i -lt $pageSize; $i++) {
            Write-Host ("|" + (" " * $innerW) + "|") -ForegroundColor DarkGray
        }

        Write-Host ("|" + ("-" * $innerW) + "|") -ForegroundColor DarkGray
        $help = " Up/Down  Enter/Right:open/select  Left/Back:up  c:select  Esc:cancel"
        if ($help.Length -gt $innerW) { $help = $help.Substring(0, $innerW) }
        Write-Host ("|" + $help.PadRight($innerW) + "|") -ForegroundColor DarkGray
        Write-Host ("+" + "-" * $innerW + "+") -ForegroundColor Cyan

        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'    { $sel = [Math]::Max(0, $sel - 1) }
            'DownArrow'  { $sel = [Math]::Min([Math]::Max(0, $items.Count - 1), $sel + 1) }
            'Enter'      {
                if ($items.Count -gt 0) {
                    if ($items[$sel].type -eq 'current') {
                        return $items[$sel].path
                    }
                    $current = $items[$sel].path
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'RightArrow' {
                if ($items.Count -gt 0) {
                    if ($items[$sel].type -eq 'current') {
                        return $items[$sel].path
                    }
                    $current = $items[$sel].path
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'LeftArrow'  {
                if ($canGoUp) {
                    $current = Split-Path -Parent $current
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'Backspace'  {
                if ($canGoUp) {
                    $current = Split-Path -Parent $current
                    $newItems = Get-BrowserItems -path $current
                    $firstSub = Get-FirstSubfolderIndex -list $newItems
                    $sel = if ($firstSub -ge 0) { $firstSub } else { 0 }
                    $pageOffset = 0
                }
            }
            'Escape'     { $done = $true; $cancel = $true }
            default {
                $ch = $key.KeyChar
                if ($ch -eq 'c') {
                    if ($items.Count -gt 0) {
                        return $items[$sel].path
                    }
                    return $current
                }
                elseif ($ch -eq 'q') {
                    $done = $true; $cancel = $true
                }
            }
        }
    }

    if ($cancel) { return $null }
    return $current
}

$script:targetDirFromBrowse = $null

function Invoke-Browse {
    $path = Show-FolderBrowser -Root $projectsDir
    if ($path) {
        $script:targetDirFromBrowse = $path
        for ($i = 0; $i -lt $menuItems.Count; $i++) {
            if ($menuItems[$i].type -eq 'browse') {
                $script:selected = $i
                break
            }
        }
        return $true
    }
    return $false
}

# ── Key Loop ──
$done = $false
while (-not $done) {
    Draw-Menu
    $key = [System.Console]::ReadKey($true)

    switch ($key.Key) {
        'UpArrow'   { $script:selected = [Math]::Max(0, $script:selected - 1) }
        'DownArrow' { $script:selected = [Math]::Min($menuItems.Count - 1, $script:selected + 1) }
        'Enter'     {
            if ($menuItems[$script:selected].type -eq 'browse') {
                if (Invoke-Browse) { $done = $true }
            } else {
                $done = $true
            }
        }
        'Escape'    { Stop-Process -Id $PID }
        'PageUp'    { $script:selected = [Math]::Max(0, $script:selected - $script:pageSize) }
        'PageDown'  { $script:selected = [Math]::Min($menuItems.Count - 1, $script:selected + $script:pageSize) }
        'Home'      { $script:selected = 0 }
        'End'       { $script:selected = $menuItems.Count - 1 }
        default {
            $ch = $key.KeyChar
            if ($ch -eq 'b') {
                if (Invoke-Browse) { $done = $true }
            }
            elseif ($ch -eq 'n') {
                for ($i = 0; $i -lt $menuItems.Count; $i++) {
                    if ($menuItems[$i].type -eq 'new') { $script:selected = $i; break }
                }
                $done = $true
            }
            elseif ($ch -eq 'w') {
                for ($i = 0; $i -lt $menuItems.Count; $i++) {
                    if ($menuItems[$i].type -eq 'nodir') { $script:selected = $i; break }
                }
                $done = $true
            }
            elseif ($ch -eq 'o') { Show-LayoutPicker }
            elseif ($ch -eq 'q') { Stop-Process -Id $PID }
            elseif ($ch -match '[0-9]') {
                $num = [int]$ch.ToString()
                if ($num -ge 1 -and $num -le $menuItems.Count) {
                    $script:selected = $num - 1
                    $done = $true
                }
            }
        }
    }
}

# ── Process Selection ──
$chosen = $menuItems[$script:selected]
$targetDir = $null

switch ($chosen.type) {
    'project' {
        $targetDir = Join-Path $projectsDir $chosen.name
        Save-History -project $chosen.name
    }
    'new' {
        Clear-Host
        Write-Host "+----------------------+" -ForegroundColor Cyan
        Write-Host "| Create New Project   |" -ForegroundColor Cyan
        Write-Host "+----------------------+" -ForegroundColor Cyan
        $name = Read-Host "Project name"
        if ([string]::IsNullOrWhiteSpace($name)) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            Stop-Process -Id $PID
        }
        $targetDir = Join-Path $projectsDir $name
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
            Write-Host "Created: $targetDir" -ForegroundColor Green
        }
        Save-History -project $name
        Start-Sleep -Milliseconds 500
    }
    'browse' {
        $targetDir = $script:targetDirFromBrowse
        if ($targetDir) {
            $histName = Split-Path $targetDir -Leaf
            if ($targetDir.StartsWith($projectsDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rel = $targetDir.Substring($projectsDir.Length).TrimStart('\', '/')
                if ($rel) { $histName = $rel }
            }
            Save-History -project $histName
        }
    }
    'nodir' {
        $targetDir = $null
    }
}

# ── Install Framework ──
Install-Framework -targetDir $targetDir

# ── Split Panes ──
# The selector pane becomes the first CLI in the layout.
# We split off panes for the remaining CLIs.
# Layout math: starting from 100%, each split takes the right portion.
# Split 1: pane2 takes 75% of current -> pane1=25%, pane2=75%
# Split 2: pane3 takes 66.67% of pane2 -> pane2=25%, pane3=50%
# Split 3: pane4 takes 50% of pane3 -> pane3=25%, pane4=25%
# Result: 25% each for 4 panes.

Clear-Host
$layout = Get-Layout
$activeCLIs = @($layout | Where-Object { $cliAvailable[$_] })
$launching = $activeCLIs -join ', '
Write-Host "Launching $launching..." -ForegroundColor Cyan

if ($activeCLIs.Count -eq 0) {
    Write-Host "No CLIs available." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Stop-Process -Id $PID
}

# Kiro agent injection
if ($cliAvailable["Kiro"] -and $targetDir) {
    $globalKiroAgents = Join-Path $env:USERPROFILE ".kiro\agents"
    $backupAgents = Join-Path $scriptDir ".kiro\agents"
    if (Test-Path $backupAgents) {
        try {
            $didCopy = $false
            Get-ChildItem -Path $backupAgents -Filter "*.json" | ForEach-Object {
                $dest = Join-Path $globalKiroAgents $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item -Path $_.FullName -Destination $dest -Force
                    $didCopy = $true
                }
            }
            if ($didCopy) {
                Write-Host "Injected Kiro agents into global profile" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "Warning: failed to inject Kiro agents: $_" -ForegroundColor Yellow
        }
    }
}

# ── Pane launch: self-driving runner vs bare CLI (ADR-0008) ──
# Each pane normally launches pane-runner.ps1 (the self-driving supervisor loop
# that auto-continues + auto-executes handoffs for its CLI). Fall back to the
# bare interactive CLI when the owner wants a plain REPL: set env RWN_PANE_BARE=1,
# or when there is no project dir (nodir mode) — the runner needs a project's
# .ai/ to watch, so no-dir always uses the bare CLI.
$cliLower = @{ Claude = 'claude'; Kiro = 'kiro'; Kimi = 'kimi'; OpenCode = 'opencode' }
$paneRunner = Join-Path $scriptDir 'pane-runner.ps1'
$bareMode = ($env:RWN_PANE_BARE -and $env:RWN_PANE_BARE -ne '0' -and $env:RWN_PANE_BARE -ne 'false')

# ── Layout gating ──
# 6pane/5pane both need a project dir (the runner watches its .ai/), an available
# Claude, the runner script, and non-bare mode. Anything else (4grid, bare, nodir,
# unknown RWN_PANE_LAYOUT value, missing Claude/runner) falls through to the legacy
# 4-grid path below — the instant, always-safe fallback.
$layoutSupported = $targetDir -and $cliAvailable['Claude'] `
                   -and (Test-Path $paneRunner) -and (-not $bareMode)
$use6pane = ($paneLayoutMode -eq '6pane') -and $layoutSupported
$use5pane = ($paneLayoutMode -eq '5pane') -and $layoutSupported

# ── 6-pane dual-operator-over-fleet layout (ADR-0009 / owner-directed 2026-07-10) ──
# Build ONE composite WT tab as a 2-over-4 grid:
#   TOP row  (topStripFraction = 50% tall) = 2 side-by-side NON-polling interactive
#            cockpits: top-LEFT = app-Claude (identity claude-code), top-RIGHT = bare
#            Kimi. Neither runs the pane-runner (no auto-continue, no claim, no poll).
#            ROLE INTENT: top-LEFT Claude is the owner's app-paired / remote-control
#            session (session-sharing with the Claude app) -- NOT a fleet executor.
#            top-RIGHT Kimi is the owner's general operator for asides / ad-hoc
#            questions -- NOT an executor lane.
#   BOTTOM row (50% tall) = up to N equal columns, each running the self-driving
#            pane-runner worker (the Claude column self-IDs as claude-auto). Same
#            fleet behavior as the 5pane bottom.
#
# WT split sequence (each split acts on the FOCUSED pane; -s sizes the NEW pane):
#   1. new-tab               -> P0 : top pane, full width (top-LEFT interactive Claude).
#   2. split-pane -H -s 0.5  -> B0 : bottom pane, full width, 50% tall (runner CLI[0]);
#                                    focus moves to B0.
#   3. split-pane -V (xN-1)  -> cut the bottom into N equal columns (pane-runners); the
#                                    k-th split gives the new pane (N-k)/(N-k+1) of the
#                                    focused region, leaving 1/N per column overall.
#   4. move-focus up         -> return focus to the still-single full-width top pane P0.
#   5. split-pane -V -s 0.5  -> split P0 into top-LEFT (Claude, kept) + top-RIGHT (Kimi).
# The top-RIGHT Kimi split is only emitted when Kimi is available; otherwise the top
# row stays one full-width interactive Claude (graceful degrade, never a broken split).
if ($use6pane) {
    $dq = '"'
    $bottomCLIs = $activeCLIs                      # available CLIs, layout order
    $n = $bottomCLIs.Count

    # TOP-LEFT pane: bare interactive Claude (app-Claude). No pane-runner, no -Owner.
    $topCmd = "powershell -NoExit -NoProfile -Command $dq$($cliDefs['Claude'].cmd)$dq"
    $wtCmd = "-w rwn4ai new-tab -d $dq$targetDir$dq $topCmd"

    # BOTTOM pane 1: split-pane -H, new (bottom) pane takes (1 - topStripFraction) = 0.5.
    $bottomFraction = [math]::Round(1 - $topStripFraction, 4)
    $runner0 = "powershell -NoExit -NoProfile -File $dq$paneRunner$dq -Cli $($cliLower[$bottomCLIs[0]]) -ProjectDir $dq$targetDir$dq"
    $wtCmd += " ; split-pane -H -s $bottomFraction -d $dq$targetDir$dq $runner0"

    # BOTTOM panes 2..N: vertical splits sized for N equal columns. Each split operates
    # on the focused (rightmost) region; the k-th split (k = 1..N-1) gives the new pane
    # (N-k)/(N-k+1) of that region, leaving 1/N per column overall.
    for ($i = 1; $i -lt $n; $i++) {
        $frac = [math]::Round(($n - $i) / ($n - $i + 1), 4)
        $runner = "powershell -NoExit -NoProfile -File $dq$paneRunner$dq -Cli $($cliLower[$bottomCLIs[$i]]) -ProjectDir $dq$targetDir$dq"
        $wtCmd += " ; split-pane -V -s $frac -d $dq$targetDir$dq $runner"
    }

    # TOP-RIGHT operator: move focus back up to the full-width top pane, then split it
    # 50/50 to place bare interactive Kimi on the right. Skip when Kimi is unavailable
    # so we never emit a broken split (top stays a single full-width Claude).
    if ($cliAvailable['Kimi']) {
        $topRightCmd = "powershell -NoExit -NoProfile -Command $dq$($cliDefs['Kimi'].cmd)$dq"
        $wtCmd += " ; move-focus up ; split-pane -V -s 0.5 -d $dq$targetDir$dq $topRightCmd"
    }

    $topDesc = if ($cliAvailable['Kimi']) { 'app-Claude | Kimi' } else { 'app-Claude' }
    Write-Host "6-pane layout (top=$topDesc, bottom=$($bottomCLIs -join ', ')):" -ForegroundColor Cyan
    Write-Host "  `"$wtExe`" $wtCmd" -ForegroundColor DarkGray
    try {
        & cmd.exe /c "`"$wtExe`" $wtCmd"
        Write-Host "Launched $(Split-Path -Leaf $targetDir) in a new tab." -ForegroundColor Green
    } catch {
        Write-Host "Failed to launch 6-pane layout: $_" -ForegroundColor Red
    }
    return
}

# ── 5-pane operator-over-fleet layout (retained fallback: RWN_PANE_LAYOUT=5pane) ──
# Build ONE composite WT tab: new-tab = TOP pane (bare interactive Claude =
# app-Claude, identity claude-code, NOT the pane-runner); split-pane -H sizes the
# new bottom region to (1 - topStripFraction) so the top strip is topStripFraction;
# then N-1 vertical splits cut the bottom into equal columns, each running the
# self-driving pane-runner (the Claude column self-IDs as claude-auto).
if ($use5pane) {
    $dq = '"'
    $bottomCLIs = $activeCLIs                      # available CLIs, layout order
    $n = $bottomCLIs.Count

    # TOP pane: bare interactive Claude (app-Claude). No pane-runner, no -Owner.
    $topCmd = "powershell -NoExit -NoProfile -Command $dq$($cliDefs['Claude'].cmd)$dq"
    $wtCmd = "-w rwn4ai new-tab -d $dq$targetDir$dq $topCmd"

    # BOTTOM pane 1: split-pane -H, new (bottom) pane takes (1 - topStripFraction).
    $bottomFraction = [math]::Round(1 - $topStripFraction, 4)
    $runner0 = "powershell -NoExit -NoProfile -File $dq$paneRunner$dq -Cli $($cliLower[$bottomCLIs[0]]) -ProjectDir $dq$targetDir$dq"
    $wtCmd += " ; split-pane -H -s $bottomFraction -d $dq$targetDir$dq $runner0"

    # BOTTOM panes 2..N: vertical splits sized for N equal columns. Each split
    # operates on the focused (rightmost) region; the k-th split (k = 1..N-1) gives
    # the new pane (N-k)/(N-k+1) of that region, leaving 1/N per column overall.
    for ($i = 1; $i -lt $n; $i++) {
        $frac = [math]::Round(($n - $i) / ($n - $i + 1), 4)
        $runner = "powershell -NoExit -NoProfile -File $dq$paneRunner$dq -Cli $($cliLower[$bottomCLIs[$i]]) -ProjectDir $dq$targetDir$dq"
        $wtCmd += " ; split-pane -V -s $frac -d $dq$targetDir$dq $runner"
    }

    Write-Host "5-pane layout (top=app-Claude, bottom=$($bottomCLIs -join ', ')):" -ForegroundColor Cyan
    Write-Host "  `"$wtExe`" $wtCmd" -ForegroundColor DarkGray
    try {
        & cmd.exe /c "`"$wtExe`" $wtCmd"
        Write-Host "Launched $(Split-Path -Leaf $targetDir) in a new tab." -ForegroundColor Green
    } catch {
        Write-Host "Failed to launch 5-pane layout: $_" -ForegroundColor Red
    }
    return
}

# ── Legacy 4-grid path (RWN_PANE_LAYOUT=4grid / bare / nodir fallback) ──
function Get-PaneLaunch {
    param([string]$CliName, [string]$TargetDir)
    if ($bareMode -or (-not $TargetDir) -or (-not (Test-Path $paneRunner))) {
        return "powershell -NoExit -NoProfile -Command `"$($cliDefs[$CliName].cmd)`""
    }
    return "powershell -NoExit -NoProfile -File `"$paneRunner`" -Cli $($cliLower[$CliName]) -ProjectDir `"$TargetDir`""
}

# Split sequence: first CLI stays in this pane, remaining CLIs split off to the right
$splitFractions = @(0.75, 0.6667, 0.5)

for ($i = 1; $i -lt $activeCLIs.Count; $i++) {
    $cliName = $activeCLIs[$i]
    $fraction = $splitFractions[$i - 1]

    $dirArg = if ($targetDir) { "-d `"$targetDir`"" } else { "" }
    $splitCmd = "$dirArg $(Get-PaneLaunch -CliName $cliName -TargetDir $targetDir)"
    $wtCmd = "-w rwn4ai split-pane -V -s $fraction $splitCmd"
    try {
        & cmd.exe /c "`"$wtExe`" $wtCmd"
        Start-Sleep -Milliseconds 400
    } catch {
        Write-Host "Failed to launch $cliName pane." -ForegroundColor Red
    }
}

# This pane -> first CLI in the layout.
# Self-driving path: run the pane-runner loop directly in this pane so it too
# supervises its CLI. Bare path (RWN_PANE_BARE / nodir): plain interactive REPL.
$firstCli = $activeCLIs[0]

Clear-Host
if ($targetDir) {
    Set-Location $targetDir
}
if ($bareMode -or (-not $targetDir) -or (-not (Test-Path $paneRunner))) {
    Invoke-Expression $cliDefs[$firstCli].cmd
} else {
    & $paneRunner -Cli $cliLower[$firstCli] -ProjectDir $targetDir
}
