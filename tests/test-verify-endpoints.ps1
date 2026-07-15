[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$verify = Join-Path $root 'scripts/verify-endpoints.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures'

$common = @{
    Domain        = 'edge.example.com'
    EdgeDomain    = 'edge.example.com'
    DirectHost    = 'direct.example.com'
    ProfilePath   = Join-Path $fixtures 'full-profile-safe.yaml'
    ProviderPath  = Join-Path $fixtures 'provider-safe.yaml'
}

& $verify @common

$risky = $common.Clone()
$risky.ProviderPath = Join-Path $fixtures 'provider-risky-edge-xhttp.yaml'
$failedAsExpected = $false
try {
    & $verify @risky
} catch {
    if ($_.Exception.Message -match 'Node routing audit failed') {
        $failedAsExpected = $true
    } else {
        throw
    }
}

if (-not $failedAsExpected) {
    throw 'Risky XHTTP fixture unexpectedly passed the node routing audit.'
}

Write-Host 'verify_endpoints_tests=passed'
