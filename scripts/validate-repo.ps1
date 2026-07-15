[CmdletBinding()]
param(
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$required = @(
    'README.md',
    'AGENTS.md',
    'CHECKLIST.md',
    'SECURITY.md',
    'docs/RUNBOOK.md',
    'docs/CLOUDFLARE.md',
    'docs/CLASH_VERGE.md',
    'docs/TROUBLESHOOTING.md',
    'scripts/preflight-server.sh',
    'scripts/verify-endpoints.ps1',
    'scripts/verify-endpoints.sh',
    'scripts/secret-scan.ps1'
)

foreach ($relative in $required) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $relative"
    }
}

$parseErrors = @()
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    $parseErrors += $errors
}
if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List
    throw 'PowerShell syntax validation failed.'
}

$bash = Get-Command bash -ErrorAction SilentlyContinue
$bashPath = if ($bash) {
    $bash.Source
} elseif (Test-Path -LiteralPath 'C:\Program Files\Git\bin\bash.exe') {
    'C:\Program Files\Git\bin\bash.exe'
} else {
    $null
}
if ($bashPath) {
    foreach ($script in Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.sh' -File) {
        & $bashPath -n $script.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "Bash syntax validation failed: $($script.Name)"
        }
    }
} else {
    Write-Warning 'bash was not found; Bash syntax checks were skipped.'
}

& (Join-Path $Root 'scripts/secret-scan.ps1') -Root $Root

Write-Host 'repo_validation=passed'
