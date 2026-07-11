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

$script:abortReason = $null
try {
    Assert-EnvOverrideContract
    Test-InstallerPath
    Test-FallbackCopyPath
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
