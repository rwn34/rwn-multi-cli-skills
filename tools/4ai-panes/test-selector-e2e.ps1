#requires -Version 5.1
<#
  End-to-end test for Selector.ps1 framework injection (Install-Framework).

  HOW IT DRIVES PRODUCTION CODE
  -----------------------------
  Selector.ps1 is an interactive launcher; it cannot be dot-sourced wholesale
  (it would draw a menu and block on a keypress). So this suite:
    1. Parses Selector.ps1 with the PowerShell AST parser.
    2. Lifts the REAL function bodies (Install-Framework, Find-Bash,
       Test-FrameworkDrift) and the REAL `$frameworkRepo = ...` assignment line
       out of the source and executes them verbatim -- no source rewriting, no
       reimplementation. If those constructs move or change shape, the suite
       fails loudly (see Assert-EnvOverrideContract) instead of silently
       testing nothing.
    3. Points the framework source at a TEMP dir by setting the
       RWN_FRAMEWORK_REPO env var that Selector.ps1 itself honors.

  HISTORY: this suite used to regex-rewrite the hardcoded `$frameworkRepo = "..."`
  literal in the source. Commit 161501b replaced that literal with an env-var
  lookup, the regex stopped matching, and the suite threw before ever calling
  Install-Framework -- i.e. it gave ZERO coverage while looking alive. The
  contract guard below exists so that cannot happen a second time.

  SAFETY: every write goes to a temp sandbox. The suite asserts, at the end,
  that neither the framework repo working tree nor ~/.rwn-auto was touched.

  SCENARIOS
    Guard 0 -- Selector.ps1 still honors RWN_FRAMEWORK_REPO (anti-rot contract).
    Test 1  -- Installer path: template = the real repo (has scripts/install-
               template.sh) -> bash installer runs; framework lands in a fresh
               temp project. Then a re-run proves the marker short-circuit.
    Test 2  -- Fallback path: template = a temp copy WITHOUT scripts/ ->
               installer cannot run -> Install-Framework's direct-copy fallback
               must still produce a complete framework + version marker.
    Test 3  -- Badges: [v SRC] for the framework source repo, [v OK] / [! OLD] /
               [- none] for target dirs, and the [H:n] badge still applies to the
               source repo. Plus the <=70-char legend budget.
    Test 4  -- Staged emission: Build-FleetTabStages yields the SAME ordered wt
               subcommands as the legacy atomic chain (stage-by-stage equality),
               and no stage can be corrupted by an embedded ' ; '.
    Test 5  -- Batch pacing: N marked projects -> exactly N `new-tab` launches
               (one wt invocation per tab), never one packed invocation.
    Test 6  -- Delay knobs: defaults when unset, honored when set, defaults on
               garbage/negative input, and 0 restores the atomic behavior.

  Tests 3-6 never invoke Windows Terminal: the launch plan is built by PURE
  production functions (Build-FleetTabStages / Get-FleetLaunchPlan) and asserted
  as data. Only Invoke-FleetLaunchPlan touches wt.exe, and it is never called here.
#>
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$launcherDir  = Split-Path -Parent $MyInvocation.MyCommand.Path        # tools/4ai-panes
$selectorPath = Join-Path $launcherDir 'Selector.ps1'
$repoRoot     = Split-Path -Parent (Split-Path -Parent $launcherDir)   # framework repo root
$sandboxRoot  = Join-Path $env:TEMP ("4ai-selector-e2e-" + [Guid]::NewGuid().ToString())
$logPath      = Join-Path $env:TEMP "4ai-selector-e2e-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$rwnAutoDir   = Join-Path $env:USERPROFILE '.rwn-auto'

New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

$script:passCount = 0
$script:failCount = 0

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    $line | Out-File -FilePath $logPath -Append -Encoding utf8
}

function Assert-That {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Detail = ''
    )
    if ($Condition) {
        $script:passCount++
        Write-Log "  PASS  $Name"
    } else {
        $script:failCount++
        $suffix = if ($Detail) { " -- $Detail" } else { '' }
        Write-Log "  FAIL  $Name$suffix"
    }
}

# ---------------------------------------------------------------------------
# Selector.ps1 AST access
# ---------------------------------------------------------------------------
function Get-SelectorAst {
    $parseErrors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($selectorPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        throw "CONTRACT BROKEN: Selector.ps1 does not parse:`n$($parseErrors | Out-String)"
    }
    return $ast
}

# Text of the top-level `$<VarName> = ...` assignment, verbatim from the source.
function Get-SelectorAssignmentText {
    param($Ast, [string]$VarName)
    $node = $Ast.Find({
        $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $args[0].Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $args[0].Left.VariablePath.UserPath -eq $VarName
    }, $true)
    if (-not $node) {
        throw "CONTRACT BROKEN: no assignment to `$$VarName found in Selector.ps1. " +
              "This suite executes that line verbatim to configure the framework source; " +
              "it cannot drive Install-Framework without it. Update the test deliberately."
    }
    return $node.Extent.Text
}

function Get-SelectorFunctionText {
    param($Ast, [string[]]$Names)
    $out = @{}
    foreach ($name in $Names) {
        $funcAst = $Ast.Find({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $args[0].Name -eq $name
        }, $true)
        if (-not $funcAst) {
            throw "CONTRACT BROKEN: function '$name' no longer exists in Selector.ps1. " +
                  "This suite lifts it out of the source to test it. Update the test deliberately."
        }
        $out[$name] = $funcAst.Extent.Text
    }
    return $out
}

# ---------------------------------------------------------------------------
# Guard 0: ANTI-ROT CONTRACT
# The whole suite rests on one property of Selector.ps1: $frameworkRepo can be
# redirected via the RWN_FRAMEWORK_REPO env var. If that ever stops being true,
# the tests below would either exercise the REAL repo or quietly test nothing.
# This guard THROWS (does not skip, does not soft-pass) in that case.
# ---------------------------------------------------------------------------
function Assert-EnvOverrideContract {
    Write-Log "===== Guard 0: RWN_FRAMEWORK_REPO override contract ====="
    $ast = Get-SelectorAst
    $assignText = Get-SelectorAssignmentText -Ast $ast -VarName 'frameworkRepo'
    Write-Log "  Selector.ps1 line: $assignText"

    if ($assignText -notmatch 'RWN_FRAMEWORK_REPO') {
        throw ("CONTRACT BROKEN: Selector.ps1 no longer resolves `$frameworkRepo from the " +
               "RWN_FRAMEWORK_REPO environment variable.`n" +
               "  Found: $assignText`n" +
               "This suite redirects the framework source to a temp dir through that env var. " +
               "Without it, running these tests would point Install-Framework at the REAL repo. " +
               "Restore the env-var override in Selector.ps1, or rewrite this suite deliberately. " +
               "DO NOT delete this guard to make the suite green.")
    }

    # Behavioural proof, not just a text match: execute the real line both ways.
    $sentinel = Join-Path $sandboxRoot 'sentinel-framework-src'
    $probe = [scriptblock]::Create($assignText + "`r`n" + '$frameworkRepo')

    $prev = $env:RWN_FRAMEWORK_REPO
    try {
        $env:RWN_FRAMEWORK_REPO = $sentinel
        $withEnv = & $probe
        Remove-Item Env:RWN_FRAMEWORK_REPO -ErrorAction SilentlyContinue
        $withoutEnv = & $probe
    } finally {
        if ($null -eq $prev) { Remove-Item Env:RWN_FRAMEWORK_REPO -ErrorAction SilentlyContinue }
        else { $env:RWN_FRAMEWORK_REPO = $prev }
    }

    if ($withEnv -ne $sentinel) {
        throw ("CONTRACT BROKEN: Selector.ps1 mentions RWN_FRAMEWORK_REPO but does not honor it. " +
               "Expected `$frameworkRepo = '$sentinel', got '$withEnv'.")
    }
    Assert-That ($withEnv -eq $sentinel) 'frameworkRepo honors RWN_FRAMEWORK_REPO when set' "got '$withEnv'"
    Assert-That (-not [string]::IsNullOrWhiteSpace($withoutEnv) -and $withoutEnv -ne $sentinel) `
        'frameworkRepo falls back to a default when the env var is unset' "got '$withoutEnv'"
}

# ---------------------------------------------------------------------------
# Harness: run the REAL Install-Framework against a temp target
# ---------------------------------------------------------------------------
function Invoke-InstallFramework {
    param(
        [Parameter(Mandatory = $true)][string]$FrameworkSrc,   # template source (temp or repo, read-only)
        [Parameter(Mandatory = $true)][string]$TargetDir,      # temp project (written)
        [Parameter(Mandatory = $true)][string]$FakeLauncherDir # stands in for $scriptDir (gets install-framework.log)
    )
    if (-not $TargetDir.StartsWith($env:TEMP, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "REFUSING to run: target '$TargetDir' is not under `$env:TEMP."
    }
    if (-not $FakeLauncherDir.StartsWith($env:TEMP, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "REFUSING to run: launcher dir '$FakeLauncherDir' is not under `$env:TEMP."
    }

    $ast = Get-SelectorAst
    $assignText = Get-SelectorAssignmentText -Ast $ast -VarName 'frameworkRepo'
    $funcNames = @('Find-Bash', 'Test-FrameworkDrift', 'Install-Framework')
    $funcs = Get-SelectorFunctionText -Ast $ast -Names $funcNames

    $prev = $env:RWN_FRAMEWORK_REPO
    try {
        $env:RWN_FRAMEWORK_REPO = $FrameworkSrc

        # Run the function under PRODUCTION conditions: Selector.ps1 sets
        # $ErrorActionPreference = 'SilentlyContinue' at the top. Under the suite's
        # 'Stop', bash writing to stderr ("Switched to a new branch ...") would
        # surface as a terminating error and divert the installer branch into
        # Install-Framework's catch -- i.e. we would silently test the fallback
        # twice and never the installer. Scoped to this function only.
        $ErrorActionPreference = 'SilentlyContinue'

        # Install-Framework reads $scriptDir and $frameworkRepo from its caller's
        # scope. $scriptDir is the launcher dir in production -> a temp stand-in
        # here, so install-framework.log never lands in the repo.
        $scriptDir = $FakeLauncherDir

        # Execute Selector.ps1's OWN assignment line -- $frameworkRepo is produced
        # by production code reading the env var, not by the test asserting it.
        . ([scriptblock]::Create($assignText))
        foreach ($n in $funcNames) { . ([scriptblock]::Create($funcs[$n])) }

        if ($frameworkRepo -ne $FrameworkSrc) {
            throw "CONTRACT BROKEN: `$frameworkRepo resolved to '$frameworkRepo', expected '$FrameworkSrc'."
        }

        Install-Framework -targetDir $TargetDir
    } finally {
        if ($null -eq $prev) { Remove-Item Env:RWN_FRAMEWORK_REPO -ErrorAction SilentlyContinue }
        else { $env:RWN_FRAMEWORK_REPO = $prev }
    }
}

# Items a complete framework install must leave in the project.
$requiredItems = @(
    '.ai',
    '.archive',
    '.claude',
    '.codegraph',
    '.github',
    '.kimi',
    '.kiro',
    'AGENTS.md',
    'CLAUDE.md',
    'docs'
)

function Assert-FrameworkComplete {
    param([string]$TargetDir, [string]$Prefix)
    $missing = @($requiredItems | Where-Object { -not (Test-Path (Join-Path $TargetDir $_)) })
    Assert-That ($missing.Count -eq 0) "$Prefix framework items present" "missing: $($missing -join ', ')"
}

function Get-TemplateVersion {
    (Get-Content (Join-Path $repoRoot 'tools/multi-cli-install/package.json') -Raw | ConvertFrom-Json).version
}

function Get-InstallLog {
    param([string]$FakeLauncherDir)
    $p = Join-Path $FakeLauncherDir 'install-framework.log'
    if (-not (Test-Path $p)) { return '' }
    return (Get-Content $p -Raw)
}

function New-Sandbox {
    param([string]$Name)
    $target  = Join-Path $sandboxRoot "$Name\project"
    $laun    = Join-Path $sandboxRoot "$Name\launcher"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    New-Item -ItemType Directory -Path $laun -Force | Out-Null
    return @{ Target = $target; Launcher = $laun }
}

# ---------------------------------------------------------------------------
# Test 1: installer path (real repo as template) + idempotent re-run
# ---------------------------------------------------------------------------
function Test-InstallerPath {
    Write-Log "===== Test 1: installer path (template = repo with scripts/install-template.sh) ====="
    $sb = New-Sandbox -Name 'installer'
    Write-Log "  target:   $($sb.Target)"
    Write-Log "  template: $repoRoot (read-only)"

    Assert-That (Test-Path (Join-Path $repoRoot 'scripts/install-template.sh')) `
        'template repo exposes scripts/install-template.sh' "repoRoot=$repoRoot"

    Invoke-InstallFramework -FrameworkSrc $repoRoot -TargetDir $sb.Target -FakeLauncherDir $sb.Launcher

    $log = Get-InstallLog -FakeLauncherDir $sb.Launcher
    # Proof the production function actually RAN (not skipped, not short-circuited).
    Assert-That ($log -match '=== Install-Framework start ===') 'Install-Framework executed' 'no start marker in install-framework.log'
    Assert-That ($log -match '=== Install-Framework end ===')   'Install-Framework ran to completion' 'no end marker in install-framework.log'
    Assert-That ($log -match [regex]::Escape("fwSource: $repoRoot")) 'template source resolved from RWN_FRAMEWORK_REPO' "log did not report fwSource: $repoRoot"
    Assert-That ($log -notmatch 'Skipped: no framework template source') 'install was not skipped'

    # The bash-installer branch (not the catch, not the fallback) must be the one
    # that ran here: the template HAS scripts/install-template.sh.
    Assert-That ($log -match 'installer exit code: 0') 'bash installer ran and exited 0' `
        'installer branch did not succeed -- the fallback would be masking it'
    Assert-That ($log -notmatch '(?m)^\[.*\] ERROR: ') 'installer branch did not throw into the catch'

    # Informational: items the bash installer does not place (the fallback tops
    # them up). Logged, not asserted -- a shrinking list is fine, a growing one is
    # a signal for install-template.sh.
    $missingLine = ([regex]::Match($log, '(?m)^\[.*\] post-install missing items: (.*)$')).Groups[1].Value
    Write-Log "  INFO  items left for the fallback after the bash installer: $missingLine"

    Assert-FrameworkComplete -TargetDir $sb.Target -Prefix 'installer path:'

    $marker = Join-Path $sb.Target '.ai\.framework-version'
    Assert-That (Test-Path $marker) 'version marker written' $marker
    if (Test-Path $marker) {
        $stamped = (Get-Content $marker -Raw | ConvertFrom-Json).framework_version
        Assert-That ($stamped -eq (Get-TemplateVersion)) 'marker version matches template SSOT' `
            "marker=$stamped template=$(Get-TemplateVersion)"
    }

    # Idempotency: a second call on an installed project must short-circuit on the
    # marker (warn-only drift check), not reinstall or mutate the marker.
    Write-Log "  -- re-run on an already-installed project --"
    $markerBefore = (Get-FileHash $marker -Algorithm SHA256).Hash
    Invoke-InstallFramework -FrameworkSrc $repoRoot -TargetDir $sb.Target -FakeLauncherDir $sb.Launcher
    $markerAfter = (Get-FileHash $marker -Algorithm SHA256).Hash
    $log2 = Get-InstallLog -FakeLauncherDir $sb.Launcher

    Assert-That ($markerBefore -eq $markerAfter) 're-run leaves the version marker byte-identical'
    Assert-That ($log2 -match 'Framework marker exists; ran drift check \(warn-only\), skipping install') `
        're-run short-circuits on the marker (no reinstall)'
    Assert-FrameworkComplete -TargetDir $sb.Target -Prefix 're-run:'
}

# ---------------------------------------------------------------------------
# Test 2: fallback copy path (template WITHOUT scripts/install-template.sh)
# ---------------------------------------------------------------------------
function New-TemplateWithoutInstaller {
    # A framework template that carries every payload item but NO scripts/ dir, so
    # Install-Framework's bash installer call cannot succeed and the direct-copy
    # fallback branch has to carry the install.
    $tpl = Join-Path $sandboxRoot 'template-no-installer'
    New-Item -ItemType Directory -Path $tpl -Force | Out-Null
    $payload = @(
        '.ai', '.claude', '.kimi', '.kiro', '.archive', '.opencode', '.codegraph',
        '.github', 'docs', 'CLAUDE.md', 'AGENTS.md', 'opencode.json',
        '.mcp.json.example', 'tools/multi-cli-install/package.json'
    )
    foreach ($item in $payload) {
        $src = Join-Path $repoRoot $item
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $tpl $item
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -Path $src -Destination $dst -Recurse -Force
    }
    return $tpl
}

function Test-FallbackCopyPath {
    Write-Log "===== Test 2: fallback copy path (template has NO scripts/install-template.sh) ====="
    $tpl = New-TemplateWithoutInstaller
    $sb = New-Sandbox -Name 'fallback'
    Write-Log "  target:   $($sb.Target)"
    Write-Log "  template: $tpl"

    Assert-That (-not (Test-Path (Join-Path $tpl 'scripts/install-template.sh'))) `
        'fallback template intentionally lacks the bash installer'
    Assert-That (Test-Path (Join-Path $tpl '.ai')) 'fallback template carries .ai (so it is a valid fwSource)'

    Invoke-InstallFramework -FrameworkSrc $tpl -TargetDir $sb.Target -FakeLauncherDir $sb.Launcher

    $log = Get-InstallLog -FakeLauncherDir $sb.Launcher
    Assert-That ($log -match '=== Install-Framework start ===') 'Install-Framework executed'
    Assert-That ($log -match 'Fallback: copying core framework template files') 'fallback copy branch taken'
    Assert-That ($log -match 'Fallback wrote \.ai/\.framework-version') 'fallback stamped the version marker'

    Assert-FrameworkComplete -TargetDir $sb.Target -Prefix 'fallback path:'

    $marker = Join-Path $sb.Target '.ai\.framework-version'
    Assert-That (Test-Path $marker) 'fallback version marker written'
    if (Test-Path $marker) {
        $m = Get-Content $marker -Raw | ConvertFrom-Json
        Assert-That ($m.framework_version -eq (Get-TemplateVersion)) 'fallback marker version matches template SSOT' `
            "marker=$($m.framework_version) template=$(Get-TemplateVersion)"
        Assert-That ($m.installer_name -eq 'Selector.ps1 fallback') 'fallback marker records the fallback installer' `
            "installer_name=$($m.installer_name)"
    }

    # The fallback must reset the copied activity log to the clean template header
    # instead of shipping the framework repo's own history into the new project.
    $activity = Join-Path $sb.Target '.ai\activity\log.md'
    Assert-That (Test-Path $activity) 'activity log present in target'
    if (Test-Path $activity) {
        $content = Get-Content $activity -Raw
        Assert-That ($content -match '^# Activity Log') 'activity log starts with the clean template header'
        Assert-That ($content -notmatch '(?m)^## \d{4}-\d{2}-\d{2} ') 'activity log carries no template-repo entries' `
            'template history leaked into the new project'
    }

    # The target is a git repo with the install committed (Install-Framework inits + commits).
    $gitDir = Join-Path $sb.Target '.git'
    Assert-That (Test-Path $gitDir) 'target was git-initialized by Install-Framework'
}

# ---------------------------------------------------------------------------
# Test 3: project badges -- [v SRC] / [v OK] / [! OLD] / [- none] + legend budget
#
# Drives the REAL Get-ProjectBadges (+ Get-CanonicalDir / Test-IsFrameworkSource)
# lifted from Selector.ps1, with the framework source pointed at a temp dir via
# RWN_FRAMEWORK_REPO -- the same env var Selector.ps1's own $frameworkRepo line reads.
# ---------------------------------------------------------------------------
function Invoke-GetProjectBadges {
    param(
        [Parameter(Mandatory = $true)][string]$Dir,
        [Parameter(Mandatory = $true)][string]$FrameworkSrc
    )
    $ast = Get-SelectorAst
    $assignText = Get-SelectorAssignmentText -Ast $ast -VarName 'frameworkRepo'
    $funcNames = @('Get-CanonicalDir', 'Test-IsFrameworkSource', 'Get-ProjectBadges')
    $funcs = Get-SelectorFunctionText -Ast $ast -Names $funcNames

    $prev = $env:RWN_FRAMEWORK_REPO
    try {
        $env:RWN_FRAMEWORK_REPO = $FrameworkSrc
        $ErrorActionPreference = 'SilentlyContinue'   # production condition

        # Scope Get-ProjectBadges reads: $frameworkRepo (production line), plus the
        # fleet CLI maps it uses for the stranded-handoff marker.
        . ([scriptblock]::Create($assignText))
        . (Join-Path $launcherDir 'fleet-clis.ps1')
        $cliKey = @{}
        $cliAvailable = @{}
        foreach ($c in $FleetClis) {
            $cliKey[$c] = $FleetCliProper[$c]
            $cliAvailable[$FleetCliProper[$c]] = $true      # every CLI present -> nothing stranded
        }
        $projectsDir = Split-Path -Parent $Dir              # -Path is used, so this is inert
        foreach ($n in $funcNames) { . ([scriptblock]::Create($funcs[$n])) }

        return (Get-ProjectBadges -Path $Dir)
    } finally {
        if ($null -eq $prev) { Remove-Item Env:RWN_FRAMEWORK_REPO -ErrorAction SilentlyContinue }
        else { $env:RWN_FRAMEWORK_REPO = $prev }
    }
}

function Test-Badges {
    Write-Log "===== Test 3: project badges (framework source vs targets) ====="
    $root = Join-Path $sandboxRoot 'badges'

    # The stand-in framework SOURCE repo: has .ai/ but NO .ai/.framework-version --
    # exactly like the real repo, which is what used to make it badge [! OLD].
    $fwSrc = Join-Path $root 'framework-repo'
    New-Item -ItemType Directory -Path (Join-Path $fwSrc '.ai') -Force | Out-Null
    Assert-That (-not (Test-Path (Join-Path $fwSrc '.ai\.framework-version'))) `
        'framework source repo carries no .framework-version marker (the premise of the bug)'

    $installed = Join-Path $root 'installed'
    New-Item -ItemType Directory -Path (Join-Path $installed '.ai') -Force | Out-Null
    '{"framework_version":"0.0.1"}' | Set-Content -Path (Join-Path $installed '.ai\.framework-version')

    $stale = Join-Path $root 'stale'
    New-Item -ItemType Directory -Path (Join-Path $stale '.ai') -Force | Out-Null

    $bare = Join-Path $root 'bare'
    New-Item -ItemType Directory -Path $bare -Force | Out-Null

    $b = Invoke-GetProjectBadges -Dir $fwSrc -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[v SRC]') 'framework source repo badges [v SRC] (not [! OLD])' "got '$b'"

    $b = Invoke-GetProjectBadges -Dir $installed -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[v OK]') 'dir with .ai/.framework-version badges [v OK]' "got '$b'"

    $b = Invoke-GetProjectBadges -Dir $stale -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[! OLD]') 'dir with .ai/ but no marker badges [! OLD]' "got '$b'"

    $b = Invoke-GetProjectBadges -Dir $bare -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[- none]') 'bare dir badges [- none]' "got '$b'"

    # Path-shape tolerance: trailing separator, forward slashes, and case must all
    # still resolve to the same source repo (canonicalized comparison).
    $b = Invoke-GetProjectBadges -Dir ($fwSrc + '\') -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[v SRC]') '[v SRC] survives a trailing separator on the dir' "got '$b'"
    $b = Invoke-GetProjectBadges -Dir $fwSrc -FrameworkSrc (($fwSrc -replace '\\', '/') + '/')
    Assert-That ($b -eq '[v SRC]') '[v SRC] survives forward slashes + trailing slash on $frameworkRepo' "got '$b'"
    $b = Invoke-GetProjectBadges -Dir $fwSrc.ToUpper() -FrameworkSrc $fwSrc.ToLower()
    Assert-That ($b -eq '[v SRC]') '[v SRC] is case-insensitive' "got '$b'"

    # A non-existent path must NOT crash the badge builder (GetFullPath on a path
    # that does not exist is fine; this guards the "do not crash" requirement).
    $ghost = Join-Path $root 'does-not-exist'
    $b = Invoke-GetProjectBadges -Dir $ghost -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[- none]') 'non-existent dir badges [- none] without throwing' "got '$b'"

    # The handoff badge is UNCHANGED for the source repo: [v SRC] + [H:n].
    # B7: with open handoffs and NO heartbeat sidecar, the badge also carries
    # the stall: marker (a queue nobody is watching — fleet-health.sh's STALL).
    New-Item -ItemType Directory -Path (Join-Path $fwSrc '.ai\handoffs\to-kimi\open') -Force | Out-Null
    'x' | Set-Content -Path (Join-Path $fwSrc '.ai\handoffs\to-kimi\open\a.md')
    'y' | Set-Content -Path (Join-Path $fwSrc '.ai\handoffs\to-kimi\open\b.md')
    $b = Invoke-GetProjectBadges -Dir $fwSrc -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[v SRC] [H:2 stall:kimi]') 'source repo gets [H:n] + stall: when the heartbeat is missing' "got '$b'"

    # B7 positive case: a FRESH heartbeat sidecar clears the stall marker.
    $hb = Join-Path $fwSrc '.ai\.heartbeat-kimi.json'
    '{"cli":"kimi","pid":1,"host":"x","ts":"now","handoff":"idle"}' | Set-Content -Path $hb
    $b = Invoke-GetProjectBadges -Dir $fwSrc -FrameworkSrc $fwSrc
    Assert-That ($b -eq '[v SRC] [H:2]') 'fresh heartbeat sidecar -> no stall: marker' "got '$b'"
    Remove-Item -Path $hb -Force

    # Legend: documents the new badge and fits the narrowest box (<= 70 chars).
    $legend = & ([scriptblock]::Create((Get-SelectorAssignmentText -Ast (Get-SelectorAst) -VarName 'badgeLegend') + "`r`n" + '$badgeLegend'))
    Write-Log "  legend ($($legend.Length) chars): $legend"
    Assert-That ($legend -match '\[v SRC\]') 'badge legend documents [v SRC]' "legend='$legend'"
    Assert-That ($legend.Length -le 70) 'badge legend fits the narrowest box (<= 70 chars)' "length=$($legend.Length)"
}

# ---------------------------------------------------------------------------
# Tests 4-6 harness: lift the PURE launch-plan production functions.
# ---------------------------------------------------------------------------

# Every `$cliDefs[...] = ...` assignment, verbatim -- the launch strings under test
# are production text, not a test reimplementation.
function Get-SelectorCliDefsText {
    param($Ast)
    $nodes = @($Ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $args[0].Left.Extent.Text -like '$cliDefs*'
    }, $true))
    if ($nodes.Count -lt 2) {
        throw "CONTRACT BROKEN: Selector.ps1 no longer builds `$cliDefs by assignment. " +
              "This suite executes those lines verbatim to build fleet-tab stages."
    }
    return (($nodes | ForEach-Object { $_.Extent.Text }) -join "`r`n")
}

function Invoke-BuildFleetTabStages {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [string]$LayoutMode = '6pane',
        [string[]]$ActiveCLIs = @('Claude', 'Kiro', 'Kimi', 'OpenCode')
    )
    $ast = Get-SelectorAst
    $funcs = Get-SelectorFunctionText -Ast $ast -Names @('Build-FleetTabStages')

    $prevBare = $env:RWN_PANE_BARE
    try {
        Remove-Item Env:RWN_PANE_BARE -ErrorAction SilentlyContinue   # bare mode would skip the composite build
        $ErrorActionPreference = 'SilentlyContinue'

        . ([scriptblock]::Create((Get-SelectorCliDefsText -Ast $ast)))
        . (Join-Path $launcherDir 'fleet-clis.ps1')
        $cliLower = @{}
        $cliAvailable = @{}
        foreach ($c in $FleetClis) {
            $cliLower[$FleetCliProper[$c]] = $c
            $cliAvailable[$FleetCliProper[$c]] = $true
        }
        $activeCLIs = $ActiveCLIs
        $paneLayoutMode = $LayoutMode
        $topStripFraction = & ([scriptblock]::Create(
            (Get-SelectorAssignmentText -Ast $ast -VarName 'topStripFraction') + "`r`n" + '$topStripFraction'))
        # Real launcher dir: pane-runner.ps1 + run-pane-supervised.ps1 must exist for the
        # composite (6pane/5pane) build. Build-FleetTabStages is pure -- it only reads.
        $scriptDir = $launcherDir

        . ([scriptblock]::Create($funcs['Build-FleetTabStages']))
        return @(Build-FleetTabStages -TargetDir $TargetDir)
    } finally {
        if ($null -ne $prevBare) { $env:RWN_PANE_BARE = $prevBare }
    }
}

function Invoke-GetFleetLaunchPlan {
    param(
        [Parameter(Mandatory = $true)][object[]]$TabStages,
        [int]$PaneDelayMs,
        [int]$TabDelayMs
    )
    $ast = Get-SelectorAst
    $funcs = Get-SelectorFunctionText -Ast $ast -Names @('Get-FleetLaunchPlan')
    . ([scriptblock]::Create($funcs['Get-FleetLaunchPlan']))
    return @(Get-FleetLaunchPlan -TabStages $TabStages -PaneDelayMs $PaneDelayMs -TabDelayMs $TabDelayMs)
}

function Invoke-GetDelayMs {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][int]$Default)
    $ast = Get-SelectorAst
    $funcs = Get-SelectorFunctionText -Ast $ast -Names @('Get-DelayMs')
    . ([scriptblock]::Create($funcs['Get-DelayMs']))
    return (Get-DelayMs -Name $Name -Default $Default)
}

# ---------------------------------------------------------------------------
# Test 4: staged emission == the legacy atomic chain, stage for stage
# ---------------------------------------------------------------------------
function Test-StagedEmission {
    Write-Log "===== Test 4: staged emission of a 6-pane group ====="
    $proj = Join-Path $sandboxRoot 'stage-proj'
    New-Item -ItemType Directory -Path $proj -Force | Out-Null

    $stages = Invoke-BuildFleetTabStages -TargetDir $proj
    Write-Log "  stages ($($stages.Count)):"
    foreach ($s in $stages) { Write-Log "    | $s" }

    # 6 panes: new-tab (1) + split -H (2) + 3x split -V (5) + move-focus/split (6).
    Assert-That ($stages.Count -eq 7) '6-pane group emits 7 stages (6 panes + move-focus)' "got $($stages.Count)"
    Assert-That ($stages[0] -like 'new-tab *') 'stage 0 is the new-tab' "got '$($stages[0])'"
    Assert-That (@($stages | Where-Object { $_ -like 'new-tab *' }).Count -eq 1) 'exactly one new-tab per project group'
    Assert-That ($stages[1] -like 'split-pane -H *') 'stage 1 is the horizontal split (top over bottom)' "got '$($stages[1])'"
    Assert-That ($stages[2] -like 'split-pane -V *' -and $stages[3] -like 'split-pane -V *' -and $stages[4] -like 'split-pane -V *') `
        'stages 2-4 are the bottom vertical splits'
    Assert-That ($stages[5] -eq 'move-focus up') 'stage 5 returns focus to the top pane' "got '$($stages[5])'"
    Assert-That ($stages[6] -like 'split-pane -V -s 0.5 *') 'stage 6 splits the top row (Kimi cockpit)' "got '$($stages[6])'"

    # No stage may contain the ' ; ' chain separator: that is precisely what would
    # make a string-split emission corrupt a command payload.
    $dirty = @($stages | Where-Object { $_ -like '* ; *' })
    Assert-That ($dirty.Count -eq 0) 'no stage contains a literal '' ; '' (chain separator cannot be corrupted)' `
        "offending: $($dirty -join ' || ')"

    # Every group's --title / -d / -w semantics preserved.
    $leaf = Split-Path -Leaf $proj
    Assert-That ($stages[0] -like "*--title `"$leaf`"*") 'new-tab keeps --title <project leaf>' "got '$($stages[0])'"
    $withDir = @($stages | Where-Object { $_ -like "*-d `"$proj`"*" })
    Assert-That ($withDir.Count -eq 6) 'every pane-creating stage keeps -d "<targetDir>"' "got $($withDir.Count) of 6"

    # STAGE-BY-STAGE EQUALITY: the paced plan, joined back with ' ; ', must be the
    # exact atomic chain that PaneDelayMs=0 produces (the legacy single invocation).
    # @( ) at the CALL site: PowerShell unrolls a single-element array on function
    # return, so a 1-invocation plan would arrive as a bare object without .Count.
    $paced  = @(Invoke-GetFleetLaunchPlan -TabStages @(, $stages) -PaneDelayMs 250 -TabDelayMs 1200)
    $atomic = @(Invoke-GetFleetLaunchPlan -TabStages @(, $stages) -PaneDelayMs 0   -TabDelayMs 1200)

    Assert-That ($paced.Count -eq 7) 'paced plan = one wt invocation per stage' "got $($paced.Count)"
    Assert-That ($atomic.Count -eq 1) 'atomic plan (pane delay 0) = one wt invocation for the tab' "got $($atomic.Count)"
    Assert-That (@($paced | Where-Object { $_.Wt -like '-w rwn4ai *' }).Count -eq 7) 'every paced invocation targets -w rwn4ai'

    $rejoined = (@($paced | ForEach-Object { $_.Wt -replace '^-w rwn4ai ', '' }) -join ' ; ')
    $atomicSubcmds = $atomic[0].Wt -replace '^-w rwn4ai ', ''
    Assert-That ($rejoined -eq $atomicSubcmds) 'staged sequence == the legacy atomic chain, subcommand for subcommand' `
        "staged='$rejoined' atomic='$atomicSubcmds'"

    # Pacing metadata: pane delay between stages, 0 after the last (single tab).
    $betweenOk = $true
    for ($i = 0; $i -lt $paced.Count - 1; $i++) { if ($paced[$i].DelayAfterMs -ne 250) { $betweenOk = $false } }
    Assert-That $betweenOk 'pane delay applied between every stage'
    Assert-That ($paced[$paced.Count - 1].DelayAfterMs -eq 0) 'no delay after the last stage of the last tab'

    # 5pane degrades to 6 stages (no top-right Kimi split, no move-focus).
    $stages5 = Invoke-BuildFleetTabStages -TargetDir $proj -LayoutMode '5pane'
    Assert-That ($stages5.Count -eq 5) '5pane group emits 5 stages (no move-focus / top-right split)' "got $($stages5.Count)"
    Assert-That (@($stages5 | Where-Object { $_ -eq 'move-focus up' }).Count -eq 0) '5pane emits no move-focus stage'
}

# ---------------------------------------------------------------------------
# Test 5: a batch of N projects = N tab launches (never one packed invocation)
# ---------------------------------------------------------------------------
function Test-BatchPacing {
    Write-Log "===== Test 5: batch of N projects -> N tab launches ====="
    $n = 5
    $tabStages = @()
    $projects = @()
    for ($i = 1; $i -le $n; $i++) {
        $p = Join-Path $sandboxRoot "batch-proj-$i"
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        $projects += $p
        $tabStages += , (Invoke-BuildFleetTabStages -TargetDir $p)
    }

    $plan = @(Invoke-GetFleetLaunchPlan -TabStages $tabStages -PaneDelayMs 250 -TabDelayMs 1200)
    $newTabs = @($plan | Where-Object { $_.Wt -like '-w rwn4ai new-tab *' })
    Write-Log "  plan: $($plan.Count) invocations, $($newTabs.Count) new-tab launches for $n projects"

    Assert-That ($newTabs.Count -eq $n) "batch of $n projects produces exactly $n tab launches" "got $($newTabs.Count)"
    Assert-That ($plan.Count -eq $n * 7) "one wt invocation per stage across the batch ($($n * 7))" "got $($plan.Count)"

    # Exactly one project per invocation: no invocation may carry two new-tabs, and
    # each project's dir appears in exactly one new-tab.
    $packed = @($plan | Where-Object { ([regex]::Matches($_.Wt, 'new-tab ')).Count -gt 1 })
    Assert-That ($packed.Count -eq 0) 'no wt invocation packs more than one project (the old batching bug)' `
        "packed invocations: $($packed.Count)"
    $everyProjectOnce = $true
    foreach ($p in $projects) {
        $hits = @($newTabs | Where-Object { $_.Wt -like "*-d `"$p`"*" })
        if ($hits.Count -ne 1) { $everyProjectOnce = $false }
    }
    Assert-That $everyProjectOnce 'each marked project owns exactly one new-tab launch'

    # Tab delay lands on the LAST stage of each tab except the last one.
    $tabBoundaryDelays = @()
    for ($t = 1; $t -le $n; $t++) { $tabBoundaryDelays += $plan[($t * 7) - 1].DelayAfterMs }
    $expected = @(1200, 1200, 1200, 1200, 0)
    Assert-That ((($tabBoundaryDelays -join ',') -eq ($expected -join ','))) `
        'tab delay separates projects; none after the last' "got $($tabBoundaryDelays -join ',')"
}

# ---------------------------------------------------------------------------
# Test 6: delay knobs -- defaults, honored values, garbage, and 0 = atomic
# ---------------------------------------------------------------------------
function Test-DelayKnobs {
    Write-Log "===== Test 6: RWN_4AI_PANE_DELAY_MS / RWN_4AI_TAB_DELAY_MS ====="

    # Contract guard: the production assignments must read THESE env names with THESE
    # defaults. If they are renamed, the knobs below would silently test nothing.
    $ast = Get-SelectorAst
    $paneAssign = Get-SelectorAssignmentText -Ast $ast -VarName 'paneDelayMs'
    $tabAssign  = Get-SelectorAssignmentText -Ast $ast -VarName 'tabDelayMs'
    Write-Log "  $paneAssign"
    Write-Log "  $tabAssign"
    Assert-That ($paneAssign -match 'RWN_4AI_PANE_DELAY_MS' -and $paneAssign -match '250') `
        '$paneDelayMs reads RWN_4AI_PANE_DELAY_MS, default 250' "got: $paneAssign"
    Assert-That ($tabAssign -match 'RWN_4AI_TAB_DELAY_MS' -and $tabAssign -match '4000') `
        '$tabDelayMs reads RWN_4AI_TAB_DELAY_MS, default 4000' "got: $tabAssign"

    $prevPane = $env:RWN_4AI_PANE_DELAY_MS
    $prevTab  = $env:RWN_4AI_TAB_DELAY_MS
    try {
        Remove-Item Env:RWN_4AI_PANE_DELAY_MS -ErrorAction SilentlyContinue
        Remove-Item Env:RWN_4AI_TAB_DELAY_MS -ErrorAction SilentlyContinue
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 250) 'pane delay: default 250 when unset'
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_TAB_DELAY_MS' -Default 4000) -eq 4000) 'tab delay: default 4000 when unset'

        $env:RWN_4AI_PANE_DELAY_MS = '500'
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 500) 'pane delay: honored when set to 500'

        $env:RWN_4AI_PANE_DELAY_MS = ' 750 '
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 750) 'pane delay: surrounding whitespace tolerated'

        $env:RWN_4AI_PANE_DELAY_MS = 'banana'
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 250) 'pane delay: garbage falls back to the default'

        $env:RWN_4AI_PANE_DELAY_MS = '-5'
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 250) 'pane delay: negative falls back to the default'

        $env:RWN_4AI_PANE_DELAY_MS = ''
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 250) 'pane delay: empty falls back to the default'

        $env:RWN_4AI_PANE_DELAY_MS = '0'
        Assert-That ((Invoke-GetDelayMs -Name 'RWN_4AI_PANE_DELAY_MS' -Default 250) -eq 0) 'pane delay: 0 is honored (atomic escape hatch)'
    } finally {
        if ($null -eq $prevPane) { Remove-Item Env:RWN_4AI_PANE_DELAY_MS -ErrorAction SilentlyContinue } else { $env:RWN_4AI_PANE_DELAY_MS = $prevPane }
        if ($null -eq $prevTab)  { Remove-Item Env:RWN_4AI_TAB_DELAY_MS -ErrorAction SilentlyContinue }  else { $env:RWN_4AI_TAB_DELAY_MS = $prevTab }
    }

    # 0 = legacy atomic behavior, per dimension.
    $a = Join-Path $sandboxRoot 'knob-proj-a'
    $b = Join-Path $sandboxRoot 'knob-proj-b'
    New-Item -ItemType Directory -Path $a -Force | Out-Null
    New-Item -ItemType Directory -Path $b -Force | Out-Null
    $tabStages = @()
    $tabStages += , (Invoke-BuildFleetTabStages -TargetDir $a)
    $tabStages += , (Invoke-BuildFleetTabStages -TargetDir $b)

    $panedAtomic = @(Invoke-GetFleetLaunchPlan -TabStages $tabStages -PaneDelayMs 0 -TabDelayMs 1200)
    Assert-That ($panedAtomic.Count -eq 2) 'pane delay 0: one atomic invocation per project (still one tab each)' "got $($panedAtomic.Count)"
    Assert-That (@($panedAtomic | Where-Object { $_.Wt -like '-w rwn4ai new-tab *' }).Count -eq 2) `
        'pane delay 0: still exactly one new-tab launch per project'
    Assert-That ($panedAtomic[0].DelayAfterMs -eq 1200 -and $panedAtomic[1].DelayAfterMs -eq 0) `
        'pane delay 0: tab delay still separates the two projects'

    $fullyAtomic = @(Invoke-GetFleetLaunchPlan -TabStages $tabStages -PaneDelayMs 250 -TabDelayMs 0)
    Assert-That ($fullyAtomic.Count -eq 1) 'tab delay 0: the whole batch collapses to ONE wt invocation (full legacy)' "got $($fullyAtomic.Count)"
    $expectedAtomic = "-w rwn4ai " + ((@($tabStages | ForEach-Object { @($_) -join ' ; ' })) -join ' ; ')
    Assert-That ($fullyAtomic[0].Wt -eq $expectedAtomic) 'tab delay 0: the atomic invocation is the exact legacy chain' `
        "got '$($fullyAtomic[0].Wt)'"
    Assert-That ($fullyAtomic[0].DelayAfterMs -eq 0) 'tab delay 0: no trailing sleep'
}

# ---------------------------------------------------------------------------
# Safety fingerprints: nothing outside the sandbox may change.
# ---------------------------------------------------------------------------
function Get-DirFingerprint($path) {
    if (-not (Test-Path $path)) { return 'ABSENT' }
    $items = @(Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue)
    $latest = ($items | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    return "count=$($items.Count);latest=$latest"
}

function Get-RepoFingerprint {
    # Never throw: this helper only exists to prove we did not dirty the repo, and
    # git writes to stderr (which is terminating under the suite's 'Stop'). A repo
    # that cannot be queried fingerprints identically before and after, so the
    # comparison stays honest.
    $status = 'UNAVAILABLE'
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $status = ((& git -C $repoRoot status --porcelain 2>&1) | Out-String)
    } catch {
        $status = 'UNAVAILABLE'
    }
    return "status=$status"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
Write-Log "Selector: $selectorPath"
Write-Log "Repo:     $repoRoot"
Write-Log "Sandbox:  $sandboxRoot"

$repoBefore    = Get-RepoFingerprint
$rwnAutoBefore = Get-DirFingerprint $rwnAutoDir

# ---------------------------------------------------------------------------
# Find-Bash must pin GIT Bash and REJECT WSL bash (2026-07-12 fleet outage).
#
# Selector.ps1 and pane-runner.ps1 both shell out to bash. Both used to trust
# `Get-Command bash` first. In the launcher's real environment (vbs -> powershell,
# persisted Machine+User PATH) C:\WINDOWS\system32 comes FIRST and Git contributes
# only ...\Git\cmd — git.exe, but NO bash.exe. So `bash` resolved to the WSL
# launcher C:\Windows\System32\bash.exe, which re-parses its arguments as a shell
# string and eats the backslashes of any Windows path handed to it:
#   C:\Users\...\wt-bootstrap.sh -> C:Users...wt-bootstrap.sh -> exit 127
#
# This test RECONSTRUCTS that exact PATH (the real repro, not a mock) and asserts
# the hardened Find-Bash still lands on Git Bash. Then it proves the resolved bash
# really does execute a BACKSLASH Windows path — the thing WSL bash cannot do, and
# the reason path conversion was never the fix.
# ---------------------------------------------------------------------------
function Test-FindBashPinsGitBash {
    Write-Log "===== Find-Bash pins Git Bash, rejects WSL ====="

    $ast = Get-SelectorAst
    $src = (Get-SelectorFunctionText -Ast $ast -Names @('Find-Bash'))['Find-Bash']

    # Order guard (anti-rot): the well-known Git Bash probes must appear BEFORE
    # any Get-Command bash fallback. This ordering IS the fix.
    $idxProbe = $src.IndexOf('Program Files\Git\bin\bash.exe')
    $idxOnPath = $src.IndexOf('Get-Command bash')
    Assert-That ($idxProbe -ge 0) 'Find-Bash probes a well-known Git Bash path' 'no Git Bash probe found'
    Assert-That ($idxOnPath -lt 0 -or $idxProbe -lt $idxOnPath) `
        'Find-Bash probes Git Bash BEFORE falling back to Get-Command bash' `
        'Get-Command bash is still consulted first -- this is the outage'
    Assert-That ($src -match '(?i)System32' -and $src -match '(?i)WindowsApps') `
        'Find-Bash explicitly rejects System32 (WSL) and WindowsApps (Store) launchers' `
        'the WSL/Store rejection is missing'

    . ([scriptblock]::Create($src))

    # THE REAL REPRO: the pane PATH, rebuilt from the persisted environment.
    $prevPath = $env:PATH
    try {
        $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path','User')

        $naive = (Get-Command bash -ErrorAction SilentlyContinue)
        if ($naive) {
            Write-Log "  (Get-Command bash).Source under the pane PATH = $($naive.Source)"
        }

        $resolved = Find-Bash
        Write-Log "  Find-Bash resolved = $resolved"

        Assert-That ($null -ne $resolved) 'Find-Bash resolves a bash under the real pane PATH' 'returned $null'
        Assert-That ($resolved -notmatch '(?i)\\System32\\') `
            'Find-Bash does NOT return WSL bash (System32) under the pane PATH' `
            "returned the WSL launcher: $resolved"
        Assert-That ($resolved -notmatch '(?i)WindowsApps') `
            'Find-Bash does NOT return a WindowsApps Store alias' "returned: $resolved"

        # REAL, non-stubbed invocation: the resolved bash must execute a script
        # addressed by a BACKSLASH Windows path. WSL bash fails this (it is how the
        # fleet died); Git Bash passes it unconverted.
        if ($resolved) {
            $shPath = Join-Path $sandboxRoot 'backslash-probe.sh'
            "echo GITBASH_OK" | Set-Content -Path $shPath -Encoding ascii
            $winPath = $shPath -replace '/', '\'
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $out = & $resolved $winPath 2>&1 | Out-String
                $code = $LASTEXITCODE
            } finally { $ErrorActionPreference = $prevEAP }
            Write-Log "  real invocation: `"$resolved`" `"$winPath`" -> exit=$code out=$($out.Trim())"
            Assert-That ($code -eq 0 -and $out -match 'GITBASH_OK') `
                'resolved bash EXECUTES a backslash Windows path (exit 0) -- no conversion needed' `
                "exit=$code out=$out"
            Assert-That ($out -notmatch 'No such file or directory') `
                'resolved bash did not eat the backslashes (no WSL "No such file" failure)' `
                "output: $out"
        }
    } finally {
        $env:PATH = $prevPath
    }
}

$script:abortReason = $null
try {
    Assert-EnvOverrideContract
    Test-FindBashPinsGitBash
    Test-InstallerPath
    Test-FallbackCopyPath
    Test-Badges
    Test-StagedEmission
    Test-BatchPacing
    Test-DelayKnobs
} catch {
    # A thrown contract guard (or any fatal error) must not be able to masquerade
    # as "0 failed". Record it, still run the safety checks, then report ABORTED.
    $script:abortReason = $_
} finally {
    Write-Log "===== Safety: nothing outside the sandbox may change ====="
    Assert-That ((Get-RepoFingerprint) -eq $repoBefore) 'framework repo working tree unchanged' `
        'Install-Framework wrote into the real repo'
    Assert-That ((Get-DirFingerprint $rwnAutoDir) -eq $rwnAutoBefore) '~/.rwn-auto unchanged' `
        "$rwnAutoDir was modified"

    Remove-Item -Path $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Cleaned sandbox: $sandboxRoot"

    if ($script:abortReason) {
        Write-Log "===== SUMMARY: ABORTED -- suite did not complete ($script:passCount passed before the abort) ====="
        Write-Log "ABORT REASON: $($script:abortReason.Exception.Message)"
    } else {
        Write-Log "===== SUMMARY: $script:passCount passed, $script:failCount failed, 0 skipped ====="
    }
    Write-Log "Full log: $logPath"
}

if ($script:abortReason -or $script:failCount -gt 0) { exit 1 }
exit 0
