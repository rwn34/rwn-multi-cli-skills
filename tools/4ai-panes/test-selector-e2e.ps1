#requires -Version 5.1
<#
  End-to-end test for Selector.ps1 framework injection.
  - Creates a temporary projects directory with a brand-new empty subfolder.
  - Extracts Install-Framework from Selector.ps1 and runs it against the subfolder
    using two different framework sources:
      1. The launcher directory (no install-template.sh -> exercises fallback copy).
      2. The real multi-cli-skills repo (install-template.sh runs and may fail
         verification; fallback ensures completeness).
  - Verifies the framework files are injected into the selected folder.
#>
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$repoRoot      = Split-Path -Parent $MyInvocation.MyCommand.Path
$selectorPath  = Join-Path $repoRoot 'Selector.ps1'
$logPath       = Join-Path $repoRoot "test-selector-e2e-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

$skillsRepo    = 'C:/Users/rwn34/Code/rwn-multi-cli-skills'

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $msg"
    Write-Host $line
    $line | Out-File -FilePath $logPath -Append -Encoding utf8
}

function Get-SelectorCode($frameworkSrc) {
    $code = Get-Content $selectorPath -Raw

    # Replace the projects directory (must match literal backslashes in file).
    $code = $code -replace '\$projectsDir = "C:\\Users\\rwn34\\Code"', "`$projectsDir = `"$tempProjects`""

    # Replace the framework repo path.
    $code = $code -replace '\$frameworkRepo = "C:/Users/rwn34/Code/rwn-multi-cli-skills"', "`$frameworkRepo = `"$frameworkSrc`""

    # Sanity-check that replacements occurred.
    if (-not $code.Contains("`$projectsDir = `"$tempProjects`"")) {
        throw "FAILED: `$projectsDir replacement did not apply."
    }
    if (-not $code.Contains("`$frameworkRepo = `"$frameworkSrc`"")) {
        throw "FAILED: `$frameworkRepo replacement did not apply."
    }

    return $code
}

function Extract-Functions($code) {
    $parseErrors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        throw "Parse errors in Selector.ps1: $($parseErrors | Out-String)"
    }

    $funcNames = @('Install-Framework', 'Find-Bash')
    $funcDefinitions = @{}
    foreach ($name in $funcNames) {
        $funcAst = $ast.Find({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $args[0].Name -eq $name
        }, $true)
        if (-not $funcAst) { throw "FAILED: Could not find function '$name' in Selector.ps1" }
        $funcDefinitions[$name] = $funcAst.Extent.Text
    }
    return $funcDefinitions
}

function Test-FrameworkInjection($frameworkSrc, $scenarioName) {
    Write-Log "===== Scenario: $scenarioName ====="
    Write-Log "Framework source: $frameworkSrc"

    $tempProjects = Join-Path $env:TEMP ("4ai-test-projects-" + [Guid]::NewGuid().ToString())
    $targetFolder = Join-Path $tempProjects 'omega-project'
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    Write-Log "Target subfolder: $targetFolder"

    try {
        $code = Get-SelectorCode -frameworkSrc $frameworkSrc
        $funcs = Extract-Functions -code $code

        # Scope the variables that Install-Framework expects.
        $script:scriptDir = $repoRoot
        $script:frameworkRepo = $frameworkSrc

        # Dot-source Find-Bash first, then Install-Framework.
        . ([scriptblock]::Create($funcs['Find-Bash']))
        . ([scriptblock]::Create($funcs['Install-Framework']))

        Write-Log "Calling Install-Framework..."
        Install-Framework -targetDir $targetFolder

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

        $missing = @()
        foreach ($item in $requiredItems) {
            $p = Join-Path $targetFolder $item
            if (-not (Test-Path $p)) { $missing += $item }
        }

        if ($missing.Count -eq 0) {
            Write-Log "PASS: All required framework items present in $targetFolder"
            return $true
        } else {
            Write-Log "FAIL: Missing items: $($missing -join ', ')"
            return $false
        }
    } finally {
        Remove-Item -Path $tempProjects -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temp directory."
    }
}

# ---------------------------------------------------------------------------
# Run both scenarios
# ---------------------------------------------------------------------------
$results = @()

# Scenario 1: launcher directory as source (missing install-template.sh -> fallback copy)
$results += Test-FrameworkInjection -frameworkSrc $repoRoot -scenarioName 'Launcher source (fallback copy)'

# Scenario 2: real skills repo as source (installer runs, may fail verification)
if (Test-Path $skillsRepo) {
    $results += Test-FrameworkInjection -frameworkSrc $skillsRepo -scenarioName 'Skills repo source (installer + fallback)'
} else {
    Write-Log "SKIP: Skills repo not found at $skillsRepo"
}

Write-Log "Full log: $logPath"

if ($results -contains $false) { exit 1 }
